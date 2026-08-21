import { useCallback, useEffect, useState } from 'react';
import { useAuth } from '../auth/AuthContext';
import { getShopHours, putShopHours } from '../api/client';
import type { WorkingHoursDay } from '../types';
import AppNav from '../components/AppNav';

const WEEKDAYS = [
  'Понедельник',
  'Вторник',
  'Среда',
  'Четверг',
  'Пятница',
  'Суббота',
  'Воскресенье',
];

const DEFAULT_OPEN = '09:00';
const DEFAULT_CLOSE = '20:00';

/** "09:00:00" → "09:00" для input type=time. */
function hhmm(value: string): string {
  return value.slice(0, 5);
}

export default function HoursPage() {
  const { state, logout } = useAuth();
  const user = state.status === 'authenticated' ? state.user : null;

  const [days, setDays] = useState<WorkingHoursDay[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [saved, setSaved] = useState(false);

  const load = useCallback(async () => {
    try {
      const savedDays = await getShopHours();
      // backend хранит только записанные дни — недостающие заполняем дефолтом
      const byWeekday = new Map(savedDays.map((d) => [d.weekday, d]));
      setDays(
        Array.from({ length: 7 }, (_, weekday) => {
          const savedDay = byWeekday.get(weekday);
          return savedDay
            ? {
                ...savedDay,
                open_time: hhmm(savedDay.open_time),
                close_time: hhmm(savedDay.close_time),
              }
            : {
                weekday,
                open_time: DEFAULT_OPEN,
                close_time: DEFAULT_CLOSE,
                is_day_off: false,
              };
        }),
      );
      setError('');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Ошибка загрузки');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  // Баннер «Сохранено» прячем через 4 секунды
  useEffect(() => {
    if (!saved) return;
    const t = window.setTimeout(() => setSaved(false), 4000);
    return () => window.clearTimeout(t);
  }, [saved]);

  const updateDay = (weekday: number, patch: Partial<WorkingHoursDay>) => {
    setDays((prev) => prev.map((d) => (d.weekday === weekday ? { ...d, ...patch } : d)));
  };

  const handleSave = async () => {
    setError('');
    setSaving(true);
    try {
      await putShopHours(days);
      setSaved(true);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Не удалось сохранить');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="page">
      <header className="header">
        <div>
          <h1 className="header-title">Часы работы</h1>
          <span className="header-user">{user?.name ?? user?.phone}</span>
        </div>
        <div className="header-right">
          <button className="btn btn-ghost" onClick={logout}>
            Выйти
          </button>
        </div>
      </header>

      <AppNav />

      {saved && <div className="banner">Часы работы сохранены</div>}
      {error && <p className="form-error">{error}</p>}

      <main className="content">
        {loading ? (
          <p className="muted">Загрузка…</p>
        ) : (
          <>
            <div className="hours-list">
              {days.map((d) => (
                <div key={d.weekday} className="card hours-row">
                  <span className="hours-day">{WEEKDAYS[d.weekday]}</span>
                  <label className="hours-off">
                    <input
                      type="checkbox"
                      checked={d.is_day_off}
                      onChange={(e) => updateDay(d.weekday, { is_day_off: e.target.checked })}
                    />
                    Выходной
                  </label>
                  <div className="hours-times">
                    <input
                      type="time"
                      className="input hours-time"
                      value={d.open_time}
                      disabled={d.is_day_off}
                      onChange={(e) => updateDay(d.weekday, { open_time: e.target.value })}
                    />
                    <span className="muted">—</span>
                    <input
                      type="time"
                      className="input hours-time"
                      value={d.close_time}
                      disabled={d.is_day_off}
                      onChange={(e) => updateDay(d.weekday, { close_time: e.target.value })}
                    />
                  </div>
                </div>
              ))}
            </div>
            <button
              className="btn btn-primary hours-save"
              onClick={() => void handleSave()}
              disabled={saving}
            >
              {saving ? 'Сохранение…' : 'Сохранить'}
            </button>
          </>
        )}
      </main>
    </div>
  );
}
