#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shlex
import sys

from model import (
    create_user,
    delete_user,
    init_state,
    login_shell,
    reset_machine,
    restore_user,
    status_rows,
)


def print_status() -> None:
    rows = status_rows()
    running = sum(1 for row in rows if row.machine_status.lower() == "running")
    archives = sum(len(row.archive_refs) for row in rows)
    print(f"Managed users: {len(rows)}")
    print(
        f"Machines:      {sum(1 for row in rows if row.machine_exists)} total / {running} running"
    )
    print(f"Archives:      {archives}")
    if not rows:
        return
    print("\nUSER               MACHINE        CONTAINER             IP")
    for row in rows:
        print(
            f"{row.username:<18} {row.machine_status:<13} {row.container_name:<21} {row.machine_ip}"
        )


def require_root(args: list[str]) -> None:
    if os.geteuid() == 0:
        return
    rendered = " ".join(shlex.quote(arg) for arg in args)
    raise RuntimeError(
        f"This command must be run with sudo. Try: sudo ./web-server/ops.py {rendered}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("login-shell")
    subparsers.add_parser("status")

    create = subparsers.add_parser("create-user")
    create.add_argument("username")
    create.add_argument("password")
    create.add_argument("comment", nargs="?", default="")

    reset_machine_cmd = subparsers.add_parser("reset-machine")
    reset_machine_cmd.add_argument("username")
    reset_machine_cmd.add_argument("--purge", action="store_true")
    reset_machine_cmd.add_argument("--dry-run", action="store_true")

    delete_user_cmd = subparsers.add_parser("delete-user")
    delete_user_cmd.add_argument("username")
    delete_user_cmd.add_argument("--purge", action="store_true")
    delete_user_cmd.add_argument("--dry-run", action="store_true")

    restore = subparsers.add_parser("restore-user")
    restore.add_argument("username")
    restore.add_argument("password")
    restore.add_argument("--archive-ref", default="")

    args = parser.parse_args()
    init_state()

    try:
        if args.command != "login-shell":
            require_root(sys.argv[1:])
        match args.command:
            case "login-shell":
                login_shell()
            case "status":
                print_status()
            case "create-user":
                print(
                    json.dumps(
                        create_user(args.username, args.password, args.comment),
                        indent=2,
                    )
                )
            case "reset-machine":
                print(
                    json.dumps(
                        reset_machine(
                            args.username, purge=args.purge, dry_run=args.dry_run
                        ),
                        indent=2,
                    )
                )
            case "delete-user":
                print(
                    json.dumps(
                        delete_user(
                            args.username, purge=args.purge, dry_run=args.dry_run
                        ),
                        indent=2,
                    )
                )
            case "restore-user":
                print(
                    json.dumps(
                        restore_user(args.username, args.password, args.archive_ref),
                        indent=2,
                    )
                )
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1) from exc


if __name__ == "__main__":
    main()
