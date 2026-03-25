#!/bin/bash
# verifier.sh — Unified verify, reset, and status logic for all challenges
# Runs as root via sudo. Subcommands: verify, reset, status

HOME="/home/ieee"
LOG="/opt/.cmd_log"
PROGRESS="/opt/.progress"
MARKERS="/opt/.reset_markers"
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
BASHRC_BASELINE="/opt/.bashrc.baseline"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Helpers ---

pass() {
    if grep -qx "$1" "$PROGRESS" 2>/dev/null; then
        echo ""
        echo -e "${YELLOW}Challenge $1 was already verified before.${NC}"
        echo -e "${YELLOW}If you want to attempt it again from scratch, run: reset $1${NC}"
        echo ""
    else
        echo "$1" >> "$PROGRESS"
        echo ""
        echo -e "${GREEN}==============================${NC}"
        echo -e "${GREEN}  Challenge $1 complete!${NC}"
        echo -e "${GREEN}  FLAG{$2}${NC}"
        echo -e "${GREEN}==============================${NC}"
        echo ""
    fi
}

fail() {
    echo ""
    echo -e "${RED}  Not quite.${NC} $1"
    echo ""
}

hint() {
    echo -e "${YELLOW}Hint:${NC} $1"
}

logged() {
    grep -qE "$1" "$LOG" 2>/dev/null
}

touch_secure_file() {
    touch "$1" 2>/dev/null
    chmod 600 "$1" 2>/dev/null
}

get_log_marker() {
    sed -n "s/^$1://p" "$MARKERS" 2>/dev/null | tail -n 1
}

set_log_marker() {
    local lines

    lines=$(wc -l < "$LOG" 2>/dev/null || echo 0)
    touch_secure_file "$MARKERS"
    sed -i "/^$1:/d" "$MARKERS" 2>/dev/null
    printf '%s:%s\n' "$1" "$lines" >> "$MARKERS"
}

logged_since() {
    local marker
    local line

    marker=$(get_log_marker "$1")
    case "$marker" in
        ''|*[!0-9]*) marker=0 ;;
    esac

    while IFS=: read -r line _; do
        [ "$line" -gt "$marker" ] && return 0
    done < <(grep -nE "$2" "$LOG" 2>/dev/null)

    return 1
}

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
    printf '%s\n' "$token"
}

verify_file_match() {
    local id="$1" flag="$2" file="$3" expected="$4"
    local empty_hint="$5" wrong_hint="$6"
    local actual

    actual=$(cat "$HOME/$file" 2>/dev/null)
    if [ -z "$actual" ]; then
        fail "File ~/$file not found or is empty."
        hint "$empty_hint"
    elif [ "$actual" = "$expected" ]; then
        pass "$id" "$flag"
    else
        fail "~/$file doesn't contain the correct output."
        hint "$wrong_hint"
    fi
}

write_getflag_script() {
    local token

    token=$(cat "$PATH_FLAG_FILE" 2>/dev/null)
    printf '#!/bin/bash\necho "%s"\n' "$token" > "$HOME/challenges/path/bin/getflag"
    chmod 755 "$HOME/challenges/path/bin/getflag"
    chown ieee:ieee "$HOME/challenges/path/bin/getflag"
}

randomize_big_file() {
    local dirs dir_index dir name path

    dirs=(logs data tmp)
    find "$HOME/challenges/search/files" -type f -name '*.bin' -delete 2>/dev/null

    dir_index=$((RANDOM % 3))
    dir="$HOME/challenges/search/files/${dirs[$dir_index]}"
    name="$(generate_token archive_).bin"
    path="$dir/$name"

    dd if=/dev/urandom of="$path" bs=1K count=200 status=none
    chown ieee:ieee "$path"
    printf '%s\n' "$path" > "$BIGFILE_PATH_FILE"
    chmod 600 "$BIGFILE_PATH_FILE"
}

spy_process_running() {
    ps -eo args= | grep -Fx "$1 99999" > /dev/null 2>&1
}

start_spy_process() {
    runuser -u ieee -- bash -c "exec -a \"$1\" sleep 99999" &
}

