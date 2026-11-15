#!/usr/bin/env bash
# Copies this sample into a NEW folder outside the crew project and commits it,
# so the crew's clean-tree check passes. Usage: ./setup.sh [target-dir]
set -eu
SRC="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-$HOME/crew-sample-repo}"
[ -e "$TARGET" ] && { echo "$TARGET already exists: pick another folder or remove it yourself"; exit 1; }
mkdir -p "$TARGET"
cp -R "$SRC"/. "$TARGET"/
rm -f "$TARGET/setup.sh"
cd "$TARGET"
git init -q -b main .
git add -A
git commit -q -m "Initial sample repo" || { echo "git commit failed: set user.name and user.email first"; exit 1; }
echo "Sample repo ready at $TARGET. Open Claude Code there and try:"
echo '  /orchestrate fix: greet() should return "Hello, stranger!" when the name is empty or only whitespace'
echo "Afterwards: git diff main, then 'git switch main && git branch -D crew/<slug>' to reset."
