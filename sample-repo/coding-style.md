# Coding style

- Python 3, type hints on public functions, one short docstring each.
- Pure functions where possible. No printing from library code.
- Tests use `unittest`, one behavior per test method, named `test_<behavior>`.
- Tests live under `tests/`. Source lives under `src/`.

## Commands
test: python3 -m unittest discover -q
