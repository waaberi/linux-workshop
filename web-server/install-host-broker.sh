#!/bin/bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
    echo "Run this script as root." >&2
    exit 1
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

WORKSHOP_IMAGE="linux-workshop"
WORKSHOP_NETWORK="workshop-net"
WORKSHOP_SUBNET="172.30.0.0/24"
WORKSHOP_CONTAINER_PREFIX="ws"
WORKSHOP_CPUS="1"
WORKSHOP_MEMORY="768m"
WORKSHOP_PIDS="256"
WORKSHOP_HOST_LABEL="$(hostname -f 2>/dev/null || hostname)"
WORKSHOP_REGISTRATION_BIND="0.0.0.0"
WORKSHOP_REGISTRATION_PORT="8088"
WORKSHOP_REGISTRATION_IP_LIMIT="1"
WORKSHOP_SESSION_SECRET=""
WORKSHOP_STATE_DB="/var/lib/workshop/registration.db"
REINSTALL=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --image) WORKSHOP_IMAGE="$2"; shift 2 ;;
        --network) WORKSHOP_NETWORK="$2"; shift 2 ;;
        --subnet) WORKSHOP_SUBNET="$2"; shift 2 ;;
        --prefix) WORKSHOP_CONTAINER_PREFIX="$2"; shift 2 ;;
        --cpus) WORKSHOP_CPUS="$2"; shift 2 ;;
        --memory) WORKSHOP_MEMORY="$2"; shift 2 ;;
        --pids) WORKSHOP_PIDS="$2"; shift 2 ;;
        --host-label) WORKSHOP_HOST_LABEL="$2"; shift 2 ;;
        --registration-bind) WORKSHOP_REGISTRATION_BIND="$2"; shift 2 ;;
        --registration-port) WORKSHOP_REGISTRATION_PORT="$2"; shift 2 ;;
        --reinstall) REINSTALL=1; shift ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if [ "$REINSTALL" -ne 1 ] && {
    [ -f /etc/systemd/system/workshop-registration.service ] ||
    [ -d /usr/local/lib/workshop/web-server ] ||
    [ -f /etc/ssh/sshd_config.d/workshop-broker.conf ];
}; then
    cat >&2 <<'EOF'
Workshop host broker already appears to be installed.

If you want to refresh or overwrite the current installation, rerun with:
  sudo ./install-host-broker.sh --reinstall
EOF
    exit 1
fi

for cmd in docker iptables sshd systemctl python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Required host command '$cmd' is missing." >&2
        exit 1
    fi
done

generate_session_secret() {
    python3 - <<'PY'
from __future__ import annotations

import secrets

print(secrets.token_hex(32))
PY
}

if [ -z "$WORKSHOP_SESSION_SECRET" ]; then
    WORKSHOP_SESSION_SECRET="$(generate_session_secret)"
fi

manage_ssh_service() {
    if systemctl list-unit-files sshd.service >/dev/null 2>&1; then
        systemctl enable --now sshd >/dev/null
        systemctl reload sshd >/dev/null 2>&1 || true
    elif systemctl list-unit-files ssh.service >/dev/null 2>&1; then
        systemctl enable --now ssh >/dev/null
        systemctl reload ssh >/dev/null 2>&1 || true
    else
        echo "Could not find an sshd systemd unit on this host." >&2
        exit 1
    fi
}

groupadd -f workshop-students

if [ -f /etc/workshop/registration.env ]; then
    existing_secret=$(sed -n 's/^WORKSHOP_SESSION_SECRET=//p' /etc/workshop/registration.env | tail -n 1)
    if [ -n "$existing_secret" ]; then
        WORKSHOP_SESSION_SECRET="$existing_secret"
    fi
fi

install -d -m 755 /usr/local/lib/workshop /usr/local/lib/workshop/web-server /usr/local/lib/workshop/web-server/views /etc/workshop /etc/ssh/sshd_config.d /var/lib/workshop
install -m 755 "$SCRIPT_DIR/workshop-login.sh" /usr/local/lib/workshop/workshop-login.sh
install -m 700 "$SCRIPT_DIR/ops.py" /usr/local/lib/workshop/web-server/ops.py
install -m 755 "$SCRIPT_DIR/workshop-register.sh" /usr/local/lib/workshop/web-server/workshop-register.sh
install -m 644 "$SCRIPT_DIR/requirements.txt" /usr/local/lib/workshop/web-server/requirements.txt
install -m 644 "$SCRIPT_DIR/app.py" /usr/local/lib/workshop/web-server/app.py
install -m 644 "$SCRIPT_DIR/model.py" /usr/local/lib/workshop/web-server/model.py
install -m 644 "$SCRIPT_DIR/views/layout.html" /usr/local/lib/workshop/web-server/views/layout.html
install -m 644 "$SCRIPT_DIR/views/home.html" /usr/local/lib/workshop/web-server/views/home.html
install -m 644 "$SCRIPT_DIR/views/student_dashboard.html" /usr/local/lib/workshop/web-server/views/student_dashboard.html
install -m 644 "$SCRIPT_DIR/views/not_found.html" /usr/local/lib/workshop/web-server/views/not_found.html

