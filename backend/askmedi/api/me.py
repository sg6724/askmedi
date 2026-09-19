from fastapi import APIRouter

from askmedi.api.deps import CurrentUser

router = APIRouter()


@router.get("/me")
def me(user: CurrentUser) -> dict[str, str | None]:
    return {"user_id": user.user_id, "email": user.email}
