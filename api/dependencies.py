"""
Common FastAPI dependencies used across routers.
"""
from typing import AsyncGenerator

from fastapi import Depends

from .database import get_db
from sqlalchemy.ext.asyncio import AsyncSession


def get_db_dependency() -> AsyncGenerator[AsyncSession, None]:
    """Dependency wrapper around :pyfunc:`get_db` to allow typing imports.

    The router code should import this function and use it with ``Depends``.
    ``get_db`` itself is defined in :mod:`database` and yields sessions.
    """
    yield from get_db()
