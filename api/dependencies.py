"""
Common FastAPI dependencies used across routers.
"""
from typing import AsyncGenerator, Optional

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer

from .database import get_db
from sqlalchemy.ext.asyncio import AsyncSession
from .auth import decode_access_token
from .models.user import User


oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


def get_db_dependency() -> AsyncGenerator[AsyncSession, None]:
    """Dependency wrapper around :pyfunc:`get_db` to allow typing imports.

    The router code should import this function and use it with ``Depends``.
    ``get_db`` itself is defined in :mod:`database` and yields sessions.
    """
    yield from get_db()


async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db_dependency)
) -> User:
    """Returns the currently authenticated user, or raises 401."""
    payload = decode_access_token(token)
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
    username: Optional[str] = payload.get("sub")
    if username is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
    result = await db.execute(
        "SELECT * FROM users WHERE username = :username",
        {"username": username},
    )
    user_obj = result.scalars().first()
    if not user_obj:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user_obj
