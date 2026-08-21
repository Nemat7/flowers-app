import { useEffect, useRef, useState } from 'react';
import type { ShopWsEvent } from '../types';
import { getAccessToken } from '../api/client';

const WS_URL: string = import.meta.env.VITE_WS_URL ?? 'ws://localhost:8000/ws';

// Подключение к /ws/shop/ с автореконнектом (экспоненциальный backoff до 15 сек).
// Токен берётся из localStorage при каждом переподключении — после refresh
// соединение поднимется уже с новым access.
export function useShopSocket(onEvent: (event: ShopWsEvent) => void) {
  const [connected, setConnected] = useState(false);
  const handlerRef = useRef(onEvent);
  handlerRef.current = onEvent;

  useEffect(() => {
    let ws: WebSocket | null = null;
    let stopped = false;
    let attempts = 0;
    let timer: number | undefined;

    const connect = () => {
      const token = getAccessToken();
      if (!token || stopped) return;
      try {
        ws = new WebSocket(`${WS_URL}/shop/?token=${encodeURIComponent(token)}`);
      } catch {
        schedule();
        return;
      }

      ws.onopen = () => {
        attempts = 0;
        setConnected(true);
      };
      ws.onmessage = (msg) => {
        try {
          const data = JSON.parse(msg.data as string) as ShopWsEvent;
          handlerRef.current(data);
        } catch {
          // некорректное сообщение — игнорируем
        }
      };
      ws.onclose = () => {
        setConnected(false);
        schedule();
      };
      ws.onerror = () => {
        ws?.close();
      };
    };

    const schedule = () => {
      if (stopped) return;
      const delay = Math.min(1000 * 2 ** attempts, 15000);
      attempts += 1;
      timer = window.setTimeout(connect, delay);
    };

    connect();

    return () => {
      stopped = true;
      if (timer !== undefined) window.clearTimeout(timer);
      ws?.close();
    };
  }, []);

  return connected;
}
