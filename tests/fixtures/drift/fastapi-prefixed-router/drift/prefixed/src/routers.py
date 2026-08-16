from fastapi import APIRouter

router = APIRouter(prefix="/api", tags=["model-sets"])


@router.get("/model-sets")
def list_model_sets():
    return []


@router.post("/model-sets")
def create_model_set():
    return {}
