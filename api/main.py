"""
VisionOps API - YOLO Object Detection Service
"""
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from prometheus_client import Counter, Histogram, CollectorRegistry
from fastapi.responses import Response
import uvicorn

from api.config import settings
from api.services.cache import CacheService
from api.services.storage import StorageService
from api.services.detector import DetectorService

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Create custom registry to avoid conflicts with reload
prom_registry = CollectorRegistry(auto_describe=True)

# Prometheus metrics (use custom registry)
REQUEST_COUNT = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'], registry=prom_registry)
INFERENCE_DURATION = Histogram('inference_duration_seconds', 'YOLO inference duration', registry=prom_registry)
CACHE_HITS = Counter('cache_hits_total', 'Cache hits', registry=prom_registry)
CACHE_MISSES = Counter('cache_misses_total', 'Cache misses', registry=prom_registry)

# services will be stored on app.state during startup


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize and cleanup services. Store them on ``app.state`` so routers can access them."""
    # Startup
    logger.info("🚀 Starting VisionOps API...")
    
    try:
        logger.info("Initializing Redis cache...")
        app.state.cache = CacheService()
        
        logger.info("Initializing MinIO storage...")
        app.state.storage = StorageService()
        
        logger.info("Loading YOLO model...")
        app.state.detector = DetectorService()
        
        # expose metrics/registry on state as well
        app.state.prom_registry = prom_registry
        app.state.REQUEST_COUNT = REQUEST_COUNT
        app.state.INFERENCE_DURATION = INFERENCE_DURATION
        app.state.CACHE_HITS = CACHE_HITS
        app.state.CACHE_MISSES = CACHE_MISSES

        logger.info("✅ All services initialized successfully!")
        
    except Exception as e:
        logger.error(f"❌ Failed to initialize services: {e}")
        raise
    
    yield
    
    # Shutdown
    logger.info("👋 Shutting down VisionOps API...")


app = FastAPI(
    title="VisionOps API",
    description="Real-time object detection using YOLO",
    version="1.0.0",
    lifespan=lifespan,
    root_path=settings.ROOT_PATH
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# routers are registered at the bottom; individual endpoints live in router modules


# health endpoint moved to routers/system.py


# metrics endpoint moved to routers/system.py


# list_models moved to routers/models.py


# stats endpoint moved to routers/system.py


# detect_objects endpoint migrated to routers/inference.py


# router registration and application setup

# include routers
from api.routers import system as system_router
from api.routers import models as models_router
from api.routers import inference as inference_router
from api.routers import auth as auth_router

app.include_router(system_router.router)
app.include_router(models_router.router, prefix="/models", tags=["models"])
app.include_router(inference_router.router, tags=["inference"])
app.include_router(auth_router.router, tags=["auth"])

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host=settings.API_HOST,
        port=settings.API_PORT,
        reload=True
    )
