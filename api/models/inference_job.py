"""ORM model for inference jobs metadata."""
from sqlalchemy import Column, Integer, ForeignKey, String, DateTime, JSON, func
from sqlalchemy.orm import relationship

from ..database import Base


class InferenceJob(Base):
    __tablename__ = "inference_jobs"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    model_id = Column(Integer, ForeignKey("models.id"), nullable=True)
    input_image = Column(String, nullable=True)
    output_result = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", back_populates="inference_jobs")
    model = relationship("ModelRegistry", back_populates="inference_jobs")
