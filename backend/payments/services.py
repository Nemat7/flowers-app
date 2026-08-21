"""Доменные сервисы платежей: возвраты (авто и ручные)."""
from decimal import Decimal

from django.db import transaction

from .models import Payment, Refund
from .providers import get_provider


@transaction.atomic
def create_auto_refund(
    payment: Payment, amount: Decimal, reason: str, created_by=None
) -> Refund:
    """Возврат по успешному платежу. created_by=None — авто-возврат системы."""
    refunded = sum(payment.refunds.values_list("amount", flat=True)) or Decimal("0")
    if amount <= 0 or refunded + amount > payment.amount:
        raise ValueError(
            f"Некорректная сумма возврата: {amount} (платёж {payment.amount}, "
            f"уже возвращено {refunded})"
        )
    provider_refund_id = get_provider(payment.provider).refund(payment, amount, reason)
    refund = Refund.objects.create(
        payment=payment,
        amount=amount,
        reason=reason,
        status=Refund.Status.SUCCESS,
        provider_refund_id=provider_refund_id,
        created_by=created_by,
    )
    refunded += amount
    payment.status = (
        Payment.Status.REFUNDED
        if refunded >= payment.amount
        else Payment.Status.PARTIALLY_REFUNDED
    )
    payment.save(update_fields=["status", "updated_at"])
    return refund
