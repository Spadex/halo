"""Model set member routes.

The router prefix is declared across several lines here, which is the other half of the
same problem: a prefix that is not read leaves every route in this file unresolvable.
"""

from fastapi import APIRouter

router = APIRouter(
    prefix="/api/model-set-members",
    tags=["model-set-members"],
)


# Slash form of the collection root — the same URL as `@router.get("")` after
# normalisation, and the form projects reach for when they want the trailing slash.
@router.get("/")
def list_members():
    return []
