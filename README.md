# herdr-claude-tab-rename

Herdr plugin that keeps each tab named after the Claude Code session running in it.

Rename a session with `/rename`, and its tab follows within about a second. Sessions you haven't renamed use Claude's auto-generated title.

## How it works

Claude Code writes its session title (your `/rename` title, or its own auto title) into the terminal title. herdr doesn't pass title changes to plugins (`pane.updated` is excluded from plugin hooks), so the startup hook launches one small background watcher. Every second it reads `herdr pane list` and runs `herdr tab rename` on any tab whose Claude pane's title changed. A pidfile in the plugin state dir keeps it to one watcher, and it exits about 30s after herdr stops answering. The `pane.agent_detected` and `pane.agent_status_changed` hooks sync too, as a backup.

Auto titles only rename tabs that still have their default number label or a name the plugin set itself, so a tab you named by hand keeps its name. A `/rename` always wins: the plugin checks the session transcript for Claude's `custom-title` record, and when the new title matches it, the tab is renamed even if you named it yourself. If you rename the tab by hand after that, your name stays until the next `/rename`.

If a tab holds several Claude panes, the one whose title changed last wins.

Claude Code needs no hooks for this.

## Requirements

- herdr >= 0.8.0 (macOS or Linux)
- bash, jq (already included in recent macOS versions)

## Install

    herdr plugin install oronbz/herdr-claude-tab-rename --yes

Or, from a local checkout:

    herdr plugin link .

## Usage

Nothing to do; it starts with herdr. To resync every tab (this also restarts the watcher if it isn't running):

    herdr plugin action invoke claude-tab-rename.sync-all

Troubleshooting:

    herdr plugin log list --plugin claude-tab-rename
