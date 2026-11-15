#!/usr/bin/env bash
# Installs the crew into ~/.claude. Existing different files are backed up first.
# Does not touch your settings.json: merge security/*.json by hand.
set -eu
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="${CLAUDE_HOME:-$HOME/.claude}"
STAMP="$(date +%Y%m%d-%H%M%S)"; BACKUP="$DEST/crew-backup-$STAMP"; backed=0

put() { # src dest
  mkdir -p "$(dirname "$2")"
  if [ -e "$2" ] && ! cmp -s "$1" "$2"; then
    mkdir -p "$BACKUP"; cp -p "$2" "$BACKUP/$(echo "${2#$DEST/}" | tr '/' '_')"; backed=1
  fi
  cp "$1" "$2"
}

for f in "$SRC"/agents/*.md; do put "$f" "$DEST/agents/$(basename "$f")"; done
for d in "$SRC"/skills/*/; do n="$(basename "$d")"; put "$d/SKILL.md" "$DEST/skills/$n/SKILL.md"; done
put "$SRC/commands/orchestrate.md" "$DEST/commands/orchestrate.md"
for f in crew.sh boundary.py; do put "$SRC/scripts/$f" "$DEST/crew/$f"; chmod +x "$DEST/crew/$f"; done

echo "Installed: 8 agents, 3 skills, 1 command, 2 scripts into $DEST"
[ "$backed" = 1 ] && echo "Replaced files were backed up to $BACKUP"
echo "Next: merge security/settings.deny-ask.json into your settings, restart Claude Code, run /orchestrate."
