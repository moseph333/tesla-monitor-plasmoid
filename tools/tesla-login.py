#!/usr/bin/env python3
"""Gets Tesla Fleet API tokens for the widget, and registers a Fleet API app.

The widget's Tesla Fleet API source signs in with pasted tokens. This gets them:

    tools/tesla-login.py register --domain example.com   # once per app and region
    tools/tesla-login.py login                           # prints what to paste

It needs an app registered at developer.tesla.com, with your domain as its allowed
origin, http://localhost:8585/callback as a redirect URI and the vehicle data scope, and
the app's public key hosted on that domain. Give the app's client ID with --client-id or
TESLA_CLIENT_ID. The client secret comes from TESLA_CLIENT_SECRET, or is asked for, so it
never shows in the shell's history or the process list.

Signing in happens in the browser: this never sees your Tesla password. Tokens are only
printed, never saved. Progress goes to stderr, so `login --json` can be piped.
"""

import argparse
import getpass
import html
import http.server
import json
import os
import re
import secrets
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser

# The same regions, in the same order, as the widget's Region setting (teslaapi.js).
REGIONS = {
    "na": ("North America, Asia-Pacific", "https://fleet-api.prd.na.vn.cloud.tesla.com"),
    "eu": ("Europe, Middle East, Africa", "https://fleet-api.prd.eu.vn.cloud.tesla.com"),
    "cn": ("China", "https://fleet-api.prd.cn.vn.cloud.tesla.cn"),
}
AUTH_URL = "https://auth.tesla.com"
TOKEN_URL = "https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token"
# China's accounts sign in, and get and renew their tokens, on a server of their own.
REGION_AUTH = {"cn": ("https://auth.tesla.cn", "https://auth.tesla.cn/oauth2/v3/token")}
# offline_access is what gives a refresh token, so the widget can renew the access token.
SCOPE = "openid offline_access vehicle_device_data"
DEFAULT_REDIRECT = "http://localhost:8585/callback"
KEY_PATH = "/.well-known/appspecific/com.tesla.3p.public-key.pem"
LOCAL_HOSTS = ("localhost", "127.0.0.1")
# How long the sign-in listener waits for a connected browser to send its request.
REQUEST_TIMEOUT = 10


class LoginError(Exception):
    """A failure worded for the person running the script."""


# ---------- pure helpers ----------

def printable(text):
    """Text from a server, safe to print to a terminal: control characters, which could
    move the cursor or rewrite what was printed before, become spaces."""
    return re.sub(r"[\x00-\x1f\x7f-\x9f]+", " ", str(text)).strip()


def callback_params(text):
    """The first value of each parameter in a callback address (or just its query)."""
    text = text.strip().split("#", 1)[0]
    # A whole address, with or without its scheme, or just the query.
    query = text.split("?", 1)[1] if "?" in text else text
    return {key: values[0] for key, values in urllib.parse.parse_qs(query).items()}

def authorize_url(auth_url, client_id, redirect_uri, state, nonce):
    """The address of Tesla's sign-in page for this app."""
    query = urllib.parse.urlencode({
        "response_type": "code",
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "scope": SCOPE,
        "state": state,
        "nonce": nonce,
        "prompt_missing_scopes": "true",
    }, quote_via=urllib.parse.quote)
    return auth_url.rstrip("/") + "/oauth2/v3/authorize?" + query


def parse_callback(text, state):
    """The code from the address the browser was sent back to (or just its query).
    Raises LoginError for a refusal, a state that isn't ours, or no code."""
    one = callback_params(text)
    if "error" in one:
        detail = one.get("error_description") or one["error"]
        raise LoginError("Tesla didn't sign you in: %s" % printable(detail))
    if one.get("state") != state:
        raise LoginError("The sign-in reply doesn't belong to this sign-in (its state doesn't match). "
                         "Start again, and use the newest sign-in address.")
    if not one.get("code"):
        raise LoginError("The address has no sign-in code. Paste the whole address the browser ended up on.")
    return one["code"]


def ends_sign_in(params, state):
    """Whether a request to the callback answers this sign-in, so waiting should end. One
    carrying another state, such as a tab from an earlier sign-in reloaded, is turned away
    without ending it. Tesla's refusal ends it even without a state."""
    if "state" in params:
        return params["state"] == state
    return "error" in params


def check_redirect(redirect_uri):
    """The (port, path) to listen on for a local redirect URI, or LoginError."""
    parts = urllib.parse.urlsplit(redirect_uri)
    if parts.scheme != "http" or parts.hostname not in LOCAL_HOSTS:
        raise LoginError("Only an http://localhost redirect URI can be caught here. For %s, use --manual."
                         % redirect_uri)
    return parts.port or 80, parts.path or "/"


