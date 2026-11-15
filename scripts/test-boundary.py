#!/usr/bin/env python3
"""Tests for boundary.py. Usage: python3 test-boundary.py [path-to-boundary.py]"""
import json, os, subprocess, sys, tempfile

HOOK = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "boundary.py")
root = tempfile.mkdtemp()
outside = tempfile.mkdtemp()
for d in (".git", ".crew/runs/s1", ".crew/runs/old", "src", "tests", "docs", "spec"):
    os.makedirs(os.path.join(root, d), exist_ok=True)
open(os.path.join(root, ".crew", "lock"), "w").write("s1 2026-11-15T00:00:00Z\n")
os.symlink(outside, os.path.join(root, "src", "escape"))

def call(agent, tool, **tool_input):
    payload = {"tool_name": tool, "tool_input": tool_input, "cwd": root}
    p = subprocess.run([sys.executable, HOOK, agent], input=json.dumps(payload), capture_output=True, text=True)
    return p.returncode, p.stderr.strip()

passed = failed = 0
def check(name, agent, tool, want_allow, **ti):
    global passed, failed
    code, err = call(agent, tool, **ti)
    allowed = code == 0
    if allowed == want_allow and (allowed or code == 2):
        passed += 1; print(f"  PASS  {name}")
    else:
        failed += 1; print(f"  FAIL  {name}: exit={code} {err[:120]}")

def P(rel): return os.path.join(root, rel)
RUN = ".crew/runs/s1/"

print("== implementer ==")
check("writes source", "implementer", "Write", True, file_path=P("src/app.py"))
check("edits source", "implementer", "Edit", True, file_path=P("src/app.py"))
check("cannot write tests/ dir", "implementer", "Write", False, file_path=P("tests/test_app.py"))
check("cannot write test_*.py anywhere", "implementer", "Edit", False, file_path=P("src/test_helper.py"))
check("cannot write *.spec.ts", "implementer", "Write", False, file_path=P("src/a.spec.ts"))
check("cannot write docs", "implementer", "Write", False, file_path=P("docs/x.md"))
check("cannot write architecture.md", "implementer", "Edit", False, file_path=P("architecture.md"))
check("cannot write .env", "implementer", "Write", False, file_path=P(".env"))
check("cannot write .github", "implementer", "Write", False, file_path=P(".github/workflows/ci.yml"))
check("cannot write outside the repo", "implementer", "Write", False, file_path="/tmp/evil.py")
check("symlink escape is blocked", "implementer", "Write", False, file_path=P("src/escape/x.py"))
check("writes own handoff", "implementer", "Write", True, file_path=P(RUN + "04-impl.md"))
check("cannot write domain handoff", "implementer", "Write", False, file_path=P(RUN + "01-domain.md"))
check("cannot write state.md", "implementer", "Write", False, file_path=P(RUN + "state.md"))
check("cannot write another run's handoff", "implementer", "Write", False, file_path=P(".crew/runs/old/04-impl.md"))
check("cannot read domain handoff", "implementer", "Read", False, file_path=P(RUN + "01-domain.md"))
check("reads design", "implementer", "Read", True, file_path=P(RUN + "02-design.md"))
check("reads tests handoff", "implementer", "Read", True, file_path=P(RUN + "03-tests.md"))
check("cannot read state.md", "implementer", "Read", False, file_path=P(RUN + "state.md"))
check("cannot read an old run", "implementer", "Read", False, file_path=P(".crew/runs/old/02-design.md"))
check("reads source", "implementer", "Read", True, file_path=P("src/app.py"))
check("reads outside the repo (libraries)", "implementer", "Read", True, file_path="/usr/lib/python3/os.py")
check("cannot read .env", "implementer", "Read", False, file_path=P(".env.local"))
check("cannot grep the .crew folder", "implementer", "Grep", False, pattern="x", path=P(".crew/runs/s1"))
check("greps source", "implementer", "Grep", True, pattern="x", path=P("src"))
check("cannot glob .crew", "implementer", "Glob", False, pattern=".crew/**/*.md")
check("cannot cat domain file via shell", "implementer", "Bash", False, command="cat .crew/runs/s1/01-domain.md")
check("runs tests via shell", "implementer", "Bash", True, command="python3 -m unittest -q 2>&1 | tail -5")

print("== tdd-expert ==")
check("writes tests dir", "tdd-expert", "Write", True, file_path=P("tests/test_new.py"))
check("writes *_test.go", "tdd-expert", "Write", True, file_path=P("pkg/a_test.go"))
check("cannot write source", "tdd-expert", "Write", False, file_path=P("src/app.py"))
check("writes own handoff", "tdd-expert", "Write", True, file_path=P(RUN + "03-tests.md"))
check("reads domain handoff", "tdd-expert", "Read", True, file_path=P(RUN + "01-domain.md"))
check("cannot read review", "tdd-expert", "Read", False, file_path=P(RUN + "06-review.md"))

