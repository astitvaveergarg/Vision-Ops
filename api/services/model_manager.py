"""
Model Manager for VisionOps

Handles:
- Multiple YOLO model versions
- Smart caching (keep 2 models in memory)
- Lazy loading
- Model metadata
"""
import logging
from typing import Dict, List, Optional
from pathlib import Path
from threading import Lock
import time

from ultralytics import YOLO

logger = logging.getLogger(__name__)


class ModelInfo:
    """Model metadata"""
    def __init__(
        self,
        name: str,
        filename: str,
        size_mb: float,
        speed_rating: int,  # 1-5, 5 is fastest
        map_score: float,  # mAP50-95
        description: str
    ):
        self.name = name
        self.filename = filename
        self.size_mb = size_mb
        self.speed_rating = speed_rating
        self.map_score = map_score
        self.description = description
        self.loaded = False
        self.load_count = 0
        self.last_used = 0


# Model registry
AVAILABLE_MODELS = {
    "yolov8n": ModelInfo(
        name="YOLOv8 Nano",
        filename="yolov8n.pt",
        size_mb=6.2,
        speed_rating=5,
        map_score=37.3,
        description="Ultra-fast, edge devices, real-time"
    ),
    "yolov8s": ModelInfo(
        name="YOLOv8 Small",
        filename="yolov8s.pt",
        size_mb=22.0,
        speed_rating=4,
        map_score=44.9,
        description="Balanced speed and accuracy"
    ),
    "yolov8m": ModelInfo(
        name="YOLOv8 Medium",
        filename="yolov8m.pt",
        size_mb=52.0,
        speed_rating=3,
        map_score=50.2,
        description="Good accuracy, moderate speed"
    ),
    "yolov8l": ModelInfo(
        name="YOLOv8 Large",
        filename="yolov8l.pt",
        size_mb=88.0,
        speed_rating=2,
        map_score=52.9,
        description="High accuracy, slower inference"
    ),
    "yolov8x": ModelInfo(
        name="YOLOv8 XLarge",
        filename="yolov8x.pt",
        size_mb=130.0,
        speed_rating=1,
        map_score=53.9,
        description="Best accuracy, slowest inference"
    )
}


class ModelManager:
    """
    Manages multiple YOLO models with smart caching
    
    Features:
    - Lazy loading (download/load on first use)
    - Keep 2 most-used models in memory
    - Thread-safe model switching
    - Automatic memory management
    """
    
    def __init__(self, models_dir: str = "models", max_cached: int = 2):
        """
        Initialize model manager
        
        Args:
            models_dir: Directory to store model files
            max_cached: Maximum models to keep in memory
        """
        self.models_dir = Path(models_dir)
        self.models_dir.mkdir(parents=True, exist_ok=True)
        
        self.max_cached = max_cached
        self._loaded_models: Dict[str, YOLO] = {}
        self._lock = Lock()
        
        logger.info(f"Initialized ModelManager with {len(AVAILABLE_MODELS)} models")
    
    def list_models(self) -> List[Dict]:
        """
        Get list of available models with metadata
        
        Returns:
            List of model info dicts
        """
        models = []
        for model_id, info in AVAILABLE_MODELS.items():
            model_path = self.models_dir / info.filename
            models.append({
                "id": model_id,
                "name": info.name,
                "filename": info.filename,
                "size_mb": info.size_mb,
                "speed_rating": info.speed_rating,
                "map_score": info.map_score,
                "description": info.description,
                "downloaded": model_path.exists(),
                "loaded": model_id in self._loaded_models,
                "load_count": info.load_count,
                "last_used": info.last_used
            })
        return models
    
    def get_model(self, model_id: str = "yolov8n") -> YOLO:
        """
        Get model by ID, loading if necessary
        
        Args:
            model_id: Model identifier (e.g., "yolov8n")
            
        Returns:
            Loaded YOLO model
            
        Raises:
            ValueError: If model ID is invalid
        """
        if model_id not in AVAILABLE_MODELS:
            raise ValueError(
                f"Invalid model ID: {model_id}. "
                f"Available: {list(AVAILABLE_MODELS.keys())}"
            )
        
        with self._lock:
            # If already loaded, return it
            if model_id in self._loaded_models:
                logger.debug(f"Using cached model: {model_id}")
                self._update_usage(model_id)
                return self._loaded_models[model_id]
            
            # Load the model
            model = self._load_model(model_id)
            
            # Add to cache
            self._loaded_models[model_id] = model
            self._update_usage(model_id)
            
            # Enforce cache limit
            self._enforce_cache_limit()
            
            return model
    
    def _load_model(self, model_id: str) -> YOLO:
        """
        Load model from disk or download
        
        Args:
            model_id: Model identifier
            
        Returns:
            Loaded YOLO model
        """
        info = AVAILABLE_MODELS[model_id]
        model_path = self.models_dir / info.filename
        
        logger.info(f"Loading model: {info.name} ({info.size_mb}MB)")
        start_time = time.time()
        
        # YOLO will auto-download if not exists
        model = YOLO(str(model_path))
        
        load_time = time.time() - start_time
        logger.info(f"Model {model_id} loaded in {load_time:.2f}s")
        
        return model
    
    def _update_usage(self, model_id: str):
        """Update model usage statistics"""
        info = AVAILABLE_MODELS[model_id]
        info.load_count += 1
        info.last_used = time.time()
        info.loaded = True
    
    def _enforce_cache_limit(self):
        """
        Remove least-recently-used models if cache is full
        """
        if len(self._loaded_models) <= self.max_cached:
            return
        
        # Sort by last used time
        models_by_usage = sorted(
            AVAILABLE_MODELS.items(),
            key=lambda x: x[1].last_used
        )
        
        # Unload oldest models
        to_remove = len(self._loaded_models) - self.max_cached
        
        for model_id, info in models_by_usage:
            if model_id in self._loaded_models and to_remove > 0:
                logger.info(f"Unloading model from cache: {model_id}")
                del self._loaded_models[model_id]
                info.loaded = False
                to_remove -= 1
    
    def preload_models(self, model_ids: List[str]):
        """
        Pre-load specific models into cache
        
        Args:
            model_ids: List of model IDs to preload
        """
        logger.info(f"Pre-loading models: {model_ids}")
        for model_id in model_ids:
            try:
                self.get_model(model_id)
            except Exception as e:
                logger.error(f"Failed to preload {model_id}: {e}")
    
    def get_cache_stats(self) -> Dict:
        """
        Get cache statistics
        
        Returns:
            Dict with cache stats
        """
        return {
            "max_cached": self.max_cached,
            "currently_loaded": len(self._loaded_models),
            "loaded_models": list(self._loaded_models.keys()),
            "total_available": len(AVAILABLE_MODELS)
        }
    
    def clear_cache(self):
        """Unload all models from memory"""
        with self._lock:
            logger.info("Clearing model cache")
            self._loaded_models.clear()
            for info in AVAILABLE_MODELS.values():
                info.loaded = False
