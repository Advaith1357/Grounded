"""Run with: python3 -m unittest Server/test_server.py  (from the repo root)"""

import io
import json
import os
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from wsgiref.simple_server import WSGIRequestHandler, make_server as make_wsgi_server

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import server  # noqa: E402


class FakeClock:
    def __init__(self, now=1_000_000.0):
        self.now = now

    def __call__(self):
        return self.now


class QuietHandler(WSGIRequestHandler):
    def log_message(self, *args):
        pass


class ServerTestCase(unittest.TestCase):
    store_options = {}

    def make_httpd(self):
        return server.make_server(os.path.join(self.tmp.name, "t.db"), port=0, clock=self.clock, **self.store_options)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.clock = FakeClock()
        self.httpd = self.make_httpd()
        self.base = "http://127.0.0.1:%d" % self.httpd.server_address[1]
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.tmp.cleanup()

    def call(self, method, path, body=None, token=None, raw=None):
        data = raw if raw is not None else (None if body is None else json.dumps(body).encode())
        request = urllib.request.Request(self.base + path, data=data, method=method)
        request.add_header("Content-Type", "application/json")
        if token:
            request.add_header("Authorization", "Bearer " + token)
        try:
            with urllib.request.urlopen(request) as response:
                text = response.read()
                return response.status, (json.loads(text) if text else None), response.headers
        except urllib.error.HTTPError as error:
            text = error.read()
            return error.code, (json.loads(text) if text else None), error.headers

    def register(self, name):
        status, body, _ = self.call("POST", "/v1/users", {"name": name})
        self.assertEqual(status, 201)
        return body

    def befriend(self, a, b):
        status, _, _ = self.call("POST", "/v1/friends", {"code": b["code"]}, a["token"])
        self.assertEqual(status, 201)


class RegistrationTests(ServerTestCase):
    def test_register_returns_credentials_and_code(self):
        user = self.register("  Alex   Q ")
        self.assertEqual(user["name"], "Alex Q")
        self.assertEqual(len(user["code"]), server.CODE_LENGTH)
        self.assertTrue(set(user["code"]) <= set(server.CODE_ALPHABET))
        status, me, _ = self.call("GET", "/v1/me", token=user["token"])
        self.assertEqual((status, me["id"], me["code"]), (200, user["id"], user["code"]))

    def test_rejects_bad_names(self):
        for name in ["", "   ", "x" * 25, "bad\x07name", 5, None]:
            status, _, _ = self.call("POST", "/v1/users", {"name": name})
            self.assertEqual(status, 400, repr(name))

    def test_token_is_not_stored_in_plain_text(self):
        user = self.register("Alex")
        with open(os.path.join(self.tmp.name, "t.db"), "rb") as f:
            self.assertNotIn(user["token"].encode(), f.read())

    def test_requires_valid_token(self):
        self.assertEqual(self.call("GET", "/v1/me")[0], 401)
        self.assertEqual(self.call("GET", "/v1/me", token="nope")[0], 401)
        self.assertEqual(self.call("GET", "/v1/friends", token="nope")[0], 401)

    def test_malformed_requests(self):
        self.assertEqual(self.call("POST", "/v1/users", raw=b"{not json")[0], 400)
        self.assertEqual(self.call("POST", "/v1/users", raw=b"[1,2]")[0], 400)
        self.assertEqual(self.call("POST", "/v1/users", raw=b"x" * 5000)[0], 413)
        self.assertEqual(self.call("GET", "/nope")[0], 404)

    def test_delete_account_removes_friendships(self):
        a, b = self.register("A"), self.register("B")
        self.befriend(a, b)
        self.assertEqual(self.call("DELETE", "/v1/me", token=a["token"])[0], 204)
        self.assertEqual(self.call("GET", "/v1/me", token=a["token"])[0], 401)
        self.assertEqual(self.call("GET", "/v1/friends", token=b["token"])[1], {"friends": []})


