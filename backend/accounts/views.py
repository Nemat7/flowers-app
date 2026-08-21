import secrets
from datetime import timedelta

from django.conf import settings
from django.core.cache import cache
from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken

from .models import OTPCode, User
from .serializers import OTPRequestSerializer, OTPVerifySerializer, UserSerializer
from .sms import send_otp


def _error(code: str, message: str, http_status: int, details=None):
    body = {"error": {"code": code, "message": message, "details": details or {}}}
    return Response(body, status=http_status)


class OTPRequestView(APIView):
    """POST /auth/otp/request/ — отправка SMS-кода. Rate limit: 1/60 сек, 5/сутки."""

    permission_classes = (AllowAny,)

    def post(self, request):
        serializer = OTPRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        phone = serializer.validated_data["phone"]

        # Rate limit через Redis (кэш): не чаще 1 SMS / 60 сек, не более 5 / сутки
        interval_key = f"otp:interval:{phone}"
        if cache.get(interval_key):
            return _error(
                "rate_limited",
                "Код уже отправлен. Повторите через минуту.",
                status.HTTP_429_TOO_MANY_REQUESTS,
            )
        daily_key = f"otp:daily:{phone}"
        daily_count = cache.get(daily_key, 0)
        if daily_count >= settings.OTP_DAILY_LIMIT:
            return _error(
                "daily_limit",
                "Превышен дневной лимит отправки SMS.",
                status.HTTP_429_TOO_MANY_REQUESTS,
            )

        code = f"{secrets.randbelow(1_000_000):06d}"
        # Новый код инвалидирует прежние неиспользованные — иначе легко ввести старый.
        OTPCode.objects.filter(phone=phone, is_used=False).update(is_used=True)
        otp = OTPCode(
            phone=phone,
            expires_at=timezone.now() + timedelta(seconds=settings.OTP_CODE_TTL_SECONDS),
        )
        otp.set_code(code)
        otp.save()

        send_otp(phone, code)
        cache.set(interval_key, 1, settings.OTP_RESEND_INTERVAL_SECONDS)
        if daily_count == 0:
            cache.set(daily_key, 1, 24 * 3600)
        else:
            cache.set(daily_key, daily_count + 1, 24 * 3600)

        data = {"detail": "Код отправлен"}
        if settings.DEBUG:
            # Только в DEBUG: код возвращается в ответе, чтобы тестировать без SMS
            data["dev_code"] = code
        return Response(data, status=status.HTTP_200_OK)


class OTPVerifyView(APIView):
    """POST /auth/otp/verify/ — проверка кода, выдача JWT, создание User при первом входе."""

    permission_classes = (AllowAny,)

    def post(self, request):
        serializer = OTPVerifySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        phone = serializer.validated_data["phone"]
        code = serializer.validated_data["code"]

        otp = (
            OTPCode.objects.filter(phone=phone, is_used=False).order_by("-id").first()
        )
        invalid = _error(
            "invalid_code", "Неверный или истёкший код.", status.HTTP_400_BAD_REQUEST
        )
        if otp is None or otp.is_expired:
            return invalid
        if otp.attempts >= settings.OTP_MAX_ATTEMPTS:
            return _error(
                "too_many_attempts",
                "Превышено число попыток. Запросите новый код.",
                status.HTTP_400_BAD_REQUEST,
            )
        if not otp.check_code(code):
            otp.attempts += 1
            otp.save(update_fields=["attempts"])
            return invalid

        otp.is_used = True
        otp.save(update_fields=["is_used"])

        user, _created = User.objects.get_or_create(
            phone=phone, defaults={"role": User.Role.CLIENT}
        )
        if not user.is_active:
            return _error(
                "user_blocked", "Пользователь заблокирован.", status.HTTP_403_FORBIDDEN
            )

        refresh = RefreshToken.for_user(user)
        return Response(
            {
                "access": str(refresh.access_token),
                "refresh": str(refresh),
                "user": UserSerializer(user).data,
            },
            status=status.HTTP_200_OK,
        )


class MeView(APIView):
    """GET/PATCH /users/me/ — профиль текущего пользователя."""

    def get(self, request):
        return Response(UserSerializer(request.user).data)

    def patch(self, request):
        serializer = UserSerializer(request.user, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)
