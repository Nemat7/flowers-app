"""Платёжные провайдеры. Сейчас — только stub; alif/dc добавляются
реализацией BasePaymentProvider и регистрацией в PROVIDERS (api.md §4)."""
import uuid

from django.conf import settings

from .models import Payment


class ProviderUnavailableError(Exception):
    pass


class BasePaymentProvider:
    """Базовый интерфейс провайдера оплаты."""

    name: str = ""

    def initiate(self, order, idempotency_key) -> Payment:
        """Создать платёж по заказу. Возвращает Payment (pending или success)."""
        raise NotImplementedError

    def refund(self, payment: Payment, amount, reason: str):
        """Инициировать возврат у провайдера. Возвращает provider_refund_id или None."""
        raise NotImplementedError


class StubPaymentProvider(BasePaymentProvider):
    """Фиктивный успешный платёж — только для dev/staging (api.md §4)."""

    name = Payment.Provider.STUB

    def is_enabled(self) -> bool:
        return settings.DEBUG or settings.ALLOW_STUB_PAYMENTS

    def initiate(self, order, idempotency_key) -> Payment:
        return Payment.objects.create(
            order=order,
            provider=self.name,
            amount=order.total,
            status=Payment.Status.SUCCESS,
            provider_txn_id=f"stub-{uuid.uuid4().hex[:16]}",
            idempotency_key=idempotency_key,
        )

    def refund(self, payment: Payment, amount, reason: str):
        return f"stub-refund-{uuid.uuid4().hex[:16]}"


# TODO: AlifPaymentProvider / DcPaymentProvider — после договоров с банками
# (мерчант-API, подписи webhook'ов; business-logic.md §7).
PROVIDERS: dict[str, type[BasePaymentProvider]] = {
    StubPaymentProvider.name: StubPaymentProvider,
}


def get_provider(name: str) -> BasePaymentProvider:
    provider_cls = PROVIDERS.get(name)
    if provider_cls is None:
        raise ProviderUnavailableError(f"Провайдер «{name}» не поддерживается")
    return provider_cls()
