import { useCallback, useMemo, useState } from "react";
import {
  FlatList,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { useFocusEffect, useRouter, type Href } from "expo-router";
import { useAuth } from "@/lib/auth-context";
import {
  listClientesForProfile,
  type ClienteListaItem,
} from "@/lib/clientes";
import {
  retornaOrdenesPorLiquidar,
  type OrdenPorLiquidarCliente,
} from "@/lib/rendiciones";
import { formatMoney } from "@/lib/format";
import {
  EmptyState,
  ErrorText,
  LoadingBlock,
  SectionTitle,
} from "@/components/ui";

type CarteraRow = {
  cliente_id: string;
  razon_social: string;
  rif_nit: string;
  monto_por_liquidar: number;
  cant_ordenes: number;
  dias_vencidos: number;
};

export default function VisitaCarteraScreen() {
  const { profile } = useAuth();
  const router = useRouter();
  const [q, setQ] = useState("");
  const [appliedQ, setAppliedQ] = useState("");
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [cartera, setCartera] = useState<OrdenPorLiquidarCliente[]>([]);
  const [clientes, setClientes] = useState<ClienteListaItem[]>([]);
  const [mode, setMode] = useState<"cartera" | "todos">("cartera");

  const load = useCallback(async () => {
    if (!profile) return;
    setError(null);
    const [cRes, cliRes] = await Promise.all([
      retornaOrdenesPorLiquidar(),
      listClientesForProfile(profile),
    ]);
    if (!cRes.ok) setError(cRes.error);
    else setCartera(cRes.items);
    if (!cliRes.ok) setError((prev) => prev ?? cliRes.error);
    else setClientes(cliRes.clientes);
    setLoading(false);
    setRefreshing(false);
  }, [profile]);

  useFocusEffect(
    useCallback(() => {
      setLoading(true);
      void load();
    }, [load]),
  );

  const carteraFiltered = useMemo(() => {
    const term = appliedQ.trim().toLowerCase();
    let rows: CarteraRow[] = cartera.map((c) => ({
      cliente_id: c.cliente_id,
      razon_social: c.razon_social,
      rif_nit: c.rif_nit,
      monto_por_liquidar: c.monto_por_liquidar,
      cant_ordenes: c.cant_ordenes,
      dias_vencidos: c.dias_vencidos,
    }));
    if (profile?.rol === "vendedor") {
      const ids = new Set(clientes.map((c) => c.id));
      if (ids.size) {
        rows = rows.filter((r) => ids.has(r.cliente_id));
      }
    }
    if (term) {
      rows = rows.filter(
        (r) =>
          r.razon_social.toLowerCase().includes(term) ||
          r.rif_nit.toLowerCase().includes(term),
      );
    }
    return rows.filter((r) => r.monto_por_liquidar > 0);
  }, [cartera, clientes, appliedQ, profile?.rol]);

  const todosFiltered = useMemo(() => {
    const term = appliedQ.trim().toLowerCase();
    if (!term) return clientes;
    return clientes.filter(
      (c) =>
        c.razon_social.toLowerCase().includes(term) ||
        c.rif_nit.toLowerCase().includes(term),
    );
  }, [clientes, appliedQ]);

  function openCliente(clienteId: string) {
    router.push(`/(app)/clientes/${clienteId}` as Href);
  }

  function openRendicion(clienteId: string) {
    router.push({
      pathname: "/(app)/rendiciones/nueva",
      params: { clienteId },
    });
  }

  if (loading) return <LoadingBlock />;

  return (
    <View style={styles.root}>
      <View style={styles.searchRow}>
        <TextInput
          style={styles.search}
          placeholder="Buscar cliente o RIF…"
          value={q}
          onChangeText={setQ}
          autoCapitalize="none"
          onSubmitEditing={() => setAppliedQ(q.trim())}
          returnKeyType="search"
        />
        <Pressable
          style={styles.searchBtn}
          onPress={() => setAppliedQ(q.trim())}
        >
          <Text style={styles.searchBtnText}>Buscar</Text>
        </Pressable>
      </View>

      <View style={styles.tabs}>
        <Pressable
          style={[styles.tab, mode === "cartera" && styles.tabActive]}
          onPress={() => setMode("cartera")}
        >
          <Text
            style={[styles.tabText, mode === "cartera" && styles.tabTextActive]}
          >
            Con saldo
          </Text>
        </Pressable>
        <Pressable
          style={[styles.tab, mode === "todos" && styles.tabActive]}
          onPress={() => setMode("todos")}
        >
          <Text
            style={[styles.tabText, mode === "todos" && styles.tabTextActive]}
          >
            Todos
          </Text>
        </Pressable>
      </View>

      <ErrorText message={error} />

      {mode === "cartera" ? (
        <FlatList
          data={carteraFiltered}
          keyExtractor={(item) => item.cliente_id}
          refreshControl={
            <RefreshControl
              refreshing={refreshing}
              onRefresh={() => {
                setRefreshing(true);
                void load();
              }}
            />
          }
          ListHeaderComponent={
            <SectionTitle>
              {`Cartera por liquidar (${carteraFiltered.length})`}
            </SectionTitle>
          }
          ListEmptyComponent={
            <EmptyState message="No hay clientes con saldo pendiente." />
          }
          renderItem={({ item }) => (
            <View style={styles.card}>
              <Pressable onPress={() => openCliente(item.cliente_id)}>
                <Text style={styles.name}>{item.razon_social}</Text>
                <Text style={styles.meta}>
                  {item.rif_nit}
                  {item.dias_vencidos > 0
                    ? ` · ${item.dias_vencidos}d venc.`
                    : ""}
                </Text>
                <Text style={styles.saldo}>
                  ${formatMoney(item.monto_por_liquidar)} · {item.cant_ordenes}{" "}
                  orden{item.cant_ordenes === 1 ? "" : "es"}
                </Text>
              </Pressable>
              <View style={styles.actions}>
                <Pressable
                  style={styles.btnGhost}
                  onPress={() => openCliente(item.cliente_id)}
                >
                  <Text style={styles.btnGhostText}>Visita</Text>
                </Pressable>
                <Pressable
                  style={styles.btn}
                  onPress={() => openRendicion(item.cliente_id)}
                >
                  <Text style={styles.btnText}>Cobrar</Text>
                </Pressable>
              </View>
            </View>
          )}
        />
      ) : (
        <FlatList
          data={todosFiltered}
          keyExtractor={(item) => item.id}
          refreshControl={
            <RefreshControl
              refreshing={refreshing}
              onRefresh={() => {
                setRefreshing(true);
                void load();
              }}
            />
          }
          ListHeaderComponent={
            <SectionTitle>{`Clientes (${todosFiltered.length})`}</SectionTitle>
          }
          ListEmptyComponent={
            <EmptyState message="No hay clientes en tu cartera." />
          }
          renderItem={({ item }) => (
            <Pressable
              style={styles.card}
              onPress={() => openCliente(item.id)}
            >
              <Text style={styles.name}>{item.razon_social}</Text>
              <Text style={styles.meta}>{item.rif_nit}</Text>
            </Pressable>
          )}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F6F8", padding: 16 },
  searchRow: { flexDirection: "row", gap: 8, marginBottom: 10 },
  search: {
    flex: 1,
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 10,
    fontSize: 16,
    color: "#0B3A5C",
  },
  searchBtn: {
    backgroundColor: "#0B3A5C",
    borderRadius: 12,
    paddingHorizontal: 14,
    justifyContent: "center",
  },
  searchBtnText: { color: "#fff", fontWeight: "600" },
  tabs: { flexDirection: "row", gap: 8, marginBottom: 8 },
  tab: {
    flex: 1,
    paddingVertical: 10,
    borderRadius: 10,
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#E5EAF0",
    alignItems: "center",
  },
  tabActive: { backgroundColor: "#0B3A5C", borderColor: "#0B3A5C" },
  tabText: { color: "#0B3A5C", fontWeight: "600" },
  tabTextActive: { color: "#fff" },
  card: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    marginBottom: 8,
    borderWidth: 1,
    borderColor: "#E5EAF0",
  },
  name: { fontSize: 16, fontWeight: "600", color: "#0B3A5C" },
  meta: { fontSize: 13, color: "#5B6B7C", marginTop: 2 },
  saldo: { marginTop: 6, fontWeight: "700", color: "#B42318" },
  actions: { flexDirection: "row", gap: 8, marginTop: 10 },
  btn: {
    flex: 1,
    backgroundColor: "#0B3A5C",
    borderRadius: 10,
    paddingVertical: 10,
    alignItems: "center",
  },
  btnText: { color: "#fff", fontWeight: "600" },
  btnGhost: {
    flex: 1,
    borderWidth: 1,
    borderColor: "#0B3A5C",
    borderRadius: 10,
    paddingVertical: 10,
    alignItems: "center",
  },
  btnGhostText: { color: "#0B3A5C", fontWeight: "600" },
});
