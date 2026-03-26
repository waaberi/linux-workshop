#!/bin/bash
# entrypoint.sh — Runs as root: starts services, then drops to ieee shell

source /opt/common.sh

AUDIT_DIR="$HOME_DIR/challenges/perms/audit"

configure_ssh_access() {
    : "${IEEE_PASSWORD:=ieee}"
    echo "ieee:${IEEE_PASSWORD}" | chpasswd
    mkdir -p /run/sshd /etc/ssh/sshd_config.d
    ssh-keygen -A >/dev/null 2>&1
}

start_network_services() {
    local hidden_port

    hidden_port=$(cat "$HIDDEN_PORT_FILE")

    write_service_config "$WEB_SERVICE_CONFIG" 8080 "$WEB_FLAG_FILE"
    write_service_config "$HIDDEN_SERVICE_CONFIG" "$hidden_port" "$HIDDEN_FLAG_FILE"

    python3 /opt/flag-server.py "$WEB_SERVICE_CONFIG" &
    python3 /opt/flag-server.py "$HIDDEN_SERVICE_CONFIG" &
}

# ============================================================
# First-boot initialization (randomize tokens, set permissions)
# ============================================================

if [ ! -f /opt/.initialized ]; then
    NEEDLE_TOKEN=$(generate_token NEEDLE_)
    sed -i "s/__NEEDLE_TOKEN__/$NEEDLE_TOKEN/" /home/ieee/challenges/files/server.log

    PIECES_TOKEN=$(generate_token PIECES_)
    sed -i "s/__PIECES_TOKEN__/$PIECES_TOKEN/" /home/ieee/challenges/files/pieces/part13.txt

    # 3.3 — randomize which audit file gets 600
    PERMS=(755 644 444 755 644)
    WINNER=$((RANDOM % 5 + 1))
    for i in 1 2 3 4 5; do
        if [ "$i" -eq "$WINNER" ]; then
            echo "AUDIT_PASS" > "$AUDIT_DIR/report${i}.txt"
            chmod 600 "$AUDIT_DIR/report${i}.txt"
        else
            chmod "${PERMS[$((i-1))]}" "$AUDIT_DIR/report${i}.txt"
        fi
    done
    chown ieee:ieee "$AUDIT_DIR"/report*.txt

    # 4.1 — randomize grep token
    GREP_TOKEN=$(generate_token GREP_)
    sed -i "s/__GREP_TOKEN__/$GREP_TOKEN/" /home/ieee/challenges/pipes/access.log

    # 4.2 — randomize stderr token
    write_secure_token STDERR_ /opt/.noisy_token

    # 4.3 — randomize pipeline token
    PIPE_TOKEN=$(generate_token PIPE_)
    echo "$PIPE_TOKEN" | rev | base64 > /opt/.pipe_token_encoded
    chmod 600 /opt/.pipe_token_encoded

    # 5.2 — randomize which file contains WORKSHOP_TOKEN
    SEARCH_DIR="/home/ieee/challenges/search/data"
    SEARCH_RAW=$((RANDOM % 30 + 1))
    SEARCH_NUM=$(printf '%02d' "$SEARCH_RAW")
    SEARCH_TOKEN=$(generate_token SEARCH_)
    printf 'Log entry %d: System check passed.\nWORKSHOP_TOKEN: %s\nEnd of log.\n' \
        "$SEARCH_RAW" "$SEARCH_TOKEN" > "$SEARCH_DIR/file_${SEARCH_NUM}.txt"
    chown ieee:ieee "$SEARCH_DIR/file_${SEARCH_NUM}.txt"

    write_secure_token SPY_ "$SPY_NAME_FILE"

    write_secure_token PROC_ "$WORKER_SECRET_FILE"
    printf '%s\n' "$((RANDOM % 4 + 1))" > "$WORKER_SLOT_FILE"
    chmod 600 "$WORKER_SLOT_FILE"

    write_secure_token ENV_ "$SECRET_FLAG_FILE"
    write_secure_token PATH_ "$PATH_FLAG_FILE"

    randomize_big_file

    write_secure_token WEB_ "$WEB_FLAG_FILE"
    write_secure_token HIDDEN_ "$HIDDEN_FLAG_FILE"
    generate_hidden_port > "$HIDDEN_PORT_FILE"
    chmod 600 "$HIDDEN_PORT_FILE"

    # 10.1 + 10.2 — ownership challenge tokens
    write_secure_token OWN_ "$OWNERSHIP_SECRET_FILE"
    write_secure_token REPORT_ "$OWNERSHIP_REPORT_FILE"

    touch /opt/.initialized
fi

if [ ! -f "$SPY_NAME_FILE" ]; then
    write_secure_token SPY_ "$SPY_NAME_FILE"
