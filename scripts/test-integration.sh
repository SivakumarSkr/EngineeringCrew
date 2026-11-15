#!/usr/bin/env bash
# Dry run of a whole fix pipeline with simulated agents, using the real crew.sh and boundary.py.
# Proves the plumbing fits together; it does not test model behavior.
HERE="$(cd "$(dirname "$0")" && pwd)"; CREW="$HERE/crew.sh"; HOOK="$HERE/boundary.py"
SRC="$HERE/../sample-repo"; T="$(mktemp -d)"; PASS=0; FAILN=0
trap 'rm -rf "$T"' EXIT
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }; bad(){ FAILN=$((FAILN+1)); echo "  FAIL  $1  ($2)"; }
hook() { # agent tool path -> exit code
  python3 - "$HOOK" "$1" "$2" "$3" "$PWD" <<'PY'
import json, subprocess, sys
hook, agent, tool, path, cwd = sys.argv[1:6]
p = subprocess.run([sys.executable, hook, agent],
    input=json.dumps({"tool_name": tool, "tool_input": {"file_path": path}, "cwd": cwd}), capture_output=True, text=True)
sys.exit(p.returncode)
PY
}
allow() { hook "$2" "$3" "$4" && ok "$1" || bad "$1" "blocked"; }
block() { hook "$2" "$3" "$4"; [ $? -eq 2 ] && ok "$1" || bad "$1" "was allowed"; }
handoff() { # file agent status [extra]
  printf '# %s handoff: s\nStatus: %s\nRound: 1\n\n## Decisions\n- ok\n\n## Files touched\n- x\n\n## Open questions\n- none\n\n## For the next agent\n- x\n%s\n' "$2" "$3" "${4:-}" > "$1"; }

cp -r "$SRC/." "$T/" && cd "$T" && git init -q -b main . && git config user.email t@t && git config user.name t && git add -A && git commit -q -m init
SLUG=empty-name-20261115; RUN=.crew/runs/$SLUG
echo "== setup =="
"$CREW" preflight $SLUG | grep -q "PREFLIGHT OK" && ok "preflight" || bad preflight ""
"$CREW" setup $SLUG fix "greet() handles empty names" | grep -q "SETUP OK" && ok "setup" || bad setup ""

echo "== tdd-expert =="
allow "tdd writes a test" tdd-expert Write "$T/tests/test_greeting.py"
block "tdd cannot touch source" tdd-expert Write "$T/src/greeting.py"
cat >> tests/test_greeting.py <<'PY'


class EmptyNameTests(unittest.TestCase):
    def test_empty_name_gets_stranger(self):
        self.assertEqual(greet("  "), "Hello, stranger!")
PY
python3 -m unittest discover -q >/dev/null 2>&1 && bad "red phase" "tests passed before the fix" || ok "red phase: new test fails first"
allow "tdd writes its handoff" tdd-expert Write "$T/$RUN/03-tests.md"
handoff $RUN/03-tests.md "TDD expert" DONE; "$CREW" check-handoff $RUN/03-tests.md | grep -q '^OK' && ok "handoff 03 valid" || bad "handoff 03" ""
"$CREW" checkpoint $SLUG tdd-expert 1 | grep -q CHECKPOINT && ok "checkpoint after tdd" || bad checkpoint ""

echo "== implementer =="
block "implementer cannot edit the new test" implementer Edit "$T/tests/test_greeting.py"
block "implementer cannot read domain handoff" implementer Read "$T/$RUN/01-domain.md"
allow "implementer reads tests handoff" implementer Read "$T/$RUN/03-tests.md"
allow "implementer edits source" implementer Edit "$T/src/greeting.py"
cat > src/greeting.py <<'PY'
def greet(name: str) -> str:
    """Return a greeting for the given name, or for a stranger if it is blank."""
    return f"Hello, {name.strip() or 'stranger'}!"
PY
python3 -m unittest discover -q >/dev/null 2>&1 && ok "green phase: tests pass" || bad "green phase" "still failing"
handoff $RUN/04-impl.md Implementer DONE; "$CREW" check-handoff $RUN/04-impl.md | grep -q '^OK' && ok "handoff 04 valid" || bad "handoff 04" ""
"$CREW" checkpoint $SLUG implementer 1 | grep -q CHECKPOINT && ok "checkpoint after implementer" || bad checkpoint ""

echo "== reviewer, tester, verifier =="
allow "reviewer writes verdict" reviewer Write "$T/$RUN/06-review.md"
block "reviewer cannot edit source" reviewer Edit "$T/src/greeting.py"
allow "tester writes results" tester Write "$T/$RUN/07-test-results.md"
block "tester cannot read the task" tester Read "$T/$RUN/00-task.md"
allow "verifier writes the feature doc" verifier Write "$T/docs/$SLUG.md"
allow "verifier updates architecture.md" verifier Edit "$T/architecture.md"
block "verifier cannot edit tests" verifier Edit "$T/tests/test_greeting.py"
mkdir -p docs; echo "# $SLUG" > docs/$SLUG.md; echo "- [$SLUG]($SLUG.md): blank names greet a stranger" > docs/INDEX.md

echo "== result =="
CHANGED="$(git add -N . && git diff --name-only main | sort | tr '\n' ' ')"
[ "$CHANGED" = "docs/INDEX.md docs/$SLUG.md src/greeting.py tests/test_greeting.py " ] && ok "diff holds exactly the expected files" || bad "diff files" "$CHANGED"
git status --porcelain | grep -q '\.crew' && bad ".crew stays out of git" "leaked" || ok ".crew stays out of git"
[ "$(git rev-parse --abbrev-ref HEAD)" = "crew/$SLUG" ] && ok "work stayed on the crew branch" || bad branch ""
[ "$(git rev-parse main)" = "$(git rev-parse HEAD)" ] && ok "nothing committed (HEAD equals base)" || bad commit "HEAD moved"
"$CREW" finish $SLUG | grep -q FINISHED && [ ! -f .crew/lock ] && ok "finish removes the lock" || bad finish ""
echo; echo "passed=$PASS failed=$FAILN"; [ "$FAILN" -eq 0 ]
