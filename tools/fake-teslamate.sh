#!/bin/sh
# Publishes made-up TeslaMate values to an MQTT broker, so the widget can be tried
# without a car, and in states a real car is rarely in. The values are retained, as
# TeslaMate's are, so the widget's next poll sees them. Each scenario changes only the
# values it names, so scenarios combine: "parked charging", then "stopped".
#
# Use a broker of your own, such as `mosquitto -p 1884 -v`, so nothing lands on a real
# TeslaMate's topics.
set -eu

host=localhost
port=1883
prefix=teslamate/cars/1

usage() {
    cat <<'EOF'
Usage: fake-teslamate.sh [-h host] [-p port] [-t prefix] scenario...

Publishes made-up TeslaMate values as retained MQTT messages, by default to
localhost, port 1883, under teslamate/cars/1. Scenarios run in the order given,
and each changes only its own values, so start with "parked".

  parked          parked and locked, everything closed; resets what the others set
  charging        charging at 11 kW on three phases, 60%
  complete        charging finished at the 80% limit
  stopped         charging stopped before the limit
  nopower         plugged in, but the charger has no power
  scheduled       plugged in, waiting for a scheduled start in 3 hours
  open, close     the driver's door and the trunk open, or closed
  unlock, lock    the car unlocked, or locked
  present, away   someone in the car, or nobody
  home            the car in a geofence called Home
  tires           low pressure in the front left tire
  tires-empty     the front left tire's warning published empty
  update          a software update available
  downloading     the update downloading, 45%
  installing      the update installing, 30%
  driving         driving at 88 km/h, drawing 25 kW
  regen           driving and regenerating 12 kW
  route, noroute  navigating to Home, or not navigating
  cold            a cold battery: 72%, of which 65% is usable
  unhealthy       TeslaMate having trouble reaching the car
  service         service mode on
  asleep          the car asleep
  car2            a second car, on the next car id, for Find Cars
  clear           remove every value this script publishes
EOF
}

while getopts h:p:t: opt; do
    case $opt in
    h) host=$OPTARG ;;
    p) port=$OPTARG ;;
    t) prefix=${OPTARG%/} ;;
    *) usage >&2; exit 2 ;;
    esac
done
shift $((OPTIND - 1))

if [ $# -eq 0 ]; then
    usage >&2
    exit 2
fi
# Every name is checked first, so a typo doesn't leave the car half changed.
for name in "$@"; do
    case $name in
    parked | charging | complete | stopped | nopower | scheduled | open | close | unlock | lock | \
        present | away | home | tires | tires-empty | update | downloading | installing | \
        driving | regen | route | noroute | cold | unhealthy | service | asleep | car2 | clear) ;;
    *)
        echo "fake-teslamate.sh: unknown scenario: $name" >&2
        usage >&2
        exit 2
        ;;
    esac
done
if ! command -v mosquitto_pub >/dev/null 2>&1; then
    echo "fake-teslamate.sh: needs mosquitto_pub, from the mosquitto or mosquitto-clients package" >&2
    exit 1
fi

# The car the values go to: the prefix, or the second car while car2 runs.
base=$prefix

pub() {
    mosquitto_pub -h "$host" -p "$port" -r -t "$base/$1" -m "$2"
}

# An empty retained message removes the value, which is how TeslaMate clears one.
drop() {
    mosquitto_pub -h "$host" -p "$port" -r -n -t "$base/$1"
}

now() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}

# A time some hours ahead, with GNU or BSD date. Other date commands can't count forward,
# so the time is then now, which still reads as a scheduled charge.
later() {
    date -u -d "+$1 hours" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || date -u -v "+$1H" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || now
}

# A new state, and when it began, as TeslaMate publishes them together.
state() {
    pub since "$(now)"
    pub state "$1"
}

# The battery level and the usable level, which differs only when the battery is cold,
# with ranges to match. awk does the decimals, which sh can't, in the C locale so the
# decimal point stays a point.
battery() {
    pub battery_level "$1"
    pub usable_battery_level "${2:-$1}"
    pub rated_battery_range_km "$(LC_ALL=C awk -v l="$1" 'BEGIN { printf "%.2f", l * 5.02 }')"
    pub est_battery_range_km "$(LC_ALL=C awk -v l="$1" 'BEGIN { printf "%.2f", l * 4.41 }')"
    pub ideal_battery_range_km "$(LC_ALL=C awk -v l="$1" 'BEGIN { printf "%.2f", l * 5.18 }')"
}

# The cable out, with the charge values TeslaMate shows between charges.
unplugged() {
    pub charging_state Disconnected
    pub plugged_in false
    pub charge_port_door_open false
    pub charger_power 0
    pub charger_actual_current 0
    pub charger_voltage 0
    drop charger_phases
    pub charge_current_request 32
    pub charge_current_request_max 32
    pub time_to_full_charge 0
    drop scheduled_charging_start_time
}

# Plugged in and not drawing power, with the charging state given.
plugged() {
    state online
    pub plugged_in true
    pub charge_port_door_open true
    pub charger_power 0
    pub charger_actual_current 0
    pub charger_voltage 0
    drop charger_phases
    pub time_to_full_charge 0
    pub charging_state "$1"
}

# Driving, with the battery's power in kW, negative while regenerating.
drive() {
    unplugged
    pub locked true
    pub is_user_present true
    drop geofence
    pub shift_state D
    pub speed 88
    pub power "$1"
    state driving
}

PARTS="driver_front driver_rear passenger_front passenger_rear"
TIRES="fl fr rl rr"

