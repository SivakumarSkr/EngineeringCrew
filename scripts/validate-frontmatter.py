#!/usr/bin/env python3
"""Strictly parse the YAML frontmatter of every crew file. Claude Code silently skips an
agent whose frontmatter does not parse, so run this after any edit.
Usage: python3 validate-frontmatter.py [crew-root]   (needs PyYAML: pip install pyyaml)"""
import pathlib, re, sys
try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required: pip install pyyaml")

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parent.parent)
bad = 0
def fail(path, msg):
    global bad; bad += 1; print(f"  FAIL  {path.relative_to(root)}: {msg}")

def frontmatter(path):
    m = re.match(r"^---\n(.*?)\n---\n", path.read_text(), re.S)
    if not m: fail(path, "no frontmatter block"); return None
    try: return yaml.safe_load(m.group(1))
    except yaml.YAMLError as e: fail(path, f"YAML does not parse ({str(e).splitlines()[0]} ... {str(e).splitlines()[-3:][0].strip()[:70]})"); return None

n = 0
for f in sorted((root / "agents").glob("*.md")):
    d = frontmatter(f); n += 1
    if d is None: continue
    if d.get("name") != f.stem: fail(f, f"name {d.get('name')!r} differs from filename")
    if not d.get("description"): fail(f, "missing description")
    if "boundary.py" not in str(d.get("hooks", "")): fail(f, "boundary hook missing")
    if d.get("omitClaudeMd") is not True: fail(f, "omitClaudeMd should be true")
    if not isinstance(d.get("maxTurns"), int): fail(f, "maxTurns missing")
for f in sorted((root / "skills").glob("*/SKILL.md")):
    d = frontmatter(f); n += 1
    if d is None: continue
    if d.get("name") != f.parent.name: fail(f, "skill name differs from folder")
    if not d.get("description"): fail(f, "missing description")
for f in sorted((root / "commands").glob("*.md")):
    d = frontmatter(f); n += 1
    if d is not None and not d.get("description"): fail(f, "missing description")
print(f"checked {n} files, {bad} problem(s)")
sys.exit(1 if bad else 0)
