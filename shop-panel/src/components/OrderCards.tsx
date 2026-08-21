import { useEffect, useRef, useState } from 'react';
import type { OrderDetail, OrderSummary } from '../types';
import { formatMoney, slotLabel, statusKind, statusLabel } from '../utils/format';

// --- Таймер обратного отсчёта ---

export function Countdown({ deadlineMs }: { deadlineMs: number }) {
  const [leftMs, setLeftMs] = useState(() => deadlineMs - Date.now());

  useEffect(() => {
    const t = window.setInterval(() => setLeftMs(deadlineMs - Date.now()), 1000);
    return () => window.clearInterval(t);
  }, [deadlineMs]);

  const totalSec = Math.max(0, Math.floor(leftMs / 1000));
  const mm = String(Math.floor(totalSec / 60)).padStart(2, '0');
  const ss = String(totalSec % 60).padStart(2, '0');
  const urgent = totalSec > 0 && totalSec < 60;
  const overdue = totalSec === 0;

  return (
    <span className={`countdown${urgent ? ' countdown-urgent' : ''}${overdue ? ' countdown-overdue' : ''}`}>
      {overdue ? 'время вышло' : `${mm}:${ss}`}
    </span>
  );
}

// --- Общие куски карточки ---

function Items({ detail }: { detail?: OrderDetail }) {
  if (!detail) return <p className="muted">Загрузка состава…</p>;
  return (
    <ul className="items-list">
      {detail.items.map((item) => (
        <li key={item.id}>
          <span className="item-qty">{item.qty} ×</span> {item.product_name}
          <span className="item-price">{formatMoney(item.price)}</span>
        </li>
      ))}
    </ul>
  );
}

function CardText({ detail }: { detail?: OrderDetail }) {
  if (!detail?.card_text) return null;
  return (
    <div className="card-text">
      <span className="card-text-label">Текст открытки</span>
      <p>{detail.card_text}</p>
    </div>
  );
}

function OrderMeta({ summary, detail }: { summary: OrderSummary; detail?: OrderDetail }) {
  return (
    <div className="order-meta">
      <span>{slotLabel(summary.slot_type, summary.scheduled_at)}</span>
      {detail?.comment && <span className="order-comment">Комментарий: {detail.comment}</span>}
    </div>
  );
}

const ETA_OPTIONS = [15, 20, 30, 45];
const QUICK_REASONS = ['Нет нужных цветов в наличии', 'Магазин закрывается', 'Не успеем собрать вовремя'];

// --- Карточка входящего заказа ---

interface PendingCardProps {
  summary: OrderSummary;
  detail?: OrderDetail;
  deadlineMs: number;
  flash: boolean;
  onAccept: (id: number, etaMinutes: number) => Promise<void>;
  onReject: (id: number, reason: string) => Promise<void>;
}

export function PendingOrderCard({ summary, detail, deadlineMs, flash, onAccept, onReject }: PendingCardProps) {
  const [acceptOpen, setAcceptOpen] = useState(false);
  const [rejectOpen, setRejectOpen] = useState(false);
  const [eta, setEta] = useState(20);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const doAccept = async () => {
    setBusy(true);
    setError('');
    try {
      await onAccept(summary.id, eta);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Не удалось принять заказ');
      setBusy(false);
    }
  };

  const doReject = async () => {
    if (!reason.trim()) return;
    setBusy(true);
    setError('');
    try {
      await onReject(summary.id, reason.trim());
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Не удалось отклонить заказ');
      setBusy(false);
    }
  };

  return (
    <div className={`card order-card${flash ? ' order-card-flash' : ''}`}>
      <div className="order-card-head">
        <div>
          <span className="order-number">{summary.number}</span>
          <span className="order-total">{formatMoney(summary.total)}</span>
        </div>
        <Countdown deadlineMs={deadlineMs} />
      </div>

      <Items detail={detail} />
      <CardText detail={detail} />
      <OrderMeta summary={summary} detail={detail} />

      {error && <p className="form-error">{error}</p>}

      {acceptOpen && (
        <div className="action-panel">
          <span className="field-label">Время сборки (ETA)</span>
          <div className="chips">
            {ETA_OPTIONS.map((m) => (
              <button
                key={m}
                type="button"
                className={`chip${eta === m ? ' chip-active' : ''}`}
                onClick={() => setEta(m)}
              >
                {m} мин
              </button>
            ))}
          </div>
          <button className="btn btn-primary btn-block" onClick={doAccept} disabled={busy}>
            {busy ? 'Принимаем…' : `Принять заказ (${eta} мин)`}
          </button>
        </div>
      )}

      {rejectOpen && (
        <div className="action-panel">
          <span className="field-label">Причина отказа (обязательно)</span>
          <div className="chips">
            {QUICK_REASONS.map((r) => (
              <button
                key={r}
                type="button"
                className={`chip${reason === r ? ' chip-active' : ''}`}
                onClick={() => setReason(r)}
              >
                {r}
              </button>
            ))}
          </div>
          <textarea
            className="input textarea"
            rows={2}
            placeholder="Или напишите свою причину…"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
          />
          <button className="btn btn-danger btn-block" onClick={doReject} disabled={busy || !reason.trim()}>
            {busy ? 'Отклоняем…' : 'Отклонить заказ'}
          </button>
        </div>
      )}

      {!acceptOpen && !rejectOpen && (
        <div className="order-actions">
          <button
            className="btn btn-primary"
            onClick={() => {
              setAcceptOpen(true);
              setRejectOpen(false);
            }}
          >
            Принять
          </button>
          <button
            className="btn btn-outline"
            onClick={() => {
              setRejectOpen(true);
              setAcceptOpen(false);
            }}
          >
            Отклонить
          </button>
        </div>
      )}
      {(acceptOpen || rejectOpen) && !busy && (
        <button
          className="btn btn-ghost btn-block"
          onClick={() => {
            setAcceptOpen(false);
            setRejectOpen(false);
            setError('');
          }}
        >
          Свернуть
        </button>
      )}
    </div>
  );
}

