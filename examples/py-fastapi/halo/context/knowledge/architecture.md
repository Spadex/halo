# Architecture

## Modules

| Module | Responsibility | Notes |
|--------|----------------|-------|
| `app/routers` | FastAPI route registration | One `APIRouter` per resource, prefix on the router |
| `app/errors.py` | Business error code constants | Read by the error code drift check |
| `tests` | AC-traced tests | Test names map to spec ACs |
