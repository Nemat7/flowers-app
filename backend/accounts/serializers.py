from django.core.validators import RegexValidator
from rest_framework import serializers

from .models import User

phone_validator = RegexValidator(
    regex=r"^\+992\d{9}$",
    message="Телефон в формате E.164: +992XXXXXXXXX",
)


class OTPRequestSerializer(serializers.Serializer):
    phone = serializers.CharField(max_length=16, validators=[phone_validator])


class OTPVerifySerializer(serializers.Serializer):
    phone = serializers.CharField(max_length=16, validators=[phone_validator])
    code = serializers.CharField(min_length=4, max_length=6)


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ("id", "phone", "name", "role")
        read_only_fields = ("id", "phone", "role")
