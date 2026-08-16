from fastapi import APIRouter

router = APIRouter(prefix="/model-sets", tags=["model-sets"])


@router.get("")
def list_model_sets():
    return []


@router.post("")
def create_model_set():
    return {}


@router.get("/{set_id}")
def get_model_set(set_id: str):
    return {}
