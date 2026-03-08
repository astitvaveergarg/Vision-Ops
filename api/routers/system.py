"""System-level endpoints: health, metrics, root, stats."""
from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse, Response
from prometheus_client import generate_latest

router = APIRouter()


@router.get("/")
async def root(request: Request):
    """Basic health/probe endpoint"""
    request.app.state.REQUEST_COUNT.labels(method='GET', endpoint='/', status='200').inc()
    return {
        "service": "VisionOps API",
        "status": "healthy",
        "version": "1.0.0"
    }


@router.get("/health")
async def health(request: Request):
    """Detailed component health checks"""
    cache = request.app.state.cache
    storage = request.app.state.storage
    detector = request.app.state.detector
    health_status = {
        "status": "healthy",
        "redis": cache.health_check() if cache else False,
        "minio": storage.health_check() if storage else False,
        "model": detector.health_check() if detector else False
    }
    request.app.state.REQUEST_COUNT.labels(method='GET', endpoint='/health', status='200').inc()
    return health_status


@router.get("/metrics")
async def metrics(request: Request):
    """Prometheus scrape endpoint"""
    return Response(content=generate_latest(request.app.state.prom_registry), media_type="text/plain")


@router.get("/stats")
async def stats(request: Request):
    """Service statistics (cache, storage, model)"""
    cache = request.app.state.cache
    storage = request.app.state.storage
    detector = request.app.state.detector
    stats_data = {
        "cache": cache.get_stats() if cache else {},
        "storage": storage.get_stats() if storage else {},
        "model": detector.get_model_info() if detector else {}
    }
    request.app.state.REQUEST_COUNT.labels(method='GET', endpoint='/stats', status='200').inc()
    return stats_data
