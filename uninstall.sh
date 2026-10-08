#!/usr/bin/env bash
set -euo pipefail

# ANSI color codes; auto-disabled when stdout isn't a TTY (e.g. piped to a logfile, run in CI).
BOLD=$'\e[1m'; BLUE=$'\e[34m'; GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; RESET=$'\e[0m'
[[ -t 1 ]] || { BOLD=; BLUE=; GREEN=; RED=; DIM=; RESET=; }
info() { printf '%s●%s %s%s%s\n' "$BLUE" "$RESET" "$BOLD" "$*" "$RESET"; }
ok()   { printf '%s✓%s %s\n'       "$GREEN" "$RESET" "$*"; }
err()  { printf '%s✗%s %s\n'       "$RED"   "$RESET" "$*" >&2; }
# `trap - ERR` disarms the ERR trap below so the explicit `exit 1` doesn't double-report.
die()  { err "$*"; trap - ERR; exit 1; }
trap 'err "uninstall.sh failed at line $LINENO"' ERR

# Container engine: Docker or Podman — same selection as the claude-pod script. RUNTIME=docker|podman
# picks one explicitly; otherwise docker if it's on PATH, else podman. The flavor is detected from
# `--version` so a `docker` that is really Podman (the podman-docker shim) is treated as Podman.
if [ -z "${RUNTIME:-}" ]; then
  if command -v docker >/dev/null; then RUNTIME=docker
  elif command -v podman >/dev/null; then RUNTIME=podman
  else die "Docker or Podman is required, but neither is on PATH."
  fi
fi
command -v "$RUNTIME" >/dev/null || die "Container engine '$RUNTIME' (from RUNTIME) is not on PATH."
IS_PODMAN=false
"$RUNTIME" --version 2>/dev/null | grep -qi podman && IS_PODMAN=true

CLAUDE_DIR="$HOME/.claude-pod"
IMAGE="claude-pod"

info "Will remove"
printf '  %simage:%s %s\n' "$DIM" "$RESET" "$IMAGE"
printf '  %sdir:  %s %s %s(auth + session history)%s\n' "$DIM" "$RESET" "$CLAUDE_DIR" "$DIM" "$RESET"
echo

info "Will NOT remove"
printf '  %snode:24-slim base image (%s rmi docker.io/library/node:24-slim to clear)%s\n' "$DIM" "$RUNTIME" "$RESET"
if [ "$IS_PODMAN" = true ]; then
  printf '  %sPodman build cache (%s image prune to clear)%s\n' "$DIM" "$RUNTIME" "$RESET"
else
  printf '  %sDocker build cache (%s builder prune to clear)%s\n' "$DIM" "$RUNTIME" "$RESET"
fi
printf '  %sthis repo folder (delete it yourself)%s\n' "$DIM" "$RESET"
echo

# `|| reply=""` so that EOF / non-interactive stdin (where read returns non-zero) is treated as
# a declined prompt under `set -e`, rather than tripping the ERR trap with a confusing line error.
read -r -p "Proceed? [y/N] " reply || reply=""
[[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
echo

info "Removing image '$IMAGE'"
# Probe with `image ls -q`, not `image inspect`: some Docker Desktop builds have a broken
# `image inspect <name>` that false-negatives on a present image, which would make us wrongly
# report "not present" and leave the image behind. `ls -q` resolves the name like `rmi` does.
if [ -n "$("$RUNTIME" image ls -q "$IMAGE" 2>/dev/null)" ]; then
  # Dim + indent the rmi output the same way install.sh dims the build output.
  "$RUNTIME" rmi -f "$IMAGE" 2>&1 \
    | sed $'s/\e\\[[0-9;]*m//g' \
    | while IFS= read -r line; do printf '%s  %s%s\n' "$DIM" "$line" "$RESET"; done
  ok "Image '$IMAGE' removed"
else
  ok "Image '$IMAGE' was not present"
fi
echo

info "Removing host directory"
if [ -d "$CLAUDE_DIR" ]; then
  rm -rf "$CLAUDE_DIR"
  ok "Removed $CLAUDE_DIR"
else
  ok "$CLAUDE_DIR was not present"
fi
echo

ok "Done"
