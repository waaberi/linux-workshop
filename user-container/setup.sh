#!/bin/bash
# setup.sh — Creates all challenge files, directories, and permissions
# Runs at Docker build time as root

set -e

HOME_DIR="/home/ieee"
CHALL_DIR="$HOME_DIR/challenges"

# ============================================================
# Concept 1: File System Navigation
# ============================================================

# 1.2 — Labyrinth
mkdir -p "$HOME_DIR/labyrinth/left/dead_end"
mkdir -p "$HOME_DIR/labyrinth/left/tunnel/another_dead_end"
mkdir -p "$HOME_DIR/labyrinth/right/dark_room"
mkdir -p "$HOME_DIR/labyrinth/right/passage/chamber"
mkdir -p "$HOME_DIR/labyrinth/straight/blocked"

echo "HIDDEN_TREASURE" > "$HOME_DIR/labyrinth/right/passage/chamber/flag.txt"
echo "Nothing here..." > "$HOME_DIR/labyrinth/left/dead_end/note.txt"
echo "This path is blocked." > "$HOME_DIR/labyrinth/straight/blocked/sign.txt"
echo "It's too dark to see anything useful." > "$HOME_DIR/labyrinth/right/dark_room/note.txt"
echo "Keep looking..." > "$HOME_DIR/labyrinth/left/tunnel/another_dead_end/note.txt"

# Set old atime on labyrinth files so verify can detect successful reads
find "$HOME_DIR/labyrinth" -type f -exec touch -a -t 200001010000.00 {} +

# 1.3 — Symlinks (5 links, 1 broken — student must find and fix it)
mkdir -p "$HOME_DIR/links/targets"
echo "alpha" > "$HOME_DIR/links/targets/alpha.txt"
echo "beta" > "$HOME_DIR/links/targets/beta.txt"
echo "gamma" > "$HOME_DIR/links/targets/gamma.txt"
echo "delta" > "$HOME_DIR/links/targets/delta.txt"
echo "epsilon" > "$HOME_DIR/links/targets/epsilon.txt"

ln -s "$HOME_DIR/links/targets/alpha.txt" "$HOME_DIR/links/link_alpha"
ln -s "$HOME_DIR/links/targets/beta.txt" "$HOME_DIR/links/link_beta"
ln -s "/old/path/gamma.txt" "$HOME_DIR/links/link_gamma"
ln -s "$HOME_DIR/links/targets/delta.txt" "$HOME_DIR/links/link_delta"
ln -s "$HOME_DIR/links/targets/epsilon.txt" "$HOME_DIR/links/link_epsilon"

# ============================================================
# Concept 2: File Operations
# ============================================================

mkdir -p "$CHALL_DIR/files/pieces"

# 2.1 — config.txt (student must edit mode=off to mode=on)
cat > "$CHALL_DIR/files/config.txt" << 'EOF'
# Application Configuration
name=workshop
version=1.0
mode=off
debug=false
EOF

# 2.2 — server.log (10,000 lines, token on line 6743 randomized at runtime)
for i in $(seq 1 10000); do
    printf '2024-03-15 14:23:%05d [INFO] Request processed - session=%05d\n' "$i" "$i"
done > "$CHALL_DIR/files/server.log"
sed -i '6743s/.*/2024-03-15 14:23:06743 [INFO] __NEEDLE_TOKEN__/' "$CHALL_DIR/files/server.log"

# 2.3 — pieces (20 part files, one contains a token randomized at runtime)
for i in $(seq -w 1 20); do
    echo "Log fragment $i: system nominal" > "$CHALL_DIR/files/pieces/part${i}.txt"
done
echo "__PIECES_TOKEN__" > "$CHALL_DIR/files/pieces/part13.txt"

# ============================================================
# Concept 3: File Permissions
# ============================================================

mkdir -p "$CHALL_DIR/perms/audit"

# 3.1 — show_flag.sh (not executable)
cat > "$CHALL_DIR/perms/show_flag.sh" << 'EOF'
#!/bin/bash
echo "EXECUTE_SUCCESS"
EOF
chmod 644 "$CHALL_DIR/perms/show_flag.sh"

# 3.2 — classified.txt (permissions 000)
echo "ACCESS_GRANTED" > "$CHALL_DIR/perms/classified.txt"
chmod 000 "$CHALL_DIR/perms/classified.txt"

# 3.3 — audit directory (which file gets 600 is randomized at runtime)
for i in 1 2 3 4 5; do
    echo "Nothing interesting in this file." > "$CHALL_DIR/perms/audit/report${i}.txt"
done

# ============================================================
# Concept 4: Streams & Piping
# ============================================================

mkdir -p "$CHALL_DIR/pipes"

# 4.1 — access.log (5000 lines, one special line randomized at runtime)
for i in $(seq 1 5000); do
    printf '192.168.1.%d - - [15/Mar/2024:10:23:%05d] "GET /page%d" 200 -\n' $((RANDOM % 254 + 1)) "$i" "$i"
done > "$CHALL_DIR/pipes/access.log"
sed -i '3847s/.*/192.168.1.42 - - [15\/Mar\/2024:10:23:03847] "GET \/secret" 200 __GREP_TOKEN__/' "$CHALL_DIR/pipes/access.log"

# 4.2 — noisy (prints junk to stdout, token to stderr, randomized at runtime)
cat > "/opt/pipes-noisy.sh" << 'SCRIPT'
#!/bin/bash
for i in $(seq 1 50); do
    echo "[stdout] Processing batch $i... status=OK checksum=$(head -c 8 /dev/urandom | xxd -p)"
