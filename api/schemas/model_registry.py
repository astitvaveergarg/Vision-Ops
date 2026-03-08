"""Schemas for model registry endpoints."""
from pydantic import BaseModel
from typing import Optional


class ModelInfo(BaseModel):
    id: int
    name: str
    framework: Optional[str]
    storage_path: str
    owner_id: int
    created_at: str

    class Config:
        orm_mode = True
