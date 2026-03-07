"""
Configuration for VisionOps API
Supports local development (Minikube services) and K8s deployment
"""
from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    """Application settings"""
    
    # API Configuration
    API_HOST: str = "0.0.0.0"
    API_PORT: int = 8000
    
    # Redis Configuration (Minikube NodePort)
    REDIS_HOST: str = "localhost"
    REDIS_PORT: int = 30379  # NodePort
    REDIS_DB: int = 0
    REDIS_PASSWORD: Optional[str] = None
    
    # MinIO Configuration (Minikube NodePort)
    MINIO_ENDPOINT: str = "localhost:30900"
    MINIO_ACCESS_KEY: str = "minioadmin"
    MINIO_SECRET_KEY: str = "minioadmin"
    MINIO_BUCKET: str = "vision-images"
    MINIO_SECURE: bool = False
    
    # PostgreSQL (optional)
    POSTGRES_HOST: str = "localhost"
    POSTGRES_PORT: int = 30432
    POSTGRES_DB: str = "visiondb"
    POSTGRES_USER: str = "postgres"
    POSTGRES_PASSWORD: str = "postgres"
    
    # YOLO Model
    MODEL_PATH: str = "models/yolov8n.pt"
    DEFAULT_MODEL_ID: str = "yolov8n"  # Default model to use
    CONF_THRESHOLD: float = 0.25
    IOU_THRESHOLD: float = 0.45
    
    # Cache Settings
    CACHE_TTL: int = 3600  # 1 hour

    # API root path (set to /api when running behind nginx proxy)
    ROOT_PATH: str = ""
    
    class Config:
        env_file = ".env"
        case_sensitive = True


settings = Settings()
