#!/bin/bash
# common.sh — Shared constants and functions for entrypoint.sh and verifier.sh

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
SSH_SECRET_ENV_CONFIG="/etc/ssh/sshd_config.d/workshop-secret.conf"

generate_token() {
    printf '%s%s\n' "$1" "$(head -c 6 /dev/urandom | xxd -p)"
}

generate_hidden_port() {
    printf '%s\n' "$((RANDOM % 800 + 9100))"
}

write_secure_token() {
    generate_token "$1" > "$2"
    chmod 600 "$2"
}

worker_config_name() {
    case "$1" in
        1) printf 'app\n' ;;
        2) printf 'db\n' ;;
        3) printf 'cache\n' ;;
        4) printf 'queue\n' ;;
        *) return 1 ;;
    esac
}

start_worker_processes() {
    local config i secret slot

    secret=$(cat "$WORKER_SECRET_FILE")
    slot=$(cat "$WORKER_SLOT_FILE")

    for i in 1 2 3 4; do
        config=$(worker_config_name "$i") || continue
        if [ "$i" = "$slot" ]; then
            PROC_SECRET="$secret" runuser -u ieee -- bash "$HOME_DIR/.process_scripts/worker_idle.sh" "worker_${i}" "/etc/${config}.conf" &
        else
            runuser -u ieee -- bash "$HOME_DIR/.process_scripts/worker_idle.sh" "worker_${i}" "/etc/${config}.conf" &
        fi
    done
}

write_getflag_script() {
    local token

    token=$(cat "$PATH_FLAG_FILE")
    printf '#!/bin/bash\necho "%s"\n' "$token" > "$HOME_DIR/challenges/path/bin/getflag"
    chmod 755 "$HOME_DIR/challenges/path/bin/getflag"
    chown ieee:ieee "$HOME_DIR/challenges/path/bin/getflag"
}

randomize_big_file() {
    local dirs dir_index dir name path

    dirs=(logs data tmp)
    find "$HOME_DIR/challenges/search/files" -type f -name '*.bin' -delete

    dir_index=$((RANDOM % 3))
    dir="$HOME_DIR/challenges/search/files/${dirs[$dir_index]}"
    name="$(generate_token archive_).bin"
    path="$dir/$name"

    dd if=/dev/urandom of="$path" bs=1K count=200 status=none
    chown ieee:ieee "$path"
    printf '%s\n' "$path" > "$BIGFILE_PATH_FILE"
    chmod 600 "$BIGFILE_PATH_FILE"
}

write_service_config() {
    printf 'PORT=%s\nFLAG_FILE=%s\n' "$2" "$3" > "$1"
    chmod 600 "$1"
}

write_secret_env_config() {
    local secret

    secret=$(cat "$SECRET_FLAG_FILE")
    mkdir -p /etc/ssh/sshd_config.d
    printf 'SetEnv SECRET_FLAG=%s\n' "$secret" > "$SSH_SECRET_ENV_CONFIG"
    chmod 600 "$SSH_SECRET_ENV_CONFIG"
}
