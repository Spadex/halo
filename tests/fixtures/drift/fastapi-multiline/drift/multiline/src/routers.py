from fastapi import APIRouter

router = APIRouter(
    prefix="/api",
    tags=["reports"],
)


@router.get("/reports")
def list_reports():
    return []


@router.get("")
def reports_service_root():
    return {"service": "reports"}


@router.post(
    "/reports",
    status_code=201,
)
def create_report():
    return {}


@router.delete(
    "/reports/{report_id}",
)
def delete_report(report_id: str):
    return {}
