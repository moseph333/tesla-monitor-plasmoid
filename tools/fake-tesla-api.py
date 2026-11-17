#!/usr/bin/env python3
"""Serves made-up Tesla Fleet API replies, so the widget's Tesla API source can be tried
without a car, without a Tesla account and without being billed.

Set the widget's Region to Custom URL with http://localhost:8765 (or the port given),
paste "access-1" as the access token, "refresh-1" as the refresh token, "fake" as the
client ID and http://localhost:8765 as the token server, and use Find Cars.

The car's state is the vehicle_data fixture in tests/fixtures, changed by a scenario.
Switch scenarios while it runs:

    curl http://localhost:8765/_scenario/charging

Scenarios: parked, charging, supercharging, complete, cold, dogmode, driving, open, unlocked,
update, scheduled, installing, performance, asleep, offline.
With --expire-first, the first access token is refused once, so the widget has to renew.
Only one token is valid at a time, as with Tesla: renewing invalidates the old ones.

The same car is also served as the widget's other sources see it, so they can be tried
the same way, with the address http://localhost:8765:

    TeslaMate API   /api/v1/cars and /api/v1/cars/1/status, without a token
    Tessie          /vehicles, /<VIN>/state, /<VIN>/status and /<VIN>/location, with any token
    Home Assistant  /api/ and /api/states, with any token; the car is blue_thunder

(For Teslemetry, which serves the Fleet API's URLs, use the Fleet API source with
Custom URL: the widget's Teslemetry source always asks Teslemetry itself.)

It also fakes signing in, for tools/tesla-login.py: the authorize page (which signs in at
once and redirects back with a code), the authorization_code and client_credentials grants,
and partner account registration. The client secret is "fake-secret" unless given with
--client-secret, and --fail-register makes registration fail as a domain mismatch would.
"""

import argparse
import copy
import json
import pathlib
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlencode, urlparse

ROOT = pathlib.Path(__file__).resolve().parent.parent
FIXTURE = ROOT / "tests" / "fixtures" / "vehicle_data_parked.json"
VIN = "5YJ3E1EA0KF000001"


def scenario(name, car):
    """Changes the parked car for a scenario. Returns the API state (online, asleep...)."""
    charge = car["charge_state"]
    drive = car["drive_state"]
    vs = car["vehicle_state"]
    vs.update(tpms_rcp_front_value=2.9, tpms_rcp_rear_value=2.9)
    car["vehicle_config"].update(trim_badging="74d", wheel_type="Pinwheel18", spoiler_type="None")
    if name == "charging":
        charge.update(charging_state="Charging", charger_power=11, charger_voltage=230,
                      charger_actual_current=16, charger_phases=3, time_to_full_charge=1.25,
                      charge_port_door_open=True, battery_level=60, charge_rate=34,
                      fast_charger_present=False, fast_charger_type="ACSingleWireCAN",
                      fast_charger_brand="<invalid>")
    elif name == "supercharging":
        # On a DC charger the car reports about 0 A and a few volts.
        charge.update(charging_state="Charging", charger_power=148, charger_voltage=2,
                      charger_actual_current=0, charger_phases=None, time_to_full_charge=0.42,
                      charge_port_door_open=True, battery_level=45, charge_energy_added=21.3,
                      charge_rate=610, fast_charger_present=True, fast_charger_type="Supercharger",
                      fast_charger_brand="Tesla")
    elif name == "cold":
        # A cold battery holds charge back, and the car is heating it.
        charge.update(usable_battery_level=65, battery_heater_on=True)
        car["climate_state"].update(outside_temp=-8.0, inside_temp=2.5, battery_heater=True)
    elif name == "dogmode":
        car["climate_state"].update(is_climate_on=True, climate_keeper_mode="dog", driver_temp_setting=20.5,
                                    inside_temp=20.5, outside_temp=31.0)
    elif name == "complete":
        charge.update(charging_state="Complete", battery_level=80, charge_port_door_open=True)
    elif name == "driving":
        drive.update(shift_state="D", speed=55, power=25, active_route_destination="Home",
                     active_route_minutes_to_arrival=12.0, active_route_miles_to_arrival=8.2,
                     active_route_energy_at_arrival=64, active_route_traffic_minutes_delay=1.5)
        vs.update(is_user_present=True)
    elif name == "open":
        vs.update(df=1, rt=1, locked=False)
    elif name == "unlocked":
        vs.update(locked=False)
    elif name == "update":
        vs["software_update"].update(status="available", version="2025.38.1")
    elif name == "scheduled":
        vs["software_update"].update(status="scheduled", version="2025.38.1",
                                     scheduled_time_ms=int((time.time() + 2 * 3600) * 1000))
    elif name == "installing":
        vs["software_update"].update(status="installing", version="2025.38.1", install_perc=40)
    elif name == "performance":
        car["vehicle_config"].update(trim_badging="p74d", wheel_type="Stiletto20", spoiler_type="Passive")
    elif name in ("asleep", "offline"):
        return name
    return "online"


