import { useAuth } from '../auth/AuthContext';

export default function NoAccessPage() {
  const { state, logout } = useAuth();
  const phone = state.status === 'no_access' ? state.user.phone : '';

  return (
    <div className="auth-screen">
      <div className="card auth-card">
        <div className="auth-logo">Нет доступа</div>
        <p className="auth-subtitle">
          Аккаунт {phone} не привязан к магазину. Доступ к панели есть только у сотрудников
          магазина — обратитесь к администратору.
        </p>
        <button className="btn btn-primary btn-block" onClick={logout}>
          Выйти
        </button>
      </div>
    </div>
  );
}
