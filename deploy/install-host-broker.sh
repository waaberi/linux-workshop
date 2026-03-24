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
WORKSHOP_REGISTRATION_CODE="$(head -c 12 /dev/urandom | xxd -p)"
REGISTRATION_CODE_EXPLICIT=0

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
        --registration-code) WORKSHOP_REGISTRATION_CODE="$2"; REGISTRATION_CODE_EXPLICIT=1; shift 2 ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

for cmd in docker iptables sshd systemctl python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Required host command '$cmd' is missing." >&2
        exit 1
    fi
done

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

if [ -f /etc/workshop/registration.env ] && [ "$REGISTRATION_CODE_EXPLICIT" -eq 0 ]; then
    existing_code=$(sed -n 's/^WORKSHOP_REGISTRATION_CODE=//p' /etc/workshop/registration.env | tail -n 1)
    if [ -n "$existing_code" ]; then
        WORKSHOP_REGISTRATION_CODE="$existing_code"
    fi
fi

install -d -m 755 /usr/local/lib/workshop /etc/workshop /etc/ssh/sshd_config.d
install -m 755 "$SCRIPT_DIR/workshop-login.sh" /usr/local/lib/workshop/workshop-login.sh
install -m 700 "$SCRIPT_DIR/workshop-login-root.sh" /usr/local/lib/workshop/workshop-login-root.sh
install -m 700 "$SCRIPT_DIR/provision-student.sh" /usr/local/lib/workshop/provision-student.sh
install -m 755 "$SCRIPT_DIR/workshop-register.py" /usr/local/lib/workshop/workshop-register.py

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
WORKSHOP_REGISTRATION_CODE=${WORKSHOP_REGISTRATION_CODE}
WORKSHOP_REGISTRATION_TITLE=Workshop Login Registration
WORKSHOP_REGISTRATION_MESSAGE=Claim a username and password for the workshop.
EOF
chmod 600 /etc/workshop/registration.env

cat > /etc/sudoers.d/workshop-broker <<'EOF'
%workshop-students ALL=(root) NOPASSWD: /usr/local/lib/workshop/workshop-login-root.sh
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
ExecStart=/usr/bin/python3 /usr/local/lib/workshop/workshop-register.py
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
  1. Build the image: docker build -t ${WORKSHOP_IMAGE} .
  2. Optional manual user creation: sudo ./deploy/provision-student.sh <username> <password>
  3. Registration site: http://${WORKSHOP_HOST_LABEL}:${WORKSHOP_REGISTRATION_PORT}/
  4. Invite code: ${WORKSHOP_REGISTRATION_CODE}
  5. Students connect with: ssh <username>@${WORKSHOP_HOST_LABEL}
EOF
