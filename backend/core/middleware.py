"""
JWT-аутентификация для WebSocket: токен в query param ?token=<access> (api.md §7).
"""
from urllib.parse import parse_qs

from channels.db import database_sync_to_async
from django.contrib.auth import get_user_model
from django.contrib.auth.models import AnonymousUser


@database_sync_to_async
def _get_user_from_token(token: str):
    if not token:
        return AnonymousUser()
    try:
        from rest_framework_simplejwt.tokens import AccessToken

        access = AccessToken(token)
        return get_user_model().objects.get(id=access["user_id"])
    except Exception:
        return AnonymousUser()


class JWTQueryParamAuthMiddleware:
    """Кладёт в scope['user'] пользователя из JWT (или AnonymousUser)."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        query = parse_qs(scope.get("query_string", b"").decode())
        token = (query.get("token") or [None])[0]
        scope["user"] = await _get_user_from_token(token)
        return await self.app(scope, receive, send)
