"""Object detection / inference endpoints."""
import hashlib
import logging
from fastapi import APIRouter, UploadFile, File, HTTPException, Request
from fastapi.responses import JSONResponse

from ..config import settings

router = APIRouter()
logger = logging.getLogger(__name__)


@router.post("/detect")
async def detect_objects(
    request: Request,
    file: UploadFile = File(...),
    model: str = None
):
    """Detection endpoint, replicate previous logic but use app.state."""
    try:
        request.app.state.REQUEST_COUNT.labels(method='POST', endpoint='/detect', status='200').inc()

        model_id = model or settings.DEFAULT_MODEL_ID
        image_bytes = await file.read()
        image_hash = hashlib.sha256(image_bytes).hexdigest()
        cache_key = f"{image_hash}:{model_id}"
        logger.info(f"Processing image: {file.filename} with {model_id} (hash: {image_hash[:8]}...)")

        cache_service = request.app.state.cache
        storage_service = request.app.state.storage
        detector_service = request.app.state.detector

        cached_result = cache_service.get_cached_result(cache_key)
        if cached_result:
            request.app.state.CACHE_HITS.inc()
            logger.info("✅ Returning cached result")
            return JSONResponse(content={
                **cached_result,
                "cached": True,
                "image_hash": image_hash,
                "model_id": model_id
            })

        request.app.state.CACHE_MISSES.inc()
        logger.info(f"⚠️  Cache miss - running detection with {model_id}")

        with request.app.state.INFERENCE_DURATION.time():
            detections = detector_service.detect(image_bytes, model_id=model_id)

        storage_url = storage_service.upload_image(
            filename=file.filename,
            data=image_bytes,
            content_type=file.content_type
        )

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
        request.app.state.REQUEST_COUNT.labels(method='POST', endpoint='/detect', status='400').inc()
        raise HTTPException(status_code=400, detail=f"Invalid image: {str(e)}")
    except Exception as e:
        logger.error(f"Detection failed: {e}")
        request.app.state.REQUEST_COUNT.labels(method='POST', endpoint='/detect', status='500').inc()
        raise HTTPException(status_code=500, detail=f"Detection failed: {str(e)}")
