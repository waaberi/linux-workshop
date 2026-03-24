#!/usr/bin/env python3
from __future__ import annotations

import html
import os
import pwd
import re
import subprocess
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs


CONFIG_PATH = Path("/etc/workshop/registration.env")
BROKER_PATH = Path("/etc/workshop/broker.env")
PROVISION_SCRIPT = "/usr/local/lib/workshop/provision-student.sh"
USERNAME_RE = re.compile(r"^[a-z][a-z0-9_-]{2,31}$")


def load_env(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    if not path.exists():
        return data
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        data[key.strip()] = value.strip()
    return data


CONFIG = load_env(CONFIG_PATH)
BROKER = load_env(BROKER_PATH)
HOST_LABEL = CONFIG.get("WORKSHOP_HOST_LABEL", "your-server")
BIND = CONFIG.get("WORKSHOP_REGISTRATION_BIND", "0.0.0.0")
PORT = int(CONFIG.get("WORKSHOP_REGISTRATION_PORT", "8088"))
TITLE = CONFIG.get("WORKSHOP_REGISTRATION_TITLE", "Workshop Login Registration")
MESSAGE = CONFIG.get(
    "WORKSHOP_REGISTRATION_MESSAGE",
    "Claim a username and password for the workshop.",
)
CODE = CONFIG.get("WORKSHOP_REGISTRATION_CODE", "")


def page(body: str, status: HTTPStatus = HTTPStatus.OK) -> tuple[HTTPStatus, bytes]:
    doc = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(TITLE)}</title>
  <style>
    body {{ font-family: sans-serif; margin: 2rem auto; max-width: 42rem; padding: 0 1rem; line-height: 1.5; }}
    form {{ display: grid; gap: 0.9rem; margin-top: 1.5rem; }}
    input {{ padding: 0.65rem; font: inherit; }}
    button {{ padding: 0.75rem 1rem; font: inherit; cursor: pointer; }}
    .card {{ border: 1px solid #ddd; border-radius: 10px; padding: 1.25rem; background: #fafafa; }}
    .error {{ color: #b00020; }}
    .success {{ color: #0a6b2d; }}
    code {{ background: #f1f1f1; padding: 0.15rem 0.3rem; border-radius: 4px; }}
  </style>
</head>
<body>
{body}
</body>
</html>
"""
    return status, doc.encode("utf-8")


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        self.respond(*page(self.render_form()))

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        payload = self.rfile.read(length).decode("utf-8", errors="replace")
        data = parse_qs(payload, keep_blank_values=True)

        username = data.get("username", [""])[0].strip().lower()
        password = data.get("password", [""])[0]
        password_confirm = data.get("password_confirm", [""])[0]
        invite_code = data.get("invite_code", [""])[0].strip()

        error = self.validate(username, password, password_confirm, invite_code)
        if error:
            self.respond(
                *page(
                    self.render_form(error=error, username=username),
                    HTTPStatus.BAD_REQUEST,
                )
            )
            return

        proc = subprocess.run(
            [PROVISION_SCRIPT, username, password, "Self-service registration"],
            text=True,
            capture_output=True,
            check=False,
        )
        if proc.returncode != 0:
            error_text = (
                proc.stderr.strip() or proc.stdout.strip() or "Provisioning failed."
            )
            self.respond(
                *page(
                    self.render_form(error=error_text, username=username),
                    HTTPStatus.BAD_REQUEST,
                )
            )
            return

        success = f"""
<h1>{html.escape(TITLE)}</h1>
<p class="success">Registration complete for <strong>{html.escape(username)}</strong>.</p>
<div class="card">
  <p>SSH command:</p>
  <p><code>ssh {html.escape(username)}@{html.escape(HOST_LABEL)}</code></p>
  <p>Your container will be created on first login and reused on reconnect.</p>
</div>
<p><a href="/">Register another account</a></p>
"""
        self.respond(*page(success))

    def validate(
        self, username: str, password: str, password_confirm: str, invite_code: str
    ) -> str | None:
        if not USERNAME_RE.fullmatch(username):
            return "Username must start with a letter and use only lowercase letters, digits, underscores, or dashes."
        try:
            pwd.getpwnam(username)
        except KeyError:
            pass
        else:
            return "That username is already taken. Pick another one."
        if len(password) < 8:
            return "Password must be at least 8 characters long."
        if password != password_confirm:
            return "Passwords do not match."
        if CODE and invite_code != CODE:
            return "Invite code is incorrect."
        return None

    def render_form(self, error: str = "", username: str = "") -> str:
        invite_field = ""
        if CODE:
            invite_field = """
  <label>
    Invite code
    <input type="password" name="invite_code" autocomplete="one-time-code" required>
  </label>
"""
        error_html = f'<p class="error">{html.escape(error)}</p>' if error else ""
        return f"""
<h1>{html.escape(TITLE)}</h1>
<p>{html.escape(MESSAGE)}</p>
{error_html}
<form method="post" class="card">
  <label>
    Username
    <input name="username" value="{html.escape(username)}" pattern="[a-z][a-z0-9_-]{{2,31}}" required>
  </label>
  <label>
    Password
    <input type="password" name="password" minlength="8" required>
  </label>
  <label>
    Confirm password
    <input type="password" name="password_confirm" minlength="8" required>
  </label>
{invite_field}
  <button type="submit">Claim account</button>
</form>
<p>After registering, connect with <code>ssh &lt;username&gt;@{html.escape(HOST_LABEL)}</code>.</p>
"""

    def respond(self, status: HTTPStatus, body: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt: str, *args: object) -> None:
        return


def main() -> None:
    os.chdir("/")
    server = ThreadingHTTPServer((BIND, PORT), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
