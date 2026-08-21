# Подключаем Celery-приложение при старте Django,
# чтобы @shared_task привязывались к нему.
from .celery import app as celery_app

__all__ = ("celery_app",)
