import React, { createContext, useCallback, useContext, useEffect, useState, ReactNode } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { api, onUnauthorized } from '@/lib/api/client';
import { ApiShop, ApiUser } from '@/lib/api/types';

type Status = 'loading' | 'signedOut' | 'signedIn';

interface SignUpInput {
  shopName: string;
  name: string;
  email: string;
  password: string;
  currency: string;
}

interface AuthContextType {
  status: Status;
  user: ApiUser | null;
  shop: ApiShop | null;
  isOwner: boolean;
  signIn: (email: string, password: string) => Promise<void>;
  signUp: (input: SignUpInput) => Promise<void>;
  signOut: () => Promise<void>;
  setShop: (shop: ApiShop) => void;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

interface SessionResponse {
  user: ApiUser;
  shop: ApiShop;
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const queryClient = useQueryClient();
  const [status, setStatus] = useState<Status>('loading');
  const [user, setUser] = useState<ApiUser | null>(null);
  const [shop, setShop] = useState<ApiShop | null>(null);

  const applySession = useCallback((session: SessionResponse) => {
    setUser(session.user);
    setShop(session.shop);
    setStatus('signedIn');
  }, []);

  const clearSession = useCallback(() => {
    setUser(null);
    setShop(null);
    setStatus('signedOut');
    // Never show one account's data to the next person who signs in.
    queryClient.clear();
  }, [queryClient]);

  // Restore the session from the cookie on load, refreshing it if needed.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const me = await api<SessionResponse>('GET', '/auth/me').catch(async () => {
          await api('POST', '/auth/refresh', {});
          return api<SessionResponse>('GET', '/auth/me');
        });
        if (!cancelled) applySession(me);
      } catch {
        if (!cancelled) setStatus('signedOut');
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [applySession]);

  useEffect(() => onUnauthorized(clearSession), [clearSession]);

  const signIn = async (email: string, password: string) => {
    applySession(await api<SessionResponse>('POST', '/auth/login', { email, password, client: 'web' }));
  };

  const signUp = async (input: SignUpInput) => {
    applySession(await api<SessionResponse>('POST', '/auth/signup', { ...input, client: 'web' }));
  };

  const signOut = async () => {
    await api('POST', '/auth/logout', {}).catch(() => undefined);
    clearSession();
  };

  return (
    <AuthContext.Provider
      value={{ status, user, shop, isOwner: user?.role === 'owner', signIn, signUp, signOut, setShop }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