KM_PER_MILE = 1.609344
PSI_PER_BAR = 14.503773800722


def teslamate_state(car):
    """The state TeslaMate would give the car."""
    if car["state"] in ("asleep", "offline"):
        return car["state"]
    if car["drive_state"].get("shift_state") in ("D", "R", "N"):
        return "driving"
    if car["charge_state"]["charging_state"] in ("Charging", "Starting"):
        return "charging"
    return "online"


def teslamate_api_status(car):
    """GET /api/v1/cars/1/status of TeslaMateApi, with TeslaMate set to km, bar and °C.
    Like TeslaMateApi, it sends every field, with Go's zero values for what it lacks."""
    c, cl, d, vs = car["charge_state"], car["climate_state"], car["drive_state"], car["vehicle_state"]
    doors = {"driver_front_door_open": vs["df"], "driver_rear_door_open": vs["dr"],
             "passenger_front_door_open": vs["pf"], "passenger_rear_door_open": vs["pr"]}
    windows = [vs["fd_window"], vs["fp_window"], vs["rd_window"], vs["rp_window"]]
    destination = d.get("active_route_destination") or ""
    update = vs["software_update"]
    status = {
        "display_name": car["display_name"],
        "state": teslamate_state(car),
        "state_since": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(State.started)),
        "odometer": round(vs["odometer"] * KM_PER_MILE, 2),
        "car_status": dict({k: bool(v) for k, v in doors.items()},
                           healthy=True, locked=vs["locked"], sentry_mode=vs["sentry_mode"],
                           windows_open=any(windows), doors_open=any(doors.values()),
                           trunk_open=bool(vs["rt"]), frunk_open=bool(vs["ft"]),
                           is_user_present=vs["is_user_present"], center_display_state=0),
        "car_details": {"model": "3", "trim_badging": car["vehicle_config"]["trim_badging"].upper()},
        "car_exterior": {"exterior_color": car["vehicle_config"]["exterior_color"],
                         "spoiler_type": car["vehicle_config"]["spoiler_type"],
                         "wheel_type": car["vehicle_config"]["wheel_type"]},
        "car_geodata": {"geofence": "Home" if teslamate_state(car) != "driving" else "",
                        "location": {"latitude": 52.52, "longitude": 13.405}, "latitude": 52.52, "longitude": 13.405},
        "car_versions": {"version": vs["car_version"].split()[0],
                         "update_available": update["status"] == "available",
                         "update_version": update.get("version") or ""},
        "driving_details": {
            "active_route": {"destination": destination,
                             "energy_at_arrival": d.get("active_route_energy_at_arrival") or 0,
                             # TeslaMateApi calls TeslaMate's miles_to_arrival this.
                             "distance_to_arrival": d.get("active_route_miles_to_arrival") or 0,
                             "minutes_to_arrival": d.get("active_route_minutes_to_arrival") or 0,
                             "traffic_minutes_delay": d.get("active_route_traffic_minutes_delay") or 0,
                             "location": {"latitude": 0, "longitude": 0}},
            "active_route_destination": destination, "active_route_latitude": 0, "active_route_longitude": 0,
            "shift_state": d.get("shift_state") or "P", "power": int(d.get("power") or 0),
            "speed": int((d.get("speed") or 0) * KM_PER_MILE), "heading": 120, "elevation": 34},
        "climate_details": {"is_climate_on": cl["is_climate_on"], "inside_temp": cl["inside_temp"],
                            "outside_temp": cl["outside_temp"], "is_preconditioning": cl["is_preconditioning"],
                            "climate_keeper_mode": cl.get("climate_keeper_mode") or "off"},
        "battery_details": {"est_battery_range": round(c["est_battery_range"] * KM_PER_MILE, 2),
                            "rated_battery_range": round(c["battery_range"] * KM_PER_MILE, 2),
                            "ideal_battery_range": round(c["ideal_battery_range"] * KM_PER_MILE, 2),
                            "battery_level": c["battery_level"], "usable_battery_level": c["usable_battery_level"]},
        "charging_details": {
            "plugged_in": c["charging_state"] != "Disconnected",
            "charging_state": c["charging_state"].lower(),
            "charge_energy_added": c["charge_energy_added"], "charge_limit_soc": c["charge_limit_soc"],
            "charge_port_door_open": c["charge_port_door_open"],
            "charger_actual_current": c["charger_actual_current"] or 0,
            "charger_phases": c["charger_phases"] or 0, "charger_power": c["charger_power"] or 0,
            "charger_voltage": c["charger_voltage"] or 0,
            "charge_current_request": c["charge_current_request"],
            "charge_current_request_max": c["charge_current_request_max"],
            "scheduled_charging_start_time": "0001-01-01T00:00:00Z",
            "time_to_full_charge": c["time_to_full_charge"]},
        "tpms_details": dict({"tpms_pressure_" + t: vs["tpms_pressure_" + t] for t in ("fl", "fr", "rl", "rr")},
                             **{"tpms_soft_warning_" + t: vs["tpms_soft_warning_" + t]
                                for t in ("fl", "fr", "rl", "rr")}),
    }
    return {"data": {"car": {"car_id": 1, "car_name": car["display_name"]}, "status": status,
                     "units": {"unit_of_length": "km", "unit_of_pressure": "bar", "unit_of_temperature": "C"}}}