worker_secret_running() {
    local slot

    slot=$(cat "$WORKER_SLOT_FILE" 2>/dev/null)
    ps -eo args= | grep -Fx "worker_${slot} --config=/etc/$(worker_config_name "$slot").conf 99999" > /dev/null 2>&1
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

stop_worker_processes() {
    local i

    for i in 1 2 3 4; do
        pkill -f "^worker_${i} " > /dev/null 2>&1 || true
    done
}

start_worker_processes() {
    local config i secret slot

    secret=$(cat "$WORKER_SECRET_FILE" 2>/dev/null)
    slot=$(cat "$WORKER_SLOT_FILE" 2>/dev/null)

    for i in 1 2 3 4; do
        config=$(worker_config_name "$i") || continue
        if [ "$i" = "$slot" ]; then
            PROC_SECRET="$secret" runuser -u ieee -- bash /home/ieee/.process_scripts/worker_idle.sh "worker_${i}" "/etc/${config}.conf" &
        else
            runuser -u ieee -- bash /home/ieee/.process_scripts/worker_idle.sh "worker_${i}" "/etc/${config}.conf" &
        fi
    done
}

write_service_config() {
    printf 'PORT=%s\nFLAG_FILE=%s\n' "$2" "$3" > "$1"
    chmod 600 "$1"
}

normalize_path() {
    if [ -z "${1:-}" ]; then
        return 1
    fi
    readlink -f -- "$1" 2>/dev/null
}

sorted_normalized_file_paths() {
    local file="$1"
    local line
    local normalized=()

    [ -f "$file" ] || return 1

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        line=${line%$'\r'}
        if [[ "$line" != /* ]]; then
            line="$HOME/$line"
        fi
        line=$(normalize_path "$line") || continue
        normalized+=("$line")
    done < "$file"

    [ "${#normalized[@]}" -gt 0 ] || return 1
    printf '%s\n' "${normalized[@]}" | sort -u
}

worker_secret_process_running() {
    local proc_dir
    local cmdline
    local environ

    for proc_dir in /proc/[0-9]*; do
        [ -r "$proc_dir/cmdline" ] || continue
        [ -r "$proc_dir/environ" ] || continue

        cmdline=$(tr '\0' ' ' < "$proc_dir/cmdline" 2>/dev/null || true)
        case "$cmdline" in
            worker_[1-4]\ --config=/etc/*.conf\ 99999\ *) ;;
            *) continue ;;
        esac

        environ=$(tr '\0' '\n' < "$proc_dir/environ" 2>/dev/null || true)
        grep -Fx "PROC_SECRET=$1" <<< "$environ" > /dev/null 2>&1 && return 0
    done

    return 1
}

start_flag_service() {
    python3 /opt/flag-server.py "$1" &
}

stop_flag_service() {
    pkill -f "/opt/flag-server.py $1$" > /dev/null 2>&1 || true
}

restart_network_services() {
    local hidden_port

    hidden_port=$(cat "$HIDDEN_PORT_FILE" 2>/dev/null)

    write_service_config "$WEB_SERVICE_CONFIG" 8080 "$WEB_FLAG_FILE"
    write_service_config "$HIDDEN_SERVICE_CONFIG" "$hidden_port" "$HIDDEN_FLAG_FILE"

    stop_flag_service "$WEB_SERVICE_CONFIG"
    stop_flag_service "$HIDDEN_SERVICE_CONFIG"
    start_flag_service "$WEB_SERVICE_CONFIG"
    start_flag_service "$HIDDEN_SERVICE_CONFIG"
}

reset_msg() {
    sed -i "/^${1}$/d" "$PROGRESS" 2>/dev/null
    echo ""
    echo -e "${CYAN}Challenge $1 has been reset.${NC}"
    echo ""
}

# ============================================================
# Challenge 1.1 — Where Am I?
# ============================================================

verify_1_1() {
    if logged_since "1.1" "\bpwd\b"; then
        pass "1.1" "you_are_here"
    else
        fail "Run 'pwd' first to see your current directory."
    fi
}

reset_1_1() {
    set_log_marker "1.1"
    reset_msg "1.1"
}

# ============================================================
# Challenge 1.2 — The Labyrinth
# ============================================================

verify_1_2() {
    local flag_file atime

    flag_file="$HOME/labyrinth/right/passage/chamber/flag.txt"
    atime=$(stat -c %X "$flag_file" 2>/dev/null || echo 0)

    if [ "$atime" -gt 946684800 ] || logged_since "1.2" "((^|[[:space:];|&(])((cat|less|more|head|tail|grep|sed|awk)([[:space:]]+[^;&|()]*)*[[:space:]]+([^[:space:]]*/)?flag\.txt([[:space:];|&)]|$))|((^|[[:space:];|&(])([^[:space:]]*/)?flag\.txt([[:space:]]|$)))"; then
        pass "1.2" "labyrinth_solved"
    else
        fail "Navigate through ~/labyrinth/ and read the flag.txt file."
        hint "Use 'ls' to explore directories and 'cd' to move into them."
    fi
}

reset_1_2() {
    find "$HOME/labyrinth" -type f -exec touch -a -t 200001010000.00 {} +
    set_log_marker "1.2"
    reset_msg "1.2"
}

# ============================================================
# Challenge 1.3 — Broken Link
# ============================================================

verify_1_3() {
    LINK="$HOME/links/link_gamma"
    TARGET="$HOME/links/targets/gamma.txt"
    if [ -L "$LINK" ] && [ "$(readlink -f "$LINK")" = "$TARGET" ]; then
        pass "1.3" "link_fixer"
    elif [ -L "$LINK" ]; then
        fail "link_gamma exists but still doesn't point to the right place."
        hint "Check where the other working links point — see the pattern?"
    else
        fail "The broken link needs to be fixed, not just removed."
        hint "Use 'ls -l' to compare the working links with the broken one."
    fi
}

reset_1_3() {
    rm -f "$HOME/links/link_gamma"
    ln -s "/old/path/gamma.txt" "$HOME/links/link_gamma"
    chown -h ieee:ieee "$HOME/links/link_gamma"
    reset_msg "1.3"
}

# ============================================================
# Challenge 2.1 — Edit a Config
# ============================================================

verify_2_1() {
    CONFIG="$HOME/challenges/files/config.txt"
    if grep -q "^mode=on$" "$CONFIG" 2>/dev/null; then
        pass "2.1" "config_editor"
    elif grep -q "^mode=off$" "$CONFIG" 2>/dev/null; then
        fail "The 'mode' setting is still set to 'off'."
        hint "Open the file in a text editor like nano and change the value."
    else
        fail "The 'mode' line seems to have been removed or malformed."
        hint "The line should read exactly: mode=on"
    fi
}

reset_2_1() {
    cat > "$HOME/challenges/files/config.txt" << 'EOF'
# Application Configuration
name=workshop
version=1.0
mode=off
debug=false
EOF
    chown ieee:ieee "$HOME/challenges/files/config.txt"
    reset_msg "2.1"
}

# ============================================================
# Challenge 2.2 — Piece It Together
# ============================================================

verify_2_2() {
    verify_file_match "2.2" "cat_concat_master" "pieces.txt" \
        "$(cat "$HOME/challenges/files/pieces"/part*.txt 2>/dev/null)" \
        "Concatenate all the part files and redirect the output to ~/pieces.txt." \
        "Make sure you're concatenating all 20 files in order."
}

reset_2_2() {
    local i
    local token

    for i in $(seq -w 1 20); do
        printf 'Log fragment %s: system nominal\n' "$i" > "$HOME/challenges/files/pieces/part${i}.txt"
    done
    token="PIECES_$(head -c 6 /dev/urandom | xxd -p)"
    printf '%s\n' "$token" > "$HOME/challenges/files/pieces/part13.txt"
    chown ieee:ieee "$HOME/challenges/files/pieces"/part*.txt
    rm -f "$HOME/pieces.txt"
    reset_msg "2.2"
}

# ============================================================
# Challenge 2.3 — Needle in a Log
# ============================================================

verify_2_3() {
    verify_file_match "2.3" "log_line_6743" "line.txt" \
        "$(sed -n '6743p' "$HOME/challenges/files/server.log")" \
        "Extract the line and save it to a file using output redirection (>)." \
        "Make sure you're extracting exactly line 6,743 — not the lines around it."
}