done
cat /opt/.noisy_token >&2
for i in $(seq 51 100); do
    echo "[stdout] Processing batch $i... status=OK checksum=$(head -c 8 /dev/urandom | xxd -p)"
done
SCRIPT
chmod 700 "/opt/pipes-noisy.sh"

cat > "$CHALL_DIR/pipes/noisy" << 'SCRIPT'
#!/bin/bash
exec sudo /opt/pipes-noisy.sh
SCRIPT
chmod +x "$CHALL_DIR/pipes/noisy"

# 4.3 — pipeline (step1 | step2 | step3, token randomized at runtime)
cat > "/opt/pipes-step1.sh" << 'EOF'
#!/bin/bash
cat /opt/.pipe_token_encoded
EOF
chmod 700 "/opt/pipes-step1.sh"

cat > "$CHALL_DIR/pipes/step1" << 'EOF'
#!/bin/bash
exec sudo /opt/pipes-step1.sh
EOF

cat > "$CHALL_DIR/pipes/step2" << 'EOF'
#!/bin/bash
base64 -d
EOF

cat > "$CHALL_DIR/pipes/step3" << 'EOF'
#!/bin/bash
rev
EOF

chmod +x "$CHALL_DIR/pipes/step1" "$CHALL_DIR/pipes/step2" "$CHALL_DIR/pipes/step3"

# ============================================================
# Concept 5: Finding Files
# ============================================================

mkdir -p "$CHALL_DIR/search/configs"

# 5.1 — one large file hidden among small ones
mkdir -p "$CHALL_DIR/search/files/logs" "$CHALL_DIR/search/files/data" "$CHALL_DIR/search/files/tmp"
for f in a.txt b.txt c.txt; do echo "small file" > "$CHALL_DIR/search/files/logs/$f"; done
for f in d.txt e.txt f.txt; do echo "small file" > "$CHALL_DIR/search/files/data/$f"; done
for f in g.txt h.txt; do echo "small file" > "$CHALL_DIR/search/files/tmp/$f"; done
dd if=/dev/urandom of="$CHALL_DIR/search/files/data/backup.bin" bs=1K count=200 2>/dev/null

# 5.2 — many files, one with WORKSHOP_TOKEN (which file is randomized at runtime)
mkdir -p "$CHALL_DIR/search/data"
for i in $(seq -w 1 30); do
    printf 'Log entry %s: Nothing relevant here.\nData processed at timestamp %d.\n' "$i" "$((1000 + 10#$i))" \
        > "$CHALL_DIR/search/data/file_${i}.txt"
done
echo "__SEARCH_TOKEN_FILE__" > "$CHALL_DIR/search/data/.token_target"

# 5.3 — .conf files with different modification times
for name in database network cache logging auth; do
    printf '# Old configuration file: %s.conf\nstatus=deprecated\n' "$name" \
        > "$CHALL_DIR/search/configs/${name}.conf"
    touch -d "30 days ago" "$CHALL_DIR/search/configs/${name}.conf"
done
printf '# Updated configuration\nstatus=active\n' > "$CHALL_DIR/search/configs/security.conf"
printf '# Updated configuration\nstatus=active\n' > "$CHALL_DIR/search/configs/updates.conf"

# ============================================================
# Concept 6: Process Management (processes started at runtime)
# ============================================================

mkdir -p "$HOME_DIR/.process_scripts"

cat > "$HOME_DIR/.process_scripts/cpu_hog.sh" << 'EOF'
#!/bin/bash
while true; do
    for i in $(seq 1 1000); do :; done
    sleep 0.01
done
EOF
chmod +x "$HOME_DIR/.process_scripts/cpu_hog.sh"

cat > "$HOME_DIR/.process_scripts/worker_idle.sh" << 'EOF'
#!/bin/bash
exec -a "$1 --config=$2" sleep 99999
EOF
chmod +x "$HOME_DIR/.process_scripts/worker_idle.sh"

# ============================================================
# Concept 7: Environment Variables & PATH
# ============================================================

mkdir -p "$CHALL_DIR/path/bin"

cat > "$CHALL_DIR/path/bin/getflag" << 'EOF'
#!/bin/bash
echo "PATH_FOUND"
EOF
chmod +x "$CHALL_DIR/path/bin/getflag"

# ============================================================
# Concept 10: Ownership & Privileges
# ============================================================

mkdir -p "$CHALL_DIR/ownership/broken_project"

# 10.1 + 10.2 — placeholder files (tokens set at runtime)
echo "PLACEHOLDER" > "$CHALL_DIR/ownership/secret.txt"
echo "PLACEHOLDER" > "$CHALL_DIR/ownership/report.txt"

# 10.3 — broken project files (ownership/perms set at runtime)
echo "database: postgres" > "$CHALL_DIR/ownership/broken_project/config.yaml"
echo "# Project README" > "$CHALL_DIR/ownership/broken_project/README.md"
printf 'print("hello")\n' > "$CHALL_DIR/ownership/broken_project/main.py"
echo "name,value" > "$CHALL_DIR/ownership/broken_project/data.csv"
echo "Some notes here." > "$CHALL_DIR/ownership/broken_project/notes.txt"

# ============================================================
# Fix ownership — everything under /home/ieee owned by ieee
# ============================================================

chown -R ieee:ieee "$HOME_DIR"
