"""ORM model for user-uploaded models registry."""
from sqlalchemy import Column, Integer, String, ForeignKey, DateTime, func
from sqlalchemy.orm import relationship

from ..database import Base


class ModelRegistry(Base):
    __tablename__ = "models"

    id = Column(Integer, primary_key=True, index=True)
    owner_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    name = Column(String, index=True)
    framework = Column(String, nullable=True)
    storage_path = Column(String, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    owner = relationship("User", back_populates="models")
    inference_jobs = relationship("InferenceJob", back_populates="model")
