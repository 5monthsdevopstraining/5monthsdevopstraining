#!/usr/bin/env bash
# carla-start - start CARLA + DCV session + viewer service. Usage: sudo carla-start [--recreate]
set -uo pipefail
COMPOSE=/opt/photorealsim/docker-compose.yml
PY=/home/dev/carla-client/bin/python
URL="https://photorealsim.icaniotech.com"
log() { echo -e "\e[1;34m[carla-start]\e[0m $*"; }
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

if [[ "${1:-}" == "--recreate" ]]; then
  log "Rebuilding CARLA container"; docker compose -f $COMPOSE up -d --build --force-recreate
else
  log "Starting CARLA container"; docker compose -f $COMPOSE up -d
fi

log "Waiting for CARLA ..."
for i in $(seq 1 45); do
  sudo -u dev $PY -c "import carla; c=carla.Client('localhost',2000); c.set_timeout(5); c.get_server_version()" >/dev/null 2>&1 && { log "CARLA is ready"; break; }
  [[ $i -eq 45 ]] && { log "CARLA not responding: docker compose -f $COMPOSE logs carla"; exit 1; }
  sleep 2
done

systemctl is-active --quiet dcvserver || { log "Starting DCV"; systemctl start dcvserver; sleep 3; }
if ! dcv list-sessions 2>/dev/null | grep -q "Session: 'carla'"; then
  log "Creating DCV session"
  systemctl restart lightdm; sleep 8
  dcv create-session --type=console --owner dev carla; sleep 5
fi
if ! pgrep -u dev -x dcvagent >/dev/null; then
  log "Repairing DCV agent"; systemctl restart lightdm; sleep 10
fi

log "Starting viewer service"
systemctl enable --quiet carla-viewer
systemctl restart carla-viewer
log "Done. Open $URL and log in as 'dev'."
