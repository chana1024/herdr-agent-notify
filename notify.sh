#!/usr/bin/env bash
# Notify on agent status transitions to blocked or done.
#
# Herdr runs this with the plugin directory as cwd and provides:
#   HERDR_PLUGIN_EVENT_JSON  full event envelope
#   HERDR_PLUGIN_STATE_DIR   durable per-plugin state directory
#
# The event payload is the serialized envelope:
#   {"event":"pane.agent_status_changed","data":{"pane_id":...,
#    "workspace_id":...,"agent_status":"blocked|done|working|idle",...}}
set -euo pipefail

json="${HERDR_PLUGIN_EVENT_JSON:-}"
state_dir="${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/herdr-agent-notify}"
mkdir -p "$state_dir"

[ -n "$json" ] || exit 0

pane_id=$(jq -r '.data.pane_id // empty' <<<"$json")
status=$(jq -r '.data.agent_status // empty' <<<"$json")
agent=$(jq -r '.data.display_agent // .data.agent // "agent"' <<<"$json")
title=$(jq -r '.data.title // empty' <<<"$json")

[ -n "$pane_id" ] && [ -n "$status" ] || exit 0

# Pane ids can contain characters unsafe for filenames; hash them instead.
key=$(printf '%s' "$pane_id" | cksum | cut -d' ' -f1)
last_file="$state_dir/$key"

last=""
[ -f "$last_file" ] && last=$(cat "$last_file")

# Only notify on transitions into blocked or done, never on repeats.
case "$status" in
    blocked|done) ;;
    *) printf '%s' "$status" >"$last_file"; exit 0 ;;
esac
[ "$status" != "$last" ] || exit 0
printf '%s' "$status" >"$last_file"

case "$status" in
    blocked)
        urgency=critical
        summary="$agent needs approval"
        ;;
    done)
        urgency=normal
        summary="$agent finished"
        ;;
esac

body="pane $pane_id"
[ -n "$title" ] && body="$title"

# Click-to-focus: notify-send -A blocks until the notification is clicked
# or dismissed (implies --wait), so it runs detached. The action must be
# named "default": Omarchy's quickshell invokes only the canonical default
# action when the card is clicked (custom names are displayed but never
# invoked). When it fires, ask herdr's socket API to focus the source pane;
# the attached client follows the server's active tab automatically.
socket="${HERDR_SOCKET_PATH:-}"
if [ -n "$socket" ] && command -v python3 >/dev/null 2>&1; then
    (
        action=$(notify-send -a herdr -u "$urgency" -A default=点击查看 "$summary" "$body" 2>/dev/null) || true
        [ "$action" = "default" ] || exit 0
        python3 - "$socket" "$pane_id" <<'PY' >/dev/null 2>&1 || true
import json, socket, sys

sock_path, pane_id = sys.argv[1], sys.argv[2]
request = json.dumps({
    "id": "agent-notify",
    "method": "pane.focus",
    "params": {"pane_id": pane_id},
}) + "\n"

conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
conn.settimeout(3)
conn.connect(sock_path)
conn.sendall(request.encode())
try:
    conn.recv(4096)
except OSError:
    pass
conn.close()
PY
    ) </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
else
    notify-send -a herdr -u "$urgency" "$summary" "$body" 2>/dev/null || true
fi
