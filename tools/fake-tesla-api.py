#!/usr/bin/env python3
"""Serves made-up Tesla Fleet API replies, so the widget's Tesla API source can be tried
without a car, without a Tesla account and without being billed.

Set the widget's Region to Custom URL with http://localhost:8765 (or the port given),
paste "access-1" as the access token, "refresh-1" as the refresh token, "fake" as the
client ID and http://localhost:8765 as the token server, and use Find Cars.

The car's state is the vehicle_data fixture in tests/fixtures, changed by a scenario.
Switch scenarios while it runs:

    curl http://localhost:8765/_scenario/charging

Scenarios: parked, charging, complete, driving, open, unlocked, update, asleep, offline.
With --expire-first, the first access token is refused once, so the widget has to renew.
Only one token is valid at a time, as with Tesla: renewing invalidates the old ones.

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
    if name == "charging":
        charge.update(charging_state="Charging", charger_power=11, charger_voltage=230,
                      charger_actual_current=16, charger_phases=3, time_to_full_charge=1.25,
                      charge_port_door_open=True, battery_level=60)
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
    elif name in ("asleep", "offline"):
        return name
    return "online"


class State:
    scenario = "parked"
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
