"""Общие помощники API: единый формат ошибок {error:{code,message,details}}."""
from rest_framework.response import Response


def error_response(code: str, message: str, http_status: int, details=None) -> Response:
    body = {"error": {"code": code, "message": message, "details": details or {}}}
    return Response(body, status=http_status)
