#!/usr/bin/env python3
"""Simple HTTP server that serves a flag from a config file."""

import http.server
from pathlib import Path
import sys


class FlagHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        flag = FLAG_FILE.read_text(encoding="utf-8").strip()
        self.wfile.write(f"{flag}\n".encode())

    def log_message(self, format, *args):
        pass  # Suppress access logs to keep terminal clean


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <config-file>")
        sys.exit(1)

    config = {}
    for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
        if not line.strip() or "=" not in line:
            continue
        key, value = line.split("=", 1)
        config[key.strip()] = value.strip()

    PORT = int(config["PORT"])
    FLAG_FILE = Path(config["FLAG_FILE"])

    server = http.server.HTTPServer(("", PORT), FlagHandler)
    server.serve_forever()
