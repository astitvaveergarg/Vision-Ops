"""
YOLO detection service for VisionOps

Handles:
- Model loading
- Object detection
- Result formatting
"""
import logging
from typing import List, Dict, Any, Optional
from pathlib import Path

import cv2
import numpy as np

from api.config import settings
from api.services.model_manager import ModelManager

logger = logging.getLogger(__name__)


class DetectorService:
    """YOLO object detection service with multi-model support"""
    
    def __init__(self, models_dir: str = "models"):
        """Initialize model manager"""
        try:
            logger.info("Initializing ModelManager...")
            self.model_manager = ModelManager(models_dir=models_dir, max_cached=2)
            
            # Pre-load default model
            default_model = settings.DEFAULT_MODEL_ID
            logger.info(f"Pre-loading default model: {default_model}")
            self.model_manager.get_model(default_model)
            
            logger.info(f"DetectorService initialized with {len(self.model_manager.list_models())} models")
            
        except Exception as e:
            logger.error(f"Failed to initialize DetectorService: {e}")
            raise
    
    def detect(
        self,
        image_bytes: bytes,
        model_id: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """
        Detect objects in image
        
        Args:
            image_bytes: Image data as bytes
            model_id: Model ID to use (default: from settings)
            
        Returns:
            List of detections with class, confidence, bbox
        """
        try:
            # Get model
            model_id = model_id or settings.DEFAULT_MODEL_ID
            model = self.model_manager.get_model(model_id)
            
            # Decode image
            nparr = np.frombuffer(image_bytes, np.uint8)
            image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            
            if image is None:
                raise ValueError("Failed to decode image")
            
            # Run inference
            results = model(
                image,
                conf=settings.CONF_THRESHOLD,
                iou=settings.IOU_THRESHOLD
            )
            
            # Extract detections
            detections = []
            
            for result in results:
                boxes = result.boxes
                
                for box in boxes:
                    detection = {
                        "class": result.names[int(box.cls)],
                        "confidence": float(box.conf),
                        "bbox": [float(x) for x in box.xyxy[0].tolist()]
                    }
                    detections.append(detection)
            
            logger.info(f"Detected {len(detections)} objects")
            return detections
            
        except Exception as e:
            logger.error(f"Detection failed: {e}")
            raise
    
    def list_models(self) -> List[Dict[str, Any]]:
        """
        Get list of available models
        
        Returns:
            List of model info dicts
        """
        return self.model_manager.list_models()
    
    def health_check(self) -> bool:
        """
        Check if model manager is initialized
        
        Returns:
            True if initialized, False otherwise
        """
        try:
            return self.model_manager is not None
        except Exception:
            return False
    
    def get_model_info(self) -> Dict[str, Any]:
        """
        Get model information
        
        Returns:
            Dict with model metadata
        """
        try:
            # Get default model for class names
            model = self.model_manager.get_model(settings.DEFAULT_MODEL_ID)
            
            return {
                "default_model": settings.DEFAULT_MODEL_ID,
                "conf_threshold": settings.CONF_THRESHOLD,
                "iou_threshold": settings.IOU_THRESHOLD,
                "available_models": len(self.model_manager.list_models()),
                "cache_stats": self.model_manager.get_cache_stats(),
                "classes": list(model.names.values()) if hasattr(model, 'names') else []
            }
        except Exception as e:
            logger.error(f"Failed to get model info: {e}")
            return {}
    
    def preload_models(self, model_ids: List[str]):
        """
        Pre-load specific models into cache
        
        Args:
            model_ids: List of model IDs to preload
        """
        self.model_manager.preload_models(model_ids)
