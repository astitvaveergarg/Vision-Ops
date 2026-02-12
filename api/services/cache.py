"""
Redis caching layer for VisionOps

Handles:
- Result caching
- Cache key management
- TTL management
"""
import redis
import json
import logging
from typing import Optional, Dict, Any

from config import settings

logger = logging.getLogger(__name__)


class CacheService:
    """Redis cache service for detection results"""
    
    def __init__(self):
        """Initialize Redis connection"""
        try:
            self.client = redis.Redis(
                host=settings.REDIS_HOST,
                port=settings.REDIS_PORT,
                db=settings.REDIS_DB,
                password=settings.REDIS_PASSWORD,
                decode_responses=True,
                socket_connect_timeout=5,
                socket_timeout=5
            )
            # Test connection
            self.client.ping()
            logger.info(f"Connected to Redis at {settings.REDIS_HOST}:{settings.REDIS_PORT}")
        except redis.ConnectionError as e:
            logger.error(f"Failed to connect to Redis: {e}")
            raise
    
    def get_cached_result(self, image_hash: str) -> Optional[Dict[str, Any]]:
        """
        Retrieve cached detection result
        
        Args:
            image_hash: SHA256 hash of image
            
        Returns:
            Cached result dict or None if not found
        """
        try:
            key = f"detection:{image_hash}"
            cached = self.client.get(key)
            
            if cached:
                logger.info(f"Cache HIT for {image_hash[:8]}...")
                return json.loads(cached)
            else:
                logger.info(f"Cache MISS for {image_hash[:8]}...")
                return None
                
        except Exception as e:
            logger.error(f"Cache read error: {e}")
            return None
    
    def cache_result(
        self,
        image_hash: str,
        result: Dict[str, Any],
        ttl: Optional[int] = None
    ) -> bool:
        """
        Store detection result in cache
        
        Args:
            image_hash: SHA256 hash of image
            result: Detection result dict
            ttl: Time-to-live in seconds (default from settings)
            
        Returns:
            True if successful, False otherwise
        """
        try:
            key = f"detection:{image_hash}"
            ttl = ttl or settings.CACHE_TTL
            
            self.client.setex(
                key,
                ttl,
                json.dumps(result)
            )
            
            logger.info(f"Cached result for {image_hash[:8]}... (TTL: {ttl}s)")
            return True
            
        except Exception as e:
            logger.error(f"Cache write error: {e}")
            return False
    
    def invalidate(self, image_hash: str) -> bool:
        """
        Remove cached result
        
        Args:
            image_hash: SHA256 hash of image
            
        Returns:
            True if deleted, False if not found
        """
        try:
            key = f"detection:{image_hash}"
            deleted = self.client.delete(key)
            return deleted > 0
        except Exception as e:
            logger.error(f"Cache delete error: {e}")
            return False
    
    def health_check(self) -> bool:
        """
        Check Redis connection health
        
        Returns:
            True if healthy, False otherwise
        """
        try:
            return self.client.ping()
        except Exception:
            return False
    
    def get_stats(self) -> Dict[str, Any]:
        """
        Get cache statistics
        
        Returns:
            Dict with cache stats
        """
        try:
            info = self.client.info()
            return {
                "connected_clients": info.get("connected_clients", 0),
                "used_memory": info.get("used_memory_human", "unknown"),
                "total_commands_processed": info.get("total_commands_processed", 0),
                "keyspace_hits": info.get("keyspace_hits", 0),
                "keyspace_misses": info.get("keyspace_misses", 0),
            }
        except Exception as e:
            logger.error(f"Failed to get cache stats: {e}")
            return {}
