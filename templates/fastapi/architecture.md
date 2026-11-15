# Architecture

<!-- EDIT: two or three sentences on what this service does and who uses it. -->

## Style

Hexagonal architecture (ports and adapters). REST over HTTP with JSON.

## Layout

```
app/
  domain/          entities and business rules. No framework imports.
  application/     use cases and the port interfaces they depend on.
  adapters/
    api/           FastAPI routers and request/response schemas.
    persistence/   repository implementations behind the ports.
  main.py          app factory and wiring.
tests/
  unit/            domain and application tests.
  api/             endpoint tests with FastAPI's TestClient.
```

## Rules

- Dependencies point inward: adapters depend on application, application depends on domain.
- Routers only translate HTTP to use-case calls and back. No business logic in routers.
- Persistence sits behind repository interfaces. Wiring happens in `main.py`.
- Configuration comes from environment variables, never hard-coded.

## Endpoints

None yet. The verifier adds new endpoints here.

## Data

None yet. The verifier adds new tables and models here.
