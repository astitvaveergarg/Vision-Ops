"""Endpoints related to available models."""
from fastapi import APIRouter, Request

router = APIRouter()


@router.get("")
async def list_models(request: Request):
    """List system-provided YOLO models"""
    detector = request.app.state.detector
    models = detector.list_models() if detector else []
    request.app.state.REQUEST_COUNT.labels(method='GET', endpoint='/models', status='200').inc()
    return {"models": models}
