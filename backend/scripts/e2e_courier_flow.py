#!/usr/bin/env python3
"""E2E-прогон курьерского флоу против живого docker-окружения (api.md §6, §9).

Запуск с хоста: python3 backend/scripts/e2e_courier_flow.py [base_url]

Сценарий: OTP клиента → заказ → оплата (stub) → магазин accept/ready →
OTP курьера → online → available → accept → pickup → location → arrive →
complete(pin) → заказ delivered → earnings → детали заказа с полной историей.

WS-проверка (status_changed/courier_location) делается отдельным слушателем
scripts/ws_client_listen.py внутри контейнера (см. e2e README/отчёт).
"""
import json
import sys
import urllib.request
import uuid

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000"
API = f"{BASE}/api/v1"

CLIENT_PHONE = "+992900000001"
STAFF_PHONE = "+992900000002"
COURIER_PHONE = "+992900000003"

failures = []


def check(name, condition, extra=""):
    status = "PASS" if condition else "FAIL"
    print(f"[{status}] {name}" + (f" — {extra}" if extra else ""))
    if not condition:
        failures.append(name)


def http(method, path, token=None, body=None, headers=None):
    request = urllib.request.Request(
        f"{API}{path}", method=method,
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


def login(phone):
    status, data = http("POST", "/auth/otp/request/", body={"phone": phone})
    assert status == 200, (status, data)
    code = data["dev_code"]  # DEBUG=1
    status, data = http(
        "POST", "/auth/otp/verify/", body={"phone": phone, "code": code}
    )
    assert status == 200, (status, data)
    return data["access"], data["user"]


def main():
    # --- клиент: заказ и оплата ---
    client_token, _ = login(CLIENT_PHONE)
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
    check("создание заказа", status == 201, f"status={status} №{order.get('number')}")
    order_id = order["id"]

    status, payment = http(
        "POST", f"/orders/{order_id}/pay/", client_token,
        body={"provider": "stub"}, headers={"Idempotency-Key": str(uuid.uuid4())},
    )
    check("оплата (stub)", status == 201 and payment["status"] == "success")

    # --- магазин: accept → ready ---
    staff_token, _ = login(STAFF_PHONE)
    status, _ = http(
        "POST", f"/shop/orders/{order_id}/accept/", staff_token, body={"eta_minutes": 15}
    )
    check("магазин accept", status == 200, f"status={status}")
    status, data = http("POST", f"/shop/orders/{order_id}/ready/", staff_token, body={})
    check("магазин ready", status == 200 and data["status"] == "ready")

    # --- курьер: online → available → accept ---
    courier_token, _ = login(COURIER_PHONE)
    status, earnings_before = http("GET", "/courier/earnings/", courier_token)
    today_before = float(earnings_before["today"]) if status == 200 else 0.0
    status, data = http("PATCH", "/courier/status/", courier_token, body={"status": "online"})
    check("курьер online", status == 200 and data["status"] == "online", f"{status} {data}")

    status, available = http("GET", "/courier/orders/available/", courier_token)
    found = [o for o in available if o["id"] == order_id]
    check("заказ в available", status == 200 and len(found) == 1,
          f"distance={found[0]['distance'] if found else '-'}")

    status, data = http("POST", f"/courier/orders/{order_id}/accept/", courier_token, body={})
    check("курьер accept", status == 200 and data["status"] == "courier_assigned", f"{status} {data}")

    status, current = http("GET", "/courier/orders/current/", courier_token)
    check("current заказ", status == 200 and current["order"]["id"] == order_id)

    # --- pickup → location → arrive → complete ---
    status, data = http("POST", f"/courier/orders/{order_id}/pickup/", courier_token, body={})
    check("pickup → on_the_way", status == 200 and data["status"] == "on_the_way")

    import time

    now = time.time()
    points = [
        {"lat": 38.5600 + i * 0.0005, "lng": 68.7875 + i * 0.0005, "ts": now + i * 10}
        for i in range(4)
    ]
    status, data = http("POST", "/courier/location/", courier_token, body={"points": points})
    check("location батч (4 точки)", status == 200 and data["accepted"] == 4, f"{status} {data}")

    status, data = http("POST", f"/courier/orders/{order_id}/arrive/", courier_token, body={})
    check("arrive", status == 200 and data["status"] == "arrived")

    # PIN клиент видит в деталях заказа — получатель называет курьеру
    status, detail = http("GET", f"/orders/{order_id}/", client_token)
    pin = detail["delivery_pin"]
    status, data = http(
        "POST", f"/courier/orders/{order_id}/complete/", courier_token,
        body={"pin": "0000" if pin != "0000" else "9999"},
    )
    check("complete с неверным PIN → 400 invalid_pin",
          status == 400 and data["error"]["code"] == "invalid_pin")
    status, data = http(
        "POST", f"/courier/orders/{order_id}/complete/", courier_token, body={"pin": pin}
    )
    check("complete(pin) → delivered", status == 200 and data["status"] == "delivered")

    # --- заработок и финальное состояние ---
    status, earnings = http("GET", "/courier/earnings/", courier_token)
    fee = float(detail["delivery_fee"])
    check("earnings вырос на fee заказа",
          status == 200
          and abs(float(earnings["today"]) - (today_before + fee)) < 0.01
          and abs(float(earnings["total"]) - float(earnings["today"])) < 0.01,
          f"{earnings} (fee={fee})")

    status, history = http("GET", "/courier/orders/history/", courier_token)
    check("история доставок курьера", status == 200 and history["count"] >= 1)

    status, detail = http("GET", f"/orders/{order_id}/", client_token)
    statuses = [h["status"] for h in detail["status_history"]]
    # история отдаётся newest-first (Meta.ordering = -created_at)
    expected = [
        "delivered", "arrived", "on_the_way", "picked_up", "courier_assigned",
        "ready", "preparing", "accepted", "shop_pending", "paid", "created",
    ]
    check("заказ delivered, история полная",
          status == 200 and detail["status"] == "delivered" and statuses == expected,
          " → ".join(statuses))

    print()
    if failures:
        print(f"E2E FAILED: {len(failures)} шаг(ов): {failures}")
        return 1
    print("E2E OK: весь курьерский флоу прошёл")
    return 0


if __name__ == "__main__":
    sys.exit(main())
