import type { Paginated, User } from '../types';

const API_URL: string = import.meta.env.VITE_API_URL ?? 'http://localhost:8000/api/v1';

const ACCESS_KEY = 'shop_panel_access';
const REFRESH_KEY = 'shop_panel_refresh';

export class ApiError extends Error {
  status: number;
  code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export function getAccessToken(): string | null {
  return localStorage.getItem(ACCESS_KEY);
}

export function setTokens(access: string, refresh: string) {
  localStorage.setItem(ACCESS_KEY, access);
  localStorage.setItem(REFRESH_KEY, refresh);
}

export function clearTokens() {
  localStorage.removeItem(ACCESS_KEY);
  localStorage.removeItem(REFRESH_KEY);
}

export function hasTokens(): boolean {
  return Boolean(localStorage.getItem(ACCESS_KEY) && localStorage.getItem(REFRESH_KEY));
}

let refreshPromise: Promise<boolean> | null = null;

function refreshTokens(): Promise<boolean> {
  if (!refreshPromise) {
    refreshPromise = (async () => {
      const refresh = localStorage.getItem(REFRESH_KEY);
      if (!refresh) return false;
      try {
        const res = await fetch(`${API_URL}/auth/refresh/`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ refresh }),
        });
        if (!res.ok) return false;
        const data = (await res.json()) as { access: string; refresh?: string };
        localStorage.setItem(ACCESS_KEY, data.access);
        if (data.refresh) localStorage.setItem(REFRESH_KEY, data.refresh);
        return true;
      } catch {
        return false;
      }
    })().finally(() => {
      refreshPromise = null;
    });
  }
  return refreshPromise;
}

async function parseError(res: Response): Promise<ApiError> {
  let code = 'error';
  let message = `Ошибка ${res.status}`;
  try {
    const body = await res.json();
    if (body?.error) {
      code = body.error.code ?? code;
      message = body.error.message ?? message;
    } else if (body?.detail) {
      message = body.detail;
    }
  } catch {
    // тело не JSON — оставляем дефолт
  }
  return new ApiError(res.status, code, message);
}

