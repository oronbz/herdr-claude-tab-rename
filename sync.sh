#!/usr/bin/env bash
set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "claude-tab-rename: jq is required, please install it and restart herdr" >&2
  exit 1
fi

herdr_bin="${HERDR_BIN_PATH:-herdr}"
state_dir="${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}/claude-tab-rename}"
pid_file="$state_dir/watch.pid"
script_path="${BASH_SOURCE[0]}"
mkdir -p "$state_dir" 2>/dev/null || exit 0

claude_panes() {
  jq -r '(.result.panes // [.result.pane])[]? | select(.agent == "claude") | [.pane_id, .tab_id, (.terminal_title_stripped // "")] | @tsv' 2>/dev/null
}

sync_pane() {
  local pane_id="$1" tab_id="$2" title="$3" label pane_state tab_state
  [ -n "$pane_id" ] && [ -n "$tab_id" ] && [ -n "$title" ] || return 0
  [ "$title" = "Claude Code" ] && return 0
  pane_state="$state_dir/pane_${pane_id//[^A-Za-z0-9_-]/_}"
  tab_state="$state_dir/tab_${tab_id//[^A-Za-z0-9_-]/_}"
  [ -r "$pane_state" ] && [ "$(cat "$pane_state")" = "$title" ] && return 0
  label="$("$herdr_bin" tab get "$tab_id" 2>/dev/null | jq -r '.result.tab.label // empty' 2>/dev/null)" || return 0
  if [[ ! "$label" =~ ^[0-9]+$ ]] && { [ ! -r "$tab_state" ] || [ "$(cat "$tab_state")" != "$label" ]; }; then
    printf '%s' "$title" > "$pane_state"
    return 0
  fi
  if [ "$label" != "$title" ]; then
    "$herdr_bin" tab rename "$tab_id" "$title" >/dev/null 2>&1 || return 0
  fi
  printf '%s' "$title" > "$tab_state"
  printf '%s' "$title" > "$pane_state"
}

sync_all() {
  local panes
  panes="$("$herdr_bin" pane list 2>/dev/null)" || return 1
  while IFS=$'\t' read -r pane_id tab_id title; do
    sync_pane "$pane_id" "$tab_id" "$title"
  done < <(claude_panes <<<"$panes")
}

watcher_running() {
  local pid
  [ -r "$pid_file" ] || return 1
  pid="$(cat "$pid_file")"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

watch() {
  local failures=0
  watcher_running && [ "$(cat "$pid_file")" != "$$" ] && exit 0
  printf '%s' "$$" > "$pid_file"
  trap '[ "$(cat "$pid_file" 2>/dev/null)" = "$$" ] && rm -f "$pid_file"' EXIT
  while [ "$failures" -lt 30 ]; do
    if sync_all; then failures=0; else failures=$((failures + 1)); fi
    sleep 1
  done
}

case "${1:-}" in
  --all)
    sync_all
    ;;
  --watch)
    watch
    ;;
  --start)
    sync_all
    if ! watcher_running; then
      nohup bash "$script_path" --watch </dev/null >/dev/null 2>&1 &
    fi
    ;;
  *)
    event_json="${HERDR_PLUGIN_EVENT_JSON:-}"
    event_pane="$(jq -r '.pane.pane_id // .pane_id // .data.pane.pane_id // .data.pane_id // empty' <<<"${event_json:-null}" 2>/dev/null)"
    event_pane="${event_pane:-${HERDR_PANE_ID:-}}"
    [ -n "$event_pane" ] || exit 0
    while IFS=$'\t' read -r pane_id tab_id title; do
      sync_pane "$pane_id" "$tab_id" "$title"
    done < <("$herdr_bin" pane get "$event_pane" 2>/dev/null | claude_panes)
    ;;
esac
exit 0
