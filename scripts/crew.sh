#!/usr/bin/env bash
# crew.sh: deterministic helpers for the engineering crew orchestrator.
# Install to ~/.claude/crew/crew.sh and always call it by that exact path.
#
#   crew.sh preflight <slug> [--resume]
#   crew.sh setup <slug> <fix|feature> <request...>
#   crew.sh checkpoint <slug> <agent> <round>
#   crew.sh treehash <slug>
#   crew.sh check-handoff <file>
#   crew.sh finish <slug>
#   crew.sh abort-help <slug>
set -u

CMD="${1:-}"; [ $# -gt 0 ] && shift

die() { echo "$*" >&2; exit 1; }

# Update "Key: value" in a file, or append it. Portable (no sed -i).
setkv() {
  local f="$1" k="$2" v="$3"
  if grep -q "^${k}:" "$f" 2>/dev/null; then
    awk -v k="$k" -v v="$v" 'index($0, k ":") == 1 { print k ": " v; next } { print }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  else
    echo "${k}: ${v}" >> "$f"
  fi
}

getkv() { awk -v k="$2" 'index($0, k ": ") == 1 { sub("^" k ": ", ""); print; exit }' "$1" 2>/dev/null; }

cap_for() {
  case "$1" in
    01-*) echo 600 ;; 02-*) echo 600 ;; 03-*) echo 400 ;; 04-*) echo 250 ;;
    05-*) echo 200 ;; 06-*) echo 300 ;; 07-*) echo 200 ;; 08-*) echo 500 ;;
    *) echo 0 ;;
  esac
}

GIT_WRITE_HELP="git add -N failed. If a sandbox blocks writes inside .git, allow them for this project or run outside the sandbox."

tree_hash() {
  local base="$1"
  git add -N . >/dev/null 2>&1 || return 1
  git diff --binary "$base" | shasum -a 256 | cut -d' ' -f1
}

cmd_preflight() {
  local slug="" resume=0 a
  for a in "$@"; do case "$a" in --resume) resume=1 ;; *) slug="$a" ;; esac; done
  [ -n "$slug" ] || die "usage: crew.sh preflight <slug> [--resume]"

  local problems=() warns=() inrepo=1
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { inrepo=0; problems+=("not a git repository: the crew needs git"); }
  if [ "$inrepo" = 1 ]; then cd "$(git rev-parse --show-toplevel)" || exit 1; fi

  # 1. Required repo inputs
  [ -s architecture.md ] || problems+=("architecture.md: missing or empty, needed by domain-expert, architect, verifier")
  if [ -s coding-style.md ]; then
    awk '/^## Commands/{s=1;next} /^## /{s=0} s' coding-style.md | grep -Eq '^test:[[:space:]]*[^[:space:]]' \
      || problems+=("coding-style.md: needs a '## Commands' section with a 'test:' line, needed by tdd-expert, tester")
  else
    problems+=("coding-style.md: missing or empty, needed by tdd-expert, implementer, refactorer, reviewer")
  fi

  if [ "$inrepo" = 1 ]; then
    git rev-parse --verify --quiet HEAD >/dev/null || problems+=("the repository has no commits yet: commit once so the crew has a base")

    # 2. Keep .crew/ out of git without touching .git or a tracked file: a .gitignore holding '*'
    #    inside .crew/ ignores the whole folder, itself included. Works in worktrees and sandboxes.
    mkdir -p .crew
    [ -f .crew/.gitignore ] || printf '*\n' > .crew/.gitignore

    # git must be able to create files in its own directory (branch, index lock). Some sandboxes forbid it.
    local gd probe; gd="$(git rev-parse --git-dir)"; probe="$gd/crew-write-probe.$$"
    if { : > "$probe"; } 2>/dev/null; then rm -f "$probe"; else
      problems+=("git cannot write inside $gd from this shell (a sandbox may be blocking it), but the crew needs that to create its branch and track new files. Allow writes to .git for this project in the sandbox settings, or run the crew outside the sandbox. The crew will not change the sandbox itself")
    fi

    # 3. Git checks
    local leaks
    leaks="$(git ls-files --others --exclude-standard -- ':(glob)**/.env*' ':(glob)**/*.pem' ':(glob)**/*.key' 2>/dev/null | grep -Ev '\.(example|sample|template)$')"
    if [ -n "$leaks" ]; then
      problems+=("secret-like files are not ignored (they would leak into diffs and patches): $(echo "$leaks" | head -10 | tr '\n' ' '). Add them to .gitignore first")
    fi

    if [ "$resume" = 0 ]; then
      local dirty; dirty="$(git status --porcelain)"
      if [ -n "$dirty" ]; then
        local hint=""
        echo "$dirty" | grep -Eq '(architecture|coding-style)\.md' && hint=" Commit architecture.md and coding-style.md first."
        problems+=("working tree is not clean, so the run's diff would mix your changes with the crew's.${hint} Dirty paths: $(echo "$dirty" | head -20 | awk '{print $2}' | tr '\n' ' ')")
      fi
      git rev-parse --verify --quiet "refs/heads/crew/$slug" >/dev/null && problems+=("branch crew/$slug already exists: choose another slug")
      if [ -f .crew/lock ]; then
        problems+=("another crew run holds .crew/lock ($(cat .crew/lock)). If it is stale, delete .crew/lock yourself")
      fi
    else
      local cur; cur="$(git rev-parse --abbrev-ref HEAD)"
      [ "$cur" = "crew/$slug" ] || problems+=("resume needs the branch crew/$slug checked out, but the current branch is $cur")
      if [ -f .crew/lock ] && ! grep -q "^$slug " .crew/lock; then
        problems+=("another crew run holds .crew/lock ($(cat .crew/lock))")
      fi
      local state=".crew/runs/$slug/state.md"
      [ -f "$state" ] || problems+=("no state file for $slug at $state")
      if [ -f "$state" ]; then
        local base saved now
        base="$(getkv "$state" Base)"; saved="$(getkv "$state" Tree-hash)"
        if [ -n "$base" ] && [ -n "$saved" ]; then
          now="$(tree_hash "$base")" || now=""
          [ -n "$now" ] || warns+=("WARN: could not compute the tree hash ($GIT_WRITE_HELP)")
          [ -z "$now" ] || [ "$now" = "$saved" ] || warns+=("WARN: the working tree changed since the last agent finished (files edited outside the crew?). Ask the user whether to continue.")
        fi
      fi
    fi
  fi

  if [ "${#problems[@]}" -gt 0 ]; then
    echo "PREFLIGHT FAILED. The crew cannot start."
    echo "Problems:"
    local p; for p in "${problems[@]}"; do echo "- $p"; done
    echo "Fix these, then run again."
    exit 1
  fi
  echo "PREFLIGHT OK"
  local w; for w in "${warns[@]:-}"; do [ -n "$w" ] && echo "$w"; done
  exit 0
}

