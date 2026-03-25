from __future__ import annotations

import base64
import grp
import hashlib
import hmac
import json
import os
from contextlib import closing
import pam
import pwd
import re
import secrets
import sqlite3
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Literal, TypedDict


CONFIG_PATH = Path("/etc/workshop/registration.env")
BROKER_PATH = Path("/etc/workshop/broker.env")
COOKIE_NAME = "workshop_session"
SESSION_TTL = 60 * 60 * 12
USERNAME_RE = re.compile(r"^[a-z][a-z0-9_-]{2,31}$")


@dataclass(frozen=True)
class AppConfig:
    host_label: str
    bind: str
    port: int
    title: str
    message: str
    pam_service: str
    session_secret: str
    state_db: Path
    ip_registration_limit: int
    image: str
    network: str
    container_prefix: str
    cpus: str
    memory: str
    pids: str


@dataclass
class MachineRecord:
    username: str
    account_exists: bool
    registered_at: str
    registered_ip: str
    container_name: str
    machine_exists: bool
    machine_status: str
    machine_image: str
    machine_ip: str
    machine_created: str
    extra_machines: int
    archive_refs: list[str]


class SessionPayload(TypedDict):
    u: str
    r: str
    exp: int
    csrf: str


class ResetMachineResult(TypedDict):
    RESULT: Literal["missing", "deleted"]
    USERNAME: str
    MODE: Literal["archive", "purge"]
    DRY_RUN: bool
    REMOVED_CONTAINER: list[str]
    ARCHIVE_REF: list[str]


class DeleteUserResult(ResetMachineResult):
    ACCOUNT_REMOVED: bool
    HOME_REMOVED: bool


class RestoreUserResult(TypedDict):
    RESULT: Literal["restored"]
    USERNAME: str
    ARCHIVE_REF: str
    CONTAINER: str


def load_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return values
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def load_config() -> AppConfig:
    registration = load_env(CONFIG_PATH)
    broker = load_env(BROKER_PATH)
    return AppConfig(
        host_label=registration.get("WORKSHOP_HOST_LABEL", "your-server"),
        bind=registration.get("WORKSHOP_REGISTRATION_BIND", "0.0.0.0"),
        port=int(registration.get("WORKSHOP_REGISTRATION_PORT", "8088")),
        title=registration.get(
            "WORKSHOP_REGISTRATION_TITLE", "Workshop Login Registration"
        ),
        message=registration.get(
            "WORKSHOP_REGISTRATION_MESSAGE",
            "Claim a username and password for the workshop.",
        ),
        pam_service=registration.get("WORKSHOP_PAM_SERVICE", "login"),
        session_secret=registration.get("WORKSHOP_SESSION_SECRET", "")
        or secrets.token_hex(32),
        state_db=Path(
            registration.get("WORKSHOP_STATE_DB", "/var/lib/workshop/registration.db")
        ),
        ip_registration_limit=max(
            1, int(registration.get("WORKSHOP_REGISTRATION_IP_LIMIT", "1"))
        ),
        image=broker.get("WORKSHOP_IMAGE", "linux-workshop"),
        network=broker.get("WORKSHOP_NETWORK", "workshop-net"),
        container_prefix=broker.get("WORKSHOP_CONTAINER_PREFIX", "ws"),
        cpus=broker.get("WORKSHOP_CPUS", "1"),
        memory=broker.get("WORKSHOP_MEMORY", "768m"),
        pids=broker.get("WORKSHOP_PIDS", "256"),
    )


APP = load_config()


