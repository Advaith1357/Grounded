#!/usr/bin/env python3
"""Grounded friends server.

A small, dependency-free (Python 3.9+ standard library + SQLite) backend for
Grounded's social features: accounts, friend codes, shared shield status and
nudges. Run it with:

    python3 Server/server.py                   # 127.0.0.1:8787, ./Server/grounded.db
    python3 Server/server.py --host 0.0.0.0    # reachable from a phone on your LAN

It also exposes a WSGI `application` for hosts such as PythonAnywhere (see the
README, "Hosting the friends server for free").

Auth is a bearer token issued at registration; only its SHA-256 is stored.
This process speaks plain HTTP — a host that provides HTTPS (or a reverse
proxy) must sit in front of it before it's exposed to the internet. All times
are Unix epoch seconds.

Environment: GROUNDED_DB (database path), GROUNDED_JOURNAL_MODE (wal|delete —
use delete on network filesystems), GROUNDED_MAX_USERS (registration cap).
"""

import argparse
from contextlib import closing
import hashlib
import json
import math
import os
import re
import secrets
import sqlite3
import time
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

MAX_BODY_BYTES = 4096
MAX_NAME_LENGTH = 24
MAX_FRIENDS = 50
DEFAULT_MAX_USERS = 1000
NUDGE_COOLDOWN_SECONDS = 60
NUDGE_RETENTION_SECONDS = 7 * 24 * 3600
# No 0/O/1/I so codes survive being read aloud or typed from a screenshot.
CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
CODE_LENGTH = 6
STATES = ("grounded", "unlocked")

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    code TEXT NOT NULL UNIQUE,
    token_hash TEXT NOT NULL UNIQUE,
    state TEXT NOT NULL DEFAULT 'grounded',
    unlock_ends_at REAL,
    status_updated_at REAL NOT NULL,
    created_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS friendships (
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    friend_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at REAL NOT NULL,
    PRIMARY KEY (user_id, friend_id)
);
CREATE TABLE IF NOT EXISTS nudges (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    from_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    to_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at REAL NOT NULL,
    delivered INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS nudges_pending ON nudges (to_id, delivered);
"""


class ApiError(Exception):
    def __init__(self, status, message, headers=None):
        super().__init__(message)
        self.status = status
        self.message = message
        self.headers = headers or {}


def hash_token(token):
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def clean_name(value):
    if not isinstance(value, str):
        raise ApiError(400, "Name is required.")
    name = " ".join(value.split())
    if not name or len(name) > MAX_NAME_LENGTH or any(ord(c) < 32 for c in name):
        raise ApiError(400, "Name must be 1-%d characters." % MAX_NAME_LENGTH)
    return name


def normalize_code(value):
    if not isinstance(value, str):
        raise ApiError(400, "Friend code is required.")
    code = value.strip().upper()
    if not re.fullmatch("[%s]{%d}" % (CODE_ALPHABET, CODE_LENGTH), code):
        raise ApiError(400, "That doesn't look like a friend code.")
    return code


def friend_json(row):
    return {
        "id": row["id"],
        "name": row["name"],
        "state": row["state"],
        "unlockEndsAt": row["unlock_ends_at"],
        "statusUpdatedAt": row["status_updated_at"],
    }


class Store:
    """All database access. One short-lived connection per call."""

    def __init__(self, path, clock=time.time, journal_mode=None, max_users=None):
        self.path = path
        self.clock = clock
        mode = (journal_mode or os.environ.get("GROUNDED_JOURNAL_MODE") or "wal").lower()
        if mode not in ("wal", "delete"):
            raise ValueError("GROUNDED_JOURNAL_MODE must be 'wal' or 'delete'")
        self.journal_mode = mode
        self.max_users = max_users or int(os.environ.get("GROUNDED_MAX_USERS") or DEFAULT_MAX_USERS)
        with closing(self._connect()) as db:
            db.executescript(SCHEMA)

    def _connect(self):
        db = sqlite3.connect(self.path, timeout=10)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys = ON")
        db.execute("PRAGMA journal_mode = %s" % self.journal_mode)
        return db

    def create_user(self, name):
        token = secrets.token_urlsafe(32)
        user_id = secrets.token_hex(8)
        now = self.clock()
        db = self._connect()
        try:
            if db.execute("SELECT COUNT(*) FROM users").fetchone()[0] >= self.max_users:
                raise ApiError(503, "This server isn't accepting new accounts right now.")
            for _ in range(20):
                code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))
                try:
                    with db:
                        db.execute(
                            "INSERT INTO users (id, name, code, token_hash, status_updated_at, created_at)"
                            " VALUES (?, ?, ?, ?, ?, ?)",
                            (user_id, name, code, hash_token(token), now, now),
                        )
                    return {"id": user_id, "name": name, "code": code, "token": token}
                except sqlite3.IntegrityError:
                    continue  # code collision; roll a new one
            raise ApiError(500, "Couldn't allocate a friend code.")
        finally:
            db.close()

    def user_for_token(self, token):
        db = self._connect()
        try:
            row = db.execute("SELECT * FROM users WHERE token_hash = ?", (hash_token(token),)).fetchone()
            return dict(row) if row else None
        finally:
            db.close()

    def delete_user(self, user_id):
        db = self._connect()
        try:
            with db:
                db.execute("DELETE FROM users WHERE id = ?", (user_id,))
        finally:
            db.close()

    def set_status(self, user_id, state, unlock_ends_at):
        db = self._connect()
        try:
            with db:
                db.execute(
                    "UPDATE users SET state = ?, unlock_ends_at = ?, status_updated_at = ? WHERE id = ?",
                    (state, unlock_ends_at, self.clock(), user_id),
                )
        finally:
            db.close()

    def friends_of(self, user_id):
        db = self._connect()
        try:
            rows = db.execute(
                "SELECT u.* FROM friendships f JOIN users u ON u.id = f.friend_id"
                " WHERE f.user_id = ? ORDER BY u.name COLLATE NOCASE, u.id",
                (user_id,),
            ).fetchall()
            return [friend_json(r) for r in rows]
        finally:
            db.close()

    def add_friend(self, user_id, code):
        db = self._connect()
        try:
            with db:
                other = db.execute("SELECT * FROM users WHERE code = ?", (code,)).fetchone()
                if other is None:
                    raise ApiError(404, "No one has that friend code.")
                if other["id"] == user_id:
                    raise ApiError(400, "That's your own friend code.")
                if db.execute(
                    "SELECT 1 FROM friendships WHERE user_id = ? AND friend_id = ?", (user_id, other["id"])
                ).fetchone():
                    raise ApiError(409, "You're already friends with %s." % other["name"])
                count = db.execute("SELECT COUNT(*) FROM friendships WHERE user_id = ?", (user_id,)).fetchone()[0]
                if count >= MAX_FRIENDS:
                    raise ApiError(400, "You've reached the %d-friend limit." % MAX_FRIENDS)
                now = self.clock()
                try:
                    db.execute("INSERT INTO friendships VALUES (?, ?, ?)", (user_id, other["id"], now))
                    db.execute("INSERT INTO friendships VALUES (?, ?, ?)", (other["id"], user_id, now))
                except sqlite3.IntegrityError:  # lost a race with a concurrent add
                    raise ApiError(409, "You're already friends with %s." % other["name"])
                return friend_json(other)
        finally:
            db.close()

    def remove_friend(self, user_id, friend_id):
        db = self._connect()
        try:
            with db:
                db.execute(
                    "DELETE FROM friendships WHERE (user_id = ? AND friend_id = ?) OR (user_id = ? AND friend_id = ?)",
                    (user_id, friend_id, friend_id, user_id),
                )
        finally:
            db.close()

    def send_nudge(self, user_id, to_id):
        db = self._connect()
        try:
            with db:
                if not db.execute(
                    "SELECT 1 FROM friendships WHERE user_id = ? AND friend_id = ?", (user_id, to_id)
                ).fetchone():
                    raise ApiError(403, "You can only nudge friends.")
                now = self.clock()
                last = db.execute(
                    "SELECT MAX(created_at) FROM nudges WHERE from_id = ? AND to_id = ?", (user_id, to_id)
                ).fetchone()[0]
                if last is not None and now - last < NUDGE_COOLDOWN_SECONDS:
                    wait = int(NUDGE_COOLDOWN_SECONDS - (now - last)) + 1
                    raise ApiError(429, "Easy - you nudged them a moment ago.", {"Retry-After": str(wait)})
                db.execute("DELETE FROM nudges WHERE created_at < ?", (now - NUDGE_RETENTION_SECONDS,))
                db.execute("INSERT INTO nudges (from_id, to_id, created_at) VALUES (?, ?, ?)", (user_id, to_id, now))
        finally:
            db.close()

    def pending_nudges(self, user_id):
        db = self._connect()
        try:
            rows = db.execute(
                "SELECT n.id, n.from_id, u.name AS from_name, n.created_at FROM nudges n"
                " JOIN users u ON u.id = n.from_id"
                " WHERE n.to_id = ? AND n.delivered = 0 ORDER BY n.id",
                (user_id,),
            ).fetchall()
            return [
                {"id": r["id"], "fromId": r["from_id"], "fromName": r["from_name"], "createdAt": r["created_at"]}
                for r in rows
            ]
        finally:
            db.close()

    def ack_nudges(self, user_id, ids):
        db = self._connect()
        try:
            with db:
                db.executemany(
                    "UPDATE nudges SET delivered = 1 WHERE id = ? AND to_id = ?", [(i, user_id) for i in ids]
                )
        finally:
            db.close()


def handle(store, method, target, authorization, content_length, read_body):
    """Routes one request. Transport-independent: used by both the standalone
    server and the WSGI app. Returns (status, json_payload_or_None, headers)."""
    path = urlparse(target).path.rstrip("/") or "/"

    def body_json():
        if content_length > MAX_BODY_BYTES:
            raise ApiError(413, "Request too large.")
        if content_length == 0:
            return {}
        try:
            data = json.loads(read_body(content_length))
        except (ValueError, UnicodeDecodeError):
            raise ApiError(400, "Body must be JSON.")
        if not isinstance(data, dict):
            raise ApiError(400, "Body must be a JSON object.")
        return data

    def current_user():
        if not authorization or not authorization.startswith("Bearer "):
            raise ApiError(401, "Missing credentials.")
        user = store.user_for_token(authorization[len("Bearer "):].strip())
        if user is None:
            raise ApiError(401, "Unknown or revoked credentials.")
        return user

    try:
        if path == "/health" and method == "GET":
            return 200, {"ok": True}, {}

        if path == "/v1/users" and method == "POST":
            name = clean_name(body_json().get("name"))
            return 201, store.create_user(name), {}

        if path == "/v1/me":
            user = current_user()
            if method == "GET":
                return 200, {"id": user["id"], "name": user["name"], "code": user["code"]}, {}
            if method == "DELETE":
                store.delete_user(user["id"])
                return 204, None, {}

        elif path == "/v1/me/status" and method == "PUT":
            user = current_user()
            body = body_json()
            state = body.get("state")
            if state not in STATES:
                raise ApiError(400, "state must be 'grounded' or 'unlocked'.")
            ends_at = body.get("unlockEndsAt")
            if state == "unlocked":
                if (
                    isinstance(ends_at, bool)
                    or not isinstance(ends_at, (int, float))
                    or not math.isfinite(ends_at)
                ):
                    raise ApiError(400, "unlockEndsAt is required when unlocked.")
            else:
                ends_at = None
            store.set_status(user["id"], state, ends_at)
            return 204, None, {}

        elif path == "/v1/sync" and method == "GET":
            # Friends + pending nudges in one round trip: what the app polls.
            user = current_user()
            return 200, {
                "friends": store.friends_of(user["id"]),
                "nudges": store.pending_nudges(user["id"]),
            }, {}

        elif path == "/v1/friends":
            user = current_user()
            if method == "GET":
                return 200, {"friends": store.friends_of(user["id"])}, {}
            if method == "POST":
                code = normalize_code(body_json().get("code"))
                return 201, {"friend": store.add_friend(user["id"], code)}, {}

        elif path.startswith("/v1/friends/") and method == "DELETE":
            user = current_user()
            store.remove_friend(user["id"], path[len("/v1/friends/"):])
            return 204, None, {}

        elif path == "/v1/nudges":
            user = current_user()
            if method == "GET":
                return 200, {"nudges": store.pending_nudges(user["id"])}, {}
            if method == "POST":
                to_id = body_json().get("to")
                if not isinstance(to_id, str):
                    raise ApiError(400, "'to' is required.")
                store.send_nudge(user["id"], to_id)
                return 201, {}, {}

        elif path == "/v1/nudges/ack" and method == "POST":
            user = current_user()
            ids = body_json().get("ids")
            if not isinstance(ids, list) or not all(isinstance(i, int) and not isinstance(i, bool) for i in ids):
                raise ApiError(400, "'ids' must be a list of integers.")
            store.ack_nudges(user["id"], ids[:200])
            return 204, None, {}

        raise ApiError(404, "Not found.")
    except ApiError as error:
        return error.status, {"error": error.message}, error.headers


def encode(payload):
    return b"" if payload is None else json.dumps(payload).encode("utf-8")


def safe_handle(store, verbose, *args):
    try:
        return handle(store, *args)
    except Exception:  # never leak internals to the client
        if verbose:
            traceback.print_exc()
        return 500, {"error": "Server error."}, {}


# -- standalone server (http.server) -----------------------------------------

class Handler(BaseHTTPRequestHandler):
    server_version = "GroundedServer/1"
    store = None  # set by make_server

    def log_message(self, fmt, *args):
        if getattr(self.server, "verbose", False):
            super().log_message(fmt, *args)

    def _dispatch(self):
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            length = -1
        if length < 0:
            status, payload, headers = 400, {"error": "Bad Content-Length."}, {}
        else:
            status, payload, headers = safe_handle(
                self.store, getattr(self.server, "verbose", False),
                self.command, self.path, self.headers.get("Authorization"), length, self.rfile.read,
            )
        body = encode(payload)
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for key, value in headers.items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    do_GET = do_POST = do_PUT = do_DELETE = _dispatch


def make_server(db_path, host="127.0.0.1", port=8787, clock=time.time, verbose=False, **store_options):
    handler = type("BoundHandler", (Handler,), {"store": Store(db_path, clock, **store_options)})
    server = ThreadingHTTPServer((host, port), handler)
    server.daemon_threads = True
    server.verbose = verbose
    return server


# -- WSGI (PythonAnywhere and friends) ---------------------------------------

REASONS = {200: "OK", 201: "Created", 204: "No Content", 400: "Bad Request", 401: "Unauthorized",
           403: "Forbidden", 404: "Not Found", 409: "Conflict", 413: "Payload Too Large",
           429: "Too Many Requests", 500: "Internal Server Error", 503: "Service Unavailable"}


def make_wsgi_app(db_path=None, clock=time.time, verbose=False, **store_options):
    """Builds a WSGI callable. The database is opened on the first request, so
    importing this module never touches the disk."""
    state = {}

    def application(environ, start_response):
        if "store" not in state:
            path = db_path or os.environ.get("GROUNDED_DB") or os.path.join(
                os.path.dirname(os.path.abspath(__file__)), "grounded.db")
            state["store"] = Store(path, clock, **store_options)
        try:
            length = int(environ.get("CONTENT_LENGTH") or 0)
        except ValueError:
            length = -1
        target = environ.get("PATH_INFO", "/")
        if length < 0:
            status, payload, headers = 400, {"error": "Bad Content-Length."}, {}
        else:
            status, payload, headers = safe_handle(
                state["store"], verbose, environ.get("REQUEST_METHOD", "GET"), target,
                environ.get("HTTP_AUTHORIZATION"), length, environ["wsgi.input"].read,
            )
        body = encode(payload)
        response_headers = [("Content-Type", "application/json"), ("Content-Length", str(len(body)))]
        response_headers += list(headers.items())
        start_response("%d %s" % (status, REASONS.get(status, "Error")), response_headers)
        return [body]

    return application


# Entry point for WSGI hosts: `from server import application`
application = make_wsgi_app()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument(
        "--db",
        default=os.environ.get("GROUNDED_DB", os.path.join(os.path.dirname(os.path.abspath(__file__)), "grounded.db")),
    )
    args = parser.parse_args()
    server = make_server(args.db, args.host, args.port, verbose=True)
    print("Grounded friends server on http://%s:%d  (db: %s)" % (args.host, args.port, args.db))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
