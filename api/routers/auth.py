"""Authentication endpoints (registration/login) - stubs for Phase 1."""
from fastapi import APIRouter, HTTPException, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select

from ..schemas.auth import UserCreate, UserLogin, Token
from ..models.user import User
from ..services import auth as auth_service
from ..dependencies import get_db_dependency

router = APIRouter(prefix="/auth")


@router.post("/register", response_model=Token)
async def register(
    user: UserCreate,
    db: AsyncSession = Depends(get_db_dependency)
):
    """Create a new user and return access token."""
    # check existing
    result = await db.execute(select(User).filter(User.username == user.username))
    existing = result.scalars().first()
    if existing:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Username already taken")

    hashed_password = auth_service.get_password_hash(user.password)
    db_user = User(username=user.username, email=user.email, hashed_password=hashed_password)
    db.add(db_user)
    await db.commit()
    await db.refresh(db_user)

    access_token = auth_service.create_access_token(data={"sub": db_user.username})
    return {"access_token": access_token, "token_type": "bearer"}


@router.post("/login", response_model=Token)
async def login(
    credentials: UserLogin,
    db: AsyncSession = Depends(get_db_dependency)
):
    """Verify credentials and return access token."""
    result = await db.execute(select(User).filter(User.username == credentials.username))
    user_obj = result.scalars().first()
    if not user_obj or not auth_service.verify_password(credentials.password, user_obj.hashed_password):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Incorrect username or password")

    access_token = auth_service.create_access_token(data={"sub": user_obj.username})
    return {"access_token": access_token, "token_type": "bearer"}
