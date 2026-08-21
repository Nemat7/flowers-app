"""E2E-прогон WebSocket против ЖИВОГО сервера (запуск внутри backend-контейнера).

  docker compose exec -T backend python scripts/e2e_ws_flow.py

Проверяет реальную цепочку: HTTP REST (daphne runserver) → services →
ws_events → Redis channel layer → consumers → WS-клиент (websockets).

JWT минтятся напрямую (django-контекст), OTP не нужен — поэтому скрипт
работает сразу после seed_demo и не упирается в rate limit SMS.
"""
import asyncio
import json
import os
import sys
import urllib.request
import uuid

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
# скрипт лежит в scripts/, а проект — в родительской директории
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import django  # noqa: E402

django.setup()

from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from accounts.models import User  # noqa: E402

BASE_HTTP = "http://localhost:8000/api/v1"
BASE_WS = "ws://localhost:8000"

CLIENT_PHONE = "+992900000001"
STAFF_PHONE = "+992900000002"
COURIER_PHONE = "+992900000003"

failures = []


def check(name, condition, extra=""):
    print(f"[{'PASS' if condition else 'FAIL'}] {name}" + (f" — {extra}" if extra else ""))
    if not condition:
        failures.append(name)


def token_for(phone):
    return str(RefreshToken.for_user(User.objects.get(phone=phone)).access_token)


def http(method, path, token=None, body=None, headers=None):
    request = urllib.request.Request(
        f"{BASE_HTTP}{path}", method=method,
        headers={"Content-Type": "application/json", **(headers or {})},
        data=json.dumps(body).encode() if body is not None else None,
    )
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(request) as response:
            return response.status, json.loads(response.read() or b"null")
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read() or b"null")


async def expect_event(ws, event_type, timeout=10, **match):
    """Ждать событие нужного типа (пропуская остальные), вернуть его.
    match — дополнительные поля, которые должны совпасть (напр. status=...)."""
    deadline = asyncio.get_event_loop().time() + timeout
    while True:
        remaining = deadline - asyncio.get_event_loop().time()
        if remaining <= 0:
            return None
        try:
            raw = await asyncio.wait_for(ws.recv(), timeout=remaining)
        except TimeoutError:
            return None
        event = json.loads(raw)
        print(f"    WS ← {event}")
        if event.get("type") == event_type and all(
            event.get(k) == v for k, v in match.items()
        ):
            return event


async def main(client_token, staff_token, courier_token):
    import websockets


    # --- подготовка: заказ → оплата → accept магазина ---
    status, shops = http("GET", "/shops/", client_token)
    shop_id = shops["results"][0]["id"]
    status, products = http("GET", f"/products/?shop_id={shop_id}", client_token)
    product_id = products["results"][0]["id"]
    status, order = http("POST", "/orders/", client_token, body={
        "shop_id": shop_id,
        "items": [{"product_id": product_id, "qty": 1}],
        "recipient_name": "Гульчехра",
        "recipient_phone": "+992900000009",
        "address": {"lat": 38.5598, "lng": 68.7870, "address_text": "Рудаки 25"},
        "slot_type": "asap",
    })
    order_id = order["id"]
    check("заказ создан", status == 201, f"№{order.get('number')}")

    # --- WS-подключения ДО событий ---
    async with websockets.connect(
        f"{BASE_WS}/ws/client/orders/{order_id}/?token={client_token}"
    ) as client_ws, websockets.connect(
        f"{BASE_WS}/ws/shop/?token={staff_token}"
    ) as shop_ws, websockets.connect(
        f"{BASE_WS}/ws/courier/?token={courier_token}"
    ) as courier_ws:
        check("WS: все три канала подключились (JWT query auth)", True)

        # оплата → магазин получает new_order
        status, _ = http(
            "POST", f"/orders/{order_id}/pay/", client_token,
            body={"provider": "stub"}, headers={"Idempotency-Key": str(uuid.uuid4())},
        )
        check("оплата", status == 201)
        event = await expect_event(shop_ws, "new_order")
        check("WS shop: new_order", event is not None and event["order_id"] == order_id,
              json.dumps(event, ensure_ascii=False) if event else "нет события")

        # магазин accept → ready → курьер получает order_available
        http("POST", f"/shop/orders/{order_id}/accept/", staff_token, body={"eta_minutes": 15})
        http("PATCH", "/courier/status/", courier_token, body={"status": "online"})
        http("POST", f"/shop/orders/{order_id}/ready/", staff_token, body={})
        event = await expect_event(courier_ws, "order_available")
        check("WS courier: order_available",
              event is not None and event["order_id"] == order_id and "distance" in event,
              json.dumps(event, ensure_ascii=False) if event else "нет события")

        # курьер accept → клиент: status_changed courier_assigned
        http("POST", f"/courier/orders/{order_id}/accept/", courier_token, body={})
        event = await expect_event(client_ws, "status_changed", status="courier_assigned")
        check("WS client: status_changed courier_assigned", event is not None)
        # курьер получает order_taken (свой же приём уводит заказ из доступных)
        event = await expect_event(courier_ws, "order_taken")
        check("WS courier: order_taken", event is not None and event["order_id"] == order_id)

        # pickup → status_changed on_the_way (picked_up — промежуточный)
        http("POST", f"/courier/orders/{order_id}/pickup/", courier_token, body={})
        event = await expect_event(client_ws, "status_changed", status="on_the_way")
        check("WS client: status_changed on_the_way после pickup", event is not None)

        # location → courier_location у клиента
        import time

        now = time.time()
        http("POST", "/courier/location/", courier_token, body={
            "points": [
                {"lat": 38.5605, "lng": 68.7880, "ts": now},
                {"lat": 38.5610, "lng": 68.7885, "ts": now + 10},
            ],
        })
        event = await expect_event(client_ws, "courier_location")
        check("WS client: courier_location",
              event is not None and abs(event["lat"] - 38.5605) < 1e-6,
              json.dumps(event) if event else "нет события")

        # arrive → complete → delivered
        http("POST", f"/courier/orders/{order_id}/arrive/", courier_token, body={})
        status, detail = http("GET", f"/orders/{order_id}/", client_token)
        http(
            "POST", f"/courier/orders/{order_id}/complete/", courier_token,
            body={"pin": detail["delivery_pin"]},
        )
        event = await expect_event(client_ws, "status_changed", status="delivered")
        check("WS client: status_changed delivered", event is not None)

    print()
    if failures:
        print(f"E2E WS FAILED: {failures}")
        return 1
    print("E2E WS OK: живые WebSocket-события прошли по всем трём каналам")
    return 0


if __name__ == "__main__":
    # токены минтятся синхронно (ORM) до входа в event loop
    tokens = (token_for(CLIENT_PHONE), token_for(STAFF_PHONE), token_for(COURIER_PHONE))
    sys.exit(asyncio.run(main(*tokens)))