print("== refactorer ==")
check("edits source", "refactorer", "Edit", True, file_path=P("src/app.py"))
check("cannot edit tests", "refactorer", "Edit", False, file_path=P("tests/test_app.py"))
check("cannot read domain handoff", "refactorer", "Read", False, file_path=P(RUN + "01-domain.md"))

print("== domain-expert and architect ==")
check("domain writes own handoff", "domain-expert", "Write", True, file_path=P(RUN + "01-domain.md"))
check("domain cannot write docs", "domain-expert", "Write", False, file_path=P("docs/x.md"))
check("domain cannot write source", "domain-expert", "Edit", False, file_path=P("src/app.py"))
check("domain reads docs index", "domain-expert", "Read", True, file_path=P("docs/INDEX.md"))
check("domain cannot read impl handoff", "domain-expert", "Read", False, file_path=P(RUN + "04-impl.md"))
check("architect writes design", "architect", "Write", True, file_path=P(RUN + "02-design.md"))
check("architect cannot write source", "architect", "Write", False, file_path=P("src/app.py"))
check("architect reads domain handoff", "architect", "Read", True, file_path=P(RUN + "01-domain.md"))
check("architect cannot read tests handoff", "architect", "Read", False, file_path=P(RUN + "03-tests.md"))

print("== reviewer (read-only) ==")
check("writes review", "reviewer", "Write", True, file_path=P(RUN + "06-review.md"))
check("cannot write source", "reviewer", "Edit", False, file_path=P("src/app.py"))
check("git diff allowed", "reviewer", "Bash", True, command="git diff abc123")
check("git status allowed", "reviewer", "Bash", True, command="git status --porcelain")
check("redirect to file blocked", "reviewer", "Bash", False, command="git diff > out.patch")
check("2>&1 is not a write", "reviewer", "Bash", True, command="git diff 2>&1")
check("sed -i blocked", "reviewer", "Bash", False, command="sed -i s/a/b/ src/app.py")
check("git commit blocked", "reviewer", "Bash", False, command="git commit -am x")
check("rm blocked", "reviewer", "Bash", False, command="rm src/app.py")
check("cannot read impl handoff", "reviewer", "Read", False, file_path=P(RUN + "04-impl.md"))
check("reads tests handoff (for the exemption check)", "reviewer", "Read", True, file_path=P(RUN + "03-tests.md"))

print("== tester (independent, read-only) ==")
check("writes results", "tester", "Write", True, file_path=P(RUN + "07-test-results.md"))
check("cannot read requirements", "tester", "Read", False, file_path=P(RUN + "01-domain.md"))
check("cannot read design", "tester", "Read", False, file_path=P(RUN + "02-design.md"))
check("cannot read task", "tester", "Read", False, file_path=P(RUN + "00-task.md"))
check("reads tests handoff", "tester", "Read", True, file_path=P(RUN + "03-tests.md"))
check("runs test suite", "tester", "Bash", True, command="python3 -m unittest 2>&1 | tail -20")
check("test output redirect blocked", "tester", "Bash", False, command="pytest -q > results.txt")

print("== verifier ==")
check("writes feature doc", "verifier", "Write", True, file_path=P("docs/feature-x.md"))
check("writes docs index", "verifier", "Edit", True, file_path=P("docs/INDEX.md"))
check("edits architecture.md", "verifier", "Edit", True, file_path=P("architecture.md"))
check("cannot edit source", "verifier", "Edit", False, file_path=P("src/app.py"))
check("cannot edit tests", "verifier", "Write", False, file_path=P("tests/test_app.py"))
check("cannot edit coding-style.md", "verifier", "Edit", False, file_path=P("coding-style.md"))
check("reads every handoff", "verifier", "Read", True, file_path=P(RUN + "01-domain.md"))
check("cannot read state.md", "verifier", "Read", False, file_path=P(RUN + "state.md"))

print("== config and failure modes ==")
check("unknown agent is blocked", "nobody", "Write", False, file_path=P("src/app.py"))
open(os.path.join(root, ".crew-test-paths"), "w").write("# custom\n^spec/\n")
check("custom test paths: spec/ is a test dir", "tdd-expert", "Write", True, file_path=P("spec/a_spec.rb"))
check("custom test paths: tests/ no longer matches", "tdd-expert", "Write", False, file_path=P("tests/test_x.py"))
check("custom test paths: implementer may now edit tests/", "implementer", "Write", True, file_path=P("tests/helper.py"))
check("custom test paths file is protected", "tdd-expert", "Write", False, file_path=P(".crew-test-paths"))
p = subprocess.run([sys.executable, HOOK, "implementer"], input="not json", capture_output=True, text=True)
if p.returncode == 2: passed += 1; print("  PASS  invalid input fails closed")
else: failed += 1; print(f"  FAIL  invalid input fails closed: exit={p.returncode}")

print(f"\npassed={passed} failed={failed}")
sys.exit(1 if failed else 0)
