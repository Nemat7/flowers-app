import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import type { User } from '../types';
import { clearTokens, getMe, hasTokens, requestOtp, setTokens, verifyOtp } from '../api/client';

type AuthState =
  | { status: 'loading' }
  | { status: 'unauthenticated' }
  | { status: 'no_access'; user: User }
  | { status: 'authenticated'; user: User };

interface AuthContextValue {
  state: AuthState;
  requestCode: (phone: string) => Promise<string | undefined>;
  login: (phone: string, code: string) => Promise<void>;
  logout: () => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

function stateFor(user: User): AuthState {
  return user.role === 'shop_staff'
    ? { status: 'authenticated', user }
    : { status: 'no_access', user };
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<AuthState>({ status: 'loading' });

  const logout = useCallback(() => {
    clearTokens();
    setState({ status: 'unauthenticated' });
  }, []);

  useEffect(() => {
    let cancelled = false;
    if (!hasTokens()) {
      setState({ status: 'unauthenticated' });
      return;
    }
    getMe()
      .then((user) => {
        if (!cancelled) setState(stateFor(user));
      })
      .catch(() => {
        if (!cancelled) setState({ status: 'unauthenticated' });
      });
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    const onUnauthorized = () => logout();
    window.addEventListener('shop-panel:unauthorized', onUnauthorized);
    return () => window.removeEventListener('shop-panel:unauthorized', onUnauthorized);
  }, [logout]);

  const requestCode = useCallback(async (phone: string) => {
    const res = await requestOtp(phone);
    return res.dev_code;
  }, []);

  const login = useCallback(async (phone: string, code: string) => {
    const res = await verifyOtp(phone, code);
    setTokens(res.access, res.refresh);
    setState(stateFor(res.user));
  }, []);

  const value = useMemo(
    () => ({ state, requestCode, login, logout }),
    [state, requestCode, login, logout],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth вне AuthProvider');
  return ctx;
}