class FriendTests(ServerTestCase):
    def test_adding_by_code_is_mutual_and_case_insensitive(self):
        a, b = self.register("Alex"), self.register("Jordan")
        status, body, _ = self.call("POST", "/v1/friends", {"code": " " + b["code"].lower() + " "}, a["token"])
        self.assertEqual(status, 201)
        self.assertEqual(body["friend"]["name"], "Jordan")
        self.assertEqual([f["name"] for f in self.call("GET", "/v1/friends", token=a["token"])[1]["friends"]], ["Jordan"])
        self.assertEqual([f["name"] for f in self.call("GET", "/v1/friends", token=b["token"])[1]["friends"]], ["Alex"])

    def test_add_friend_errors(self):
        a, b = self.register("Alex"), self.register("Jordan")
        self.assertEqual(self.call("POST", "/v1/friends", {"code": a["code"]}, a["token"])[0], 400)  # own code
        self.assertEqual(self.call("POST", "/v1/friends", {"code": "AAAAAA"}, a["token"])[0], 404)  # unknown
        self.assertEqual(self.call("POST", "/v1/friends", {"code": "bad"}, a["token"])[0], 400)  # malformed
        self.befriend(a, b)
        self.assertEqual(self.call("POST", "/v1/friends", {"code": b["code"]}, a["token"])[0], 409)
        self.assertEqual(self.call("POST", "/v1/friends", {"code": a["code"]}, b["token"])[0], 409)  # reverse dup

    def test_friend_limit(self):
        a = self.register("Alex")
        original = server.MAX_FRIENDS
        server.MAX_FRIENDS = 2
        try:
            self.befriend(a, self.register("B"))
            self.befriend(a, self.register("C"))
            d = self.register("D")
            self.assertEqual(self.call("POST", "/v1/friends", {"code": d["code"]}, a["token"])[0], 400)
        finally:
            server.MAX_FRIENDS = original

    def test_remove_friend_is_mutual(self):
        a, b = self.register("Alex"), self.register("Jordan")
        self.befriend(a, b)
        self.assertEqual(self.call("DELETE", "/v1/friends/" + b["id"], token=a["token"])[0], 204)
        self.assertEqual(self.call("GET", "/v1/friends", token=a["token"])[1], {"friends": []})
        self.assertEqual(self.call("GET", "/v1/friends", token=b["token"])[1], {"friends": []})

    def test_status_is_visible_to_friends_only(self):
        a, b, stranger = self.register("Alex"), self.register("Jordan"), self.register("Eve")
        self.befriend(a, b)
        self.clock.now += 5
        ends = self.clock.now + 600
        self.assertEqual(self.call("PUT", "/v1/me/status", {"state": "unlocked", "unlockEndsAt": ends}, a["token"])[0], 204)
        friend = self.call("GET", "/v1/friends", token=b["token"])[1]["friends"][0]
        self.assertEqual((friend["state"], friend["unlockEndsAt"]), ("unlocked", ends))
        self.assertEqual(friend["statusUpdatedAt"], self.clock.now)
        self.assertEqual(self.call("GET", "/v1/friends", token=stranger["token"])[1], {"friends": []})
        self.call("PUT", "/v1/me/status", {"state": "grounded", "unlockEndsAt": 123}, a["token"])
        friend = self.call("GET", "/v1/friends", token=b["token"])[1]["friends"][0]
        self.assertEqual((friend["state"], friend["unlockEndsAt"]), ("grounded", None))

    def test_status_validation(self):
        a = self.register("Alex")
        for body in [{"state": "asleep"}, {}, {"state": "unlocked"}, {"state": "unlocked", "unlockEndsAt": "soon"},
                     {"state": "unlocked", "unlockEndsAt": True}]:
            self.assertEqual(self.call("PUT", "/v1/me/status", body, a["token"])[0], 400, body)
        self.assertEqual(self.call("PUT", "/v1/me/status", raw=b'{"state":"unlocked","unlockEndsAt":NaN}', token=a["token"])[0], 400)


class NudgeTests(ServerTestCase):
    def test_nudge_flow_with_ack(self):
        a, b = self.register("Alex"), self.register("Jordan")
        self.befriend(a, b)
        self.assertEqual(self.call("POST", "/v1/nudges", {"to": b["id"]}, a["token"])[0], 201)
        nudges = self.call("GET", "/v1/nudges", token=b["token"])[1]["nudges"]
        self.assertEqual([(n["fromName"], n["fromId"]) for n in nudges], [("Alex", a["id"])])
        self.assertEqual(self.call("GET", "/v1/nudges", token=a["token"])[1], {"nudges": []})
        # still pending until acknowledged
        self.assertEqual(len(self.call("GET", "/v1/nudges", token=b["token"])[1]["nudges"]), 1)
        self.assertEqual(self.call("POST", "/v1/nudges/ack", {"ids": [n["id"] for n in nudges]}, b["token"])[0], 204)
        self.assertEqual(self.call("GET", "/v1/nudges", token=b["token"])[1], {"nudges": []})

    def test_cannot_ack_someone_elses_nudges(self):
        a, b, c = self.register("A"), self.register("B"), self.register("C")
        self.befriend(a, b)
        self.call("POST", "/v1/nudges", {"to": b["id"]}, a["token"])
        nudge_id = self.call("GET", "/v1/nudges", token=b["token"])[1]["nudges"][0]["id"]
        self.call("POST", "/v1/nudges/ack", {"ids": [nudge_id]}, c["token"])
        self.assertEqual(len(self.call("GET", "/v1/nudges", token=b["token"])[1]["nudges"]), 1)

    def test_only_friends_can_be_nudged(self):
        a, stranger = self.register("Alex"), self.register("Eve")
        self.assertEqual(self.call("POST", "/v1/nudges", {"to": stranger["id"]}, a["token"])[0], 403)
        self.assertEqual(self.call("POST", "/v1/nudges", {"to": "nobody"}, a["token"])[0], 403)
        self.assertEqual(self.call("POST", "/v1/nudges", {}, a["token"])[0], 400)

    def test_cooldown_per_pair(self):
        a, b, c = self.register("A"), self.register("B"), self.register("C")
        self.befriend(a, b)
        self.befriend(a, c)
        self.assertEqual(self.call("POST", "/v1/nudges", {"to": b["id"]}, a["token"])[0], 201)
        status, body, headers = self.call("POST", "/v1/nudges", {"to": b["id"]}, a["token"])
        self.assertEqual(status, 429)
        self.assertEqual(int(headers["Retry-After"]), server.NUDGE_COOLDOWN_SECONDS + 1)
        self.assertEqual(self.call("POST", "/v1/nudges", {"to": c["id"]}, a["token"])[0], 201)  # other friend is fine
        self.clock.now += server.NUDGE_COOLDOWN_SECONDS + 1
        self.assertEqual(self.call("POST", "/v1/nudges", {"to": b["id"]}, a["token"])[0], 201)

    def test_removed_friends_cannot_nudge(self):
        a, b = self.register("A"), self.register("B")
        self.befriend(a, b)
        self.call("DELETE", "/v1/friends/" + a["id"], token=b["token"])
        self.assertEqual(self.call("POST", "/v1/nudges", {"to": b["id"]}, a["token"])[0], 403)


