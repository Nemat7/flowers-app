import { useCallback, useEffect, useMemo, useState } from 'react';
import { useAuth } from '../auth/AuthContext';
import {
  getFinancePayouts,
  getFinanceSummary,
  getFinanceTransactions,
} from '../api/client';
import type {
  BalanceTransaction,
  BalanceTransactionType,
  FinanceSummary,
  Paginated,
  ShopPayout,
} from '../types';
import { formatDateTime, formatMoney } from '../utils/format';
import AppNav from '../components/AppNav';

const TXN_TYPE_LABELS: Record<BalanceTransactionType, string> = {
  accrual: 'Начисление',
  commission: 'Комиссия',
  payout: 'Выплата',
  adjustment: 'Корректировка',
};

const TXN_TYPE_BADGES: Record<BalanceTransactionType, string> = {
  accrual: 'badge-done',
  commission: 'badge-progress',
  payout: 'badge-bad',
  adjustment: 'badge-new',
};

const PAYOUT_STATUS_LABELS: Record<string, string> = {
  pending: 'Ожидает',
  paid: 'Выплачена',
  failed: 'Ошибка',
};

const PAYOUT_METHOD_LABELS: Record<string, string> = {
  alif: 'Алиф',
  dc: 'Душанбе Сити',
  bank: 'Банк',
  cash: 'Наличные',
};

const MONTH_FORMATTER = new Intl.DateTimeFormat('ru-RU', {
  month: 'long',
  year: 'numeric',
});

function toIso(d: Date): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/** Период выбранного месяца: для текущего — по сегодня, для прошлых — целиком. */
function monthPeriod(month: Date): { from: string; to: string; isCurrent: boolean } {
  const now = new Date();
  const isCurrent =
    month.getFullYear() === now.getFullYear() && month.getMonth() === now.getMonth();
  const from = new Date(month.getFullYear(), month.getMonth(), 1);
  const to = isCurrent
    ? now
    : new Date(month.getFullYear(), month.getMonth() + 1, 0);
  return { from: toIso(from), to: toIso(to), isCurrent };
}

function shiftMonth(month: Date, delta: number): Date {
  return new Date(month.getFullYear(), month.getMonth() + delta, 1);
}

