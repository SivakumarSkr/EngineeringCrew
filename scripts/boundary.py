#!/usr/bin/env python3
"""PreToolUse hook enforcing each crew agent's read and write boundaries.

Wired per agent through frontmatter hooks:  python3 ~/.claude/crew/boundary.py <agent>
Reads the hook JSON on stdin. Exit 0 allows the call, exit 2 blocks it and feeds
stderr back to the agent.

Covers: Write, Edit, MultiEdit, NotebookEdit, Read, Grep, Glob and Bash.
Bash is best effort only: any command that mentions .crew is blocked for every agent,
and write-like commands are blocked for the reviewer and tester. A determined shell
command can still get around this, so pair it with Claude Code sandboxing.
"""
import json
import os
import re
import sys

HANDOFFS = [
    "00-task.md", "01-domain.md", "02-design.md", "03-tests.md", "04-impl.md",
    "05-refactor.md", "06-review.md", "07-test-results.md", "08-verify.md",
]

AGENTS = {
    "domain-expert": dict(
        write_run=["01-domain.md"], write_repo=None,
        read_run=["00-task.md", "01-domain.md", "02-design.md", "03-tests.md"]),
    "architect": dict(
        write_run=["02-design.md"], write_repo=None,
        read_run=["00-task.md", "01-domain.md", "02-design.md", "06-review.md"]),
    "tdd-expert": dict(
        write_run=["03-tests.md"], write_repo="tests",
        read_run=["00-task.md", "01-domain.md", "02-design.md", "03-tests.md", "04-impl.md"]),
    "implementer": dict(
        write_run=["04-impl.md"], write_repo="source",
        read_run=["00-task.md", "02-design.md", "03-tests.md", "04-impl.md", "06-review.md", "07-test-results.md"]),
    "refactorer": dict(
        write_run=["05-refactor.md"], write_repo="source",
        read_run=["00-task.md", "02-design.md", "04-impl.md", "05-refactor.md"]),
    "reviewer": dict(
        write_run=["06-review.md"], write_repo=None,
        read_run=["00-task.md", "02-design.md", "03-tests.md", "05-refactor.md", "06-review.md"]),
    "tester": dict(
        write_run=["07-test-results.md"], write_repo=None,
        read_run=["03-tests.md", "06-review.md", "07-test-results.md"]),
    "verifier": dict(
        write_run=["08-verify.md"], write_repo="docs",
        read_run=list(HANDOFFS)),
}

DEFAULT_TEST_PATTERNS = [
    r"(^|/)(tests?|__tests__|spec|specs|e2e|testing|fixtures)/",
    r"(^|/)test_[^/]*\.[A-Za-z0-9]+$",
    r"_test\.[A-Za-z0-9]+$",
    r"\.(test|spec)\.[A-Za-z0-9]+$",
    r"(^|/)conftest\.py$",
    r"(Test|Tests)\.(java|kt|cs|swift|scala)$",
]

NEVER_WRITE_PREFIXES = (".git/", ".claude/", ".github/")
SECRET_NAME = re.compile(r"(^|/)\.env[^/]*$|\.(pem|key)$")


def deny(msg):
    sys.stderr.write("BOUNDARY: " + msg + "\n")
    sys.exit(2)


def find_root(start):
    cur = os.path.realpath(start)
    while True:
        if os.path.exists(os.path.join(cur, ".git")):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            return None
        cur = parent


def current_slug(root):
    try:
        with open(os.path.join(root, ".crew", "lock")) as fh:
            return fh.read().split()[0]
    except (OSError, IndexError):
        return None


def test_patterns(root):
    path = os.path.join(root, ".crew-test-paths")
    if os.path.isfile(path):
        with open(path) as fh:
            lines = [ln.strip() for ln in fh if ln.strip() and not ln.startswith("#")]
        if lines:
            return lines
    return DEFAULT_TEST_PATTERNS


def is_test(rel, root):
    return any(re.search(p, rel) for p in test_patterns(root))


def relpath(path, root, cwd):
    if not os.path.isabs(path):
        path = os.path.join(cwd, path)
    real = os.path.realpath(path)  # resolves symlinks, also for files that do not exist yet
    rel = os.path.relpath(real, root).replace(os.sep, "/")
    return rel


def run_file(rel):
    m = re.match(r"^\.crew/runs/([^/]+)/([^/]+)$", rel)
    return (m.group(1), m.group(2)) if m else (None, None)