fi

if [ ! -f "$WORKER_SECRET_FILE" ] || [ ! -f "$WORKER_SLOT_FILE" ]; then
    write_secure_token PROC_ "$WORKER_SECRET_FILE"
    printf '%s\n' "$((RANDOM % 4 + 1))" > "$WORKER_SLOT_FILE"
    chmod 600 "$WORKER_SLOT_FILE"
fi

if [ ! -f "$SECRET_FLAG_FILE" ]; then
    write_secure_token ENV_ "$SECRET_FLAG_FILE"
fi

if [ ! -f "$PATH_FLAG_FILE" ]; then
    write_secure_token PATH_ "$PATH_FLAG_FILE"
fi

if [ ! -f "$BIGFILE_PATH_FILE" ] || [ ! -f "$(cat "$BIGFILE_PATH_FILE" 2>/dev/null)" ]; then
    randomize_big_file
fi

if [ ! -f "$WEB_FLAG_FILE" ]; then
    write_secure_token WEB_ "$WEB_FLAG_FILE"
fi

if [ ! -f "$HIDDEN_FLAG_FILE" ] || [ ! -f "$HIDDEN_PORT_FILE" ]; then
    write_secure_token HIDDEN_ "$HIDDEN_FLAG_FILE"
    generate_hidden_port > "$HIDDEN_PORT_FILE"
    chmod 600 "$HIDDEN_PORT_FILE"
fi

if [ ! -f "$OWNERSHIP_SECRET_FILE" ]; then
    write_secure_token OWN_ "$OWNERSHIP_SECRET_FILE"
fi

if [ ! -f "$OWNERSHIP_REPORT_FILE" ]; then
    write_secure_token REPORT_ "$OWNERSHIP_REPORT_FILE"
fi

# ============================================================
# Set up ownership challenge files (Concept 10)
# ============================================================

# 10.1: rewrite every boot (student doesn't modify this file)
cat "$OWNERSHIP_SECRET_FILE" > "$HOME_DIR/challenges/ownership/secret.txt"
chown root:root "$HOME_DIR/challenges/ownership/secret.txt"
chmod 600 "$HOME_DIR/challenges/ownership/secret.txt"

# 10.2 + 10.3: only set up if still placeholder (student modifies these)
if grep -q "PLACEHOLDER" "$HOME_DIR/challenges/ownership/report.txt" 2>/dev/null; then
    cat "$OWNERSHIP_REPORT_FILE" > "$HOME_DIR/challenges/ownership/report.txt"
    chown root:root "$HOME_DIR/challenges/ownership/report.txt"
    chmod 600 "$HOME_DIR/challenges/ownership/report.txt"
    setup_broken_project
fi

write_getflag_script
rm -f /etc/profile.d/workshop-secret.sh
write_secret_env_config
configure_ssh_access

SPY_NAME=$(cat "$SPY_NAME_FILE")
SECRET_FLAG=$(cat "$SECRET_FLAG_FILE")

# ============================================================
# Start background processes as ieee (for Concept 6)
# ============================================================

runuser -u ieee -- bash -c "exec -a \"$SPY_NAME\" sleep 99999" &
runuser -u ieee -- bash -c 'exec -a "cpu_hog" bash /home/ieee/.process_scripts/cpu_hog.sh' &
start_worker_processes

# ============================================================
# Start HTTP servers as ieee (for Concept 9)
# ============================================================

start_network_services

# ============================================================
# Touch recent config files for Challenge 5.3
# ============================================================

touch /home/ieee/challenges/search/configs/security.conf
touch /home/ieee/challenges/search/configs/updates.conf

# ============================================================
# Set old atimes for file-read verification
# ============================================================

find /home/ieee/labyrinth -type f -exec touch -a -t 200001010000.00 {} +
touch -a -t 200001010000.00 "$AUDIT_DIR"/report*.txt

# ============================================================
# Initialize verifier state (root-only)
# ============================================================

touch /opt/.cmd_log
chmod 600 /opt/.cmd_log
touch /opt/.progress /opt/.reset_markers
chmod 600 /opt/.progress /opt/.reset_markers
cp /home/ieee/.bashrc /opt/.bashrc_clean
chmod 600 /opt/.bashrc_clean

# ============================================================
# SSH server + optional local shell
# ============================================================

if [ -t 0 ] && [ -t 1 ]; then
    /usr/local/bin/welcome
    /usr/sbin/sshd -D -e >/dev/null 2>&1 &
    export SECRET_FLAG
    export HOME="$HOME_DIR"
    export USER="ieee"
    export LOGNAME="ieee"
    export SHELL="/bin/bash"
    exec runuser --preserve-environment -u ieee -- bash -l
else
    exec /usr/sbin/sshd -D -e
fi
