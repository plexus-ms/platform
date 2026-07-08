#!/usr/bin/env bash
#
# Plexus deploy verb — PLEXUS.md §5. A stateless procedure, not a system:
#
#   ssh → docker compose pull → mise migrate → docker compose up -d
#       → poll /healthz → on failure: re-up the previous image, exit non-zero
#
# State lives in git (compose.yml + the app's mise.toml, placed on the host by the
# tenant's Ansible) and in the registry (the image). "Which version is live" is the
# running container's image, queried from `docker` (reality) — never a file we own.
# No persistent state, no daemon, no UI, no reconciliation loop.
#
# Degradation test — hand-runnable with no extra machinery:
#   ./deploy.sh deploy@1.2.3.4 plexus-website ghcr.io/org/plexus-website:<sha>
#
set -euo pipefail

HOST="${1:?usage: deploy.sh <ssh-host> <app> <image-ref>}"
APP="${2:?usage: deploy.sh <ssh-host> <app> <image-ref>}"
IMAGE="${3:?usage: deploy.sh <ssh-host> <app> <image-ref>}"

# Overridable knobs (sane defaults for the stateless-app profile).
APP_DIR="${PLEXUS_APP_DIR:-/opt/plexus/$APP}"
HEALTH_URL="${PLEXUS_HEALTH_URL:-http://127.0.0.1:3000/healthz}"
RETRIES="${PLEXUS_HEALTH_RETRIES:-30}"

echo "→ deploying $IMAGE"
echo "  host:   $HOST"
echo "  dir:    $APP_DIR"
echo "  health: $HEALTH_URL"

# Everything below runs on the host. Args are passed positionally (no fragile
# remote-env forwarding); the heredoc is quoted so it is not expanded locally.
ssh -o StrictHostKeyChecking=accept-new "$HOST" bash -seuo pipefail -- \
  "$APP_DIR" "$IMAGE" "$HEALTH_URL" "$RETRIES" <<'REMOTE'
APP_DIR="$1"; IMAGE="$2"; HEALTH_URL="$3"; RETRIES="$4"
cd "$APP_DIR"

# Reality is the source of truth: read the currently-live image for rollback.
PREV_IMAGE=""
CID="$(docker compose ps -q web 2>/dev/null || true)"
[ -n "$CID" ] && PREV_IMAGE="$(docker inspect --format '{{.Config.Image}}' "$CID" 2>/dev/null || true)"
echo "  previous: ${PREV_IMAGE:-<none>}"

up() {  # $1 = image ref
  echo "IMAGE=$1" > .env   # reproducibility cache for a manual `docker compose up`
  IMAGE="$1" docker compose pull web
  IMAGE="$1" docker compose up -d web
}

healthy() {
  for _ in $(seq 1 "$RETRIES"); do
    curl -fsS -o /dev/null "$HEALTH_URL" && return 0
    sleep 2
  done
  return 1
}

# Pull → migrate (idempotent; a no-op for stateless apps) → up.
echo "IMAGE=$IMAGE" > .env
IMAGE="$IMAGE" docker compose pull web
# Bare `mise migrate` (not `:migrate`): the app dir on the host holds a
# standalone mise.toml, and monorepo path syntax requires a monorepo root.
mise trust . >/dev/null 2>&1 || true
mise migrate
IMAGE="$IMAGE" docker compose up -d web

if healthy; then
  echo "✓ $IMAGE is live and healthy"
  exit 0
fi

echo "✗ healthcheck failed after $((RETRIES * 2))s"
if [ -n "$PREV_IMAGE" ] && [ "$PREV_IMAGE" != "$IMAGE" ]; then
  echo "↩ rolling back to $PREV_IMAGE"
  up "$PREV_IMAGE"
  if healthy; then echo "✓ rolled back to $PREV_IMAGE"; else echo "✗ rollback also unhealthy — manual intervention needed"; fi
fi
exit 1
REMOTE
