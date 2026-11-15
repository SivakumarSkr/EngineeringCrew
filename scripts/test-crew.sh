#!/usr/bin/env bash
# Tests for crew.sh against throwaway git repos. Usage: ./test-crew.sh [path-to-crew.sh]
CREW="${1:-$(cd "$(dirname "$0")" && pwd)/crew.sh}"
ROOT="$(mktemp -d)"; PASS=0; FAILN=0
trap 'rm -rf "$ROOT"' EXIT

ok()   { PASS=$((PASS+1)); echo "  PASS  $1"; }
bad()  { FAILN=$((FAILN+1)); echo "  FAIL  $1"; echo "        got: $2" | head -5; }
expect() { # name, output, regex
  if echo "$2" | grep -Eq "$3"; then ok "$1"; else bad "$1 (wanted /$3/)" "$2"; fi; }
refute() { # name, output, regex
  if echo "$2" | grep -Eq "$3"; then bad "$1 (must not match /$3/)" "$2"; else ok "$1"; fi; }

make_repo() { # dir
  mkdir -p "$1" && cd "$1" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t
  echo "# arch" > architecture.md
  printf '# style\n\n## Commands\ntest: python3 -m unittest\nlint: ruff check .\n' > coding-style.md
  echo "print('hi')" > app.py
  git add -A && git commit -q -m init
}

echo "== preflight =="
mkdir -p "$ROOT/nogit" && cd "$ROOT/nogit" && out="$("$CREW" preflight s1 2>&1)"
expect "non-git folder is reported" "$out" "not a git repository"

make_repo "$ROOT/r1"; out="$("$CREW" preflight s1 2>&1)"
expect "clean repo passes" "$out" "^PREFLIGHT OK"
[ "$(cat .crew/.gitignore)" = "*" ] && ok ".crew ignores itself via .crew/.gitignore" || bad ".crew/.gitignore" "missing"
[ -z "$(git status --porcelain)" ] && ok "tree stays clean after preflight" || bad "tree clean after preflight" "$(git status --porcelain)"
[ -z "$(git rev-parse --git-path info/exclude | xargs grep -s crew)" ] && ok "nothing written to .git/info/exclude" || bad "info/exclude untouched" "crew line found"

make_repo "$ROOT/r2"; rm coding-style.md; git add -A; git commit -q -m rm
out="$("$CREW" preflight s1 2>&1)"
expect "missing coding-style.md is a hard stop" "$out" "coding-style.md: missing"

make_repo "$ROOT/r3"; printf '# style\n' > coding-style.md; git commit -qam x
out="$("$CREW" preflight s1 2>&1)"
expect "coding-style without Commands/test is a hard stop" "$out" "needs a '## Commands' section"

make_repo "$ROOT/r4"; echo new > architecture.md
out="$("$CREW" preflight s1 2>&1)"
expect "dirty tree stops and hints to commit the two files" "$out" "not clean.*Commit architecture.md and coding-style.md"

make_repo "$ROOT/r5"; mkdir config; echo X=1 > config/.env; echo X=1 > .env.example
out="$("$CREW" preflight s1 2>&1)"
expect "nested config/.env is caught" "$out" "secret-like files.*config/\.env"
refute ".env.example is not treated as a secret" "$(echo "$out" | grep 'secret-like')" "\.env\.example"
echo "config/.env" > .gitignore; echo ".env.example" >> .gitignore; git add .gitignore; git commit -qm ign
out="$("$CREW" preflight s1 2>&1)"
expect "gitignored secrets pass" "$out" "^PREFLIGHT OK"

echo "== git directory not writable (sandbox case) =="
if [ "$(id -u)" != 0 ]; then
  make_repo "$ROOT/r8"; chmod a-w .git
  out="$("$CREW" preflight s1 2>&1)"; chmod u+w .git
  expect "unwritable .git is one clear problem" "$out" "git cannot write inside .*sandbox may be blocking"
  expect "message says the crew will not change the sandbox" "$out" "will not change the sandbox"
else echo "  SKIP  running as root, permissions are not enforced"; fi

echo "== setup, lock, resume =="
make_repo "$ROOT/r6"; "$CREW" preflight s1 >/dev/null
out="$("$CREW" setup s1 fix 'handle empty name' 2>&1)"
expect "setup succeeds" "$out" "^SETUP OK branch=crew/s1"
expect "on the crew branch" "$(git rev-parse --abbrev-ref HEAD)" "^crew/s1$"
for f in 00-task.md state.md loops.md usage.md; do
  [ -f ".crew/runs/s1/$f" ] && ok "run file $f exists" || bad "run file $f exists" "missing"
