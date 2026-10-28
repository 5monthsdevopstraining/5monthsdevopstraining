#!/usr/bin/env bash
# carla-stop - stop viewer + CARLA. Usage: sudo carla-stop [--all]
set -uo pipefail
log() { echo -e "\e[1;34m[carla-stop]\e[0m $*"; }
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
log "Stopping viewer";  systemctl stop carla-viewer; systemctl disable --quiet carla-viewer
log "Stopping CARLA";   docker compose -f /opt/photorealsim/docker-compose.yml stop
[[ "${1:-}" == "--all" ]] && { log "Closing DCV session"; dcv close-session carla 2>/dev/null; }
log "Done. (Pause the instance in Jarvislabs to stop billing.)"
