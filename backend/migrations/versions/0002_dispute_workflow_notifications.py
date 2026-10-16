"""dispute workflow and notifications

Revision ID: 0002
Revises: 0001
"""
from alembic import op
import sqlalchemy as sa


revision = '0002'
down_revision = '0001'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. Add columns to disputes table
    with op.batch_alter_table('disputes', schema=None) as batch_op:
        batch_op.add_column(sa.Column('assigned_officer_id', sa.String(length=36), nullable=True))
        batch_op.add_column(sa.Column('reinspection_certificate_id', sa.String(length=36), nullable=True))
        batch_op.create_foreign_key('fk_disputes_assigned_officer_id', 'users', ['assigned_officer_id'], ['id'])
        batch_op.create_foreign_key('fk_disputes_reinspection_certificate_id', 'certificates', ['reinspection_certificate_id'], ['id'])
        batch_op.create_index('ix_disputes_assigned_officer_id', ['assigned_officer_id'], unique=False)
        batch_op.create_index('ix_disputes_reinspection_certificate_id', ['reinspection_certificate_id'], unique=False)

    # 2. Create notifications table
    op.create_table('notifications',
        sa.Column('id', sa.String(length=36), nullable=False),
        sa.Column('user_id', sa.String(length=36), nullable=False),
        sa.Column('title', sa.String(length=200), nullable=False),
        sa.Column('message', sa.Text(), nullable=False),
        sa.Column('dispute_id', sa.String(length=36), nullable=True),
        sa.Column('is_read', sa.Boolean(), nullable=False, server_default=sa.text('false')),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['dispute_id'], ['disputes.id'], name='fk_notifications_dispute_id'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], name='fk_notifications_user_id'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_notifications_user_id', 'notifications', ['user_id'], unique=False)
    op.create_index('ix_notifications_dispute_id', 'notifications', ['dispute_id'], unique=False)


def downgrade() -> None:
    op.drop_index('ix_notifications_dispute_id', table_name='notifications')
    op.drop_index('ix_notifications_user_id', table_name='notifications')
    op.drop_table('notifications')

    with op.batch_alter_table('disputes', schema=None) as batch_op:
        batch_op.drop_index('ix_disputes_reinspection_certificate_id')
        batch_op.drop_index('ix_disputes_assigned_officer_id')
        batch_op.drop_constraint('fk_disputes_reinspection_certificate_id', type_='foreignkey')
        batch_op.drop_constraint('fk_disputes_assigned_officer_id', type_='foreignkey')
        batch_op.drop_column('reinspection_certificate_id')
        batch_op.drop_column('assigned_officer_id')
