import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { supabase } from "./supabase";
import {
  fetchProfile,
  type AppProfile,
  signOut as authSignOut,
} from "./auth";

type AuthState = {
  loading: boolean;
  sessionUserId: string | null;
  profile: AppProfile | null;
  error: string | null;
  refresh: () => Promise<void>;
  signOut: () => Promise<void>;
};

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [loading, setLoading] = useState(true);
  const [sessionUserId, setSessionUserId] = useState<string | null>(null);
  const [profile, setProfile] = useState<AppProfile | null>(null);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setError(null);
    const { data } = await supabase.auth.getSession();
    const userId = data.session?.user?.id ?? null;
    setSessionUserId(userId);
    if (!userId) {
      setProfile(null);
      setLoading(false);
      return;
    }
    const result = await fetchProfile(userId);
    if (!result.ok) {
      setProfile(null);
      setError(result.error);
      await authSignOut();
      setSessionUserId(null);
      setLoading(false);
      return;
    }
    setProfile(result.profile);
    setLoading(false);
  }, []);

  useEffect(() => {
    void refresh();
    const { data: sub } = supabase.auth.onAuthStateChange(() => {
      void refresh();
    });
    return () => sub.subscription.unsubscribe();
  }, [refresh]);

  const signOut = useCallback(async () => {
    await authSignOut();
    setProfile(null);
    setSessionUserId(null);
  }, []);

  const value = useMemo(
    () => ({
      loading,
      sessionUserId,
      profile,
      error,
      refresh,
      signOut,
    }),
    [loading, sessionUserId, profile, error, refresh, signOut],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth debe usarse dentro de AuthProvider");
  return ctx;
}