done
[ -f .crew/lock ] && ok "lock created" || bad "lock created" "missing"
expect "state starts at tdd-expert in fix mode" "$(cat .crew/runs/s1/state.md)" "Stage: tdd-expert"
git status --porcelain | grep -q . && bad "crew files stay out of git status" "$(git status --porcelain)" || ok "crew files stay out of git status"

git switch -q main
out="$("$CREW" preflight s2 2>&1)"
expect "second run is blocked by the lock" "$out" "holds .crew/lock"
git switch -q crew/s1
out="$("$CREW" preflight s1 --resume 2>&1)"
expect "resume on the right branch passes" "$out" "^PREFLIGHT OK"
git switch -q main
out="$("$CREW" preflight s1 --resume 2>&1)"
expect "resume on the wrong branch fails" "$out" "needs the branch crew/s1"
git switch -q crew/s1

echo "== checkpoint and outside edits =="
mkdir -p src && echo "def f(): pass" > src/new.py
out="$("$CREW" checkpoint s1 implementer 1 2>&1)"
expect "checkpoint written" "$out" "^CHECKPOINT .*checkpoint-implementer-r1.patch"
expect "patch contains the new untracked file" "$(cat .crew/runs/s1/checkpoint-implementer-r1.patch)" "src/new.py"
out="$("$CREW" preflight s1 --resume 2>&1)"
refute "no warning when tree unchanged" "$out" "WARN"
echo "# edited by hand" >> app.py
out="$("$CREW" preflight s1 --resume 2>&1)"
expect "outside edit is flagged on resume" "$out" "WARN: the working tree changed"
git checkout -q app.py

echo "== worktree =="
make_repo "$ROOT/r7"; git worktree add -q "$ROOT/r7-wt" -b wtb 2>/dev/null; cd "$ROOT/r7-wt"
out="$("$CREW" preflight s1 2>&1)"
expect "preflight works inside a worktree" "$out" "^PREFLIGHT OK"
echo x > .crew/probe.txt; [ -z "$(git status --porcelain)" ] && ok "worktree: .crew content is ignored" || bad "worktree ignore" "$(git status --porcelain)"

echo "== check-handoff =="
cd "$ROOT"; mkdir -p h
good() { printf '# Domain expert handoff: s\nStatus: %s\nRound: 1\n\n## Decisions\n- a\n\n## Files touched\n- none\n\n## Open questions\n%s\n\n## For the next agent\n- x\n' "$1" "$2"; }
good DONE "- none" > h/01-domain.md
expect "valid DONE handoff" "$("$CREW" check-handoff h/01-domain.md)" "^OK status=DONE round=1"
good NEEDS_USER "- none" > h/01-domain.md
expect "NEEDS_USER without questions rejected" "$("$CREW" check-handoff h/01-domain.md)" "^FAIL.*NEEDS_USER"
good NEEDS_USER "- Which currency?" > h/01-domain.md
expect "NEEDS_USER with a question accepted" "$("$CREW" check-handoff h/01-domain.md)" "^OK status=NEEDS_USER"
good ROUTE:architect "- none" > h/06-review.md
expect "ROUTE without Route reason rejected" "$("$CREW" check-handoff h/06-review.md)" "^FAIL.*Route reason"
{ good ROUTE:architect "- none"; printf '\n## Route reason\n- boundary wrong\n'; } > h/06-review.md
expect "ROUTE with Route reason accepted" "$("$CREW" check-handoff h/06-review.md)" "^OK status=ROUTE:architect"
good DONE "- none" | sed 's/^Status: DONE/Status: MAYBE/' > h/02-design.md
expect "bad status rejected" "$("$CREW" check-handoff h/02-design.md)" "^FAIL.*Status"
{ good DONE "- none"; yes word | head -700 | tr '\n' ' '; } > h/04-impl.md
expect "over-cap handoff rejected" "$("$CREW" check-handoff h/04-impl.md)" "^FAIL over-cap: words=[0-9]+ cap=250"
printf 'no header\nStatus: DONE\n' > h/05-refactor.md
expect "missing header rejected" "$("$CREW" check-handoff h/05-refactor.md)" "^FAIL"

echo "== finish =="
cd "$ROOT/r6"; out="$("$CREW" finish s1 2>&1)"
expect "finish reports and removes the lock" "$out" "FINISHED s1"
[ -f .crew/lock ] && bad "lock removed" "still there" || ok "lock removed"
expect "abort-help prints manual commands" "$("$CREW" abort-help s1)" "git branch -D crew/s1"

echo; echo "passed=$PASS failed=$FAILN"; [ "$FAILN" -eq 0 ]