def looks_like_public_key(text):
    """Whether text is a PEM public key, as Tesla wants hosted for the app's domain."""
    return "-----BEGIN PUBLIC KEY-----" in text and "-----END PUBLIC KEY-----" in text


def describe_error(status, body):
    """An HTTP failure from Tesla in words. status 0 means no reply."""
    detail = ""
    code = ""
    if isinstance(body, dict):
        code = str(body.get("error") or "")
        detail = printable(body.get("error_description") or code)[:500]
    elif body:
        detail = printable(body)[:200]
    if status == 0:
        return "Couldn't reach Tesla: %s" % (detail or "no reply")
    if code == "invalid_client" or (status == 401 and "secret" in detail.lower()):
        return "Tesla refused the client ID or client secret. Copy them again from developer.tesla.com."
    if code == "invalid_grant" and "redirect" in detail.lower():
        return "The redirect URI doesn't match the one the app has at developer.tesla.com: %s" % detail
    if code == "invalid_grant":
        return "Tesla refused the sign-in code, which only works once and only briefly. Sign in again. (%s)" % detail
    if status == 412 or "register" in detail.lower():
        return "The app isn't registered in this region. Run the register command first. (%s)" % detail
    if status == 421:
        return "The account belongs to another region. Try a different --region."
    return "Tesla answered %d: %s" % (status, detail or "no details")


def tokens_from(reply, now):
    """A token reply as {access, refresh, expires_at (ms)}, or LoginError."""
    if not isinstance(reply, dict) or not reply.get("access_token"):
        raise LoginError("Tesla's token reply has no access token.")
    seconds = reply.get("expires_in")
    seconds = seconds if isinstance(seconds, (int, float)) else 8 * 3600
    return {
        "access": reply["access_token"],
        "refresh": reply.get("refresh_token") or "",
        "expires_at": int((now + seconds) * 1000),
    }


def vehicles_from(reply):
    """GET /api/1/vehicles as [{vin, name}]."""
    listing = reply.get("response") if isinstance(reply, dict) else None
    if not isinstance(listing, list):
        return []
    return [{"vin": printable(v["vin"]), "name": printable(v.get("display_name") or "")}
            for v in listing if isinstance(v, dict) and v.get("vin")]


def region_label(region, api_url):
    name, base = REGIONS[region]
    return name if api_url.rstrip("/") == base else "Custom URL: %s" % api_url


def format_result(region, api_url, client_id, tokens, vehicles):
    """What to paste into the widget's Connection settings."""
    expires = time.strftime("%Y-%m-%d %H:%M", time.localtime(tokens["expires_at"] / 1000))
    rows = [
        ("Data source", "Tesla Fleet API"),
        ("Region", region_label(region, api_url)),
        ("Access token", tokens["access"]),
        ("Refresh token", tokens["refresh"] or "(none: the app wasn't given offline_access)"),
        ("Client ID", client_id),
    ]
    if vehicles:
        for car in vehicles:
            rows.append(("VIN", car["vin"] + (" (%s)" % car["name"] if car["name"] else "")))
    else:
        rows.append(("VIN", "(use Find Cars in the widget's settings)"))
    width = max(len(label) for label, _ in rows) + 2
    lines = ["Signed in. Paste these into the widget's settings, on the Connection page:", ""]
    lines += ["  %s%s" % ((label + ":").ljust(width), value) for label, value in rows]
    lines += ["", "The access token expires at %s. With the refresh token and client ID, the widget "
              "renews it itself." % expires if tokens["refresh"] else
              "The access token expires at %s, and can't be renewed without a refresh token." % expires,
              "Keep the tokens secret: they give access to the car's data."]
    return "\n".join(lines)


def result_json(region, api_url, client_id, tokens, vehicles):
    return json.dumps({
        "region": region,
        "api_url": api_url,
        "access_token": tokens["access"],
        "refresh_token": tokens["refresh"],
        "client_id": client_id,
        "expires_at": tokens["expires_at"],
        "vehicles": vehicles,
    }, indent=2)


# ---------- I/O ----------

def say(text):
    print(text, file=sys.stderr, flush=True)


def http_json(method, url, form=None, body=None, token=None, timeout=30):
    """(status, reply) for one request. reply is parsed JSON, or text. status 0: no reply."""
    data = None
    headers = {"Accept": "application/json", "User-Agent": "tesla-monitor-login"}
    if form is not None:
        data = urllib.parse.urlencode(form).encode()
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    elif body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = "Bearer " + token
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as reply:
            status, text = reply.status, reply.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        status, text = error.code, error.read().decode("utf-8", "replace")
    except (urllib.error.URLError, OSError) as error:
        return 0, str(getattr(error, "reason", error))
    try:
        return status, json.loads(text)
    except ValueError:
        return status, text