reset_2_3() {
    local token

    token="NEEDLE_$(head -c 6 /dev/urandom | xxd -p)"
    sed -i "6743s/.*/2024-03-15 14:23:06743 [INFO] ${token}/" "$HOME/challenges/files/server.log"
    chown ieee:ieee "$HOME/challenges/files/server.log"
    rm -f "$HOME/line.txt"
    reset_msg "2.3"
}

# ============================================================
# Challenge 3.1 — Make It Run
# ============================================================

verify_3_1() {
    local out

    if ! runuser -u ieee -- test -x "$HOME/challenges/perms/show_flag.sh"; then
        fail "The script still isn't executable."
        hint "chmod can add the execute permission to a file."
        return
    fi

    out=$(runuser -u ieee -- "$HOME/challenges/perms/show_flag.sh" 2>/dev/null || true)
    if [ "$out" = "EXECUTE_SUCCESS" ]; then
        pass "3.1" "execute_permission"
    else
        fail "The script is executable, but it does not run correctly yet."
        hint "Run the script directly and make sure it prints the expected message."
    fi
}

reset_3_1() {
    chmod 644 "$HOME/challenges/perms/show_flag.sh"
    reset_msg "3.1"
}

# ============================================================
# Challenge 3.2 — Locked Out
# ============================================================

verify_3_2() {
    if runuser -u ieee -- test -r "$HOME/challenges/perms/classified.txt"; then
        pass "3.2" "access_unlocked"
    else
        fail "The file still isn't readable."
        hint "chmod can add read permission for the file owner."
    fi
}

reset_3_2() {
    chmod 000 "$HOME/challenges/perms/classified.txt"
    reset_msg "3.2"
}

# ============================================================
# Challenge 3.3 — Permission Audit
# ============================================================

verify_3_3() {
    local audit_dir target perm atime target_name f

    audit_dir="$HOME/challenges/perms/audit"
    target=""
    for f in "$audit_dir"/report*.txt; do
        perm=$(stat -c '%a' "$f" 2>/dev/null || true)
        [ "$perm" = "600" ] && target="$f"
    done

    if [ -z "$target" ]; then
        fail "Challenge state is broken — no 600-permission file found."
        hint "Run 'reset 3.3' to restore the challenge state."
        return
    fi

    atime=$(stat -c '%X' "$target" 2>/dev/null || echo 0)
    target_name=$(basename "$target")

    if [ "$atime" -gt 946684800 ] || logged_since "3.3" "((^|[[:space:];|&(])((cat|less|more|head|tail|grep|sed|awk)([[:space:]]+[^;&|()]*)*[[:space:]]+([^[:space:]]*/)?${target_name}([[:space:];|&)]|$))|((^|[[:space:];|&(])([^[:space:]]*/)?${target_name}([[:space:]]|$)))"; then
        pass "3.3" "permission_reader"
    else
        fail "You haven't read the 600-permission file yet."
        hint "Use 'ls -l' to inspect permissions, then read the file that matches 600."
    fi
}

reset_3_3() {
    local perms
    local winner
    local i

    perms=(755 644 444 755 644)
    winner=$((RANDOM % 5 + 1))
    for i in 1 2 3 4 5; do
        if [ "$i" -eq "$winner" ]; then
            printf 'AUDIT_PASS\n' > "$HOME/challenges/perms/audit/report${i}.txt"
            chmod 600 "$HOME/challenges/perms/audit/report${i}.txt"
        else
            printf 'Nothing interesting in this file.\n' > "$HOME/challenges/perms/audit/report${i}.txt"
            chmod "${perms[$((i-1))]}" "$HOME/challenges/perms/audit/report${i}.txt"
        fi
    done
    chown ieee:ieee "$HOME/challenges/perms/audit"/report*.txt
    touch -a -t 200001010000.00 "$HOME/challenges/perms/audit"/report*.txt
    set_log_marker "3.3"
    reset_msg "3.3"
}

# ============================================================
# Challenge 4.1 — The Pipeline
# ============================================================

verify_4_1() {
    verify_file_match "4.1" "pipe_it_all" "pipeline.txt" \
        "$("$HOME/challenges/pipes/step1" | "$HOME/challenges/pipes/step2" | "$HOME/challenges/pipes/step3" 2>/dev/null)" \
        "Pipe the three programs together and redirect the final output to a file." \
        "Make sure you pipe all three in the right order: step1 | step2 | step3."
}

reset_4_1() {
    printf '%s\n' "PIPE_$(head -c 6 /dev/urandom | xxd -p)" | rev | base64 > /opt/.pipe_token_encoded
    chmod 600 /opt/.pipe_token_encoded
    rm -f "$HOME/pipeline.txt"
    reset_msg "4.1"
}

# ============================================================
# Challenge 4.2 — Grep the Logs
# ============================================================

verify_4_2() {
    verify_file_match "4.2" "grep_the_logs" "grep_result.txt" \
        "$(grep "secret" "$HOME/challenges/pipes/access.log" 2>/dev/null)" \
        "Use grep to find the unusual line, then redirect the output to a file." \
        "Look at what 'normal' lines have in common. Grep for something different."
}

reset_4_2() {
    local i
    local token

    for i in $(seq 1 5000); do
        printf '192.168.1.%d - - [15/Mar/2024:10:23:%05d] "GET /page%d" 200 -\n' $((RANDOM % 254 + 1)) "$i" "$i"
    done > "$HOME/challenges/pipes/access.log"
    token="GREP_$(head -c 6 /dev/urandom | xxd -p)"
    sed -i "3847s/.*/192.168.1.42 - - [15\/Mar\/2024:10:23:03847] \"GET \/secret\" 200 ${token}/" "$HOME/challenges/pipes/access.log"
    chown ieee:ieee "$HOME/challenges/pipes/access.log"
    rm -f "$HOME/grep_result.txt"
    reset_msg "4.2"
}

# ============================================================
# Challenge 4.3 — Noisy Program
# ============================================================