def check_write(agent, cfg, rel, root):
    if rel == ".." or rel.startswith("../"):
        deny(f"{agent} may not write outside the repository ({rel}).")
    if rel == ".crew" or rel.startswith(".crew/"):
        slug, name = run_file(rel)
        cur = current_slug(root)
        if name in cfg["write_run"] and (cur is None or slug == cur):
            return
        deny(f"{agent} may write only its own handoff in the current run folder: {', '.join(cfg['write_run'])}. Tried: {rel}")
    if rel.startswith(NEVER_WRITE_PREFIXES) or rel == ".crew-test-paths" or SECRET_NAME.search(rel):
        deny(f"{agent} may not write {rel} (protected path or secret-like file).")
    kind = cfg["write_repo"]
    if kind is None:
        deny(f"{agent} may not edit repository files. Tried: {rel}")
    if kind == "tests":
        if not is_test(rel, root):
            deny(f"{agent} may edit test files only. {rel} is not a test path (see .crew-test-paths to customise).")
    elif kind == "source":
        if is_test(rel, root):
            deny(f"{agent} may not edit tests. {rel} is a test path. If a test is wrong, report it in your handoff.")
        if rel.startswith("docs/") or rel in ("architecture.md", "coding-style.md"):
            deny(f"{agent} may not edit docs or the architecture and coding-style files. Tried: {rel}")
    elif kind == "docs":
        if not (rel.startswith("docs/") or rel == "architecture.md"):
            deny(f"{agent} may write only docs/ and architecture.md. Tried: {rel}")


def check_read(agent, cfg, rel, root):
    if rel == ".." or rel.startswith("../"):
        return  # outside the repo (libraries, stdlib); secrets are covered by permission deny rules
    if rel == ".crew" or rel.startswith(".crew/"):
        slug, name = run_file(rel)
        cur = current_slug(root)
        if name in cfg["read_run"] and (cur is None or slug == cur):
            return
        deny(f"{agent} may not read {rel}. Allowed run files: {', '.join(cfg['read_run'])}.")
    if SECRET_NAME.search(rel):
        deny(f"{agent} may not read secret-like file {rel}.")


WRITE_LIKE = [
    r"(^|[^<>\d&])>{1,2}\s*[^\s&]",          # redirect into a file
    r"\btee\b",
    r"\bsed\s+(-[A-Za-z]*i|--in-place)",
    r"\b(rm|mv|cp|chmod|chown|dd|truncate|touch|mkdir|ln)\b",
    r"\bgit\s+(commit|push|reset|clean|checkout|restore|apply|stash|rebase|merge|add|switch|branch|tag|am|cherry-pick|rm|mv)\b",
]


def check_bash(agent, command):
    if ".crew" in command:
        deny(f"{agent} may not touch .crew from the shell. Use the Read tool on your allowed handoff files.")
    if agent in ("reviewer", "tester"):
        cleaned = re.sub(r"\d?>&\d|&>\s*/dev/null|\d?>\s*/dev/null", "", command)
        for pat in WRITE_LIKE:
            if re.search(pat, cleaned):
                deny(f"{agent} is read-only. This command looks like it writes or changes state: {command[:120]}")


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in AGENTS:
        deny(f"hook misconfigured: unknown agent {sys.argv[1:] }")
    agent = sys.argv[1]
    cfg = AGENTS[agent]
    data = json.load(sys.stdin)
    tool = data.get("tool_name", "")
    ti = data.get("tool_input") or {}
    cwd = data.get("cwd") or os.getcwd()
    root = find_root(cwd)
    if root is None:
        return  # not in a repo: nothing to enforce

    if tool in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        path = ti.get("file_path") or ti.get("notebook_path")
        if not path:
            deny(f"{agent}: {tool} call without a file path.")
        check_write(agent, cfg, relpath(path, root, cwd), root)
    elif tool == "Read":
        path = ti.get("file_path")
        if path:
            check_read(agent, cfg, relpath(path, root, cwd), root)
    elif tool in ("Grep", "Glob"):
        path = ti.get("path")
        if path:
            rel = relpath(path, root, cwd)
            if rel == ".crew" or rel.startswith(".crew"):
                deny(f"{agent} may not search the .crew folder. Read your allowed handoff files directly.")
        for key in ("pattern", "glob"):
            if ".crew" in str(ti.get(key, "")):
                deny(f"{agent} may not search the .crew folder.")
    elif tool == "Bash":
        check_bash(agent, ti.get("command", ""))


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:  # fail closed so a bug is visible, not silently permissive
        deny(f"hook error ({type(exc).__name__}: {exc}). Blocking to be safe.")