# Every value this script publishes, for clear.
keys() {
    echo display_name exterior_color state since healthy version update_available update_version \
        download_perc install_perc geofence shift_state speed power locked sentry_mode \
        is_user_present doors_open windows_open frunk_open trunk_open sun_roof_installed \
        sun_roof_percent_open is_climate_on is_preconditioning inside_temp outside_temp \
        odometer battery_level usable_battery_level rated_battery_range_km \
        est_battery_range_km ideal_battery_range_km charge_limit_soc plugged_in \
        charge_port_door_open charging_state charge_energy_added charger_power \
        charger_actual_current charger_voltage charger_phases charge_current_request \
        charge_current_request_max scheduled_charging_start_time time_to_full_charge \
        active_route service_mode
    for part in $PARTS; do echo "${part}_door_open ${part}_window_open"; done
    for tire in $TIRES; do echo "tpms_pressure_$tire tpms_soft_warning_$tire"; done
}

# The car id after the prefix's own, under the same namespace, or 2 if the prefix doesn't
# end in a number.
second_car() {
    id=${prefix##*/}
    case $id in
    '' | *[!0-9]*) echo "${prefix%/*}/2" ;;
    *) echo "${prefix%/*}/$((id + 1))" ;;
    esac
}

scenario() {
    case $1 in
    parked)
        pub display_name "Fake Model 3"
        pub exterior_color DeepBlue
        state online
        # TeslaMate 2.1 and newer don't retain healthy, so it's removed, as there. The card
        # keeps a warning from unhealthy for 10 minutes, as it does with a real TeslaMate.
        drop healthy
        pub version 2024.44.25
        pub update_available false
        drop update_version
        pub download_perc 0
        pub install_perc 0
        pub service_mode false
        drop geofence
        drop shift_state
        drop speed
        pub power 0
        pub locked true
        pub sentry_mode false
        pub is_user_present false
        for part in $PARTS; do
            pub "${part}_door_open" false
            pub "${part}_window_open" false
        done
        pub doors_open false
        pub windows_open false
        pub frunk_open false
        pub trunk_open false
        pub sun_roof_installed false
        drop sun_roof_percent_open
        pub is_climate_on false
        pub is_preconditioning false
        pub inside_temp 21.5
        pub outside_temp 12.0
        pub odometer 42137.52
        battery 72
        pub charge_limit_soc 80
        pub charge_energy_added 0
        unplugged
        for tire in $TIRES; do
            pub "tpms_pressure_$tire" 2.9
            pub "tpms_soft_warning_$tire" false
        done
        pub active_route '{"error":"No active route available"}'
        ;;
    charging)
        battery 60
        drop scheduled_charging_start_time
        pub plugged_in true
        pub charge_port_door_open true
        pub charger_power 11
        pub charger_actual_current 16
        pub charger_voltage 230
        pub charger_phases 3
        pub charge_current_request 16
        pub charge_current_request_max 32
        pub charge_energy_added 4.2
        pub time_to_full_charge 1.5
        pub charging_state Charging
        state charging
        ;;
    complete)
        drop scheduled_charging_start_time
        battery 80
        plugged Complete
        ;;
    stopped)
        drop scheduled_charging_start_time
        plugged Stopped
        ;;
    nopower)
        drop scheduled_charging_start_time
        plugged NoPower
        ;;
    scheduled)
        # The start time goes first, so no poll sees Stopped without it, which would read as
        # a charge that stopped early.
        pub scheduled_charging_start_time "$(later 3)"
        plugged Stopped
        ;;
    open)
        pub driver_front_door_open true
        pub doors_open true
        pub trunk_open true
        ;;
    close)
        pub driver_front_door_open false
        pub doors_open false
        pub trunk_open false
        ;;
    unlock) pub locked false ;;
    lock) pub locked true ;;
    present) pub is_user_present true ;;
    away) pub is_user_present false ;;
    home) pub geofence Home ;;
    tires)
        pub tpms_pressure_fl 2.1
        pub tpms_soft_warning_fl true
        ;;
    tires-empty) drop tpms_soft_warning_fl ;;
    # The version goes before update_available, so no poll sees an update without one,
    # which the widget would count as a different update.
    # The car often reports a leftover install_perc of 1 while an update is only available.
    update)
        pub update_version 2024.45.32
        pub download_perc 0
        pub install_perc 1
        pub update_available true
        ;;
    downloading)
        pub update_version 2024.45.32
        pub download_perc 45
        pub install_perc 0
        pub update_available true
        ;;
    installing)
        pub update_version 2024.45.32
        pub download_perc 100
        pub install_perc 30
        pub update_available true
        state updating
        ;;
    driving) drive 25 ;;
    regen) drive -12 ;;
    route)
        pub active_route '{"destination":"Home","energy_at_arrival":58.4,"miles_to_arrival":12.6,"minutes_to_arrival":23.5,"traffic_minutes_delay":4.2,"location":{"latitude":52.52,"longitude":13.405},"error":null}'
        ;;
    noroute) pub active_route '{"error":"No active route available"}' ;;
    cold) battery 72 65 ;;
    unhealthy) pub healthy false ;;
    service) pub service_mode true ;;
    asleep)
        drop shift_state
        drop speed
        pub power 0
        pub is_user_present false
        state asleep
        ;;
    car2)
        base=$(second_car)
        pub display_name "Fake Model Y"
        state asleep
        battery 54
        pub charge_limit_soc 90
        base=$prefix
        ;;
    clear)
        for base in "$prefix" "$(second_car)"; do
            for key in $(keys); do drop "$key"; done
        done
        base=$prefix
        ;;
    esac
}

for name in "$@"; do
    scenario "$name"
    echo "$name: done"
done
