#!/bin/bash
set -euo pipefail

CONFIG_FILE="/etc/workshop/broker.env"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Workshop broker is not configured on this host." >&2
    exit 1
fi

# shellcheck disable=SC1091
. "$CONFIG_FILE"

student="${SUDO_USER:-${USER:-}}"
if [ -z "$student" ]; then
    echo "Unable to determine the student account." >&2
    exit 1
fi

container_user=$(printf '%s' "$student" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_.-')
if [ -z "$container_user" ]; then
    echo "The student username '$student' cannot be mapped to a container name." >&2
    exit 1
fi

container_name="${WORKSHOP_CONTAINER_PREFIX}-${container_user}"

if ! command -v docker >/dev/null 2>&1; then
    echo "docker is not installed on the host." >&2
    exit 1
fi

if ! docker image inspect "$WORKSHOP_IMAGE" >/dev/null 2>&1; then
    echo "Docker image '$WORKSHOP_IMAGE' is not present on the host." >&2
    exit 1
fi

if ! docker network inspect "$WORKSHOP_NETWORK" >/dev/null 2>&1; then
    echo "Docker network '$WORKSHOP_NETWORK' is missing. Run the host setup script again." >&2
    exit 1
fi

if ! docker container inspect "$container_name" >/dev/null 2>&1; then
    docker run -d \
        --name "$container_name" \
        --hostname "$container_name" \
        --network "$WORKSHOP_NETWORK" \
        --restart unless-stopped \
        --cpus "$WORKSHOP_CPUS" \
        --memory "$WORKSHOP_MEMORY" \
        --pids-limit "$WORKSHOP_PIDS" \
        --label "workshop.student=$student" \
        "$WORKSHOP_IMAGE" >/dev/null
fi

if [ "$(docker inspect -f '{{.State.Running}}' "$container_name")" != "true" ]; then
    docker start "$container_name" >/dev/null
    sleep 1
fi

docker_flags=(-i)
if [ -t 0 ] && [ -t 1 ]; then
    docker_flags=(-it)
fi

exec docker exec "${docker_flags[@]}" "$container_name" bash -lc '
SECRET_FLAG=$(cat /opt/.secret_flag 2>/dev/null || true)
export SECRET_FLAG
export HOME=/home/ieee
export USER=ieee
export LOGNAME=ieee
export SHELL=/bin/bash
/usr/local/bin/welcome
exec runuser --preserve-environment -u ieee -- bash -l
'