cat > /usr/local/bin/workshop-ops <<'EOF'
#!/bin/bash
set -euo pipefail
exec /usr/local/lib/workshop/web-server/ops.py "$@"
EOF
chmod 755 /usr/local/bin/workshop-ops

python3 -m venv /usr/local/lib/workshop/web-server/.venv
/usr/local/lib/workshop/web-server/.venv/bin/pip install --upgrade pip >/dev/null
/usr/local/lib/workshop/web-server/.venv/bin/pip install --requirement /usr/local/lib/workshop/web-server/requirements.txt >/dev/null

cat > /etc/workshop/broker.env <<EOF
WORKSHOP_IMAGE=${WORKSHOP_IMAGE}
WORKSHOP_NETWORK=${WORKSHOP_NETWORK}
WORKSHOP_SUBNET=${WORKSHOP_SUBNET}
WORKSHOP_CONTAINER_PREFIX=${WORKSHOP_CONTAINER_PREFIX}
WORKSHOP_CPUS=${WORKSHOP_CPUS}
WORKSHOP_MEMORY=${WORKSHOP_MEMORY}
WORKSHOP_PIDS=${WORKSHOP_PIDS}
EOF
chmod 600 /etc/workshop/broker.env

cat > /etc/workshop/registration.env <<EOF
WORKSHOP_HOST_LABEL=${WORKSHOP_HOST_LABEL}
WORKSHOP_REGISTRATION_BIND=${WORKSHOP_REGISTRATION_BIND}
WORKSHOP_REGISTRATION_PORT=${WORKSHOP_REGISTRATION_PORT}
WORKSHOP_REGISTRATION_IP_LIMIT=${WORKSHOP_REGISTRATION_IP_LIMIT}
WORKSHOP_SESSION_SECRET=${WORKSHOP_SESSION_SECRET}
WORKSHOP_STATE_DB=${WORKSHOP_STATE_DB}
WORKSHOP_REGISTRATION_TITLE=Workshop Login Registration
WORKSHOP_REGISTRATION_MESSAGE=Claim a username and password for the workshop.
EOF
chmod 600 /etc/workshop/registration.env

cat > /etc/sudoers.d/workshop-broker <<'EOF'
%workshop-students ALL=(root) NOPASSWD: /usr/local/lib/workshop/web-server/ops.py login-shell
EOF
chmod 440 /etc/sudoers.d/workshop-broker

cat > /etc/ssh/sshd_config.d/workshop-broker.conf <<'EOF'
Match Group workshop-students
    ForceCommand /usr/local/lib/workshop/workshop-login.sh
    PermitTTY yes
    PasswordAuthentication yes
    PubkeyAuthentication yes
    X11Forwarding no
    AllowAgentForwarding no
    AllowTcpForwarding no
    GatewayPorts no
    PermitTunnel no
EOF
chmod 600 /etc/ssh/sshd_config.d/workshop-broker.conf

cat > /etc/systemd/system/workshop-registration.service <<'EOF'
[Unit]
Description=Workshop registration website
After=network.target

[Service]
Type=simple
EnvironmentFile=/etc/workshop/registration.env
WorkingDirectory=/usr/local/lib/workshop/web-server
ExecStart=/usr/local/lib/workshop/web-server/workshop-register.sh
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

if ! docker network inspect "$WORKSHOP_NETWORK" >/dev/null 2>&1; then
    docker network create --subnet "$WORKSHOP_SUBNET" "$WORKSHOP_NETWORK" >/dev/null
fi

iptables -N WORKSHOP-EGRESS 2>/dev/null || true
iptables -F WORKSHOP-EGRESS
iptables -A WORKSHOP-EGRESS -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
iptables -A WORKSHOP-EGRESS -s "$WORKSHOP_SUBNET" -j REJECT --reject-with icmp-admin-prohibited
iptables -C DOCKER-USER -j WORKSHOP-EGRESS >/dev/null 2>&1 || iptables -I DOCKER-USER 1 -j WORKSHOP-EGRESS

systemctl daemon-reload
manage_ssh_service
systemctl enable workshop-registration.service >/dev/null
systemctl restart workshop-registration.service >/dev/null

cat <<EOF
Host broker installed.

Image:   ${WORKSHOP_IMAGE}
Network: ${WORKSHOP_NETWORK} (${WORKSHOP_SUBNET})

Next steps:
  1. Build the image: docker build -t ${WORKSHOP_IMAGE} ./user-container
  2. Optional manual user creation: sudo workshop-ops create-user <username> <password>
  3. Reset a machine: sudo workshop-ops reset-machine <username>
  4. Recoverable user deletion: sudo workshop-ops delete-user <username>
  5. Restore a deleted user: sudo workshop-ops restore-user <username> <password>
  6. Current workshop status: sudo workshop-ops status
  7. Registration site: http://${WORKSHOP_HOST_LABEL}:${WORKSHOP_REGISTRATION_PORT}/
  8. Students connect with: ssh <username>@${WORKSHOP_HOST_LABEL}
EOF
