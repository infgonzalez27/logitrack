import { useCallback, useState } from "react";
import { useFocusEffect } from "expo-router";
import { useAuth } from "@/lib/auth-context";
import {
  listOrdenesForProfile,
  type OrdenListaItem,
} from "@/lib/ordenes";

export interface UseOrdenesListResult {
  ordenes: OrdenListaItem[];
  loading: boolean;
  refreshing: boolean;
  error: string | null;
  puedeCrear: boolean;
  refresh: () => void;
  retry: () => void;
}

export function useOrdenesList(): UseOrdenesListResult {
  const { profile } = useAuth();
  const [ordenes, setOrdenes] = useState<OrdenListaItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(
    async (mode: "initial" | "refresh") => {
      if (!profile) return;
      if (mode === "refresh") setRefreshing(true);
      else setLoading(true);
      setError(null);

      const res = await listOrdenesForProfile(profile);
      if (!res.ok) {
        setError(res.error);
        setOrdenes([]);
      } else {
        setOrdenes(res.ordenes);
      }
      setLoading(false);
      setRefreshing(false);
    },
    [profile],
  );

  useFocusEffect(
    useCallback(() => {
      void load("initial");
    }, [load]),
  );

  const refresh = useCallback(() => {
    void load("refresh");
  }, [load]);

  const retry = useCallback(() => {
    void load("initial");
  }, [load]);

  const puedeCrear =
    profile?.rol === "vendedor" ||
    profile?.rol === "gerente" ||
    profile?.rol === "admin";

  return {
    ordenes,
    loading,
    refreshing,
    error,
    puedeCrear,
    refresh,
    retry,
  };
}