export default function FinancePage() {
  const { state, logout } = useAuth();
  const user = state.status === 'authenticated' ? state.user : null;

  const [month, setMonth] = useState(() => {
    const now = new Date();
    return new Date(now.getFullYear(), now.getMonth(), 1);
  });
  const [summary, setSummary] = useState<FinanceSummary | null>(null);
  const [txns, setTxns] = useState<Paginated<BalanceTransaction> | null>(null);
  const [payouts, setPayouts] = useState<ShopPayout[]>([]);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const period = useMemo(() => monthPeriod(month), [month]);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [summaryData, txnData, payoutData] = await Promise.all([
        getFinanceSummary(period.from, period.to),
        getFinanceTransactions(period.from, period.to, page),
        getFinancePayouts(),
      ]);
      setSummary(summaryData);
      setTxns(txnData);
      setPayouts(payoutData.results);
      setError('');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Ошибка загрузки');
    } finally {
      setLoading(false);
    }
  }, [period.from, period.to, page]);

  useEffect(() => {
    void load();
  }, [load]);

  const changeMonth = (delta: number) => {
    setMonth((m) => shiftMonth(m, delta));
    setPage(1);
  };

  return (
    <div className="page">
      <header className="header">
        <div>
          <h1 className="header-title">Финансы</h1>
          <span className="header-user">{user?.name ?? user?.phone}</span>
        </div>
        <div className="header-right">
          <button className="btn btn-ghost" onClick={logout}>
            Выйти
          </button>
        </div>
      </header>

      <AppNav />

      {error && <p className="form-error">{error}</p>}

      <main className="content">
        <div className="finance-period">
          <button className="btn btn-ghost" onClick={() => changeMonth(-1)}>
            ←
          </button>
          <span className="finance-period-label">
            {MONTH_FORMATTER.format(month)}
          </span>
          <button
            className="btn btn-ghost"
            onClick={() => changeMonth(1)}
            disabled={period.isCurrent}
          >
            →
          </button>
        </div>

        <div className="finance-grid">
          <div className="card finance-balance">
            <span className="muted">Текущий баланс</span>
            <span className="finance-balance-value">
              {summary ? formatMoney(summary.balance) : '—'}
            </span>
            <span className="muted">
              К выплате: {summary ? formatMoney(summary.pending_payout) : '—'}
            </span>
          </div>
          <div className="card finance-mini">
            <span className="muted">Начислено за месяц</span>
            <span className="finance-mini-value finance-plus">
              {summary ? `+${formatMoney(summary.accrued)}` : '—'}
            </span>
          </div>
          <div className="card finance-mini">
            <span className="muted">Комиссия платформы</span>
            <span className="finance-mini-value finance-minus">
              {summary ? `−${formatMoney(summary.commission)}` : '—'}
            </span>
          </div>
          <div className="card finance-mini">
            <span className="muted">Выплачено</span>
            <span className="finance-mini-value">
              {summary ? formatMoney(summary.paid_out) : '—'}
            </span>
          </div>
        </div>

        <h2 className="finance-section-title">Транзакции</h2>
        {loading && !txns ? (
          <p className="muted">Загрузка…</p>
        ) : !txns || txns.results.length === 0 ? (
          <div className="card empty-state">За этот период транзакций нет.</div>
        ) : (
          <div className="card finance-table-card">
            <table className="finance-table">
              <thead>
                <tr>
                  <th>Дата</th>
                  <th>Тип</th>
                  <th>Сумма</th>
                  <th>Заказ</th>
                  <th>Комментарий</th>
                  <th>Баланс</th>
                </tr>
              </thead>
              <tbody>
                {txns.results.map((t) => {
                  const negative = Number(t.amount) < 0;
                  return (
                    <tr key={t.id}>
                      <td className="muted">{formatDateTime(t.created_at)}</td>
                      <td>
                        <span className={`badge ${TXN_TYPE_BADGES[t.type]}`}>
                          {TXN_TYPE_LABELS[t.type]}
                        </span>
                      </td>
                      <td className={negative ? 'finance-minus' : 'finance-plus'}>
                        {negative ? '−' : '+'}
                        {formatMoney(Math.abs(Number(t.amount)))}
                      </td>
                      <td>{t.order_number ?? '—'}</td>
                      <td className="muted">{t.comment}</td>
                      <td>{formatMoney(t.balance_after)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
            <div className="finance-pagination">
              <button
                className="btn btn-ghost"
                disabled={!txns.previous}
                onClick={() => setPage((p) => p - 1)}
              >
                ← Назад
              </button>
              <span className="muted">
                Страница {page} · всего {txns.count}
              </span>
              <button
                className="btn btn-ghost"
                disabled={!txns.next}
                onClick={() => setPage((p) => p + 1)}
              >
                Вперёд →
              </button>
            </div>
          </div>
        )}

        <h2 className="finance-section-title">История выплат</h2>
        {payouts.length === 0 ? (
          <div className="card empty-state">Выплат пока не было.</div>
        ) : (
          <div className="history-list">
            {payouts.map((p) => (
              <div key={p.id} className="card history-row">
                <div>
                  <div>{formatMoney(p.amount)}</div>
                  <span className="muted">
                    {PAYOUT_METHOD_LABELS[p.method] ?? p.method} · период{' '}
                    {p.period_from} — {p.period_to}
                  </span>
                </div>
                <span
                  className={`badge ${
                    p.status === 'paid'
                      ? 'badge-done'
                      : p.status === 'failed'
                        ? 'badge-bad'
                        : 'badge-progress'
                  }`}
                >
                  {PAYOUT_STATUS_LABELS[p.status] ?? p.status}
                </span>
              </div>
            ))}
          </div>
        )}
      </main>
    </div>
  );
}