verify_4_3() {
    EXPECTED=$(cat /opt/.noisy_token 2>/dev/null)
    ACTUAL=$(cat "$HOME/errors.txt" 2>/dev/null)
    if [ -z "$ACTUAL" ]; then
        fail "File ~/errors.txt not found or is empty."
        hint "Run the noisy program and redirect its stderr to ~/errors.txt."
    elif [ "$ACTUAL" = "$EXPECTED" ] && logged_since "4.3" '(^|[[:space:]])([^[:space:]]*/)?noisy([[:space:]]|$).*2>>?[[:space:]]*(~|\$HOME|/home/ieee)/errors\.txt|2>>?[[:space:]]*(~|\$HOME|/home/ieee)/errors\.txt.*(^|[[:space:]])([^[:space:]]*/)?noisy([[:space:]]|$)' ; then
        pass "4.3" "stderr_secrets"
    elif [ "$ACTUAL" = "$EXPECTED" ]; then
        fail "~/errors.txt has the right contents, but stderr wasn't redirected from noisy since the last reset."
        hint "Run ~/challenges/pipes/noisy with 2> ~/errors.txt to capture only stderr."
    else
        fail "~/errors.txt doesn't contain the stderr message."
        hint "Make sure you're redirecting stderr (stream 2), not stdout."
    fi
}

reset_4_3() {
    printf 'STDERR_%s\n' "$(head -c 6 /dev/urandom | xxd -p)" > /opt/.noisy_token
    chmod 600 /opt/.noisy_token
    rm -f "$HOME/errors.txt"
    reset_msg "4.3"
}

# ============================================================
# Challenge 5.1 — Find the Big File
# ============================================================

verify_5_1() {
    EXPECTED=$(cat "$BIGFILE_PATH_FILE" 2>/dev/null)
    ACTUAL=$(sed -n '1{s/[[:space:]]*$//;p;}' "$HOME/bigfile.txt" 2>/dev/null)
    if [ -z "$EXPECTED" ]; then
        fail "Challenge state is missing the large file path."
        hint "Run 'reset 5.1' to restore the challenge state, then try again."
    elif [ -z "$ACTUAL" ]; then
        fail "File ~/bigfile.txt not found or is empty."
        hint "Use 'find' with a size filter, then save the result to ~/bigfile.txt."
    elif [ "$(normalize_path "$ACTUAL")" = "$(normalize_path "$EXPECTED")" ]; then
        pass "5.1" "big_file_found"
    else
        fail "~/bigfile.txt doesn't contain the correct path."
        hint "Make sure you're searching for files over 100K in ~/challenges/search/files/."
    fi
}

reset_5_1() {
    randomize_big_file
    rm -f "$HOME/bigfile.txt"
    reset_msg "5.1"
}

# ============================================================
# Challenge 5.2 — Search Inside Files
# ============================================================

verify_5_2() {
    local expected_recursive
    local expected_line
    local actual

    expected_recursive=$(grep -r "WORKSHOP_TOKEN" "$HOME/challenges/search/data/" 2>/dev/null)
    expected_line=$(printf '%s\n' "$expected_recursive" | sed 's|^[^:]*:||')
    actual=$(cat "$HOME/token.txt" 2>/dev/null)

    if [ -z "$actual" ]; then
        fail "File ~/token.txt not found or is empty."
        hint "Use grep to search recursively, then redirect the matching result to ~/token.txt."
    elif [ "$actual" = "$expected_recursive" ] || [ "$actual" = "$expected_line" ]; then
        pass "5.2" "recursive_grep"
    else
        fail "~/token.txt doesn't contain the correct grep result."
        hint "Search for the exact string 'WORKSHOP_TOKEN' across the directory and save either the recursive grep result or the matching line."
    fi
}

reset_5_2() {
    local i
    local target
    local token

    for i in $(seq -w 1 30); do
        printf 'Log entry %s: Nothing relevant here.\nData processed at timestamp %d.\n' "$i" "$((1000 + 10#$i))" \
            > "$HOME/challenges/search/data/file_${i}.txt"
    done
    target=$(printf '%02d' $((RANDOM % 30 + 1)))
    token="SEARCH_$(head -c 6 /dev/urandom | xxd -p)"
    printf 'Log entry %s: System check passed.\nWORKSHOP_TOKEN: %s\nEnd of log.\n' "$target" "$token" \
        > "$HOME/challenges/search/data/file_${target}.txt"
    chown ieee:ieee "$HOME/challenges/search/data"/file_*.txt
    rm -f "$HOME/token.txt"
    reset_msg "5.2"
}

# ============================================================
# Challenge 5.3 — Recent Changes
# ============================================================

verify_5_3() {
    EXPECTED=$(find "$HOME/challenges/search/configs/" -name "*.conf" -mtime -7 2>/dev/null | sort)
    ACTUAL=$(sorted_normalized_file_paths "$HOME/recent.txt" 2>/dev/null || true)
    if [ -z "$ACTUAL" ]; then
        fail "File ~/recent.txt not found or is empty."
        hint "Use 'find' with a time filter, then redirect the output to ~/recent.txt."
    elif [ "$ACTUAL" = "$EXPECTED" ]; then
        pass "5.3" "recent_changes"
    else
        fail "~/recent.txt doesn't contain the correct file paths."
        hint "Make sure you're filtering for .conf files modified within the last 7 days."
    fi
}

