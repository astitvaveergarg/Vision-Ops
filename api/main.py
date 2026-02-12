"""
VisionOps API - YOLO Object Detection Service
"""
import hashlib
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from prometheus_client import Counter, Histogram, generate_latest, CollectorRegistry, REGISTRY
from fastapi.responses import Response
import uvicorn

from config import settings
from services.cache import CacheService
from services.storage import StorageService
from services.detector import DetectorService

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

# Initialize services
cache_service = None
storage_service = None
detector_service = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize and cleanup services"""
    global cache_service, storage_service, detector_service
    
    # Startup
    logger.info("🚀 Starting VisionOps API...")
    
    try:
        logger.info("Initializing Redis cache...")
        cache_service = CacheService()
        
        logger.info("Initializing MinIO storage...")
        storage_service = StorageService()
        
        logger.info("Loading YOLO model...")
        detector_service = DetectorService()
        
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
    lifespan=lifespan
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
async def root():
    """Health check endpoint"""
    REQUEST_COUNT.labels(method='GET', endpoint='/', status='200').inc()
    return {
        "service": "VisionOps API",
        "status": "healthy",
        "version": "1.0.0"
    }


@app.get("/health")
async def health():
    """Detailed health check"""
    health_status = {
        "status": "healthy",
        "redis": cache_service.health_check() if cache_service else False,
        "minio": storage_service.health_check() if storage_service else False,
        "model": detector_service.health_check() if detector_service else False
    }
    
    REQUEST_COUNT.labels(method='GET', endpoint='/health', status='200').inc()
    return health_status


@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    return Response(content=generate_latest(prom_registry), media_type="text/plain")


@app.get("/models")
async def list_models():
    """Get list of available models"""
    models = detector_service.list_models() if detector_service else []
    REQUEST_COUNT.labels(method='GET', endpoint='/models', status='200').inc()
    return {"models": models}


@app.get("/stats")
async def get_stats():
    """Get service statistics"""
    stats = {
        "cache": cache_service.get_stats() if cache_service else {},
        "storage": storage_service.get_stats() if storage_service else {},
        "model": detector_service.get_model_info() if detector_service else {}
    }
    REQUEST_COUNT.labels(method='GET', endpoint='/stats', status='200').inc()
    return stats


@app.post("/detect")
async def detect_objects(
    file: UploadFile = File(...),
    model: str = None
):
    """
    Detect objects in uploaded image
    
    Query Parameters:
        model: Model ID to use (yolov8n, yolov8s, yolov8m, yolov8l, yolov8x)
    
    Returns:
        - detected objects
        - bounding boxes
        - confidence scores
        - storage URL
        - cache status
        - model used
    """
    try:
        REQUEST_COUNT.labels(method='POST', endpoint='/detect', status='200').inc()
        
        # Use default model if not specified
        model_id = model or settings.DEFAULT_MODEL_ID
        
        # Read image bytes
        image_bytes = await file.read()
        
        # Calculate image hash for caching
        image_hash = hashlib.sha256(image_bytes).hexdigest()
        
        # Create cache key with model ID
        cache_key = f"{image_hash}:{model_id}"
        logger.info(f"Processing image: {file.filename} with {model_id} (hash: {image_hash[:8]}...)")
        
        # Check cache first
        cached_result = cache_service.get_cached_result(cache_key)
        
        if cached_result:
            CACHE_HITS.inc()
            logger.info("✅ Returning cached result")
            return JSONResponse(content={
                **cached_result,
                "cached": True,
                "image_hash": image_hash,
                "model_id": model_id
            })
        
        # Cache miss - perform detection
        CACHE_MISSES.inc()
        logger.info(f"⚠️  Cache miss - running detection with {model_id}")
        
        # Run inference with specified model
        with INFERENCE_DURATION.time():
            detections = detector_service.detect(image_bytes, model_id=model_id)
        
        # Upload to storage
        storage_url = storage_service.upload_image(
            filename=file.filename,
            data=image_bytes,
            content_type=file.content_type
        )
        
        # Prepare result
        result = {
            "filename": file.filename,
            "detections": detections,
            "detection_count": len(detections),
            "storage_url": storage_url,
            "model_id": model_id,
            "model_info": {
                "conf_threshold": settings.CONF_THRESHOLD,
                "iou_threshold": settings.IOU_THRESHOLD
            }
        }
        
        # Cache the result with model-specific key
        cache_service.cache_result(cache_key, result)
        
        logger.info(f"✅ Detection complete: {len(detections)} objects found")
        
        return JSONResponse(content={
            **result,
            "cached": False,
            "image_hash": image_hash,
            "model_id": model_id
        })
        
    except ValueError as e:
        logger.error(f"Invalid image: {e}")
        REQUEST_COUNT.labels(method='POST', endpoint='/detect', status='400').inc()
        raise HTTPException(status_code=400, detail=f"Invalid image: {str(e)}")
        
    except Exception as e:
        logger.error(f"Detection failed: {e}")
        REQUEST_COUNT.labels(method='POST', endpoint='/detect', status='500').inc()
        raise HTTPException(status_code=500, detail=f"Detection failed: {str(e)}")


if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host=settings.API_HOST,
        port=settings.API_PORT,
        reload=True
    )
