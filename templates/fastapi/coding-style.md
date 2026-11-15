# Coding style

- Python 3 as set in `pyproject.toml`. Type hints on every public function.
- Pydantic models for request and response bodies. Keep them separate from domain entities.
- Small functions, one responsibility each. No printing: use the `logging` module.
- Raise domain errors in the domain and application layers. Map them to HTTP status codes in the API layer only.
- Tests use pytest, one behavior per test, named `test_<behavior>`. Unit tests use no network and no real database.
- Tests live under `tests/`. Source lives under `app/`.

## Commands
test: pytest -q
lint: ruff check .
typecheck: mypy .

<!-- EDIT: delete the lint and typecheck lines unless ruff and mypy are installed in this project.
The crew runs exactly the commands listed here, and a missing tool counts as a failure. -->