reset_5_3() {
    local name

    for name in database network cache logging auth; do
        printf '# Old configuration file: %s.conf\nstatus=deprecated\n' "$name" \
            > "$HOME/challenges/search/configs/${name}.conf"
        touch -d '30 days ago' "$HOME/challenges/search/configs/${name}.conf"
    done
    printf '# Updated configuration\nstatus=active\n' > "$HOME/challenges/search/configs/security.conf"
    printf '# Updated configuration\nstatus=active\n' > "$HOME/challenges/search/configs/updates.conf"
    chown ieee:ieee "$HOME/challenges/search/configs"/*.conf
    rm -f "$HOME/recent.txt"
    reset_msg "5.3"
}

# ============================================================
# Challenge 6.1 — Spy on Processes
# ============================================================

verify_6_1() {
    EXPECTED=$(cat "$SPY_NAME_FILE" 2>/dev/null)
    ACTUAL=$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$HOME/spy_name.txt" 2>/dev/null)

    if [ -z "$EXPECTED" ]; then
        fail "Challenge state is missing the unusual process name."
        hint "Run 'reset 6.1' to restore the challenge state, then try again."
    elif [ -z "$ACTUAL" ]; then
        fail "File ~/spy_name.txt not found or is empty."
        hint "Use 'ps' to find the unusual process, then save just its name to ~/spy_name.txt."
    elif [ "$ACTUAL" = "$EXPECTED" ]; then
        if spy_process_running "$EXPECTED"; then
            pass "6.1" "process_spotted"
        else
            fail "The unusual process doesn't seem to be running right now."
            hint "Run 'reset 6.1' to restore the challenge state, then look for the process again."
        fi
    elif [ "$ACTUAL" = "$EXPECTED 99999" ] || [[ "$ACTUAL" == *[[:space:]]* ]]; then
        fail "~/spy_name.txt should contain only the unusual process name."
        hint "Save just the standout name, not the PID or the full ps output line."
    elif spy_process_running "$ACTUAL"; then
        fail "~/spy_name.txt contains a running process name, but not the unusual one for this challenge."
        hint "Look for the standout process name in the ps output and save only that name."
    elif logged_since "6.1" "ps\b"; then
        fail "~/spy_name.txt doesn't contain the correct process name."
        hint "Save only the unusual process name, not the PID or the full ps output."
    else
        fail "Use 'ps' to find the unusual process, then save its name to ~/spy_name.txt."
        hint "Try 'ps' with options to show all processes. Look for the standout name."
    fi
}

reset_6_1() {
    CURRENT=$(cat "$SPY_NAME_FILE" 2>/dev/null)
    if [ -n "$CURRENT" ]; then
        pkill -f "^${CURRENT} 99999$" > /dev/null 2>&1 || true
    fi
    NEXT=$(write_secure_token SPY_ "$SPY_NAME_FILE")
    start_spy_process "$NEXT"
    rm -f "$HOME/spy_name.txt"
    set_log_marker "6.1"
    reset_msg "6.1"
}

# ============================================================
# Challenge 6.2 — Stop the Hog
# ============================================================

verify_6_2() {
    if pgrep -f "cpu_hog" > /dev/null 2>&1; then
        fail "The cpu_hog process is still running!"
        hint "Use 'ps' to find its PID, then use 'kill' to stop it."
    else
        pass "6.2" "kill_confirmed"
    fi
}

reset_6_2() {
    pkill -f "cpu_hog" > /dev/null 2>&1 || true
    runuser -u ieee -- bash -c 'exec -a "cpu_hog" bash /home/ieee/.process_scripts/cpu_hog.sh' &
    reset_msg "6.2"
}

# ============================================================
# Challenge 6.3 — Inside /proc
# ============================================================

verify_6_3() {
    EXPECTED=$(cat "$WORKER_SECRET_FILE" 2>/dev/null)
    ACTUAL=$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$HOME/worker_secret.txt" 2>/dev/null)

    if [ -z "$EXPECTED" ]; then
        fail "Challenge state is missing the worker secret."
        hint "Run 'reset 6.3' to restore the challenge state, then try again."
    elif [ -z "$ACTUAL" ]; then
        fail "File ~/worker_secret.txt not found or is empty."
        hint "Find the right worker PID, read /proc/<PID>/environ, and save just the secret value to ~/worker_secret.txt."
    elif [ "$ACTUAL" = "$EXPECTED" ]; then
        if worker_secret_process_running "$EXPECTED"; then
            pass "6.3" "proc_explorer"
        else
            fail "The worker carrying the secret doesn't seem to be running right now."
            hint "Run 'reset 6.3' to restore the challenge state, then find the worker again."
        fi
    elif [[ "$ACTUAL" == *[[:space:]]* ]]; then
        fail "~/worker_secret.txt should contain only the secret value."
        hint "Save just the secret, not the full environ output."
    elif logged_since "6.3" "/proc/.*environ"; then
        fail "~/worker_secret.txt doesn't contain the correct secret."
        hint "Inspect the worker environments carefully and copy only the secret value."
    else
        fail "Find the right worker PID, read /proc/<PID>/environ, and save the secret to ~/worker_secret.txt."
        hint "Use 'ps' to list the worker processes first, then inspect /proc/<PID>/environ."
    fi
}

reset_6_3() {
    write_secure_token PROC_ "$WORKER_SECRET_FILE" > /dev/null
    WORKER_SLOT=$((RANDOM % 4 + 1))
    printf '%s\n' "$WORKER_SLOT" > "$WORKER_SLOT_FILE"
    chmod 600 "$WORKER_SLOT_FILE"
    stop_worker_processes
    start_worker_processes
    rm -f "$HOME/worker_secret.txt"
    set_log_marker "6.3"
    reset_msg "6.3"
}

# ============================================================
# Challenge 7.1 — Hidden in the Environment
# ============================================================

verify_7_1() {
    EXPECTED=$(cat "$SECRET_FLAG_FILE" 2>/dev/null)
    ACTUAL=$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$HOME/secret_flag.txt" 2>/dev/null)

    if [ -z "$EXPECTED" ]; then
        fail "Challenge state is missing SECRET_FLAG."
        hint "Run 'reset 7.1' to restore the challenge state, then try again."
    elif [ -z "$ACTUAL" ]; then
        fail "File ~/secret_flag.txt not found or is empty."
        hint "Use printenv or echo to find SECRET_FLAG, then save just its value to ~/secret_flag.txt."
    elif [ "$ACTUAL" = "$EXPECTED" ] && logged_since "7.1" "printenv|echo.*SECRET_FLAG|env\b"; then
        pass "7.1" "env_variable"
    elif [ "$ACTUAL" = "$EXPECTED" ]; then
        fail "You found the right value, but not by using the environment tools since the last reset."
        hint "Use printenv or echo to reveal SECRET_FLAG, then save its value to ~/secret_flag.txt."
    elif [[ "$ACTUAL" == SECRET_FLAG=* ]] || [[ "$ACTUAL" == *=* ]]; then
        fail "~/secret_flag.txt should contain only the variable value."
        hint "Save just the SECRET_FLAG value, not 'SECRET_FLAG=' or extra text."
    elif logged_since "7.1" "printenv|echo.*SECRET_FLAG|env\b"; then
        fail "~/secret_flag.txt doesn't contain the correct SECRET_FLAG value."
        hint "Double-check the variable output and save only its value."
    else
        fail "Use printenv or echo to find SECRET_FLAG, then save its value to ~/secret_flag.txt."
        hint "Environment variables can be printed with 'printenv' or 'echo \$VARNAME'."
    fi
}

reset_7_1() {
    if [ ! -f "$SECRET_FLAG_FILE" ]; then
        write_secure_token ENV_ "$SECRET_FLAG_FILE" > /dev/null
    fi
    rm -f "$HOME/secret_flag.txt"
    set_log_marker "7.1"
    reset_msg "7.1"
}

# ============================================================
# Challenge 7.2 — Extend Your PATH
# ============================================================

verify_7_2() {
    EXPECTED=$(cat "$PATH_FLAG_FILE" 2>/dev/null)
    ACTUAL=$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$HOME/path_flag.txt" 2>/dev/null)

    if [ -z "$EXPECTED" ]; then
        fail "Challenge state is missing the getflag output token."
        hint "Run 'reset 7.2' to restore the challenge state, then try again."
    elif [ -z "$ACTUAL" ]; then
        fail "File ~/path_flag.txt not found or is empty."
        hint "Add ~/challenges/path/bin to PATH, run getflag, and save its output to ~/path_flag.txt."
    elif [ "$ACTUAL" = "$EXPECTED" ] && logged_since "7.2" "(export.*PATH|PATH=).*path/bin" && logged_since "7.2" "\bgetflag\b"; then
        pass "7.2" "path_updated"
    elif [ "$ACTUAL" = "$EXPECTED" ] && logged_since "7.2" "(export.*PATH|PATH=).*path/bin"; then
        fail "You updated your PATH — now run 'getflag'."
    elif [ "$ACTUAL" = "$EXPECTED" ] && logged_since "7.2" "\bgetflag\b"; then
        fail "getflag won't work until you add its directory to PATH."
        hint "Use 'export' to append the directory to your PATH variable."
    elif [[ "$ACTUAL" == *[[:space:]]* ]]; then
        fail "~/path_flag.txt should contain only the output of getflag."
        hint "Save just the command output, not the command itself or extra text."
    elif logged_since "7.2" "(export.*PATH|PATH=).*path/bin" && logged_since "7.2" "\bgetflag\b"; then
        fail "~/path_flag.txt doesn't contain the correct getflag output."
        hint "Run getflag after updating PATH, then save only its output to ~/path_flag.txt."
    else
        fail "Add ~/challenges/path/bin to your PATH, run getflag, and save its output to ~/path_flag.txt."
        hint "PATH is a colon-separated list of directories. Use 'export' to extend it."
    fi
}

reset_7_2() {
    write_secure_token PATH_ "$PATH_FLAG_FILE" > /dev/null
    write_getflag_script
    rm -f "$HOME/path_flag.txt"
    set_log_marker "7.2"
    reset_msg "7.2"
}

# ============================================================
# Challenge 7.3 — Customize Your Shell
# ============================================================

verify_7_3() {
    out=$(runuser -u ieee -- bash -ic 'hello' 2>/dev/null)
    if [ "$out" = "Hello, Linux!" ]; then
        pass "7.3" "bashrc_hacker"
    else
        fail "Alias 'hello' not working or output is wrong."
        hint "Define an alias in ~/.bashrc using the 'alias' keyword, then reload the file with 'source'."
        if [ -n "$out" ]; then
            echo "  Your output: $out"
            echo "  Expected:    Hello, Linux!"
        fi
    fi
}

reset_7_3() {
    if [ -f "$BASHRC_BASELINE" ]; then
        cp "$BASHRC_BASELINE" "$HOME/.bashrc"
        chown ieee:ieee "$HOME/.bashrc"
    else
        sed -i "/^alias hello=/d" "$HOME/.bashrc"
    fi
    reset_msg "7.3"
}

# ============================================================
# Challenge 8.1 — Your First Script
# ============================================================

verify_8_1() {
    local first_line
    local out

    if [ ! -f "$HOME/myscript.sh" ]; then
        fail "File ~/myscript.sh not found."
        hint "Create the file using a text editor like nano or vim."
    elif ! runuser -u ieee -- test -x "$HOME/myscript.sh"; then
        fail "~/myscript.sh exists, but it isn't executable."
        hint "Use chmod +x so you can run the script directly."
    else
        first_line=$(sed -n '1p' "$HOME/myscript.sh" 2>/dev/null)
        if [ "$first_line" != '#!/bin/bash' ]; then
            fail "~/myscript.sh is missing the required shebang line."
            hint "Put '#!/bin/bash' on the first line of the script."
            return
        fi

        out=$(runuser -u ieee -- "$HOME/myscript.sh" 2>/dev/null)
        if [ "$out" = "Hello, World!" ]; then
            pass "8.1" "hello_world_script"
        else
            fail "Script output doesn't match."
            echo "  Expected: Hello, World!"
            echo "  Got:      $out"
        fi
    fi
}

reset_8_1() {
    rm -f "$HOME/myscript.sh"
    reset_msg "8.1"
}

# ============================================================
# Challenge 8.2 — Project Setup Script
# ============================================================

verify_8_2() {
    local sandbox
    local first_line

    if [ ! -f "$HOME/organize.sh" ]; then
        fail "File ~/organize.sh not found."
        hint "Create the script file in your home directory using a text editor."
    elif ! runuser -u ieee -- test -x "$HOME/organize.sh"; then
        fail "~/organize.sh exists, but it isn't executable."
        hint "Use chmod +x so you can run the script directly."
    else
        first_line=$(sed -n '1p' "$HOME/organize.sh" 2>/dev/null)
        if [ "$first_line" != '#!/bin/bash' ]; then
            fail "~/organize.sh is missing the required shebang line."
            hint "Put '#!/bin/bash' on the first line of the script."
            return
        fi

        sandbox=$(mktemp -d /tmp/workshop-8.2.XXXXXX)
        chown ieee:ieee "$sandbox"

        runuser -u ieee -- env HOME="$sandbox" bash -c 'cd "$HOME" && /home/ieee/organize.sh' 2>/dev/null

        if [ -d "$sandbox/workshop_project/src" ] && \
           [ -d "$sandbox/workshop_project/docs" ] && \
           [ -d "$sandbox/workshop_project/assets" ]; then
            pass "8.2" "dirs_organized"
        else
            fail "Your script doesn't create src, docs, and assets inside ~/workshop_project/."
            echo "  Expected in sandbox home: workshop_project/src, workshop_project/docs, workshop_project/assets"
        fi

        rm -rf "$sandbox"
    fi
}

reset_8_2() {
    rm -f "$HOME/organize.sh"
    rm -rf "$HOME/workshop_project"
    reset_msg "8.2"
}

# ============================================================
# Challenge 8.3 — Script Arguments
# ============================================================

verify_8_3() {
    local out1
    local out2
    local exp1
    local exp2

    if [ ! -f "$HOME/greet.sh" ]; then
        fail "File ~/greet.sh not found."
        hint "Create the script file in your home directory using a text editor."
    elif ! runuser -u ieee -- test -x "$HOME/greet.sh"; then
        fail "~/greet.sh exists, but it isn't executable."
        hint "Use chmod +x so you can run ./greet.sh Alice directly."
    else
        out1=$(runuser -u ieee -- bash -lc 'cd "$HOME" && ./greet.sh Alice' 2>/dev/null)
        out2=$(runuser -u ieee -- bash -lc 'cd "$HOME" && ./greet.sh Bob' 2>/dev/null)
        exp1="Hello, Alice! Welcome to the workshop."
        exp2="Hello, Bob! Welcome to the workshop."
        if [ "$out1" = "$exp1" ] && [ "$out2" = "$exp2" ]; then
            pass "8.3" "greet_with_args"
        else
            fail "Output doesn't match expected format."
            echo "  Expected: Hello, <name>! Welcome to the workshop."
            echo ""
            echo "  Test 1: ./greet.sh Alice"
            echo "    Expected: $exp1"
            echo "    Got:      $out1"
            echo ""
            echo "  Test 2: ./greet.sh Bob"
            echo "    Expected: $exp2"
            echo "    Got:      $out2"
        fi
    fi
}

reset_8_3() {
    rm -f "$HOME/greet.sh"
    reset_msg "8.3"
}

# ============================================================
# Challenge 9.1 — Ping!
# ============================================================

verify_9_1() {
    ACTUAL=$(cat "$HOME/ping_result.txt" 2>/dev/null)

    if [ -z "$ACTUAL" ]; then
        fail "File ~/ping_result.txt not found or is empty."
        hint "Run ping against localhost and save the output to ~/ping_result.txt."
    elif ! logged_since "9.1" "ping.*localhost|ping.*127\.0\.0\.1"; then
        fail "Run ping against localhost, then save its output to ~/ping_result.txt."
        hint "Try 'ping -c 3 localhost > ~/ping_result.txt'."
    elif printf '%s\n' "$ACTUAL" | grep -Eq '0% packet loss'; then
        pass "9.1" "ping_success"
    else
        fail "~/ping_result.txt doesn't show a successful ping to localhost."
        hint "Save the output of a successful localhost ping, such as 'ping -c 3 localhost'."
    fi
}

reset_9_1() {
    rm -f "$HOME/ping_result.txt"
    set_log_marker "9.1"
    reset_msg "9.1"
}

# ============================================================
# Challenge 9.2 — Fetch from the Web
# ============================================================

verify_9_2() {
    EXPECTED=$(cat "$WEB_FLAG_FILE" 2>/dev/null)
    ACTUAL=$(cat "$HOME/web_flag.txt" 2>/dev/null)

    if [ -z "$EXPECTED" ]; then
        fail "Challenge state is missing the web flag."
        hint "Run 'reset 9.2' to restore the challenge state, then try again."
    elif [ -z "$ACTUAL" ]; then
        fail "File ~/web_flag.txt not found or is empty."
        hint "Use curl to fetch the page on port 8080 and save the response to ~/web_flag.txt."
    elif [ "$ACTUAL" = "$EXPECTED" ] && logged_since "9.2" "curl.*8080"; then
        pass "9.2" "curl_the_web"
    elif [ "$ACTUAL" = "$EXPECTED" ]; then
        fail "You have the right response, but curl wasn't run since the last reset."
        hint "Fetch http://localhost:8080/flag with curl and save it to ~/web_flag.txt."
    else
        fail "~/web_flag.txt doesn't contain the correct web response."
        hint "Fetch http://localhost:8080/flag with curl and save only the response body."
    fi
}

reset_9_2() {
    write_secure_token WEB_ "$WEB_FLAG_FILE" > /dev/null
    restart_network_services
    rm -f "$HOME/web_flag.txt"
    set_log_marker "9.2"
    reset_msg "9.2"
}

# ============================================================
# Challenge 9.3 — Find the Hidden Service
# ============================================================

verify_9_3() {
    EXPECTED_PORT=$(cat "$HIDDEN_PORT_FILE" 2>/dev/null)
    EXPECTED_FLAG=$(cat "$HIDDEN_FLAG_FILE" 2>/dev/null)
    ACTUAL_PORT=$(cat "$HOME/hidden_port.txt" 2>/dev/null | tr -d '[:space:]')
    ACTUAL_FLAG=$(cat "$HOME/hidden_flag.txt" 2>/dev/null)

    if [ -z "$EXPECTED_PORT" ] || [ -z "$EXPECTED_FLAG" ]; then
        fail "Challenge state is missing the hidden service details."
        hint "Run 'reset 9.3' to restore the challenge state, then try again."
    elif [ -z "$ACTUAL_PORT" ]; then
        fail "File ~/hidden_port.txt not found or is empty."
        hint "Use ss to find the mystery port, then save just the port number to ~/hidden_port.txt."
    elif [ -z "$ACTUAL_FLAG" ]; then
        fail "File ~/hidden_flag.txt not found or is empty."
        hint "Use curl to fetch the mystery service response and save it to ~/hidden_flag.txt."
    elif [ "$ACTUAL_PORT" = "$EXPECTED_PORT" ] && [ "$ACTUAL_FLAG" = "$EXPECTED_FLAG" ] && logged_since "9.3" "ss.*-.*[tuln]" && logged_since "9.3" "curl.*${EXPECTED_PORT}"; then
        pass "9.3" "hidden_service"
    elif [ "$ACTUAL_PORT" != "$EXPECTED_PORT" ]; then
        fail "~/hidden_port.txt doesn't contain the correct mystery port."
        hint "Use ss to list listening ports and save only the unfamiliar port number."
    elif [ "$ACTUAL_FLAG" != "$EXPECTED_FLAG" ]; then
        fail "~/hidden_flag.txt doesn't contain the correct mystery service response."
        hint "Curl the service on the port from ~/hidden_port.txt and save only the response body."
    elif ! logged_since "9.3" "ss.*-.*[tuln]"; then
        fail "Run ss to find the mystery port before verifying."
        hint "Try options that show listening TCP or UDP sockets with numeric ports."
    elif ! logged_since "9.3" "curl.*${EXPECTED_PORT}"; then
        fail "You found the mystery port — now curl it and save the response."
        hint "Fetch http://localhost:<port>/flag with curl and save the body to ~/hidden_flag.txt."
    else
        fail "Use ss to find the mystery service, then save the port and response to files."
        hint "Save the port in ~/hidden_port.txt and the response body in ~/hidden_flag.txt."
    fi
}

reset_9_3() {
    write_secure_token HIDDEN_ "$HIDDEN_FLAG_FILE" > /dev/null
    generate_hidden_port > "$HIDDEN_PORT_FILE"
    chmod 600 "$HIDDEN_PORT_FILE"
    restart_network_services
    rm -f "$HOME/hidden_port.txt" "$HOME/hidden_flag.txt"
    set_log_marker "9.3"
    reset_msg "9.3"
}

# ============================================================
# Dispatch: verify
# ============================================================

cmd_verify() {
    if [ -z "$1" ]; then
        echo "Usage: verify <challenge_number>"
        echo "Example: verify 1.1"
        echo ""
        echo "Run 'challenges' to see the full challenge list."
        return 1
    fi
    case "$1" in
        1.1) verify_1_1 ;; 1.2) verify_1_2 ;; 1.3) verify_1_3 ;;
        2.1) verify_2_1 ;; 2.2) verify_2_2 ;; 2.3) verify_2_3 ;;
        3.1) verify_3_1 ;; 3.2) verify_3_2 ;; 3.3) verify_3_3 ;;
        4.1) verify_4_1 ;; 4.2) verify_4_2 ;; 4.3) verify_4_3 ;;
        5.1) verify_5_1 ;; 5.2) verify_5_2 ;; 5.3) verify_5_3 ;;
        6.1) verify_6_1 ;; 6.2) verify_6_2 ;; 6.3) verify_6_3 ;;
        7.1) verify_7_1 ;; 7.2) verify_7_2 ;; 7.3) verify_7_3 ;;
        8.1) verify_8_1 ;; 8.2) verify_8_2 ;; 8.3) verify_8_3 ;;
        9.1) verify_9_1 ;; 9.2) verify_9_2 ;; 9.3) verify_9_3 ;;
        *) echo "Unknown challenge: $1"; echo "Run 'challenges' to see the full list." ;;
    esac
}

# ============================================================
# Dispatch: reset
# ============================================================

cmd_reset() {
    if [ -z "$1" ]; then
        echo "Usage: reset <challenge_number>"
        echo "Example: reset 2.2"
        return 1
    fi
    case "$1" in
        1.1) reset_1_1 ;; 1.2) reset_1_2 ;; 1.3) reset_1_3 ;;
        2.1) reset_2_1 ;; 2.2) reset_2_2 ;; 2.3) reset_2_3 ;;
        3.1) reset_3_1 ;; 3.2) reset_3_2 ;; 3.3) reset_3_3 ;;
        4.1) reset_4_1 ;; 4.2) reset_4_2 ;; 4.3) reset_4_3 ;;
        5.1) reset_5_1 ;; 5.2) reset_5_2 ;; 5.3) reset_5_3 ;;
        6.1) reset_6_1 ;; 6.2) reset_6_2 ;; 6.3) reset_6_3 ;;
        7.1) reset_7_1 ;; 7.2) reset_7_2 ;; 7.3) reset_7_3 ;;
        8.1) reset_8_1 ;; 8.2) reset_8_2 ;; 8.3) reset_8_3 ;;
        9.1) reset_9_1 ;; 9.2) reset_9_2 ;; 9.3) reset_9_3 ;;
        *) echo "Unknown challenge: $1"; echo "Run 'challenges' to see the full list." ;;
    esac
}

# ============================================================
# Dispatch: status
# ============================================================

cmd_status() {
    TOTAL=27
    DONE=$(wc -l < "$PROGRESS" 2>/dev/null || echo 0)
    echo ""
    echo -e "${BOLD}Progress: ${GREEN}${DONE}${NC}${BOLD}/${TOTAL} completed${NC}"
    echo ""

    CONCEPTS=(
        "1:File System Navigation:1.1 1.2 1.3"
        "2:File Operations:2.1 2.2 2.3"
        "3:File Permissions:3.1 3.2 3.3"
        "4:Streams & Piping:4.1 4.2 4.3"
        "5:Finding Files:5.1 5.2 5.3"
        "6:Process Management:6.1 6.2 6.3"
        "7:Environment & PATH:7.1 7.2 7.3"
        "8:Bash Scripting:8.1 8.2 8.3"
        "9:Networking:9.1 9.2 9.3"
    )

    for entry in "${CONCEPTS[@]}"; do
        IFS=':' read -r num name challenges <<< "$entry"
        printf "  Concept %s  %-25s" "$num" "$name"
        for ch in $challenges; do
            if grep -qx "$ch" "$PROGRESS" 2>/dev/null; then
                printf " ${GREEN}[done]${NC}"
            else
                printf " ${RED}[ -- ]${NC}"
            fi
        done
        echo ""
    done
    echo ""
}

# ============================================================
# Main
# ============================================================

touch_secure_file "$PROGRESS"
touch_secure_file "$MARKERS"

case "$1" in
    verify) cmd_verify "$2" ;;
    reset)  cmd_reset "$2" ;;
    retry)  cmd_reset "$2" ;;
    status) cmd_status ;;
    *)
        echo "Usage: verifier {verify|reset|status} [challenge]"
        echo ""
        echo "  verify X.Y    Check your work on a challenge"
        echo "  reset X.Y     Reset a challenge to try again"
        echo "  status        Show progress overview"
        ;;
esac