def init_state() -> None:
    APP.state_db.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(APP.state_db)
    with conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS registrations (
                username TEXT PRIMARY KEY,
                remote_ip TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS audit_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                actor TEXT NOT NULL,
                action TEXT NOT NULL,
                target TEXT NOT NULL,
                detail TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
            """
        )


def db_connect() -> sqlite3.Connection:
    conn = sqlite3.connect(APP.state_db)
    conn.row_factory = sqlite3.Row
    return conn


def audit(actor: str, action: str, target: str, detail: str) -> None:
    with closing(db_connect()) as conn, conn:
        conn.execute(
            "INSERT INTO audit_log(actor, action, target, detail) VALUES (?, ?, ?, ?)",
            (actor, action, target, detail),
        )


def recent_activity(limit: int = 12) -> list[sqlite3.Row]:
    with closing(db_connect()) as conn:
        return conn.execute(
            "SELECT actor, action, target, detail, created_at FROM audit_log ORDER BY id DESC LIMIT ?",
            (limit,),
        ).fetchall()


def registrations_by_username() -> dict[str, sqlite3.Row]:
    with closing(db_connect()) as conn:
        rows = conn.execute(
            "SELECT username, remote_ip, created_at FROM registrations ORDER BY username"
        ).fetchall()
    return {row["username"]: row for row in rows}


def registrations_for_ip(remote_ip: str) -> list[sqlite3.Row]:
    with closing(db_connect()) as conn:
        return conn.execute(
            "SELECT username, remote_ip, created_at FROM registrations WHERE remote_ip = ? ORDER BY created_at",
            (remote_ip,),
        ).fetchall()


def record_registration(username: str, remote_ip: str) -> None:
    with closing(db_connect()) as conn, conn:
        conn.execute(
            "INSERT OR REPLACE INTO registrations(username, remote_ip, created_at) VALUES (?, ?, CURRENT_TIMESTAMP)",
            (username, remote_ip),
        )


def delete_registration(username: str) -> None:
    with closing(db_connect()) as conn, conn:
        conn.execute("DELETE FROM registrations WHERE username = ?", (username,))


def user_in_group(username: str, group_name: str) -> bool:
    try:
        group = grp.getgrnam(group_name)
        account = pwd.getpwnam(username)
    except KeyError:
        return False
    return username in group.gr_mem or account.pw_gid == group.gr_gid


def is_student_user(username: str) -> bool:
    return user_in_group(username, "workshop-students")


def b64encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def b64decode(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + ("=" * (-len(value) % 4)))


def sign_bytes(data: bytes) -> bytes:
    return hmac.new(APP.session_secret.encode("utf-8"), data, hashlib.sha256).digest()


def make_session(username: str, role: str) -> str:
    payload: dict[str, str | int] = {
        "u": username,
        "r": role,
        "exp": int(time.time()) + SESSION_TTL,
        "csrf": secrets.token_hex(16),
    }
    encoded = b64encode(
        json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
    )
    signature = b64encode(sign_bytes(encoded.encode("ascii")))
    return f"{encoded}.{signature}"


def load_session(raw_cookie: str | None) -> dict[str, str] | None:
    if not raw_cookie or "." not in raw_cookie:
        return None
    encoded, signature = raw_cookie.split(".", 1)
    if not hmac.compare_digest(
        signature, b64encode(sign_bytes(encoded.encode("ascii")))
    ):
        return None
    try:
        payload: SessionPayload = json.loads(b64decode(encoded).decode("utf-8"))
        expires_at = int(payload["exp"])
        username = payload["u"]
        role = payload["r"]
        csrf = payload["csrf"]
    except (ValueError, json.JSONDecodeError, KeyError, TypeError):
        return None
    if expires_at <= int(time.time()):
        return None
    if not username or not csrf or role != "student" or not is_student_user(username):
        return None
    return {"username": username, "role": role, "csrf": csrf}


def run(args: list[str], *, input_text: str | None = None, check: bool = True) -> str:
    proc = subprocess.run(
        args, input=input_text, text=True, capture_output=True, check=False
    )
    if check and proc.returncode != 0:
        raise RuntimeError(
            proc.stderr.strip() or proc.stdout.strip() or "Command failed."
        )
    return proc.stdout


def ensure_root() -> None:
    if os.geteuid() != 0:
        raise RuntimeError("This operation requires root privileges.")


def validate_username(username: str) -> None:
    if not USERNAME_RE.fullmatch(username):
        raise RuntimeError(
            "Username must start with a letter and use only lowercase letters, digits, underscores, or dashes."
        )


def validate_password(password: str) -> None:
    if len(password) < 8:
        raise RuntimeError("Password must be at least 8 characters long.")


def account_exists(username: str) -> bool:
    try:
        pwd.getpwnam(username)
    except KeyError:
        return False
    return True


def authenticate_with_pam(username: str, password: str) -> bool:
    return bool(pam.authenticate(username, password, service=APP.pam_service))


def container_name_for(username: str) -> str:
    safe = "".join(ch for ch in username.lower() if ch.isalnum() or ch in "._-")
    if not safe:
        raise RuntimeError(
            f"The username '{username}' cannot be mapped to a container name."
        )
    return f"{APP.container_prefix}-{safe}"


def ensure_student_group() -> None:
    try:
        grp.getgrnam("workshop-students")
    except KeyError as exc:
        raise RuntimeError(
            "Group workshop-students is missing. Run ./install-host-broker.sh first."
        ) from exc


def create_user(username: str, password: str, comment: str = "") -> dict[str, str]:
    ensure_root()
    validate_username(username)
    validate_password(password)
    ensure_student_group()
    if account_exists(username):
        if not is_student_user(username):
            raise RuntimeError(
                f"Existing user '{username}' is not managed by the workshop broker."
            )
        run(["usermod", "-a", "-G", "workshop-students", username])
    else:
        run(["useradd", "-m", "-s", "/bin/bash", "-G", "workshop-students", username])
    run(["chpasswd"], input_text=f"{username}:{password}\n")
    home_dir = Path(pwd.getpwnam(username).pw_dir)
    run(
        [
            "install",
            "-d",
            "-m",
            "700",
            "-o",
            username,
            "-g",
            username,
            str(home_dir / ".ssh"),
        ]
    )
    if comment:
        note = home_dir / ".workshop-note"
        note.write_text(comment + "\n", encoding="utf-8")
        account = pwd.getpwnam(username)
        os.chown(note, account.pw_uid, account.pw_gid)
    return {"username": username}


def validate_registration(
    username: str,
    password: str,
    password_confirm: str,
    remote_ip: str,
) -> str | None:
    try:
        validate_username(username)
        validate_password(password)
    except RuntimeError as exc:
        return str(exc)
    if password != password_confirm:
        return "Passwords do not match."
    if account_exists(username):
        return "That username is already taken. Pick another one."
    claims = registrations_for_ip(remote_ip)
    if len(claims) >= APP.ip_registration_limit:
        return f"This IP address already claimed {claims[0]['username']}. Ask the workshop operator to delete that account before registering another one."
    return None


def create_account(username: str, password: str, remote_ip: str) -> None:
    create_user(username, password, "Self-service registration")
    record_registration(username, remote_ip)


def archive_refs(username: str) -> list[str]:
    try:
        output = run(
            [
                "docker",
                "image",
                "ls",
                "--filter",
                f"label=workshop.archive.username={username}",
                "--format",
                "{{.Repository}}:{{.Tag}}",
            ]
        )
    except RuntimeError:
        return []
    return sorted(
        (line.strip() for line in output.splitlines() if line.strip()), reverse=True
    )


def container_names_for_user(username: str) -> list[str]:
    names: list[str] = []
    preferred = container_name_for(username)
    try:
        run(["docker", "container", "inspect", preferred])
    except RuntimeError:
        pass
    else:
        names.append(preferred)
    try:
        output = run(
            [
                "docker",
                "ps",
                "-a",
                "--filter",
                f"label=workshop.student={username}",
                "--format",
                "{{.Names}}",
            ]
        )
    except RuntimeError:
        output = ""
    for raw in output.splitlines():
        name = raw.strip()
        if name and name not in names:
            names.append(name)
    return names


def inspect_container(name: str) -> dict[str, str]:
    output = run(
        [
            "docker",
            "inspect",
            name,
            "--format",
            "{{.Name}}\t{{.State.Status}}\t{{.Config.Image}}\t{{.Created}}\t{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}",
        ]
    ).strip()
    pieces = output.split("\t")
    if len(pieces) != 5:
        raise RuntimeError("Could not inspect the workshop machine.")
    return {
        "name": pieces[0].lstrip("/"),
        "status": pieces[1],
        "image": pieces[2],
        "created": pieces[3].replace("T", " ").replace("Z", ""),
        "ip": pieces[4] or "-",
    }


def reset_machine(
    username: str, *, purge: bool = False, dry_run: bool = False
) -> ResetMachineResult:
    ensure_root()
    validate_username(username)
    names = container_names_for_user(username)
    result: ResetMachineResult = {
        "RESULT": "missing" if not names else "deleted",
        "USERNAME": username,
        "MODE": "purge" if purge else "archive",
        "DRY_RUN": dry_run,
        "REMOVED_CONTAINER": names,
        "ARCHIVE_REF": [],
    }
    if not names:
        return result
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    archives: list[str] = []
    for index, name in enumerate(names, start=1):
        if not purge:
            suffix = "" if len(names) == 1 else f"-{index}"
            ref = f"workshop-archive:{username}-{stamp}{suffix}"
            archives.append(ref)
            if not dry_run:
                run(
                    [
                        "docker",
                        "commit",
                        "--change",
                        "LABEL workshop.archive=true",
                        "--change",
                        f"LABEL workshop.archive.username={username}",
                        "--change",
                        f"LABEL workshop.archive.created_at={stamp}",
                        "--change",
                        f"LABEL workshop.archive.source_container={name}",
                        name,
                        ref,
                    ]
                )
        if not dry_run:
            run(["docker", "rm", "-f", name])
    result["ARCHIVE_REF"] = archives
    return result


def delete_user(
    username: str, *, purge: bool = False, dry_run: bool = False
) -> DeleteUserResult:
    ensure_root()
    validate_username(username)
    if not account_exists(username):
        raise RuntimeError(f"User '{username}' does not exist.")
    if not is_student_user(username):
        raise RuntimeError(f"User '{username}' is not managed by the workshop broker.")
    result = reset_machine(username, purge=purge, dry_run=dry_run)
    if dry_run:
        return {**result, "ACCOUNT_REMOVED": False, "HOME_REMOVED": False}
    subprocess.run(
        ["loginctl", "terminate-user", username],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    subprocess.run(
        ["pkill", "-KILL", "-u", username],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    run(["userdel", "-r", username])
    subprocess.run(
        ["groupdel", username],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    delete_registration(username)
    return {**result, "ACCOUNT_REMOVED": True, "HOME_REMOVED": True}


def restore_user(
    username: str, password: str, archive_ref: str = ""
) -> RestoreUserResult:
    ensure_root()
    validate_username(username)
    validate_password(password)
    chosen = archive_ref or (
        archive_refs(username)[0] if archive_refs(username) else ""
    )
    if not chosen:
        raise RuntimeError(f"No archived machine found for '{username}'.")
    run(["docker", "image", "inspect", chosen])
    container_name = container_name_for(username)
    try:
        run(["docker", "container", "inspect", container_name])
    except RuntimeError:
        pass
    else:
        raise RuntimeError(f"Container '{container_name}' already exists.")
    create_user(username, password, f"Restored from {chosen}")
    run(
        [
            "docker",
            "create",
            "--name",
            container_name,
            "--hostname",
            container_name,
            "--network",
            APP.network,
            "--restart",
            "unless-stopped",
            "--cpus",
            APP.cpus,
            "--memory",
            APP.memory,
            "--pids-limit",
            APP.pids,
            "--label",
            f"workshop.student={username}",
            chosen,
        ]
    )
    run(["docker", "start", container_name])
    return {
        "RESULT": "restored",
        "USERNAME": username,
        "ARCHIVE_REF": chosen,
        "CONTAINER": container_name,
    }


def machine_record(username: str, registration: sqlite3.Row | None) -> MachineRecord:
    names = container_names_for_user(username)
    container_name = container_name_for(username)
    machine_exists = False
    machine_status = "Not created"
    machine_image = "-"
    machine_ip = "-"
    machine_created = "-"
    extra = 0
    if names:
        try:
            data = inspect_container(names[0])
        except RuntimeError:
            machine_status = "Inspection failed"
        else:
            machine_exists = True
            container_name = data["name"]
            machine_status = data["status"].capitalize()
            machine_image = data["image"]
            machine_ip = data["ip"]
            machine_created = data["created"]
            extra = max(0, len(names) - 1)
    return MachineRecord(
        username=username,
        account_exists=account_exists(username),
        registered_at=registration["created_at"] if registration else "-",
        registered_ip=registration["remote_ip"] if registration else "-",
        container_name=container_name,
        machine_exists=machine_exists,
        machine_status=machine_status,
        machine_image=machine_image,
        machine_ip=machine_ip,
        machine_created=machine_created,
        extra_machines=extra,
        archive_refs=archive_refs(username),
    )


def machine_usernames() -> set[str]:
    try:
        output = run(
            [
                "docker",
                "ps",
                "-a",
                "--filter",
                "label=workshop.student",
                "--format",
                '{{.Label "workshop.student"}}',
            ]
        )
    except RuntimeError:
        return set()
    return {line.strip() for line in output.splitlines() if line.strip()}


def student_members() -> list[str]:
    try:
        group = grp.getgrnam("workshop-students")
    except KeyError:
        return []
    members = set(group.gr_mem)
    for account in pwd.getpwall():
        if account.pw_gid == group.gr_gid:
            members.add(account.pw_name)
    return sorted(members)


def status_rows() -> list[MachineRecord]:
    registrations = registrations_by_username()
    usernames = set(registrations)
    usernames.update(student_members())
    usernames.update(machine_usernames())
    return [
        machine_record(username, registrations.get(username))
        for username in sorted(usernames)
    ]


def ensure_machine(username: str) -> str:
    ensure_root()
    validate_username(username)
    run(["docker", "image", "inspect", APP.image])
    run(["docker", "network", "inspect", APP.network])
    container_name = container_name_for(username)
    try:
        run(["docker", "container", "inspect", container_name])
    except RuntimeError:
        run(
            [
                "docker",
                "run",
                "-d",
                "--name",
                container_name,
                "--hostname",
                container_name,
                "--network",
                APP.network,
                "--restart",
                "unless-stopped",
                "--cpus",
                APP.cpus,
                "--memory",
                APP.memory,
                "--pids-limit",
                APP.pids,
                "--label",
                f"workshop.student={username}",
                APP.image,
            ]
        )
    running = run(
        ["docker", "inspect", "-f", "{{.State.Running}}", container_name]
    ).strip()
    if running != "true":
        run(["docker", "start", container_name])
        time.sleep(1)
    return container_name


def login_shell() -> None:
    student = os.environ.get("SUDO_USER") or os.environ.get("USER") or ""
    if not student:
        raise RuntimeError("Unable to determine the student account.")
    container_name = ensure_machine(student)
    docker_flags = ["-i"]
    if sys.stdin.isatty() and sys.stdout.isatty():
        docker_flags = ["-it"]
    os.execvp(
        "docker",
        [
            "docker",
            "exec",
            *docker_flags,
            container_name,
            "bash",
            "-lc",
            "SECRET_FLAG=$(cat /opt/.secret_flag 2>/dev/null || true); export SECRET_FLAG HOME=/home/ieee USER=ieee LOGNAME=ieee SHELL=/bin/bash; /usr/local/bin/welcome; exec runuser --preserve-environment -u ieee -- bash -l",
        ],
    )
