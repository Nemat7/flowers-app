import { useEffect, useRef, useState } from 'react';
import type { FormEvent } from 'react';
import {
  createShopProduct,
  deleteProductPhoto,
  updateShopProduct,
  uploadProductPhotos,
  type ShopProductPayload,
} from '../api/client';
import type { Category, ShopProduct, ShopProductPhoto } from '../types';

const MAX_PHOTOS = 5;

interface NewFile {
  file: File;
  url: string;
}

interface Props {
  product: ShopProduct | null; // null — создание нового
  categories: Category[];
  onClose: () => void;
  onSaved: () => void;
}

/** Форма товара (создание/правка) с фото до 5 штук и превью. */
export default function ProductForm({ product, categories, onClose, onSaved }: Props) {
  const [name, setName] = useState(product?.name ?? '');
  const [categoryId, setCategoryId] = useState<number>(product?.category ?? categories[0]?.id ?? 0);
  const [price, setPrice] = useState(product?.price ?? '');
  const [composition, setComposition] = useState(product?.composition ?? '');
  const [description, setDescription] = useState(product?.description ?? '');
  const [photos, setPhotos] = useState<ShopProductPhoto[]>(product?.photos ?? []);
  const [newFiles, setNewFiles] = useState<NewFile[]>([]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const fileInputRef = useRef<HTMLInputElement>(null);

  // превью — objectURL, чистим при размонтировании
  useEffect(
    () => () => {
      newFiles.forEach((f) => URL.revokeObjectURL(f.url));
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [],
  );

  const totalPhotos = photos.length + newFiles.length;

  const addFiles = (files: FileList | null) => {
    if (!files) return;
    const room = MAX_PHOTOS - totalPhotos;
    const added: NewFile[] = Array.from(files)
      .slice(0, room)
      .map((file) => ({ file, url: URL.createObjectURL(file) }));
    if (added.length < files.length) setError(`Не больше ${MAX_PHOTOS} фото на товар`);
    else setError('');
    setNewFiles((prev) => [...prev, ...added]);
    if (fileInputRef.current) fileInputRef.current.value = '';
  };

  const removeNewFile = (index: number) => {
    setNewFiles((prev) => {
      URL.revokeObjectURL(prev[index].url);
      return prev.filter((_, i) => i !== index);
    });
  };

  const removePhoto = async (photoId: number) => {
    if (!product) return;
    try {
      await deleteProductPhoto(product.id, photoId);
      setPhotos((prev) => prev.filter((p) => p.id !== photoId));
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Не удалось удалить фото');
    }
  };

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    setSaving(true);
    const payload: ShopProductPayload = {
      name: name.trim(),
      category: categoryId,
      price,
      composition: composition.trim(),
      description: description.trim(),
      tags: product?.tags ?? [],
      sort_order: product?.sort_order ?? 0,
    };
    try {
      const saved = product
        ? await updateShopProduct(product.id, payload)
        : await createShopProduct(payload);
      if (newFiles.length > 0) {
        await uploadProductPhotos(
          saved.id,
          newFiles.map((f) => f.file),
        );
      }
      onSaved();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Не удалось сохранить товар');
      setSaving(false);
    }
  };

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="card modal" onClick={(e) => e.stopPropagation()}>
        <h2 className="modal-title">{product ? 'Правка товара' : 'Новый товар'}</h2>
        <form onSubmit={handleSubmit} className="product-form">
          <div>
            <label className="field-label" htmlFor="pf-name">Название</label>
            <input
              id="pf-name"
              className="input"
              value={name}
              onChange={(e) => setName(e.target.value)}
              maxLength={150}
              required
            />
          </div>
          <div className="product-form-row">
            <div>
              <label className="field-label" htmlFor="pf-category">Категория</label>
              <select
                id="pf-category"
                className="input"
                value={categoryId}
                onChange={(e) => setCategoryId(Number(e.target.value))}
                required
              >
                {categories.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="field-label" htmlFor="pf-price">Цена, сомони</label>
              <input
                id="pf-price"
                className="input"
                type="number"
                min="0"
                step="0.01"
                value={price}
                onChange={(e) => setPrice(e.target.value)}
                required
              />
            </div>
          </div>
          <div>
            <label className="field-label" htmlFor="pf-composition">Состав</label>
            <input
              id="pf-composition"
              className="input"
              value={composition}
              onChange={(e) => setComposition(e.target.value)}
              maxLength={500}
              placeholder="15 роз, эвкалипт, упаковка"
            />
          </div>
          <div>
            <label className="field-label" htmlFor="pf-description">Описание</label>
            <textarea
              id="pf-description"
              className="input textarea"
              rows={3}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
          </div>
          <div>
            <label className="field-label">Фото ({totalPhotos}/{MAX_PHOTOS})</label>
            <div className="photo-previews">
              {photos.map((p) => (
                <div key={p.id} className="photo-preview">
                  <img src={p.image} alt="" />
                  <button
                    type="button"
                    className="photo-remove"
                    title="Удалить фото"
                    onClick={() => void removePhoto(p.id)}
                  >
                    ×
                  </button>
                </div>
              ))}
              {newFiles.map((f, i) => (
                <div key={f.url} className="photo-preview">
                  <img src={f.url} alt="" />
                  <button
                    type="button"
                    className="photo-remove"
                    title="Убрать"
                    onClick={() => removeNewFile(i)}
                  >
                    ×
                  </button>
                </div>
              ))}
              {totalPhotos < MAX_PHOTOS && (
                <button
                  type="button"
                  className="photo-add"
                  onClick={() => fileInputRef.current?.click()}
                >
                  +
                </button>
              )}
            </div>
            <input
              ref={fileInputRef}
              type="file"
              accept="image/*"
              multiple
              hidden
              onChange={(e) => addFiles(e.target.files)}
            />
          </div>
          {error && <p className="form-error">{error}</p>}
          <div className="product-form-actions">
            <button type="button" className="btn btn-ghost" onClick={onClose} disabled={saving}>
              Отмена
            </button>
            <button type="submit" className="btn btn-primary" disabled={saving}>
              {saving ? 'Сохранение…' : 'Сохранить'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
