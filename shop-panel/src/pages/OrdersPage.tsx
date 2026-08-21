import { useCallback, useEffect, useRef, useState } from 'react';
import { useAuth } from '../auth/AuthContext';
import {
  acceptOrder,
  getShopOrder,
  getShopOrders,
  markOrderReady,
  rejectOrder,
  uploadOrderPhoto,
  type ShopOrderFilter,
} from '../api/client';
import type { OrderDetail, OrderSummary, ShopWsEvent } from '../types';
import { useShopSocket } from '../hooks/useShopSocket';
import { playNewOrderSound } from '../utils/sound';
import AppNav from '../components/AppNav';
import { ActiveOrderCard, HistoryOrderCard, PendingOrderCard } from '../components/OrderCards';

type Tab = ShopOrderFilter;

const TABS: { key: Tab; label: string }[] = [
  { key: 'pending', label: 'Входящие' },
  { key: 'active', label: 'В работе' },
  { key: 'history', label: 'История' },
];

const POLL_INTERVAL_MS = 15000;
// Backend даёт магазину 5–7 минут на принятие; точный expires_at приходит
// только в WS-событии, для заказов из REST оцениваем от created_at.
const ESTIMATED_ACCEPT_WINDOW_MS = 6 * 60 * 1000;

function summaryFromDetail(d: OrderDetail): OrderSummary {
  return {
    id: d.id,
    number: d.number,
    status: d.status,
    shop: d.shop,
    shop_name: d.shop_name,
    slot_type: d.slot_type,
    total: d.total,
    created_at: d.created_at,
    recipient_name: d.recipient_name,
    scheduled_at: d.scheduled_at,
    expires_at: null,
  };
}

