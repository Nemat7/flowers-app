import { useCallback, useEffect, useState } from 'react';
import { useAuth } from '../auth/AuthContext';
import {
  deleteShopProduct,
  getCategories,
  getShopProducts,
  toggleProductAvailable,
} from '../api/client';
import type { Category, ShopProduct } from '../types';
import { formatMoney } from '../utils/format';
import AppNav from '../components/AppNav';
import ProductForm from '../components/ProductForm';

export default function ProductsPage() {
  const { state, logout } = useAuth();
  const user = state.status === 'authenticated' ? state.user : null;

  const [products, setProducts] = useState<ShopProduct[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [editing, setEditing] = useState<ShopProduct | 'new' | null>(null);
  const [toggling, setToggling] = useState<ReadonlySet<number>>(new Set());

  const load = useCallback(async () => {
    try {
      const [productList, categoryList] = await Promise.all([
        getShopProducts(),
        getCategories(),
      ]);
      setProducts(productList);
      setCategories(categoryList);
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

  const handleToggle = useCallback(async (product: ShopProduct) => {
    setToggling((prev) => new Set(prev).add(product.id));
    try {
      const res = await toggleProductAvailable(product.id);
      setProducts((prev) =>
        prev.map((p) => (p.id === product.id ? { ...p, is_available: res.is_available } : p)),
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Не удалось переключить наличие');
    } finally {
      setToggling((prev) => {
        const next = new Set(prev);
        next.delete(product.id);
        return next;
      });
    }
  }, []);

  const handleArchive = useCallback(
    async (product: ShopProduct) => {
      if (!window.confirm(`Убрать «${product.name}» в архив? Товар скроется из приложения.`)) {
        return;
      }
      try {
        await deleteShopProduct(product.id);
        setProducts((prev) =>
          prev.map((p) => (p.id === product.id ? { ...p, is_active: false } : p)),
        );
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Не удалось архивировать товар');
      }
    },
    [],
  );

  const active = products.filter((p) => p.is_active);
  const archived = products.filter((p) => !p.is_active);

  const renderCard = (p: ShopProduct) => {
    const photo = p.photos[0]?.image;
    return (
      <div key={p.id} className={`card product-card${p.is_active ? '' : ' product-archived'}`}>
        <div className="product-main">
          {photo ? (
            <img className="product-photo" src={photo} alt={p.name} />
          ) : (
            <div className="product-photo product-photo-empty">Нет фото</div>
          )}
          <div className="product-info">
            <span className="product-name">{p.name}</span>
            <span className="muted">{p.category_name}</span>
            {p.composition && <span className="muted product-composition">{p.composition}</span>}
          </div>
          <span className="order-total">{formatMoney(p.price)}</span>
        </div>
        <div className="product-actions">
          <label className="product-availability">
            <span className="switch">
              <input
                type="checkbox"
                checked={p.is_available}
                disabled={toggling.has(p.id) || !p.is_active}
                onChange={() => void handleToggle(p)}
              />
              <span className="switch-slider" />
            </span>
            В наличии
          </label>
          <button className="btn btn-ghost" onClick={() => setEditing(p)}>
            Изменить
          </button>
          {p.is_active && (
            <button className="btn btn-ghost product-archive" onClick={() => void handleArchive(p)}>
              В архив
            </button>
          )}
        </div>
      </div>
    );
  };

  return (
    <div className="page">
      <header className="header">
        <div>
          <h1 className="header-title">Товары</h1>
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
        <div className="products-toolbar">
          <button className="btn btn-primary" onClick={() => setEditing('new')}>
            Добавить товар
          </button>
        </div>

        {loading ? (
          <p className="muted">Загрузка…</p>
        ) : products.length === 0 ? (
          <div className="card empty-state">
            Пока нет товаров. Добавьте первый — он появится в приложении.
          </div>
        ) : (
          <>
            <div className="cards-grid">{active.map(renderCard)}</div>
            {archived.length > 0 && (
              <>
                <h2 className="archive-title muted">Архив</h2>
                <div className="cards-grid">{archived.map(renderCard)}</div>
              </>
            )}
          </>
        )}
      </main>

      {editing !== null && (
        <ProductForm
          product={editing === 'new' ? null : editing}
          categories={categories}
          onClose={() => setEditing(null)}
          onSaved={() => {
            setEditing(null);
            void load();
          }}
        />
      )}
    </div>
  );
}