def request_ok(method, url, **kwargs):
    status, reply = http_json(method, url, **kwargs)
    if not 200 <= status < 300:
        raise LoginError(describe_error(status, reply))
    return reply


def client_secret():
    secret = os.environ.get("TESLA_CLIENT_SECRET", "").strip()
    if secret:
        return secret
    if not sys.stdin.isatty():
        raise LoginError("Set TESLA_CLIENT_SECRET, or run this in a terminal to be asked for the client secret.")
    secret = getpass.getpass("Client secret (from developer.tesla.com): ").strip()
    if not secret:
        raise LoginError("The client secret is needed.")
    return secret


def wait_for_callback(redirect_uri, state, timeout, url, open_browser):
    """Listens for the browser's return from the sign-in page and gives back the code."""
    port, path = check_redirect(redirect_uri)
    result = {}

    class Handler(http.server.BaseHTTPRequestHandler):
        # A browser that connects but sends nothing can't hold up the deadline.
        timeout = REQUEST_TIMEOUT

        def do_GET(self):
            parts = urllib.parse.urlsplit(self.path)
            if parts.path != path:
                self.send_error(404)
                return
            if not ends_sign_in(callback_params(parts.query), state):
                status, message = 400, ("This reply doesn't belong to the sign-in that's waiting. "
                                        "Use the newest sign-in address from the terminal.")
            else:
                try:
                    result["code"] = parse_callback(parts.query, state)
                    status, message = 200, "Signed in. You can close this tab and go back to the terminal."
                except LoginError as error:
                    result["error"] = str(error)
                    status, message = 400, str(error)
            page = ("<!doctype html><meta charset=utf-8><title>Tesla Monitor</title>"
                    "<p style='font:16px sans-serif;margin:2em'>%s</p>" % html.escape(message)).encode()
            self.send_response(status)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(page)))
            # The address holds the sign-in code, so the page isn't kept or passed on.
            self.send_header("Cache-Control", "no-store")
            self.send_header("Referrer-Policy", "no-referrer")
            self.end_headers()
            self.wfile.write(page)

        def log_message(self, fmt, *args):
            pass

    try:
        server = http.server.HTTPServer(("127.0.0.1", port), Handler)
    except OSError as error:
        raise LoginError("Can't listen on port %d for the sign-in reply: %s. Use another port in "
                         "--redirect-uri (and in the app's settings), or --manual." % (port, error))
    with server:
        server.timeout = 1
        say("Sign in to Tesla in your browser. If it doesn't open, go to:\n\n  %s\n" % url)
        if open_browser:
            webbrowser.open(url)
        deadline = time.monotonic() + timeout
        while "code" not in result and "error" not in result:
            if time.monotonic() > deadline:
                raise LoginError("No sign-in reply within %d seconds. Run login again." % timeout)
            server.handle_request()
    if "error" in result:
        raise LoginError(result["error"])
    return result["code"]


def manual_code(url, state):
    say("Open this address, sign in, and copy the address the browser ends up on, even if the page "
        "doesn't load:\n\n  %s\n" % url)
    # The prompt goes to stderr, like all progress, so --json output stays clean.
    sys.stderr.write("Address: ")
    sys.stderr.flush()
    pasted = sys.stdin.readline()
    if not pasted.strip():
        raise LoginError("No address was pasted.")
    return parse_callback(pasted, state)


def api_url_of(args):
    return (args.api_url or REGIONS[args.region][1]).rstrip("/")


def auth_urls_of(args):
    """The sign-in page's base and the token endpoint: the region's, unless given."""
    auth_url, token_url = REGION_AUTH.get(args.region, (AUTH_URL, TOKEN_URL))
    return args.auth_url or auth_url, args.token_url or token_url


