"""initial migration

Revision ID: 0001_initial
Revises: 
Create Date: 2026-03-09 00:00:00.000000
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '0001_initial'
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    # users table
    op.create_table(
        'users',
        sa.Column('id', sa.Integer, primary_key=True, index=True),
        sa.Column('username', sa.String(), unique=True, index=True, nullable=False),
        sa.Column('hashed_password', sa.String(), nullable=False),
        sa.Column('email', sa.String(), unique=True, index=True, nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    # models table
    op.create_table(
        'models',
        sa.Column('id', sa.Integer, primary_key=True, index=True),
        sa.Column('owner_id', sa.Integer, sa.ForeignKey('users.id'), nullable=False),
        sa.Column('name', sa.String(), index=True),
        sa.Column('framework', sa.String(), nullable=True),
        sa.Column('storage_path', sa.String(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    # inference_jobs table
    op.create_table(
        'inference_jobs',
        sa.Column('id', sa.Integer, primary_key=True, index=True),
        sa.Column('user_id', sa.Integer, sa.ForeignKey('users.id'), nullable=True),
        sa.Column('model_id', sa.Integer, sa.ForeignKey('models.id'), nullable=True),
        sa.Column('input_image', sa.String(), nullable=True),
        sa.Column('output_result', sa.JSON(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
    )


def downgrade():
    op.drop_table('inference_jobs')
    op.drop_table('models')
    op.drop_table('users')
