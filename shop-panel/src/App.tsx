import { useEffect } from 'react';
import type { ReactElement } from 'react';
import { Navigate, Route, Routes } from 'react-router-dom';
import { AuthProvider, useAuth } from './auth/AuthContext';
import LoginPage from './pages/LoginPage';
import NoAccessPage from './pages/NoAccessPage';
import OrdersPage from './pages/OrdersPage';
import ProductsPage from './pages/ProductsPage';
import HoursPage from './pages/HoursPage';
import FinancePage from './pages/FinancePage';
import { unlockAudio } from './utils/sound';

function AppRoutes() {
  const { state } = useAuth();

  if (state.status === 'loading') {
    return (
      <div className="auth-screen">
        <p className="muted">Загрузка…</p>
      </div>
    );
  }

  const guard = (element: ReactElement) =>
    state.status === 'authenticated' ? (
      element
    ) : state.status === 'no_access' ? (
      <Navigate to="/no-access" replace />
    ) : (
      <Navigate to="/login" replace />
    );

  return (
    <Routes>
      <Route
        path="/login"
        element={state.status === 'unauthenticated' ? <LoginPage /> : <Navigate to="/orders" replace />}
      />
      <Route path="/no-access" element={<NoAccessPage />} />
      <Route path="/orders" element={guard(<OrdersPage />)} />
      <Route path="/products" element={guard(<ProductsPage />)} />
      <Route path="/hours" element={guard(<HoursPage />)} />
      <Route path="/finance" element={guard(<FinancePage />)} />
      <Route path="*" element={<Navigate to="/orders" replace />} />
    </Routes>
  );
}

export default function App() {
  // Разблокировка AudioContext по первому клику (autoplay-политика браузеров)
  useEffect(() => {
    const unlock = () => unlockAudio();
    document.addEventListener('pointerdown', unlock);
    document.addEventListener('keydown', unlock);
    return () => {
      document.removeEventListener('pointerdown', unlock);
      document.removeEventListener('keydown', unlock);
    };
  }, []);

  return (
    <AuthProvider>
      <AppRoutes />
    </AuthProvider>
  );
}
