"""ORM model for users table."""
from sqlalchemy import Column, Integer, String, DateTime, func
from sqlalchemy.orm import relationship

from ..database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    email = Column(String, unique=True, index=True, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    models = relationship("ModelRegistry", back_populates="owner")
    inference_jobs = relationship("InferenceJob", back_populates="user")