cmd_setup() {
  [ $# -ge 3 ] || die "usage: crew.sh setup <slug> <fix|feature> <request...>"
  local slug="$1" mode="$2"; shift 2
  local request="$*"
  case "$mode" in fix|feature) ;; *) die "mode must be fix or feature" ;; esac
  cd "$(git rev-parse --show-toplevel)" || exit 1
  local origin base run
  origin="$(git rev-parse --abbrev-ref HEAD)"; base="$(git rev-parse HEAD)"
  git switch -c "crew/$slug" >/dev/null 2>&1 || die "could not create branch crew/$slug. If a sandbox blocks writes inside .git, allow them for this project, or create the branch yourself outside the sandbox and tell the orchestrator."
  run=".crew/runs/$slug"; mkdir -p "$run"
  {
    echo "# Task: $slug"
    echo "Mode: $mode"
    echo "Base: $base"
    echo "Origin-branch: $origin"
    echo "Branch: crew/$slug"
    echo "Request: $request"
  } > "$run/00-task.md"
  {
    echo "Mode: $mode"
    echo "Slug: $slug"
    echo "Branch: crew/$slug"
    echo "Origin-branch: $origin"
    echo "Base: $base"
    echo "Stage: $([ "$mode" = feature ] && echo domain-expert || echo tdd-expert)"
    echo "Loops: 0"
    echo "Agent-runs: 0"
    echo "Approved: $([ "$mode" = feature ] && echo no || echo n/a)"
    echo "Tree-hash: "
  } > "$run/state.md"
  echo "# Loops for $slug (number | route | raised by | reason)" > "$run/loops.md"
  echo "# Usage for $slug (agent | round | tokens | duration | handoff words)" > "$run/usage.md"
  echo "$slug $(date -u +%Y-%m-%dT%H:%M:%SZ)" > .crew/lock
  echo "SETUP OK branch=crew/$slug base=$base run=$run"
}

