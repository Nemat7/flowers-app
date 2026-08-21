"""Отправка SMS (OTP, уведомления).

Структура backend'ов, выбор — через settings.SMS_BACKEND:
- "console" — печать в лог/консоль (default в DEBUG);
- "osonsms" — шлюз osonsms.com (провайдер РТ, business-logic.md §10).
"""
import logging

from django.conf import settings

logger = logging.getLogger(__name__)


class BaseSMSBackend:
    """Базовый интерфейс SMS-backend'а."""

    name = ""

    def send(self, phone: str, text: str) -> bool:
        """Отправить SMS. Возвращает True при успешной постановке в отправку."""
        raise NotImplementedError


class ConsoleSMSBackend(BaseSMSBackend):
    """Dev-backend: SMS не уходит, текст пишется в лог/консоль."""

    name = "console"

    def send(self, phone: str, text: str) -> bool:
        logger.info("SMS console → %s: %s", phone, text)
        print(f"[SMS console] {phone}: {text}")
        return True


class OsonSMSBackend(BaseSMSBackend):
    """Шлюз osonsms.com (провайдер РТ, протокол v2.0.2 — docs/sms-api-documentation.pdf).

    Отправка: GET {OSONSMS_API_URL} (api.osonsms.com/sendsms_v1.php)
    Заголовок: Authorization: Bearer {OSONSMS_HASH}
    Параметры: from, phone_number (992XXXXXXXXX, без +), msg, login, txn_id.
    201 + status=ok — в очереди; txn_id уникален (повтор с тем же txn_id → 409,
    провайдер сам защищает от дублей). is_confidential=true — коды не хранятся
    в личном кабинете провайдера.
    Важно: у провайдера белый список IP (код 114) — IP сервера должен быть
    в whitelist в кабинете OsonSMS.
    """

    name = "osonsms"
    timeout = 20  # по протоколу провайдера

    def send(self, phone: str, text: str) -> bool:
        import uuid

        import requests

        # +992XXXXXXXXX → 992XXXXXXXXX (формат протокола)
        phone_digits = phone.lstrip("+")
        params = {
            "from": settings.OSONSMS_SENDER,
            "phone_number": phone_digits,
            "msg": text,
            "login": settings.OSONSMS_LOGIN,
            "txn_id": uuid.uuid4().hex,
            "is_confidential": "true",
        }
        try:
            resp = requests.get(
                settings.OSONSMS_API_URL,
                params=params,
                headers={"Authorization": f"Bearer {settings.OSONSMS_HASH}"},
                timeout=self.timeout,
            )
        except requests.RequestException as e:
            logger.error("OsonSMS недоступен (%s): %s", phone_digits, e)
            return False

        if resp.status_code == 201:
            logger.info("OsonSMS → %s: в очереди (%s)", phone_digits, resp.text[:200])
            return True

        # 4xx/5xx — разбираем код ошибки провайдера для логов
        logger.warning(
            "OsonSMS → %s: отказ HTTP %s: %s", phone_digits, resp.status_code, resp.text[:300]
        )
        return False


_BACKENDS: dict[str, type[BaseSMSBackend]] = {
    ConsoleSMSBackend.name: ConsoleSMSBackend,
    OsonSMSBackend.name: OsonSMSBackend,
}


def get_sms_backend() -> BaseSMSBackend:
    backend_cls = _BACKENDS.get(settings.SMS_BACKEND)
    if backend_cls is None:
        raise ValueError(f"Неизвестный SMS_BACKEND: {settings.SMS_BACKEND!r}")
    return backend_cls()


def send_sms(phone: str, text: str) -> bool:
    return get_sms_backend().send(phone, text)


def send_otp(phone: str, code: str) -> bool:
    return send_sms(phone, f"Ваш код подтверждения Flowers & Sweets: {code}")