// --- Карточка заказа в работе ---

interface ActiveCardProps {
  summary: OrderSummary;
  detail?: OrderDetail;
  onReady: (id: number) => Promise<void>;
  onPhotoUpload: (id: number, file: File) => Promise<void>;
}

// Фото букета можно отправить, пока заказ в сборке (backend: accepted..ready).
const PHOTO_STATUSES = new Set(['accepted', 'preparing', 'ready']);

export function ActiveOrderCard({ summary, detail, onReady, onPhotoUpload }: ActiveCardProps) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const canReady = summary.status === 'accepted' || summary.status === 'preparing';

  const fileInputRef = useRef<HTMLInputElement>(null);
  const [photoFile, setPhotoFile] = useState<File | null>(null);
  const [photoPreview, setPhotoPreview] = useState('');
  const [photoBusy, setPhotoBusy] = useState(false);
  const [photoError, setPhotoError] = useState('');

  const canPhoto = PHOTO_STATUSES.has(summary.status);
  const bouquet = detail?.bouquet_photo ?? null;

  const pickPhoto = (file: File | null) => {
    if (photoPreview) URL.revokeObjectURL(photoPreview);
    setPhotoFile(file);
    setPhotoPreview(file ? URL.createObjectURL(file) : '');
    setPhotoError('');
  };

  const doUploadPhoto = async () => {
    if (!photoFile) return;
    setPhotoBusy(true);
    setPhotoError('');
    try {
      await onPhotoUpload(summary.id, photoFile);
      pickPhoto(null);
      if (fileInputRef.current) fileInputRef.current.value = '';
    } catch (e) {
      setPhotoError(e instanceof Error ? e.message : 'Не удалось отправить фото');
    } finally {
      setPhotoBusy(false);
    }
  };

  const doReady = async () => {
    setBusy(true);
    setError('');
    try {
      await onReady(summary.id);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Не удалось отметить готовность');
      setBusy(false);
    }
  };

  return (
    <div className="card order-card">
      <div className="order-card-head">
        <div>
          <span className="order-number">{summary.number}</span>
          <span className={`badge badge-${statusKind(summary.status)}`}>{statusLabel(summary.status)}</span>
        </div>
        <span className="order-total">{formatMoney(summary.total)}</span>
      </div>

      <Items detail={detail} />
      <CardText detail={detail} />
      <OrderMeta summary={summary} detail={detail} />

      <div className="order-recipient">
        <div>
          <span className="field-label">Получатель</span>
          <p>
            {summary.recipient_name || '—'}
            {detail?.recipient_phone ? ` · ${detail.recipient_phone}` : ''}
          </p>
        </div>
        <div>
          <span className="field-label">Адрес</span>
          <p>
            {detail?.address?.address_text ?? '—'}
            {detail?.address?.details ? ` (${detail.address.details})` : ''}
          </p>
        </div>
        {detail?.courier && (
          <div>
            <span className="field-label">Курьер</span>
            <p>
              {detail.courier.name} · {detail.courier.phone}
            </p>
          </div>
        )}
      </div>

      {(canPhoto || bouquet) && (
        <div className="photo-panel">
          <span className="field-label">Фото букета</span>

          {bouquet && (
            <div className="photo-status">
              <img className="photo-thumb" src={bouquet.url} alt="Фото букета" />
              {bouquet.approved === null && (
                <span className="badge badge-progress">ждёт клиента</span>
              )}
              {bouquet.approved === true && (
                <span className="badge badge-done">✓ одобрено</span>
              )}
              {bouquet.approved === false && (
                <span className="badge badge-bad">переделать</span>
              )}
            </div>
          )}

          {photoPreview && (
            <div className="photo-preview">
              <img className="photo-thumb photo-thumb-large" src={photoPreview} alt="Предпросмотр" />
              <div className="order-actions">
                <button className="btn btn-primary" onClick={doUploadPhoto} disabled={photoBusy}>
                  {photoBusy ? 'Отправляем…' : 'Отправить клиенту'}
                </button>
                <button className="btn btn-ghost" onClick={() => pickPhoto(null)} disabled={photoBusy}>
                  Отмена
                </button>
              </div>
            </div>
          )}

          {photoError && <p className="form-error">{photoError}</p>}

          {canPhoto && !photoPreview && (
            <button
              className="btn btn-outline btn-block"
              onClick={() => fileInputRef.current?.click()}
            >
              {bouquet ? 'Отправить новое фото' : 'Фото букета'}
            </button>
          )}
          <input
            ref={fileInputRef}
            type="file"
            accept="image/*"
            hidden
            onChange={(e) => pickPhoto(e.target.files?.[0] ?? null)}
          />
        </div>
      )}

      {error && <p className="form-error">{error}</p>}

      {canReady && (
        <button className="btn btn-success btn-block" onClick={doReady} disabled={busy}>
          {busy ? 'Отправляем…' : 'Заказ готов'}
        </button>
      )}
    </div>
  );
}

// --- Строка истории ---

export function HistoryOrderCard({ summary }: { summary: OrderSummary }) {
  return (
    <div className="card history-row">
      <div className="history-main">
        <span className="order-number">{summary.number}</span>
        <span className={`badge badge-${statusKind(summary.status)}`}>{statusLabel(summary.status)}</span>
        <span className="muted">{summary.recipient_name || '—'}</span>
      </div>
      <div className="history-side">
        <span className="order-total">{formatMoney(summary.total)}</span>
      </div>
    </div>
  );
}
