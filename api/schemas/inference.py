"""Schemas for inference endpoints"""
from pydantic import BaseModel
from typing import Any, List, Optional


class Detection(BaseModel):
    label: str
    confidence: float
    bbox: List[float]


class DetectionResponse(BaseModel):
    filename: str
    detections: List[Detection]
    detection_count: int
    storage_url: str
    model_id: str
    model_info: dict
    cached: bool
    image_hash: str
