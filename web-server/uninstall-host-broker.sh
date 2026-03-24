#!/bin/bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
    echo "Run this script as root." >&2
    exit 1
fi

reload_ssh_service() {
    if systemctl list-unit-files sshd.service >/dev/null 2>&1; then
        systemctl reload sshd >/dev/null 2>&1 || true
    elif systemctl list-unit-files ssh.service >/dev/null 2>&1; then
        systemctl reload ssh >/dev/null 2>&1 || true
    fi
}

if [ -f /etc/systemd/system/workshop-registration.service ]; then
    systemctl disable --now workshop-registration.service >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/workshop-registration.service
    systemctl daemon-reload
    systemctl reset-failed workshop-registration.service >/dev/null 2>&1 || true
fi

rm -f /etc/ssh/sshd_config.d/workshop-broker.conf
rm -f /etc/sudoers.d/workshop-broker
rm -rf /usr/local/lib/workshop/web-server
rm -f /usr/local/lib/workshop/workshop-login.sh
rm -f /usr/local/bin/workshop-ops

if [ -d /usr/local/lib/workshop ] && [ -z "$(ls -A /usr/local/lib/workshop 2>/dev/null)" ]; then
    rmdir /usr/local/lib/workshop
fi

rm -f /etc/workshop/broker.env /etc/workshop/registration.env
if [ -d /etc/workshop ] && [ -z "$(ls -A /etc/workshop 2>/dev/null)" ]; then
    rmdir /etc/workshop
fi

while iptables -C DOCKER-USER -j WORKSHOP-EGRESS >/dev/null 2>&1; do
    iptables -D DOCKER-USER -j WORKSHOP-EGRESS >/dev/null 2>&1 || true
done
iptables -F WORKSHOP-EGRESS >/dev/null 2>&1 || true
iptables -X WORKSHOP-EGRESS >/dev/null 2>&1 || true

reload_ssh_service

cat <<'EOF'
Workshop host broker removed.

Kept in place:
  - workshop users and home directories
  - student containers and Docker images
  - /var/lib/workshop state
  - Docker network(s)

If you want to remove user accounts too, use:
  sudo workshop-ops delete-user <username>
EOF