def home_assistant_states(car):
    """GET /api/states of a Home Assistant in US units, with the car as its Teslemetry
    integration names it, and an unrelated phone and the sun."""
    c, cl, d, vs = car["charge_state"], car["climate_state"], car["drive_state"], car["vehicle_state"]
    prefix, name = "blue_thunder", car["display_name"]
    changed = time.strftime("%Y-%m-%dT%H:%M:%S+00:00", time.gmtime(State.started))
    entities = []

    def add(domain, key, label, state, unit=None, **attributes):
        if unit:
            attributes["unit_of_measurement"] = unit
        attributes["friendly_name"] = name + " " + label
        entities.append({"entity_id": "%s.%s_%s" % (domain, prefix, key), "attributes": attributes,
                         "state": "unknown" if state is None else str(state),
                         "last_changed": changed, "last_updated": changed})

    def on(value):
        return "on" if value else "off"

    awake = car["state"] not in ("asleep", "offline")
    add("binary_sensor", "status", "Status", on(awake), device_class="connectivity")
    add("sensor", "battery_level", "Battery level", c["battery_level"], "%")
    add("sensor", "usable_battery_level", "Usable battery level", c["usable_battery_level"], "%")
    add("sensor", "battery_range", "Battery range", c["battery_range"], "mi")
    add("sensor", "estimate_battery_range", "Estimate battery range", c["est_battery_range"], "mi")
    add("sensor", "ideal_battery_range", "Ideal battery range", c["ideal_battery_range"], "mi")
    add("number", "charge_limit", "Charge limit", c["charge_limit_soc"], "%")
    add("sensor", "charging", "Charging", c["charging_state"].lower().replace("nopower", "no_power"))
    add("sensor", "charger_power", "Charger power", c["charger_power"] or 0, "kW")
    add("sensor", "charger_voltage", "Charger voltage", c["charger_voltage"] or 0, "V")
    add("sensor", "charger_current", "Charger current", c["charger_actual_current"] or 0, "A")
    add("sensor", "charge_energy_added", "Charge energy added", c["charge_energy_added"], "kWh")
    add("sensor", "charge_rate", "Charge rate", c.get("charge_rate"), "mph")
    add("sensor", "fast_charger_type", "Fast charger type", c.get("fast_charger_type"))
    full = c["time_to_full_charge"]
    add("sensor", "time_to_full_charge", "Time to full charge",
        time.strftime("%Y-%m-%dT%H:%M:%S+00:00", time.gmtime(time.time() + full * 3600)) if full else None,
        device_class="timestamp")
    add("cover", "charge_port_door", "Charge port door", "open" if c["charge_port_door_open"] else "closed")
    keeper = cl.get("climate_keeper_mode") or "off"
    add("climate", "climate", "Climate", "heat_cool" if cl["is_climate_on"] else "off",
        preset_mode="keep" if keeper == "on" else keeper)
    setting = cl.get("driver_temp_setting")
    add("sensor", "driver_temperature_setting", "Driver temperature setting",
        None if setting is None else round(setting * 9 / 5 + 32, 1), "°F")
    add("sensor", "inside_temperature", "Inside temperature", round(cl["inside_temp"] * 9 / 5 + 32, 1), "°F")
    add("sensor", "outside_temperature", "Outside temperature", round(cl["outside_temp"] * 9 / 5 + 32, 1), "°F")
    add("sensor", "shift_state", "Shift state", (d.get("shift_state") or "").lower() or None)
    add("sensor", "speed", "Speed", d.get("speed") or 0, "mph")
    add("sensor", "power", "Power", d.get("power") or 0, "kW")
    add("sensor", "odometer", "Odometer", round(vs["odometer"], 1), "mi")
    add("lock", "lock", "Lock", "locked" if vs["locked"] else "unlocked")
    add("switch", "sentry_mode", "Sentry mode", on(vs["sentry_mode"]))
    add("binary_sensor", "user_present", "User present", on(vs["is_user_present"]))
    add("binary_sensor", "battery_heater", "Battery heater", on(c.get("battery_heater_on")))
    add("cover", "frunk", "Frunk", "open" if vs["ft"] else "closed")
    add("cover", "trunk", "Trunk", "open" if vs["rt"] else "closed")
    for key, label, value in (("front_driver", "Front driver", vs["df"]), ("rear_driver", "Rear driver", vs["dr"]),
                              ("front_passenger", "Front passenger", vs["pf"]),
                              ("rear_passenger", "Rear passenger", vs["pr"])):
        add("binary_sensor", key + "_door", label + " door", on(value))
    for key, label, value in (("front_driver", "Front driver", vs["fd_window"]),
                              ("rear_driver", "Rear driver", vs["rd_window"]),
                              ("front_passenger", "Front passenger", vs["fp_window"]),
                              ("rear_passenger", "Rear passenger", vs["rp_window"])):
        add("binary_sensor", key + "_window", label + " window", on(value))
    for key, label, tire in (("front_left", "front left", "fl"), ("front_right", "front right", "fr"),
                             ("rear_left", "rear left", "rl"), ("rear_right", "rear right", "rr")):
        add("sensor", "tire_pressure_" + key, "Tire pressure " + label,
            round(vs["tpms_pressure_" + tire] * PSI_PER_BAR, 1), "psi")
        add("binary_sensor", "tire_pressure_warning_" + key, "Tire pressure warning " + label,
            on(vs["tpms_soft_warning_" + tire]))
    update = vs["software_update"]
    add("update", "update", "Update", on(update["status"] == "available"),
        installed_version=vs["car_version"].split()[0], latest_version=update.get("version") or None,
        in_progress=False, update_percentage=None)
    add("sensor", "destination", "Destination", d.get("active_route_destination"))
    if d.get("active_route_destination"):
        add("sensor", "time_to_arrival", "Time to arrival",
            time.strftime("%Y-%m-%dT%H:%M:%S+00:00",
                          time.gmtime(time.time() + 60 * d["active_route_minutes_to_arrival"])),
            device_class="timestamp")
        add("sensor", "distance_to_arrival", "Distance to arrival", d["active_route_miles_to_arrival"], "mi")
        add("sensor", "state_of_charge_at_arrival", "State of charge at arrival",
            d["active_route_energy_at_arrival"], "%")
        add("sensor", "traffic_delay", "Traffic delay", d["active_route_traffic_minutes_delay"], "min")
    add("device_tracker", "location", "Location", "not_home" if d.get("shift_state") == "D" else "home",
        source_type="gps", latitude=52.52, longitude=13.405)
    entities.append({"entity_id": "sensor.pixel_8_battery_level", "state": "54",
                     "attributes": {"unit_of_measurement": "%", "friendly_name": "Pixel 8 Battery level"},
                     "last_changed": changed, "last_updated": changed})
    entities.append({"entity_id": "sun.sun", "state": "above_horizon", "attributes": {"friendly_name": "Sun"},
                     "last_changed": changed, "last_updated": changed})
    return entities


