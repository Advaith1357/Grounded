#!/usr/bin/env python3
"""Grounded friends server.

A small, dependency-free (Python 3.9+ standard library + SQLite) backend for
Grounded's social features: accounts, friend codes, shared shield status and
nudges. Run it with:

    python3 Server/server.py                   # 127.0.0.1:8787, ./Server/grounded.db
    python3 Server/server.py --host 0.0.0.0    # reachable from a phone on your LAN

Auth is a bearer token issued at registration; only its SHA-256 is stored.
There is no TLS here — put it behind an HTTPS reverse proxy before exposing it
to the internet. All times are Unix epoch seconds.
"""

import argparse
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

    def __init__(self, path, clock=time.time):
        self.path = path
        self.clock = clock
        with self._connect() as db:
            db.executescript(SCHEMA)

    def _connect(self):
        db = sqlite3.connect(self.path, timeout=10)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys = ON")
        db.execute("PRAGMA journal_mode = WAL")
        return db

    def create_user(self, name):
        token = secrets.token_urlsafe(32)
        user_id = secrets.token_hex(8)
        now = self.clock()
        db = self._connect()
        try:
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


class Handler(BaseHTTPRequestHandler):
    server_version = "GroundedServer/1"
    store = None  # set by make_server

    def log_message(self, fmt, *args):
        if getattr(self.server, "verbose", False):
            super().log_message(fmt, *args)

    # -- plumbing ---------------------------------------------------------

    def _send(self, status, payload=None, headers=None):
        body = b"" if payload is None else json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _read_json(self):
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            raise ApiError(400, "Bad Content-Length.")
        if length > MAX_BODY_BYTES:
            raise ApiError(413, "Request too large.")
        if length == 0:
            return {}
        try:
            data = json.loads(self.rfile.read(length))
        except (ValueError, UnicodeDecodeError):
            raise ApiError(400, "Body must be JSON.")
        if not isinstance(data, dict):
            raise ApiError(400, "Body must be a JSON object.")
        return data

    def _user(self):
        header = self.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            raise ApiError(401, "Missing credentials.")
        user = self.store.user_for_token(header[len("Bearer "):].strip())
        if user is None:
            raise ApiError(401, "Unknown or revoked credentials.")
        return user

    def _dispatch(self):
        path = urlparse(self.path).path.rstrip("/") or "/"
        method = self.command
        try:
            if path == "/health" and method == "GET":
                return self._send(200, {"ok": True})

            if path == "/v1/users" and method == "POST":
                name = clean_name(self._read_json().get("name"))
                return self._send(201, self.store.create_user(name))

            if path == "/v1/me":
                user = self._user()
                if method == "GET":
                    return self._send(200, {"id": user["id"], "name": user["name"], "code": user["code"]})
                if method == "DELETE":
                    self.store.delete_user(user["id"])
                    return self._send(204)

            elif path == "/v1/me/status" and method == "PUT":
                user = self._user()
                body = self._read_json()
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
                self.store.set_status(user["id"], state, ends_at)
                return self._send(204)

            elif path == "/v1/friends":
                user = self._user()
                if method == "GET":
                    return self._send(200, {"friends": self.store.friends_of(user["id"])})
                if method == "POST":
                    code = normalize_code(self._read_json().get("code"))
                    return self._send(201, {"friend": self.store.add_friend(user["id"], code)})

            elif path.startswith("/v1/friends/") and method == "DELETE":
                user = self._user()
                self.store.remove_friend(user["id"], path[len("/v1/friends/"):])
                return self._send(204)

            elif path == "/v1/nudges":
                user = self._user()
                if method == "GET":
                    return self._send(200, {"nudges": self.store.pending_nudges(user["id"])})
                if method == "POST":
                    to_id = self._read_json().get("to")
                    if not isinstance(to_id, str):
                        raise ApiError(400, "'to' is required.")
                    self.store.send_nudge(user["id"], to_id)
                    return self._send(201, {})

            elif path == "/v1/nudges/ack" and method == "POST":
                user = self._user()
                ids = self._read_json().get("ids")
                if not isinstance(ids, list) or not all(isinstance(i, int) and not isinstance(i, bool) for i in ids):
                    raise ApiError(400, "'ids' must be a list of integers.")
                self.store.ack_nudges(user["id"], ids[:200])
                return self._send(204)

            raise ApiError(404, "Not found.")
        except ApiError as error:
            self._send(error.status, {"error": error.message}, error.headers)
        except Exception:  # never leak internals to the client
            if getattr(self.server, "verbose", False):
                traceback.print_exc()
            self._send(500, {"error": "Server error."})

    do_GET = do_POST = do_PUT = do_DELETE = _dispatch


def make_server(db_path, host="127.0.0.1", port=8787, clock=time.time, verbose=False):
    handler = type("BoundHandler", (Handler,), {"store": Store(db_path, clock)})
    server = ThreadingHTTPServer((host, port), handler)
    server.daemon_threads = True
    server.verbose = verbose
    return server


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
