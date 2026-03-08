"""A generic, single-template script for use with ``alembic init``.

This file is used by ``alembic revision`` when using the ``--autogenerate``
option.  This template is intended to be the minimal template that still
supports the basic functionality of unnamed revisions.  See the documentation
for ``alembic revision`` for additional information.
"""

"""Revision ID: ${up_revision}
Revises: ${down_revision | comma,n}
Create Date: ${create_date}
"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = ${repr(up_revision)}
down_revision = ${repr(down_revision)}
branch_labels = ${repr(branch_labels)}
depends_on = ${repr(depends_on)}


def upgrade():
    pass


def downgrade():
    pass
