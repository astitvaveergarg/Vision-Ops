"""
MinIO/S3 storage layer for VisionOps

Handles:
- Image storage
- Bucket management
- Object retrieval
"""
import io
import logging
from typing import Optional
from datetime import datetime

from minio import Minio
from minio.error import S3Error

from config import settings

logger = logging.getLogger(__name__)


class StorageService:
    """MinIO/S3 storage service for images"""
    
    def __init__(self):
        """Initialize MinIO client"""
        try:
            self.client = Minio(
                settings.MINIO_ENDPOINT,
                access_key=settings.MINIO_ACCESS_KEY,
                secret_key=settings.MINIO_SECRET_KEY,
                secure=settings.MINIO_SECURE
            )
            
            # Ensure bucket exists
            self._ensure_bucket()
            
            logger.info(f"Connected to MinIO at {settings.MINIO_ENDPOINT}")
        except Exception as e:
            logger.error(f"Failed to initialize MinIO client: {e}")
            raise
    
    def _ensure_bucket(self):
        """Create bucket if it doesn't exist"""
        try:
            if not self.client.bucket_exists(settings.MINIO_BUCKET):
                self.client.make_bucket(settings.MINIO_BUCKET)
                logger.info(f"Created bucket: {settings.MINIO_BUCKET}")
            else:
                logger.info(f"Bucket exists: {settings.MINIO_BUCKET}")
        except S3Error as e:
            logger.error(f"Failed to check/create bucket: {e}")
            raise
    
    def upload_image(
        self,
        filename: str,
        data: bytes,
        content_type: str = "image/jpeg"
    ) -> Optional[str]:
        """
        Upload image to storage
        
        Args:
            filename: Name for the stored file
            data: Image bytes
            content_type: MIME type
            
        Returns:
            Object URL or None if failed
        """
        try:
            # Add timestamp to filename to avoid collisions
            timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
            object_name = f"{timestamp}_{filename}"
            
            # Upload
            self.client.put_object(
                bucket_name=settings.MINIO_BUCKET,
                object_name=object_name,
                data=io.BytesIO(data),
                length=len(data),
                content_type=content_type
            )
            
            logger.info(f"Uploaded image: {object_name} ({len(data)} bytes)")
            
            # Return URL
            return f"{settings.MINIO_ENDPOINT}/{settings.MINIO_BUCKET}/{object_name}"
            
        except S3Error as e:
            logger.error(f"Failed to upload image: {e}")
            return None
    
    def download_image(self, object_name: str) -> Optional[bytes]:
        """
        Download image from storage
        
        Args:
            object_name: Name of stored object
            
        Returns:
            Image bytes or None if failed
        """
        try:
            response = self.client.get_object(
                bucket_name=settings.MINIO_BUCKET,
                object_name=object_name
            )
            data = response.read()
            response.close()
            response.release_conn()
            
            logger.info(f"Downloaded image: {object_name} ({len(data)} bytes)")
            return data
            
        except S3Error as e:
            logger.error(f"Failed to download image: {e}")
            return None
    
    def delete_image(self, object_name: str) -> bool:
        """
        Delete image from storage
        
        Args:
            object_name: Name of stored object
            
        Returns:
            True if successful, False otherwise
        """
        try:
            self.client.remove_object(
                bucket_name=settings.MINIO_BUCKET,
                object_name=object_name
            )
            logger.info(f"Deleted image: {object_name}")
            return True
            
        except S3Error as e:
            logger.error(f"Failed to delete image: {e}")
            return False
    
    def health_check(self) -> bool:
        """
        Check MinIO connection health
        
        Returns:
            True if healthy, False otherwise
        """
        try:
            # Check if bucket exists
            return self.client.bucket_exists(settings.MINIO_BUCKET)
        except Exception:
            return False
    
    def get_stats(self) -> dict:
        """
        Get storage statistics
        
        Returns:
            Dict with storage stats
        """
        try:
            objects = self.client.list_objects(settings.MINIO_BUCKET)
            count = sum(1 for _ in objects)
            
            return {
                "bucket": settings.MINIO_BUCKET,
                "object_count": count,
                "endpoint": settings.MINIO_ENDPOINT
            }
        except Exception as e:
            logger.error(f"Failed to get storage stats: {e}")
            return {}
