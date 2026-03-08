"""Authentication endpoints (registration/login) - stubs for Phase 1."""
from fastapi import APIRouter, HTTPException

from ..schemas.auth import UserCreate, UserLogin, Token

router = APIRouter(prefix="/auth")


@router.post("/register", response_model=Token)
async def register(user: UserCreate):
    """Register endpoint (not implemented during Phase 1)."""
    # placeholder / future implementation
    raise HTTPException(status_code=501, detail="Registration not implemented yet")


@router.post("/login", response_model=Token)
async def login(credentials: UserLogin):
    """Login endpoint (not implemented during Phase 1)."""
    raise HTTPException(status_code=501, detail="Login not implemented yet")