cmd_checkpoint() {
  [ $# -eq 3 ] || die "usage: crew.sh checkpoint <slug> <agent> <round>"
  local slug="$1" agent="$2" round="$3" state base out h
  cd "$(git rev-parse --show-toplevel)" || exit 1
  state=".crew/runs/$slug/state.md"; base="$(getkv "$state" Base)"
  [ -n "$base" ] || die "no Base in $state"
  git add -N . >/dev/null 2>&1 || die "$GIT_WRITE_HELP"
  out=".crew/runs/$slug/checkpoint-$agent-r$round.patch"
  git diff --binary "$base" > "$out"
  h="$(shasum -a 256 "$out" | cut -d' ' -f1)"
  setkv "$state" Tree-hash "$h"
  echo "CHECKPOINT $out tree-hash=$h"
}

cmd_treehash() {
  [ $# -eq 1 ] || die "usage: crew.sh treehash <slug>"
  local slug="$1" state base h
  cd "$(git rev-parse --show-toplevel)" || exit 1
  state=".crew/runs/$slug/state.md"; base="$(getkv "$state" Base)"
  [ -n "$base" ] || die "no Base in $state"
  h="$(tree_hash "$base")" || die "$GIT_WRITE_HELP"
  setkv "$state" Tree-hash "$h"
  echo "TREEHASH $h"
}

cmd_check_handoff() {
  [ $# -eq 1 ] || die "usage: crew.sh check-handoff <file>"
  local f="$1" b cap words status round head6
  fail() { echo "FAIL: $*"; exit 1; }
  [ -f "$f" ] || fail "no such file $f"
  b="$(basename "$f")"; cap="$(cap_for "$b")"
  words="$(wc -w < "$f" | tr -d ' ')"
  head6="$(sed -n '1,6p' "$f")"
  echo "$head6" | head -1 | grep -q '^# ' || fail "first line must be '# <Agent> handoff: <slug>'"
  status="$(echo "$head6" | grep -m1 '^Status: ' | sed 's/^Status: //')"
  echo "$status" | grep -Eq '^(DONE|NEEDS_USER|ROUTE:(domain-expert|architect|tdd-expert|implementer|refactorer|reviewer|tester|verifier))$' \
    || fail "bad or missing Status line"
  round="$(echo "$head6" | grep -m1 -E '^Round: [0-9]+$' | sed 's/^Round: //')"
  [ -n "$round" ] || fail "bad or missing Round line"
  grep -q '^## Decisions' "$f" || fail "missing '## Decisions'"
  grep -q '^## Open questions' "$f" || fail "missing '## Open questions'"
  case "$status" in
    ROUTE:*) grep -q '^## Route reason' "$f" || fail "ROUTE status needs a '## Route reason' section" ;;
    NEEDS_USER)
      local oq; oq="$(awk '/^## Open questions/{s=1;next} /^## /{s=0} s' "$f" | sed '/^[[:space:]]*$/d')"
      if { [ -z "$oq" ] || echo "$oq" | grep -Eqi '^-?[[:space:]]*none\.?[[:space:]]*$'; } && ! grep -q '^## Route reason' "$f"; then
        fail "NEEDS_USER needs real Open questions or a Route reason"
      fi ;;
  esac
  if [ "$cap" -gt 0 ] && [ "$words" -gt "$cap" ]; then
    echo "FAIL over-cap: words=$words cap=$cap status=$status"; exit 1
  fi
  echo "OK status=$status round=$round words=$words/$cap"
}

cmd_finish() {
  [ $# -eq 1 ] || die "usage: crew.sh finish <slug>"
  local slug="$1"
  cd "$(git rev-parse --show-toplevel)" || exit 1
  setkv ".crew/runs/$slug/state.md" Stage done
  rm -f .crew/lock
  echo "FINISHED $slug (lock removed)"
  cat ".crew/runs/$slug/usage.md" 2>/dev/null
}

cmd_abort_help() {
  [ $# -eq 1 ] || die "usage: crew.sh abort-help <slug>"
  local slug="$1" origin
  origin="$(getkv ".crew/runs/$slug/state.md" Origin-branch)"
  echo "To abandon this run, run these yourself (the crew never deletes anything):"
  echo "  git switch ${origin:-<original-branch>}"
  echo "  git branch -D crew/$slug"
  echo "  rm .crew/lock"
}

case "$CMD" in
  preflight) cmd_preflight "$@" ;;
  setup) cmd_setup "$@" ;;
  checkpoint) cmd_checkpoint "$@" ;;
  treehash) cmd_treehash "$@" ;;
  check-handoff) cmd_check_handoff "$@" ;;
  finish) cmd_finish "$@" ;;
  abort-help) cmd_abort_help "$@" ;;
  *) die "usage: crew.sh preflight|setup|checkpoint|treehash|check-handoff|finish|abort-help ..." ;;
esac
