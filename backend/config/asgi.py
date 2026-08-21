import os

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

from django.core.asgi import get_asgi_application  # noqa: E402

django_asgi_app = get_asgi_application()

from channels.routing import ProtocolTypeRouter, URLRouter  # noqa: E402

import core.routing  # noqa: E402
from core.middleware import JWTQueryParamAuthMiddleware  # noqa: E402

application = ProtocolTypeRouter(
    {
        "http": django_asgi_app,
        # JWT-аутентификация для WS — через query param ?token=<access> (api.md §7)
        "websocket": JWTQueryParamAuthMiddleware(
            URLRouter(core.routing.websocket_urlpatterns)
        ),
    }
)
