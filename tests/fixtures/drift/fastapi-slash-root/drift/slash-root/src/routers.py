from fastapi import APIRouter

router = APIRouter(prefix="/reports", tags=["reports"])


@router.get("/")
def list_reports():
    return []


@router.post("/")
def create_report():
    return {}


@router.get("/{report_id}")
def get_report(report_id: str):
    return {}
