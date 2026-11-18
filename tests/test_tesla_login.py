"""Tests for tools/tesla-login.py. Run with `make test`.

The end-to-end tests run the script against tools/fake-tesla-api.py on free local ports.
"""

import importlib.util
import json
import os
import pathlib
import socket
import subprocess
import sys
import time
import unittest
import urllib.error
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
LOGIN = ROOT / "tools" / "tesla-login.py"
FAKE = ROOT / "tools" / "fake-tesla-api.py"

spec = importlib.util.spec_from_file_location("tesla_login", LOGIN)
login = importlib.util.module_from_spec(spec)
spec.loader.exec_module(login)

# Local requests must not go through a proxy from the environment.
DIRECT = urllib.request.build_opener(urllib.request.ProxyHandler({}))


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


NO_REDIRECT = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect)


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class PureTests(unittest.TestCase):
    def test_authorize_url(self):
        url = login.authorize_url("https://auth.example/", "my id", "http://localhost:8585/callback", "st", "no")
        parts = urllib.parse.urlsplit(url)
        self.assertEqual(parts.scheme + "://" + parts.netloc + parts.path, "https://auth.example/oauth2/v3/authorize")
        query = dict(urllib.parse.parse_qsl(parts.query))
        self.assertEqual(query, {
            "response_type": "code", "client_id": "my id", "redirect_uri": "http://localhost:8585/callback",
            "scope": "openid offline_access vehicle_device_data", "state": "st", "nonce": "no",
            "prompt_missing_scopes": "true"})
        self.assertNotIn("+", parts.query, "spaces are encoded as %20")

    def test_parse_callback_reads_the_code_from_any_form_of_the_address(self):
        for text in ["http://localhost:8585/callback?code=abc&state=st",
                     " localhost:8585/callback?state=st&code=abc#frag ",
                     "code=abc&state=st",
                     "?code=abc&state=st"]:
            self.assertEqual(login.parse_callback(text, "st"), "abc", text)

    def test_parse_callback_refuses_errors_other_states_and_no_code(self):
        with self.assertRaisesRegex(login.LoginError, "didn't sign you in: user cancelled"):
            login.parse_callback("?error=access_denied&error_description=user+cancelled&state=st", "st")
        with self.assertRaisesRegex(login.LoginError, "state doesn't match"):
            login.parse_callback("?code=abc&state=other", "st")
        with self.assertRaisesRegex(login.LoginError, "no sign-in code"):
            login.parse_callback("?state=st", "st")

    def test_ends_sign_in_only_for_this_state_or_a_refusal(self):
        self.assertTrue(login.ends_sign_in({"state": "st", "code": "abc"}, "st"))
        self.assertTrue(login.ends_sign_in({"state": "st", "error": "access_denied"}, "st"))
        self.assertTrue(login.ends_sign_in({"error": "access_denied"}, "st"))
        self.assertFalse(login.ends_sign_in({"state": "old", "code": "abc"}, "st"))
        self.assertFalse(login.ends_sign_in({"state": "old", "error": "access_denied"}, "st"))
        self.assertFalse(login.ends_sign_in({"code": "abc"}, "st"))
        self.assertFalse(login.ends_sign_in({}, "st"))

    def test_printable_drops_terminal_control_characters(self):
        self.assertEqual(login.printable("bad\x1b[2J\x1b]0;title\x07thing\r\n"), "bad [2J ]0;title thing")
        self.assertEqual(login.printable("Blue Thunder"), "Blue Thunder")
        self.assertNotIn("\x1b", login.describe_error(400, {"error": "x", "error_description": "a\x1b[31mb"}))
        self.assertNotIn("\x1b", login.describe_error(500, "page\x1b[2J"))
        cars = login.vehicles_from({"response": [{"vin": "V1", "display_name": "Car\x1b[2J"}]})
        self.assertEqual(cars, [{"vin": "V1", "name": "Car [2J"}])
        with self.assertRaises(login.LoginError) as refused:
            login.parse_callback("?error=x&error_description=no%1B%5B2J&state=st", "st")
        self.assertNotIn("\x1b", str(refused.exception))

    def test_check_redirect(self):
        self.assertEqual(login.check_redirect("http://localhost:8585/callback"), (8585, "/callback"))
        self.assertEqual(login.check_redirect("http://127.0.0.1/"), (80, "/"))
        for uri in ["https://localhost:8585/callback", "http://example.com/callback"]:
            with self.assertRaisesRegex(login.LoginError, "--manual"):
                login.check_redirect(uri)

    def test_looks_like_public_key(self):
        self.assertTrue(login.looks_like_public_key("-----BEGIN PUBLIC KEY-----\nMFkw\n-----END PUBLIC KEY-----\n"))
        self.assertFalse(login.looks_like_public_key("<html>Not found</html>"))

    def test_describe_error(self):
        self.assertIn("Couldn't reach", login.describe_error(0, "timed out"))
        self.assertIn("client ID or client secret", login.describe_error(401, {"error": "invalid_client"}))
        self.assertIn("redirect URI", login.describe_error(400, {"error": "invalid_grant",
                                                                 "error_description": "redirect_uri does not match"}))
        self.assertIn("only works once", login.describe_error(400, {"error": "invalid_grant"}))
        self.assertIn("register command", login.describe_error(412, {"error": "x"}))
        self.assertIn("another region", login.describe_error(421, ""))
        self.assertEqual(login.describe_error(500, ""), "Tesla answered 500: no details")

    def test_tokens_from(self):
        self.assertEqual(login.tokens_from({"access_token": "a", "refresh_token": "r", "expires_in": 60}, 1000),
                         {"access": "a", "refresh": "r", "expires_at": 1060000})
        self.assertEqual(login.tokens_from({"access_token": "a"}, 0)["expires_at"], 8 * 3600 * 1000)
        with self.assertRaises(login.LoginError):
            login.tokens_from({"error": "x"}, 0)

    def test_vehicles_from(self):
        reply = {"response": [{"vin": "V1", "display_name": "Car"}, {"vin": "V2", "display_name": None}, {}]}
        self.assertEqual(login.vehicles_from(reply), [{"vin": "V1", "name": "Car"}, {"vin": "V2", "name": ""}])
        self.assertEqual(login.vehicles_from({"response": None}), [])

    def test_regions_match_the_widget(self):
        source = (ROOT / "package" / "contents" / "ui" / "teslaapi.js").read_text()
        for key in ["na", "eu", "cn"]:
            self.assertIn('"%s"' % login.REGIONS[key][1], source)

    def test_auth_urls_follow_the_region(self):
        urls = lambda *argv: login.auth_urls_of(login.parse_args(["login", "--client-id", "c", *argv]))
        world = ("https://auth.tesla.com", "https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token")
        self.assertEqual(urls(), world)
        self.assertEqual(urls("--region", "eu"), world)
        self.assertEqual(urls("--region", "cn"), ("https://auth.tesla.cn", "https://auth.tesla.cn/oauth2/v3/token"))
        self.assertEqual(urls("--region", "cn", "--auth-url", "http://a", "--token-url", "http://t"),
                         ("http://a", "http://t"))
        # The widget renews China's tokens on the same server.
        source = (ROOT / "package" / "contents" / "ui" / "teslaapi.js").read_text()
        self.assertIn('"%s"' % login.REGION_AUTH["cn"][0], source)

    def test_format_result(self):
        tokens = {"access": "AAA", "refresh": "RRR", "expires_at": 0}
        text = login.format_result("eu", login.REGIONS["eu"][1], "cid", tokens, [{"vin": "V1", "name": "Car"}])
        self.assertIn("Region:", text)
        self.assertIn("Europe, Middle East, Africa", text)
        self.assertIn("AAA", text)
        self.assertIn("RRR", text)
        self.assertIn("cid", text)
        self.assertIn("V1 (Car)", text)
        custom = login.format_result("na", "http://localhost:1", "cid", dict(tokens, refresh=""), [])
        self.assertIn("Custom URL: http://localhost:1", custom)
        self.assertIn("can't be renewed", custom)
        self.assertIn("Find Cars", custom)
        data = json.loads(login.result_json("na", "u", "cid", tokens, []))
        self.assertEqual(data["refresh_token"], "RRR")


