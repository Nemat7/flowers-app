import { useState } from 'react';
import type { FormEvent } from 'react';
import { useAuth } from '../auth/AuthContext';
import { ApiError } from '../api/client';

function normalizePhone(raw: string): string {
  let v = raw.replace(/[^\d+]/g, '');
  if (v.startsWith('992')) v = `+${v}`;
  if (!v.startsWith('+')) v = `+${v}`;
  return v;
}

export default function LoginPage() {
  const { requestCode, login } = useAuth();
  const [phone, setPhone] = useState('+992');
  const [code, setCode] = useState('');
  const [step, setStep] = useState<'phone' | 'code'>('phone');
  const [devCode, setDevCode] = useState<string | undefined>(undefined);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const submitPhone = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    setBusy(true);
    try {
      const dev = await requestCode(normalizePhone(phone));
      setDevCode(dev);
      setStep('code');
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Не удалось отправить код');
    } finally {
      setBusy(false);
    }
  };

  const submitCode = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    setBusy(true);
    try {
      await login(normalizePhone(phone), code.trim());
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Неверный код');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="auth-screen">
      <div className="card auth-card">
        <div className="auth-logo">Панель магазина</div>
        <p className="auth-subtitle">Flowers &amp; Sweets — Душанбе</p>

        {step === 'phone' ? (
          <form onSubmit={submitPhone}>
            <label className="field-label" htmlFor="phone">
              Номер телефона
            </label>
            <input
              id="phone"
              className="input"
              type="tel"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              placeholder="+992 XX XXX XXXX"
              autoFocus
            />
            <button className="btn btn-primary btn-block" type="submit" disabled={busy || phone.trim().length < 10}>
              {busy ? 'Отправляем…' : 'Получить код'}
            </button>
          </form>
        ) : (
          <form onSubmit={submitCode}>
            <label className="field-label" htmlFor="code">
              Код из SMS на {phone}
            </label>
            <input
              id="code"
              className="input input-code"
              type="text"
              inputMode="numeric"
              value={code}
              onChange={(e) => setCode(e.target.value)}
              placeholder="••••••"
              autoFocus
            />
            {import.meta.env.DEV && devCode && (
              <p className="dev-hint">dev-подсказка: код {devCode}</p>
            )}
            <button className="btn btn-primary btn-block" type="submit" disabled={busy || code.trim().length < 4}>
              {busy ? 'Проверяем…' : 'Войти'}
            </button>
            <button
              className="btn btn-ghost btn-block"
              type="button"
              onClick={() => {
                setStep('phone');
                setCode('');
                setError('');
              }}
            >
              Изменить номер
            </button>
          </form>
        )}

        {error && <p className="form-error">{error}</p>}
      </div>
    </div>
  );
}