export default function OrdersPage() {
  const { state, logout } = useAuth();
  const user = state.status === 'authenticated' ? state.user : null;

  const [tab, setTab] = useState<Tab>('pending');
  const [lists, setLists] = useState<Record<Tab, OrderSummary[]>>({ pending: [], active: [], history: [] });
  const [details, setDetails] = useState<Record<number, OrderDetail>>({});
  const [expires, setExpires] = useState<Record<number, number>>({});
  const [flashIds, setFlashIds] = useState<ReadonlySet<number>>(new Set());
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [banner, setBanner] = useState('');

  const tabRef = useRef(tab);
  tabRef.current = tab;

  const loadTab = useCallback(async (t: Tab) => {
    const page = await getShopOrders(t);
    setLists((prev) => ({ ...prev, [t]: page.results }));

    if (t === 'pending') {
      setExpires((prev) => {
        const next = { ...prev };
        for (const o of page.results) {
          // точный expires_at приходит от backend; fallback — оценка от created_at
          if (!next[o.id]) {
            next[o.id] = o.expires_at
              ? Date.parse(o.expires_at)
              : Date.parse(o.created_at) + ESTIMATED_ACCEPT_WINDOW_MS;
          }
        }
        return next;
      });
    }

    if (t !== 'history') {
      const settled = await Promise.allSettled(page.results.map((o) => getShopOrder(o.id)));
      const map: Record<number, OrderDetail> = {};
      settled.forEach((r, i) => {
        if (r.status === 'fulfilled') map[page.results[i].id] = r.value;
      });
      if (Object.keys(map).length > 0) setDetails((prev) => ({ ...prev, ...map }));
    }
  }, []);

  const refreshAll = useCallback(async () => {
    try {
      await loadTab('pending');
      const current = tabRef.current;
      if (current !== 'pending') await loadTab(current);
      setError('');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Ошибка загрузки');
    } finally {
      setLoading(false);
    }
  }, [loadTab]);

  // Первичная загрузка + polling fallback каждые 15 сек
  useEffect(() => {
    void refreshAll();
    const t = window.setInterval(() => void refreshAll(), POLL_INTERVAL_MS);
    return () => window.clearInterval(t);
  }, [refreshAll]);

  // Переключение вкладки — догружаем её данные
  useEffect(() => {
    loadTab(tab).catch((e) => setError(e instanceof Error ? e.message : 'Ошибка загрузки'));
  }, [tab, loadTab]);

  const flashOrder = useCallback((id: number) => {
    setFlashIds((prev) => new Set(prev).add(id));
    window.setTimeout(() => {
      setFlashIds((prev) => {
        const next = new Set(prev);
        next.delete(id);
        return next;
      });
    }, 4000);
  }, []);

  const handleWsEvent = useCallback(
    (event: ShopWsEvent) => {
      const raw = event as Record<string, unknown>;
      const type = (raw.type ?? raw.event) as string | undefined;

      if (type === 'new_order') {
        const orderId = Number(raw.order_id);
        if (!Number.isFinite(orderId)) return;

        const expiresAt = typeof raw.expires_at === 'string' ? Date.parse(raw.expires_at) : NaN;
        setExpires((prev) => ({
          ...prev,
          [orderId]: Number.isFinite(expiresAt) ? expiresAt : Date.now() + 5 * 60 * 1000,
        }));

        playNewOrderSound();
        flashOrder(orderId);
        setBanner(`Новый заказ ${typeof raw.number === 'string' ? raw.number : ''}`.trim());

        getShopOrder(orderId)
          .then((detail) => {
            setDetails((prev) => ({ ...prev, [orderId]: detail }));
            setLists((prev) =>
              prev.pending.some((o) => o.id === orderId)
                ? prev
                : { ...prev, pending: [summaryFromDetail(detail), ...prev.pending] },
            );
          })
          .catch(() => {
            // деталь не получили — просто перезагрузим входящие
            loadTab('pending').catch(() => undefined);
          });
        return;
      }

      if (type === 'order_cancelled') {
        const orderId = Number(raw.order_id);
        setLists((prev) => ({
          ...prev,
          pending: prev.pending.filter((o) => o.id !== orderId),
          active: prev.active.filter((o) => o.id !== orderId),
        }));
        setBanner('Заказ отменён клиентом');
        return;
      }

      if (type === 'photo_approved' || type === 'photo_rejected') {
        const orderId = Number(raw.order_id);
        if (!Number.isFinite(orderId)) return;
        setBanner(
          type === 'photo_approved'
            ? 'Клиент одобрил фото букета'
            : 'Клиент попросил переделать букет',
        );
        getShopOrder(orderId)
          .then((detail) => setDetails((prev) => ({ ...prev, [orderId]: detail })))
          .catch(() => loadTab('active').catch(() => undefined));
      }
    },
    [flashOrder, loadTab],
  );

  const wsConnected = useShopSocket(handleWsEvent);

  // Баннер прячем через 5 секунд
  useEffect(() => {
    if (!banner) return;
    const t = window.setTimeout(() => setBanner(''), 5000);
    return () => window.clearTimeout(t);
  }, [banner]);

  const handleAccept = useCallback(
    async (id: number, etaMinutes: number) => {
      await acceptOrder(id, etaMinutes);
      await Promise.all([loadTab('pending'), loadTab('active')]);
    },
    [loadTab],
  );

  const handleReject = useCallback(
    async (id: number, reason: string) => {
      await rejectOrder(id, reason);
      await loadTab('pending');
    },
    [loadTab],
  );

  const handleReady = useCallback(
    async (id: number) => {
      await markOrderReady(id);
      await loadTab('active');
    },
    [loadTab],
  );

  const handlePhotoUpload = useCallback(async (id: number, file: File) => {
    await uploadOrderPhoto(id, file);
    const detail = await getShopOrder(id);
    setDetails((prev) => ({ ...prev, [id]: detail }));
  }, []);

  const shopName =
    lists.pending[0]?.shop_name ?? lists.active[0]?.shop_name ?? lists.history[0]?.shop_name ?? '';

  const currentList = lists[tab];

  return (
    <div className="page">
      <header className="header">
        <div>
          <h1 className="header-title">{shopName || 'Панель магазина'}</h1>
          <span className="header-user">{user?.name ?? user?.phone}</span>
        </div>
        <div className="header-right">
          <span
            className={`ws-dot${wsConnected ? ' ws-dot-on' : ''}`}
            title={wsConnected ? 'WebSocket подключён' : 'WebSocket не подключён — обновление каждые 15 сек'}
          />
          <button className="btn btn-ghost" onClick={logout}>
            Выйти
          </button>
        </div>
      </header>

      <AppNav />

      {banner && <div className="banner">{banner}</div>}

      <nav className="tabs">
        {TABS.map((t) => (
          <button
            key={t.key}
            className={`tab${tab === t.key ? ' tab-active' : ''}`}
            onClick={() => setTab(t.key)}
          >
            {t.label}
            {t.key === 'pending' && lists.pending.length > 0 && (
              <span className="tab-badge">{lists.pending.length}</span>
            )}
          </button>
        ))}
      </nav>

      {error && <p className="form-error">{error}</p>}

      <main className="content">
        {loading && currentList.length === 0 ? (
          <p className="muted">Загрузка…</p>
        ) : currentList.length === 0 ? (
          <div className="card empty-state">
            {tab === 'pending' && 'Пока нет входящих заказов. Новые появятся автоматически.'}
            {tab === 'active' && 'Нет заказов в работе.'}
            {tab === 'history' && 'История заказов пуста.'}
          </div>
        ) : (
          <div className={tab === 'history' ? 'history-list' : 'cards-grid'}>
            {tab === 'pending' &&
              currentList.map((o) => (
                <PendingOrderCard
                  key={o.id}
                  summary={o}
                  detail={details[o.id]}
                  deadlineMs={expires[o.id] ?? Date.parse(o.created_at) + ESTIMATED_ACCEPT_WINDOW_MS}
                  flash={flashIds.has(o.id)}
                  onAccept={handleAccept}
                  onReject={handleReject}
                />
              ))}
            {tab === 'active' &&
              currentList.map((o) => (
                <ActiveOrderCard
                  key={o.id}
                  summary={o}
                  detail={details[o.id]}
                  onReady={handleReady}
                  onPhotoUpload={handlePhotoUpload}
                />
              ))}
            {tab === 'history' && currentList.map((o) => <HistoryOrderCard key={o.id} summary={o} />)}
          </div>
        )}
      </main>
    </div>
  );
}
