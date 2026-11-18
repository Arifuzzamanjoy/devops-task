#!/usr/bin/env bash
#
# deploy.sh - roll the app container to a new image on the server, with
# automatic rollback if it doesn't come up healthy.
#
# Runs on the Contabo VPS as the deploy user, called by the CD workflow over SSH.
#
#   deploy.sh <image>      deploy an image (e.g. ghcr.io/owner/repo:sha-abc123)
#   deploy.sh --rollback   go back to the previously deployed image
#   deploy.sh --status     print current and previous image
#
# Exit codes: 0 deployed, 1 usage error, 2 failed but rolled back,
#             3 failed and rollback also failed

set -euo pipefail

APP_DIR="${APP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
STATE_DIR="${APP_DIR}/.deploy"
ENV_FILE="${APP_DIR}/.env"
SERVICE="app"
CONTAINER="devops-task-app"
HEALTH_RETRIES="${HEALTH_RETRIES:-20}"
HEALTH_DELAY="${HEALTH_DELAY:-3}"

log() { printf '%s [deploy] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
die() { log "ERROR: $*"; exit 1; }

usage() {
    sed -n '3,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

current_image() {
    cat "${STATE_DIR}/current" 2>/dev/null || true
}

previous_image() {
    cat "${STATE_DIR}/previous" 2>/dev/null || true
}

# Persist APP_IMAGE in .env so a plain `docker compose up -d` later
# keeps running the same image instead of falling back to the default.
set_image() {
    local image="$1"
    touch "$ENV_FILE"
    if grep -q '^APP_IMAGE=' "$ENV_FILE"; then
        sed -i "s|^APP_IMAGE=.*|APP_IMAGE=${image}|" "$ENV_FILE"
    else
        printf 'APP_IMAGE=%s\n' "$image" >> "$ENV_FILE"
    fi
}

start() {
    local image="$1"
    set_image "$image"
    # sha- tags are immutable, so a local copy is good enough. This also lets
    # a rollback work when the registry is unreachable.
    if ! docker image inspect "$image" >/dev/null 2>&1; then
        docker compose pull --quiet "$SERVICE" || return 1
    fi
    docker compose up -d --no-build --no-deps "$SERVICE" || return 1
}

wait_healthy() {
    local status i
    for ((i = 1; i <= HEALTH_RETRIES; i++)); do
        status="$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo missing)"
        if [[ "$status" == "healthy" ]]; then
            log "container healthy after $((i * HEALTH_DELAY))s"
            return 0
        fi
        log "waiting for health ($i/${HEALTH_RETRIES}): ${status}"
        sleep "$HEALTH_DELAY"
    done
    docker logs --tail 50 "$CONTAINER" 2>&1 || true
    return 1
}

deploy() {
    local image="$1" before
    before="$(current_image)"

    log "deploying ${image} (current: ${before:-none})"
    if start "$image" && wait_healthy; then
        if [[ -n "$before" && "$before" != "$image" ]]; then
            printf '%s\n' "$before" > "${STATE_DIR}/previous"
        fi
        printf '%s\n' "$image" > "${STATE_DIR}/current"
        log "deploy ok"
        return 0
    fi

    log "new image is unhealthy"
    if [[ -z "$before" ]]; then
        log "nothing to roll back to"
        exit 3
    fi

    log "rolling back to ${before}"
    if start "$before" && wait_healthy; then
        log "rollback ok"
        exit 2
    fi
    log "rollback failed too, manual action needed"
    exit 3
}

rollback() {
    local prev cur
    prev="$(previous_image)"
    cur="$(current_image)"
    [[ -n "$prev" ]] || die "no previous image recorded"

    log "rolling back ${cur:-none} -> ${prev}"
    start "$prev"
    wait_healthy || { log "previous image is unhealthy as well"; exit 3; }

    printf '%s\n' "$prev" > "${STATE_DIR}/current"
    [[ -n "$cur" ]] && printf '%s\n' "$cur" > "${STATE_DIR}/previous"
    log "rollback ok"
}

main() {
    [[ $# -eq 1 ]] || { usage; exit 1; }

    cd "$APP_DIR"
    mkdir -p "$STATE_DIR"

    # One deploy at a time on this host
    exec 9>"${STATE_DIR}/lock"
    flock -n 9 || die "another deploy is running"

    case "$1" in
        -h|--help) usage ;;
        --status)
            printf 'current:  %s\nprevious: %s\n' "$(current_image)" "$(previous_image)" ;;
        --rollback) rollback ;;
        -*) usage; exit 1 ;;
        *) deploy "$1" ;;
    esac
}

main "$@"