class SyncTests(ServerTestCase):
    def test_sync_returns_friends_and_nudges_together(self):
        a, b = self.register("Alex"), self.register("Jordan")
        self.befriend(a, b)
        self.call("POST", "/v1/nudges", {"to": b["id"]}, a["token"])
        status, body, _ = self.call("GET", "/v1/sync", token=b["token"])
        self.assertEqual(status, 200)
        self.assertEqual([f["name"] for f in body["friends"]], ["Alex"])
        self.assertEqual([n["fromName"] for n in body["nudges"]], ["Alex"])
        self.assertEqual(self.call("GET", "/v1/sync", token=a["token"])[1]["nudges"], [])

    def test_sync_requires_auth(self):
        self.assertEqual(self.call("GET", "/v1/sync")[0], 401)


class RegistrationCapTests(ServerTestCase):
    store_options = {"max_users": 2}

    def test_registration_closes_at_the_cap(self):
        self.register("A")
        self.register("B")
        status, body, _ = self.call("POST", "/v1/users", {"name": "C"})
        self.assertEqual(status, 503)
        self.assertIn("accepting", body["error"])


class DeleteJournalModeTests(ServerTestCase):
    """The mode used on network filesystems such as PythonAnywhere's."""
    store_options = {"journal_mode": "delete"}

    def test_works_without_wal(self):
        a, b = self.register("Alex"), self.register("Jordan")
        self.befriend(a, b)
        self.assertEqual(len(self.call("GET", "/v1/sync", token=a["token"])[1]["friends"]), 1)
        self.assertFalse(os.path.exists(os.path.join(self.tmp.name, "t.db-wal")))


class ConfigTests(unittest.TestCase):
    def test_rejects_unknown_journal_mode(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ValueError):
                server.Store(os.path.join(tmp, "t.db"), journal_mode="memory")

    def test_wsgi_app_opens_the_database_lazily(self):
        # PythonAnywhere imports `application` before any request arrives.
        self.assertTrue(callable(server.application))
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "lazy.db")
            app = server.make_wsgi_app(path)
            self.assertFalse(os.path.exists(path))
            environ = {"REQUEST_METHOD": "GET", "PATH_INFO": "/health", "wsgi.input": io.BytesIO(b"")}
            captured = {}
            body = app(environ, lambda status, headers: captured.update(status=status))
            self.assertEqual(captured["status"], "200 OK")
            self.assertEqual(json.loads(b"".join(body)), {"ok": True})
            self.assertTrue(os.path.exists(path))


class WSGIMixin:
    """Runs a test class's whole suite against the WSGI app instead of http.server."""

    def make_httpd(self):
        app = server.make_wsgi_app(os.path.join(self.tmp.name, "t.db"), clock=self.clock, **self.store_options)
        return make_wsgi_server("127.0.0.1", 0, app, handler_class=QuietHandler)


for _case in (RegistrationTests, FriendTests, NudgeTests, SyncTests, RegistrationCapTests):
    _name = _case.__name__ + "OverWSGI"
    globals()[_name] = type(_name, (WSGIMixin, _case), {})
del _case, _name


if __name__ == "__main__":
    unittest.main()