export async function apiFetch<T>(path: string, options: RequestInit = {}, allowRetry = true): Promise<T> {
  const access = getAccessToken();
  const headers = new Headers(options.headers);
  if (options.body != null && !(options.body instanceof FormData)) {
    headers.set('Content-Type', 'application/json');
  }
  if (access) headers.set('Authorization', `Bearer ${access}`);

  let res: Response;
  try {
    res = await fetch(`${API_URL}${path}`, { ...options, headers });
  } catch {
    throw new ApiError(0, 'network', 'Нет соединения с сервером');
  }

  if (res.status === 401 && allowRetry) {
    const ok = await refreshTokens();
    if (ok) return apiFetch<T>(path, options, false);
    clearTokens();
    window.dispatchEvent(new Event('shop-panel:unauthorized'));
    throw new ApiError(401, 'unauthorized', 'Сессия истекла');
  }

  if (!res.ok) throw await parseError(res);
  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

// --- Auth ---

export interface OtpRequestResponse {
  detail?: string;
  dev_code?: string;
}

export interface OtpVerifyResponse {
  access: string;
  refresh: string;
  user: User;
}

export function requestOtp(phone: string): Promise<OtpRequestResponse> {
  return apiFetch<OtpRequestResponse>('/auth/otp/request/', {
    method: 'POST',
    body: JSON.stringify({ phone }),
  });
}

export function verifyOtp(phone: string, code: string): Promise<OtpVerifyResponse> {
  return apiFetch<OtpVerifyResponse>('/auth/otp/verify/', {
    method: 'POST',
    body: JSON.stringify({ phone, code }),
  });
}

export function getMe(): Promise<User> {
  return apiFetch<User>('/users/me/');
}

// --- Заказы магазина ---

import type { BouquetPhoto, OrderDetail, OrderSummary } from '../types';

export type ShopOrderFilter = 'pending' | 'active' | 'history';

export function getShopOrders(status: ShopOrderFilter): Promise<Paginated<OrderSummary>> {
  return apiFetch<Paginated<OrderSummary>>(`/shop/orders/?status=${status}`);
}

export function getShopOrder(id: number): Promise<OrderDetail> {
  return apiFetch<OrderDetail>(`/shop/orders/${id}/`);
}

export function acceptOrder(id: number, etaMinutes: number): Promise<unknown> {
  return apiFetch(`/shop/orders/${id}/accept/`, {
    method: 'POST',
    body: JSON.stringify({ eta_minutes: etaMinutes }),
  });
}

export function rejectOrder(id: number, reason: string): Promise<unknown> {
  return apiFetch(`/shop/orders/${id}/reject/`, {
    method: 'POST',
    body: JSON.stringify({ reason }),
  });
}

export function markOrderReady(id: number): Promise<unknown> {
  return apiFetch(`/shop/orders/${id}/ready/`, { method: 'POST' });
}

export function uploadOrderPhoto(id: number, file: File): Promise<BouquetPhoto> {
  const form = new FormData();
  form.append('image', file);
  return apiFetch<BouquetPhoto>(`/shop/orders/${id}/photo/`, {
    method: 'POST',
    body: form,
  });
}

// --- Каталог магазина ---

import type { Category, ShopProduct, ShopProductPhoto, WorkingHoursDay } from '../types';

export function getCategories(): Promise<Category[]> {
  return apiFetch<Category[]>('/categories/');
}

export function getShopProducts(): Promise<ShopProduct[]> {
  return apiFetch<ShopProduct[]>('/shop/products/');
}

export interface ShopProductPayload {
  name: string;
  category: number;
  price: string;
  composition: string;
  description: string;
  tags: string[];
  sort_order: number;
}

export function createShopProduct(data: ShopProductPayload): Promise<ShopProduct> {
  return apiFetch<ShopProduct>('/shop/products/', {
    method: 'POST',
    body: JSON.stringify(data),
  });
}

export function updateShopProduct(
  id: number,
  data: Partial<ShopProductPayload>,
): Promise<ShopProduct> {
  return apiFetch<ShopProduct>(`/shop/products/${id}/`, {
    method: 'PATCH',
    body: JSON.stringify(data),
  });
}

export function deleteShopProduct(id: number): Promise<void> {
  return apiFetch<void>(`/shop/products/${id}/`, { method: 'DELETE' });
}

export function toggleProductAvailable(
  id: number,
): Promise<{ id: number; is_available: boolean }> {
  return apiFetch(`/shop/products/${id}/toggle-available/`, { method: 'POST' });
}

export function uploadProductPhotos(id: number, files: File[]): Promise<ShopProductPhoto[]> {
  const form = new FormData();
  files.forEach((file) => form.append('photos', file));
  return apiFetch<ShopProductPhoto[]>(`/shop/products/${id}/photos/`, {
    method: 'POST',
    body: form,
  });
}

export function deleteProductPhoto(productId: number, photoId: number): Promise<void> {
  return apiFetch<void>(`/shop/products/${productId}/photos/${photoId}/`, {
    method: 'DELETE',
  });
}

// --- Часы работы ---

export function getShopHours(): Promise<WorkingHoursDay[]> {
  return apiFetch<WorkingHoursDay[]>('/shop/hours/');
}

export function putShopHours(days: WorkingHoursDay[]): Promise<WorkingHoursDay[]> {
  return apiFetch<WorkingHoursDay[]>('/shop/hours/', {
    method: 'PUT',
    body: JSON.stringify(days),
  });
}

// --- Финансы магазина ---

import type { BalanceTransaction, FinanceSummary, ShopPayout } from '../types';

export function getFinanceSummary(from: string, to: string): Promise<FinanceSummary> {
  return apiFetch<FinanceSummary>(`/shop/finance/summary/?from=${from}&to=${to}`);
}

export function getFinanceTransactions(
  from: string,
  to: string,
  page: number,
): Promise<Paginated<BalanceTransaction>> {
  return apiFetch<Paginated<BalanceTransaction>>(
    `/shop/finance/transactions/?from=${from}&to=${to}&page=${page}`,
  );
}

export function getFinancePayouts(): Promise<Paginated<ShopPayout>> {
  return apiFetch<Paginated<ShopPayout>>('/shop/finance/payouts/');
}