def run_register(args, client_id):
    api_url = api_url_of(args)
    domain = args.domain.strip().lower()
    domain = urllib.parse.urlsplit(domain).hostname if "://" in domain else domain.strip("/")
    if not args.skip_key_check:
        key_url = "https://%s%s" % (domain, KEY_PATH)
        say("Checking the public key at %s…" % key_url)
        status, reply = http_json("GET", key_url)
        if status != 200 or not isinstance(reply, str) or not looks_like_public_key(reply):
            raise LoginError(
                "Tesla needs the app's public key at %s, and it isn't there (%s). Make a key pair with\n"
                "  openssl ecparam -name prime256v1 -genkey -noout -out private-key.pem\n"
                "  openssl ec -in private-key.pem -pubout -out com.tesla.3p.public-key.pem\n"
                "host the public one at that address, and keep the private one to yourself."
                % (key_url, "HTTP %d" % status if status else reply))
    secret = client_secret()
    say("Getting a partner token…")
    partner = request_ok("POST", auth_urls_of(args)[1], form={
        "grant_type": "client_credentials", "client_id": client_id, "client_secret": secret,
        "audience": api_url, "scope": "openid vehicle_device_data"})
    partner_token = partner.get("access_token") if isinstance(partner, dict) else None
    if not partner_token:
        raise LoginError("Tesla's partner token reply has no token.")
    say("Registering %s…" % domain)
    request_ok("POST", api_url + "/api/1/partner_accounts", body={"domain": domain}, token=partner_token)
    request_ok("GET", api_url + "/api/1/partner_accounts/public_key?" + urllib.parse.urlencode({"domain": domain}),
               token=partner_token)
    print("Registered %s with the Fleet API (%s). Now run: tools/tesla-login.py login%s"
          % (domain, region_label(args.region, api_url), "" if args.region == "na" else " --region " + args.region))


def run_login(args, client_id):
    api_url = api_url_of(args)
    if not args.manual:
        check_redirect(args.redirect_uri)
    secret = client_secret()
    state = secrets.token_urlsafe(24)
    auth_url, token_url = auth_urls_of(args)
    url = authorize_url(auth_url, client_id, args.redirect_uri, state, secrets.token_urlsafe(16))
    code = (manual_code(url, state) if args.manual
            else wait_for_callback(args.redirect_uri, state, args.timeout, url, not args.no_browser))
    say("Getting tokens…")
    reply = request_ok("POST", token_url, form={
        "grant_type": "authorization_code", "client_id": client_id, "client_secret": secret,
        "code": code, "audience": api_url, "redirect_uri": args.redirect_uri})
    tokens = tokens_from(reply, time.time())
    vehicles = []
    if not args.no_vehicles:
        # One billed request, to fill in the VIN.
        status, listing = http_json("GET", api_url + "/api/1/vehicles", token=tokens["access"])
        if 200 <= status < 300:
            vehicles = vehicles_from(listing)
        else:
            say("Couldn't list the cars: %s" % describe_error(status, listing))
    print(result_json(args.region, api_url, client_id, tokens, vehicles) if args.json
          else format_result(args.region, api_url, client_id, tokens, vehicles))


def parse_args(argv):
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--client-id", default=os.environ.get("TESLA_CLIENT_ID", ""),
                        help="the app's client ID (default: $TESLA_CLIENT_ID)")
    common.add_argument("--region", choices=sorted(REGIONS), default="na",
                        help="na: North America and Asia-Pacific (default), eu: Europe, Middle East "
                             "and Africa, cn: China")
    # For the fake server in tools/, and for services with the same API.
    common.add_argument("--api-url", help=argparse.SUPPRESS)
    common.add_argument("--auth-url", help=argparse.SUPPRESS)
    common.add_argument("--token-url", help=argparse.SUPPRESS)

    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0],
                                     epilog="Run a command with --help for its options.")
    commands = parser.add_subparsers(dest="command", required=True)
    register = commands.add_parser("register", parents=[common],
                                   help="register the app with the Fleet API, once per region")
    register.add_argument("--domain", required=True, help="the app's domain, which hosts its public key")
    register.add_argument("--skip-key-check", action="store_true",
                          help="don't fetch the public key first (Tesla still checks it)")
    login = commands.add_parser("login", parents=[common],
                                help="sign in to Tesla and print the tokens for the widget")
    login.add_argument("--redirect-uri", default=DEFAULT_REDIRECT,
                       help="one of the app's redirect URIs (default: %s)" % DEFAULT_REDIRECT)
    login.add_argument("--manual", action="store_true",
                       help="paste the address the browser ends up on, instead of catching it")
    login.add_argument("--no-browser", action="store_true", help="only print the sign-in address")
    login.add_argument("--no-vehicles", action="store_true", help="don't list the account's cars")
    login.add_argument("--json", action="store_true", help="print the result as JSON")
    login.add_argument("--timeout", type=int, default=300, help="seconds to wait for the sign-in (default 300)")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)
    client_id = args.client_id.strip()
    try:
        if not client_id:
            raise LoginError("Give the app's client ID with --client-id or TESLA_CLIENT_ID.")
        if args.command == "register":
            run_register(args, client_id)
        else:
            run_login(args, client_id)
    except LoginError as error:
        say("Error: %s" % error)
        return 1
    except KeyboardInterrupt:
        say("Cancelled.")
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
