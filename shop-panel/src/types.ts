export interface User {
  id: number;
  phone: string;
  name: string;
  role: string;
}

export interface OrderSummary {
  id: number;
  number: string;
  status: string;
  shop: number;
  shop_name: string;
  slot_type: 'asap' | 'scheduled';
  total: string;
  created_at: string;
  recipient_name: string;
  scheduled_at: string | null;
  expires_at: string | null;
}

export interface OrderItem {
  id: number;
  product: number;
  product_name: string;
  price: string;
  qty: number;
  photo_url: string;
}

export interface OrderAddress {
  lat: number;
  lng: number;
  address_text: string;
  details: string;
}

export interface StatusHistoryEntry {
  status: string;
  comment: string;
  created_at: string;
}

export interface BouquetPhoto {
  url: string;
  approved: boolean | null;
}

export interface OrderDetail {
  id: number;
  number: string;
  status: string;
  shop: number;
  shop_name: string;
  courier: { name: string; phone: string } | null;
  items: OrderItem[];
  card_text: string;
  card_price: string;
  is_anonymous: boolean;
  recipient_name: string;
  recipient_phone: string | null;
  address: OrderAddress | null;
  slot_type: 'asap' | 'scheduled';
  scheduled_at: string | null;
  subtotal: string;
  delivery_fee: string;
  discount: string;
  total: string;
  cancel_reason: string;
  comment: string;
  bouquet_photo: BouquetPhoto | null;
  status_history: StatusHistoryEntry[];
  created_at: string;
}

export interface Paginated<T> {
  count: number;
  next: string | null;
  previous: string | null;
  results: T[];
}

export interface Category {
  id: number;
  name: string;
  slug: string;
  icon: string;
  sort_order: number;
}

export interface ShopProductPhoto {
  id: number;
  image: string;
  sort_order: number;
}

export interface ShopProduct {
  id: number;
  name: string;
  category: number;
  category_name: string;
  price: string;
  composition: string;
  description: string;
  is_available: boolean;
  is_active: boolean;
  tags: string[];
  sort_order: number;
  photos: ShopProductPhoto[];
  created_at: string;
  updated_at: string;
}

export interface WorkingHoursDay {
  weekday: number;
  open_time: string;
  close_time: string;
  is_day_off: boolean;
}

export type ShopWsEvent =
  | { type: 'new_order'; order_id: number; number: string; total: string; expires_at?: string }
  | { type: 'order_cancelled'; order_id: number; number?: string }
  | { type: 'photo_approved'; order_id: number; number?: string }
  | { type: 'photo_rejected'; order_id: number; number?: string }
  | { type?: string; [key: string]: unknown };

export interface FinanceSummary {
  balance: string;
  pending_payout: string;
  period: { from: string; to: string };
  accrued: string;
  commission: string;
  paid_out: string;
}

export type BalanceTransactionType = 'accrual' | 'commission' | 'payout' | 'adjustment';

export interface BalanceTransaction {
  id: number;
  created_at: string;
  type: BalanceTransactionType;
  amount: string;
  order_number: string | null;
  comment: string;
  balance_after: string;
}

export interface ShopPayout {
  id: number;
  amount: string;
  method: string;
  status: string;
  period_from: string;
  period_to: string;
  created_at: string;
  paid_at: string | null;
}
