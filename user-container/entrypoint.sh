#!/bin/bash
set -euo pipefail
# entrypoint.sh — Runs as root: starts services, then drops to ieee shell

AUDIT_DIR="/home/ieee/challenges/perms/audit"
HOME_DIR="/home/ieee"
SPY_NAME_FILE="/opt/.spy_process_name"
WORKER_SECRET_FILE="/opt/.worker_secret"
WORKER_SLOT_FILE="/opt/.worker_secret_slot"
SECRET_FLAG_FILE="/opt/.secret_flag"
PATH_FLAG_FILE="/opt/.path_flag"
BIGFILE_PATH_FILE="/opt/.bigfile_path"
WEB_FLAG_FILE="/opt/.web_flag"
HIDDEN_FLAG_FILE="/opt/.hidden_flag"
HIDDEN_PORT_FILE="/opt/.hidden_port"
WEB_SERVICE_CONFIG="/opt/.web_service"
HIDDEN_SERVICE_CONFIG="/opt/.hidden_service"

generate_token() {
    printf '%s%s\n' "$1" "$(head -c 6 /dev/urandom | xxd -p)"
}

generate_hidden_port() {
    printf '%s\n' "$((RANDOM % 800 + 9100))"
}

write_secure_token() {
    local token

    token=$(generate_token "$1")
    printf '%s\n' "$token" > "$2"
    chmod 600 "$2"
}

write_getflag_script() {
    local token

    token=$(cat "$PATH_FLAG_FILE")
    printf '#!/bin/bash\necho "%s"\n' "$token" > /home/ieee/challenges/path/bin/getflag
    chmod 755 /home/ieee/challenges/path/bin/getflag
    chown ieee:ieee /home/ieee/challenges/path/bin/getflag
}

randomize_big_file() {
    local dirs dir_index dir name path

    dirs=(logs data tmp)
    find "$HOME_DIR/challenges/search/files" -type f -name '*.bin' -delete 2>/dev/null

    dir_index=$((RANDOM % 3))
    dir="$HOME_DIR/challenges/search/files/${dirs[$dir_index]}"
    name="$(generate_token archive_).bin"
    path="$dir/$name"

    dd if=/dev/urandom of="$path" bs=1K count=200 status=none
    chown ieee:ieee "$path"
    printf '%s\n' "$path" > "$BIGFILE_PATH_FILE"
    chmod 600 "$BIGFILE_PATH_FILE"
}

start_worker_processes() {
    local configs i secret slot

    configs=(app db cache queue)
    secret=$(cat "$WORKER_SECRET_FILE")
    slot=$(cat "$WORKER_SLOT_FILE")

    for i in 1 2 3 4; do
        if [ "$i" = "$slot" ]; then
            PROC_SECRET="$secret" runuser -u ieee -- bash /home/ieee/.process_scripts/worker_idle.sh "worker_${i}" "/etc/${configs[$((i-1))]}.conf" &
        else
            runuser -u ieee -- bash /home/ieee/.process_scripts/worker_idle.sh "worker_${i}" "/etc/${configs[$((i-1))]}.conf" &
        fi
    done
}

write_service_config() {
    printf 'PORT=%s\nFLAG_FILE=%s\n' "$2" "$3" > "$1"
    chmod 600 "$1"
}

start_flag_service() {
    local config_file="$1"
    local pid

    python3 /opt/flag-server.py "$config_file" &
    pid=$!
    sleep 0.2
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "Failed to start flag service for $config_file" >&2
        exit 1
    fi
}

start_network_services() {
    local hidden_port

    hidden_port=$(cat "$HIDDEN_PORT_FILE")

    write_service_config "$WEB_SERVICE_CONFIG" 8080 "$WEB_FLAG_FILE"
    write_service_config "$HIDDEN_SERVICE_CONFIG" "$hidden_port" "$HIDDEN_FLAG_FILE"

    start_flag_service "$WEB_SERVICE_CONFIG"
    start_flag_service "$HIDDEN_SERVICE_CONFIG"
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

write_getflag_script

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

# ============================================================
# Runtime mode
# ============================================================

if [ -t 0 ] && [ -t 1 ]; then
    /usr/local/bin/welcome
    export SECRET_FLAG
    export HOME="$HOME_DIR"
    export USER="ieee"
    export LOGNAME="ieee"
    export SHELL="/bin/bash"
    exec runuser --preserve-environment -u ieee -- bash -l
else
    exec tail -f /dev/null
fi