class State:
    scenario = "parked"
    started = time.time()
    access = "access-1"
    refresh = "refresh-1"
    serial = 1
    expire_first = False
    requests = 0
    client_secret = "fake-secret"
    fail_register = False
    # Authorization code -> the redirect URI it was issued for. Each code works once.
    codes = {}
    partner_tokens = set()
    domains = set()


class Handler(BaseHTTPRequestHandler):
    server_version = "fake-tesla-api"

    def reply(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def bearer(self):
        return self.headers.get("Authorization", "").removeprefix("Bearer ").strip()

    def authorized(self):
        token = self.bearer()
        if State.expire_first and token == "access-1":
            State.expire_first = False
            return False
        return token == State.access

    def car(self):
        car = copy.deepcopy(json.loads(FIXTURE.read_text())["response"])
        car["state"] = scenario(State.scenario, car)
        return car

    def authorize(self, query):
        """The sign-in page: signs in at once and sends the browser back with a code."""
        one = {k: v[0] for k, v in query.items()}
        redirect = one.get("redirect_uri", "")
        if not one.get("client_id") or not redirect or one.get("response_type") != "code" \
                or "openid" not in one.get("scope", "").split() or not one.get("state"):
            self.reply(400, {"error": "invalid_request",
                             "error_description": "client_id, redirect_uri, response_type=code, "
                                                  "scope with openid and state are required"})
            return
        code = "code-%d" % (len(State.codes) + 1)
        State.codes[code] = redirect
        separator = "&" if "?" in redirect else "?"
        self.send_response(302)
        self.send_header("Location", redirect + separator + urlencode({"code": code, "state": one["state"]}))
        self.send_header("Content-Length", "0")
        self.end_headers()

    def partner_key(self, query):
        if self.bearer() not in State.partner_tokens:
            self.reply(401, {"error": "invalid bearer token"})
            return
        domain = query.get("domain", [""])[0]
        if domain not in State.domains:
            self.reply(404, {"error": "not_found", "error_description": "no partner account for " + domain})
            return
        self.reply(200, {"response": {"public_key": "04" + "ab" * 64, "name": "Fake app"}})

    def do_GET(self):
        url = urlparse(self.path)
        path = url.path.rstrip("/")
        if path.startswith("/_scenario/"):
            State.scenario = path.split("/")[-1]
            self.reply(200, {"scenario": State.scenario})
            return
        if path == "/oauth2/v3/authorize":
            self.authorize(parse_qs(url.query))
            return
        if path == "/api/1/partner_accounts/public_key":
            self.partner_key(parse_qs(url.query))
            return
        if path.startswith("/api/v1/cars"):
            self.teslamate_api(path)
            return
        if path in ("/api", "/api/states") or path == "/vehicles" or path.startswith("/" + VIN):
            if not self.bearer():
                self.reply(401, {"message": "401: Unauthorized"})
            elif path == "/api":
                self.reply(200, {"message": "API running."})
            elif path == "/api/states":
                self.reply(200, home_assistant_states(self.car()))
            else:
                self.tessie(path)
            return
        State.requests += 1
        if not self.authorized():
            self.reply(401, {"error": "invalid bearer token"})
            return
        car = self.car()
        summary = {k: car[k] for k in ("id", "vehicle_id", "vin", "display_name", "state")}
        if path == "/api/1/vehicles":
            self.reply(200, {"response": [summary], "count": 1})
        elif path == "/api/1/vehicles/" + VIN:
            self.reply(200, {"response": summary})
        elif path == "/api/1/vehicles/" + VIN + "/vehicle_data":
            if car["state"] != "online":
                self.reply(408, {"response": None,
                                 "error": "vehicle unavailable: vehicle is offline or asleep",
                                 "error_description": ""})
                return
            car["drive_state"]["timestamp"] = int(time.time() * 1000)
            self.reply(200, {"response": car})
        elif path.startswith("/api/1/vehicles/"):
            self.reply(404, {"error": "not_found", "error_description": "no vehicle with that VIN"})
        else:
            self.reply(404, {"error": "not_found"})

    def teslamate_api(self, path):
        """TeslaMateApi, which sends its errors with HTTP 200."""
        car = self.car()
        if path == "/api/v1/cars":
            self.reply(200, {"data": {"cars": [{
                "car_id": 1, "name": car["display_name"],
                "car_details": {"eid": car["id"], "vid": car["vehicle_id"], "vin": VIN, "model": "3",
                                "trim_badging": car["vehicle_config"]["trim_badging"].upper(), "efficiency": 0.153},
                "car_exterior": {"exterior_color": car["vehicle_config"]["exterior_color"],
                                 "spoiler_type": car["vehicle_config"]["spoiler_type"],
                                 "wheel_type": car["vehicle_config"]["wheel_type"]}}]}})
        elif path == "/api/v1/cars/1/status":
            self.reply(200, teslamate_api_status(car))
        elif path.endswith("/status"):
            self.reply(200, {"error": "no info on this car ID"})
        else:
            self.reply(404, {"error": "not_found"})

    def tessie(self, path):
        """Tessie, which keeps the last state while the car sleeps."""
        car = self.car()
        if path == "/vehicles":
            self.reply(200, {"results": [{"vin": VIN, "is_active": True,
                                          "last_state": {"display_name": car["display_name"],
                                                         "state": car["state"], "vin": VIN}}]})
        elif path == "/" + VIN + "/state":
            self.reply(200, car)
        elif path == "/" + VIN + "/status":
            self.reply(200, {"status": "asleep" if car["state"] in ("asleep", "offline") else "awake"})
        elif path == "/" + VIN + "/location":
            driving = car["drive_state"].get("shift_state") == "D"
            self.reply(200, {"latitude": 52.52, "longitude": 13.405, "address": "1 Example Street",
                             "saved_location": None if driving else "Home"})
        else:
            self.reply(404, {"error": "Vehicle not found"})

    def issue(self):
        """New user tokens. Like Tesla, this invalidates the old ones."""
        State.serial += 1
        State.access = "access-%d" % State.serial
        State.refresh = "refresh-%d" % State.serial
        self.reply(200, {"access_token": State.access, "refresh_token": State.refresh,
                         "expires_in": 28800, "token_type": "Bearer"})

    def token(self, form):
        one = {k: v[0] for k, v in form.items()}
        grant = one.get("grant_type", "")
        if not one.get("client_id"):
            self.reply(400, {"error": "invalid_request", "error_description": "client_id is required"})
        elif grant == "refresh_token":
            if one.get("refresh_token") != State.refresh:
                self.reply(401, {"error": "invalid_grant", "error_description": "refresh token is not valid"})
            else:
                self.issue()
        elif one.get("client_secret") != State.client_secret:
            self.reply(401, {"error": "invalid_client", "error_description": "client secret is not valid"})
        elif not one.get("audience"):
            self.reply(400, {"error": "invalid_request", "error_description": "audience is required"})
        elif grant == "authorization_code":
            redirect = State.codes.pop(one.get("code", ""), None)
            if redirect is None:
                self.reply(400, {"error": "invalid_grant", "error_description": "authorization code is not valid"})
            elif redirect != one.get("redirect_uri"):
                self.reply(400, {"error": "invalid_grant", "error_description": "redirect_uri does not match"})
            else:
                self.issue()
        elif grant == "client_credentials":
            token = "partner-%d" % (len(State.partner_tokens) + 1)
            State.partner_tokens.add(token)
            self.reply(200, {"access_token": token, "expires_in": 28800, "token_type": "Bearer"})
        else:
            self.reply(400, {"error": "unsupported_grant_type"})

    def register(self, body):
        if self.bearer() not in State.partner_tokens:
            self.reply(401, {"error": "invalid bearer token"})
            return
        try:
            domain = json.loads(body or "{}").get("domain", "")
        except ValueError:
            domain = ""
        if not domain:
            self.reply(400, {"error": "invalid_request", "error_description": "domain is required"})
        elif State.fail_register:
            self.reply(400, {"error": "invalid_domain",
                             "error_description": "Root domain %s must match registered allowed origin" % domain})
        else:
            State.domains.add(domain)
            self.reply(200, {"response": {"domain": domain, "public_key": "04" + "ab" * 64}})

    def do_POST(self):
        path = urlparse(self.path).path.rstrip("/")
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length).decode()
        if path == "/oauth2/v3/token":
            self.token(parse_qs(body))
        elif path == "/api/1/partner_accounts":
            self.register(body)
        else:
            self.reply(404, {"error": "not_found"})

    def log_message(self, fmt, *args):
        sys.stderr.write("[%s] %s (%d API requests)\n" % (State.scenario, fmt % args, State.requests))


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("-p", "--port", type=int, default=8765)
    parser.add_argument("-s", "--scenario", default="parked")
    parser.add_argument("--expire-first", action="store_true",
                        help="refuse the first access token once, to exercise renewal")
    parser.add_argument("--client-secret", default=State.client_secret,
                        help="the client secret the sign-in grants require")
    parser.add_argument("--fail-register", action="store_true",
                        help="refuse partner registration as a domain mismatch")
    args = parser.parse_args()
    State.scenario = args.scenario
    State.expire_first = args.expire_first
    State.client_secret = args.client_secret
    State.fail_register = args.fail_register
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print("Fake Tesla API on http://localhost:%d, VIN %s" % (args.port, VIN), file=sys.stderr)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
