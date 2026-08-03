"""Model set routes.

The registration styles here are deliberate. drift-check reads route declarations out of
source text, so this file carries the shapes real FastAPI projects use: an empty decorator
path for the collection root, a path parameter, and decorators spread over several lines.
"""

from fastapi import APIRouter

from app.errors import MODEL_SET_NAME_CONFLICT, MODEL_SET_NOT_FOUND

router = APIRouter(prefix="/api/model-sets", tags=["model-sets"])


# Collection root. FastAPI registers it as an empty decorator path so the URL has no
# trailing slash; the prefix carries the whole route.
@router.get("")
def list_model_sets():
    return []


@router.post("")
def create_model_set(name: str):
    if name == "duplicate":
        return {"code": MODEL_SET_NAME_CONFLICT}
    return {"id": "ms-1", "name": name}


@router.get("/{set_id}")
def get_model_set(set_id: str):
    if set_id == "missing":
        return {"code": MODEL_SET_NOT_FOUND}
    return {"id": set_id}


# Multi-line decorator: ordinary once a route declares a response model or status code.
@router.put(
    "/{set_id}",
    summary="Rename a model set",
)
def update_model_set(set_id: str, name: str):
    return {"id": set_id, "name": name}


@router.delete(
    "/{set_id}",
    status_code=204,
)
def delete_model_set(set_id: str):
    return None