class EndToEndTests(unittest.TestCase):
    def start_fake(self, *flags):
        port = free_port()
        proc = subprocess.Popen([sys.executable, "-I", str(FAKE), "-p", str(port), *flags],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(proc.wait)
        self.addCleanup(proc.terminate)
        deadline = time.monotonic() + 10
        while True:
            try:
                socket.create_connection(("127.0.0.1", port), timeout=0.2).close()
                break
            except OSError:
                if time.monotonic() > deadline:
                    raise
                time.sleep(0.05)
        return "http://localhost:%d" % port

    def env(self):
        env = dict(os.environ, TESLA_CLIENT_ID="fake", TESLA_CLIENT_SECRET="fake-secret",
                   no_proxy="localhost,127.0.0.1", NO_PROXY="localhost,127.0.0.1")
        return env

    def urls(self, base):
        return ["--api-url", base, "--auth-url", base, "--token-url", base + "/oauth2/v3/token"]

    def run_login(self, *args, stdin=None):
        return subprocess.run([sys.executable, "-I", str(LOGIN), *args], env=self.env(), input=stdin,
                              capture_output=True, text=True, timeout=60)

    def start_login(self, base, *args):
        redirect = "http://localhost:%d/callback" % free_port()
        proc = subprocess.Popen([sys.executable, "-I", str(LOGIN), "login", "--json", "--redirect-uri", redirect,
                                 *self.urls(base), *args], env=self.env(), text=True,
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(lambda: proc.poll() is None and proc.kill())
        for line in proc.stderr:
            if "/oauth2/v3/authorize?" in line:
                return proc, line.strip()
        self.fail("no sign-in address: " + proc.stdout.read())

    def check_signed_in(self, proc, base):
        out, err = proc.communicate(timeout=30)
        self.assertEqual(proc.returncode, 0, err)
        result = json.loads(out)
        self.assertEqual(result["access_token"], "access-2")
        self.assertEqual(result["refresh_token"], "refresh-2")
        self.assertEqual(result["client_id"], "fake")
        self.assertEqual(result["vehicles"], [{"vin": "5YJ3E1EA0KF000001", "name": "Blue Thunder"}])
        request = urllib.request.Request(base + "/api/1/vehicles", headers={"Authorization": "Bearer access-2"})
        with DIRECT.open(request, timeout=10) as reply:
            self.assertEqual(reply.status, 200)

    def test_register(self):
        base = self.start_fake()
        done = self.run_login("register", "--domain", "https://Example.com/", "--skip-key-check", *self.urls(base))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("Registered example.com", done.stdout)

    def test_register_reports_tesla_refusing_the_domain(self):
        base = self.start_fake("--fail-register")
        done = self.run_login("register", "--domain", "example.com", "--skip-key-check", *self.urls(base))
        self.assertEqual(done.returncode, 1)
        self.assertIn("must match registered allowed origin", done.stderr)

    def test_register_reports_a_wrong_client_secret(self):
        base = self.start_fake("--client-secret", "other")
        done = self.run_login("register", "--domain", "example.com", "--skip-key-check", *self.urls(base))
        self.assertEqual(done.returncode, 1)
        self.assertIn("client ID or client secret", done.stderr)

    def test_login_catches_the_browser_coming_back(self):
        base = self.start_fake()
        proc, url = self.start_login(base, "--no-browser")
        # The browser's part: the fake signs in at once and redirects to the helper.
        with DIRECT.open(url, timeout=10) as page:
            self.assertIn("Signed in", page.read().decode())
        self.check_signed_in(proc, base)

    def test_login_turns_away_a_reply_from_another_sign_in(self):
        base = self.start_fake()
        proc, url = self.start_login(base, "--no-browser")
        redirect = dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(url).query))["redirect_uri"]
        # Such as a tab from an earlier sign-in reloaded: refused, and the sign-in still waits.
        with self.assertRaises(urllib.error.HTTPError) as stale:
            DIRECT.open(redirect + "?code=old&state=old", timeout=10)
        self.assertEqual(stale.exception.code, 400)
        self.assertEqual(stale.exception.headers["Cache-Control"], "no-store")
        self.assertIsNone(proc.poll())
        with DIRECT.open(url, timeout=10) as page:
            self.assertIn("Signed in", page.read().decode())
        self.check_signed_in(proc, base)

    def test_login_manual_reads_the_pasted_address(self):
        base = self.start_fake()
        proc, url = self.start_login(base, "--manual")
        with self.assertRaises(urllib.error.HTTPError) as redirect:
            NO_REDIRECT.open(url, timeout=10)
        self.assertEqual(redirect.exception.code, 302)
        proc.stdin.write(redirect.exception.headers["Location"] + "\n")
        proc.stdin.flush()
        self.check_signed_in(proc, base)

    def test_login_needs_a_client_id_and_a_local_redirect(self):
        env_less = subprocess.run([sys.executable, "-I", str(LOGIN), "login"], capture_output=True, text=True,
                                  env=dict(os.environ, TESLA_CLIENT_ID=""), timeout=30)
        self.assertEqual(env_less.returncode, 1)
        self.assertIn("client ID", env_less.stderr)
        remote = self.run_login("login", "--redirect-uri", "https://example.com/cb")
        self.assertEqual(remote.returncode, 1)
        self.assertIn("--manual", remote.stderr)


if __name__ == "__main__":
    unittest.main()
