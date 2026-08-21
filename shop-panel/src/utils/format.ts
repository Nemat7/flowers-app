export function formatMoney(value: string | number): string {
  const n = typeof value === 'string' ? Number(value) : value;
  if (Number.isNaN(n)) return `${value} с.`;
  return `${n.toLocaleString('ru-RU')} с.`;
}

export function formatDateTime(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleString('ru-RU', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
}

export function formatPhone(phone: string): string {
  return phone;
}

const STATUS_LABELS: Record<string, string> = {
  created: 'Создан',
  paid: 'Оплачен',
  shop_pending: 'Новый',
  accepted: 'Принят',
  preparing: 'Готовится',
  ready: 'Готов',
  courier_assigned: 'Курьер назначен',
  picked_up: 'Курьер забрал',
  on_the_way: 'В пути',
  arrived: 'Курьер на месте',
  delivered: 'Доставлен',
  completed: 'Завершён',
  rejected: 'Отклонён',
  timeout: 'Таймаут',
  cancelled_client: 'Отменён клиентом',
  cancelled_admin: 'Отменён админом',
  expired: 'Истёк',
  disputed: 'Спор',
};

export function statusLabel(status: string): string {
  return STATUS_LABELS[status] ?? status;
}

export function statusKind(status: string): 'new' | 'progress' | 'done' | 'bad' {
  if (status === 'shop_pending') return 'new';
  if (['accepted', 'preparing', 'ready', 'courier_assigned', 'picked_up', 'on_the_way', 'arrived'].includes(status))
    return 'progress';
  if (['delivered', 'completed'].includes(status)) return 'done';
  return 'bad';
}

export function slotLabel(slotType: string, scheduledAt: string | null): string {
  if (slotType === 'scheduled' && scheduledAt) {
    return `Ко времени: ${formatDateTime(scheduledAt)}`;
  }
  return 'Как можно скорее';
}
