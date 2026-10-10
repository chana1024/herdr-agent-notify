# herdr agent-notify

A herdr plugin that sends a desktop notification when a coding agent
completes a task (`done`) or requests approval (`blocked`).

## How it works

Subscribes to the `pane.agent_status_changed` event. When a pane's agent
status transitions into `blocked` or `done`, it calls `notify-send`
(freedesktop desktop notifications). Repeats of the same status are
suppressed, so you get one notification per transition.

Notification urgency:

- `blocked` (needs your approval): critical
- `done`: normal

## Requirements

- Linux with `notify-send` (libnotify) and a notification daemon
- `jq`

## Install

```bash
herdr plugin link /path/to/herdr-agent-notify
```

or install from GitHub:

```bash
herdr plugin install chana1024/herdr-agent-notify
```

Verify it is registered:

```bash
herdr plugin list
```

## Test

Run the hook directly with a fake event envelope:

```bash
export HERDR_PLUGIN_STATE_DIR=/tmp/agent-notify-test
export HERDR_PLUGIN_EVENT_JSON='{"event":"pane.agent_status_changed","data":{
  "pane_id":"w1:p1","workspace_id":"w1","agent_status":"blocked",
  "display_agent":"claude","title":"fix the login bug"}}'
bash notify.sh
```

Then end-to-end: link the plugin, start herdr, run a real agent task in a
pane, and confirm the desktop notification appears when it finishes.

## Files

- `herdr-plugin.toml` — manifest declaring the event hook
- `notify.sh` — parses `HERDR_PLUGIN_EVENT_JSON`, deduplicates per pane
  using `HERDR_PLUGIN_STATE_DIR`, calls `notify-send`

## Click to focus

Notifications are sent with a `default` libnotify action. Clicking the
notification (anywhere on the card) asks herdr's socket API to focus the
pane the agent ran in (`pane.focus`), and the attached client jumps to
that pane's tab automatically.

Notes:

- The action is named `default` on purpose: Omarchy's quickshell
  notification cards invoke only the canonical `default` action on
  click; custom action names are displayed but never invoked.
- Requires `python3` (socket API call) and `HERDR_SOCKET_PATH` in the
  plugin environment (provided by herdr >= 0.7).
- Without a socket or python3 the plugin falls back to a plain
  notification.
