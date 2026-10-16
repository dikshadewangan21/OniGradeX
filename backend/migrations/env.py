from alembic import context

from app import models  # noqa: F401  (registers tables)
from app.config import get_settings
from app.db import Base, get_engine

target_metadata = Base.metadata


def run_migrations_online():
    engine = get_engine()
    with engine.connect() as conn:
        context.configure(connection=conn, target_metadata=target_metadata, compare_type=True,
                          render_as_batch=get_settings().database_url.startswith("sqlite"))
        with context.begin_transaction():
            context.run_migrations()


run_migrations_online()
