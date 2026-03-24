#!/bin/bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
    echo "Run this script as root." >&2
    exit 1
fi

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Usage: $0 <username> <password> [comment]" >&2
    exit 1
fi

username="$1"
password="$2"
comment="${3:-}"

if ! [[ "$username" =~ ^[a-z][a-z0-9_-]{2,31}$ ]]; then
    echo "Username must match: ^[a-z][a-z0-9_-]{2,31}$" >&2
    exit 1
fi

if [ "${#password}" -lt 8 ]; then
    echo "Password must be at least 8 characters." >&2
    exit 1
fi

if ! getent group workshop-students >/dev/null 2>&1; then
    echo "Group workshop-students is missing. Run deploy/install-host-broker.sh first." >&2
    exit 1
fi

if id "$username" >/dev/null 2>&1; then
    if ! id -nG "$username" | tr ' ' '\n' | grep -qx 'workshop-students'; then
        echo "Existing user '$username' is not managed by the workshop broker." >&2
        exit 1
    fi
    usermod -a -G workshop-students "$username"
else
    useradd -m -s /bin/bash -G workshop-students "$username"
fi

echo "$username:$password" | chpasswd

home_dir=$(getent passwd "$username" | cut -d: -f6)
install -d -m 700 -o "$username" -g "$username" "$home_dir/.ssh"

if [ -n "$comment" ]; then
    printf '%s\n' "$comment" > "$home_dir/.workshop-note"
    chown "$username:$username" "$home_dir/.workshop-note"
fi

cat <<EOF
Provisioned workshop login for ${username}.

Student command:
  ssh ${username}@<host>
EOF
