"""Push-уведомления (FCM) — заглушка до подключения Firebase.

TODO(FCM): подключить firebase-admin, брать токены из accounts.Device
и отправлять уведомления через FCM. Пока — только логирование, чтобы
места вызовов уже были расставлены по коду.
"""
import logging

logger = logging.getLogger(__name__)


def send_push(user, type: str, data: dict | None = None) -> None:
    """Отправить push одному пользователю (пока — лог)."""
    logger.info(
        "push stub → user=%s type=%s data=%s", getattr(user, "id", user), type, data or {}
    )


def send_push_many(users, type: str, data: dict | None = None) -> None:
    """Отправить push списку пользователей (пока — лог)."""
    for user in users:
        send_push(user, type, data)
