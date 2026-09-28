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
import {
  agruparSaldosPorCliente,
  listarSaldosContenedores,
  type ClienteSaldoContenedoresResumen,
} from "@/lib/contenedores";
import {
  EmptyState,
  ErrorText,
  LoadingBlock,
  SectionTitle,
} from "@/components/ui";

export default function ContenedoresIndexScreen() {
  const router = useRouter();
  const [q, setQ] = useState("");
  const [appliedQ, setAppliedQ] = useState("");
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [clientes, setClientes] = useState<ClienteSaldoContenedoresResumen[]>(
    [],
  );

  const load = useCallback(async () => {
    setError(null);
    const res = await listarSaldosContenedores({
      q: appliedQ,
      soloConSaldo: true,
    });
    if (!res.ok) {
      setError(res.error);
      setClientes([]);
    } else {
      setClientes(agruparSaldosPorCliente(res.rows));
    }
    setLoading(false);
    setRefreshing(false);
  }, [appliedQ]);

  useFocusEffect(
    useCallback(() => {
      setLoading(true);
      void load();
    }, [load]),
  );

  const total = useMemo(
    () => clientes.reduce((s, c) => s + c.total_saldo, 0),
    [clientes],
  );

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

      <ErrorText message={error} />
      <Text style={styles.summary}>
        {clientes.length} cliente{clientes.length === 1 ? "" : "s"} · Saldo
        total: {total}
      </Text>
      <SectionTitle>Saldos de vacíos</SectionTitle>

      <FlatList
        data={clientes}
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
        ListEmptyComponent={
          <EmptyState message="No hay saldos de contenedores." />
        }
        renderItem={({ item }) => (
          <Pressable
            style={styles.card}
            onPress={() =>
              router.push(
                `/(app)/contenedores/${item.cliente_id}` as Href,
              )
            }
          >
            <Text style={styles.name}>{item.cliente_razon}</Text>
            <Text style={styles.meta}>{item.cliente_rif}</Text>
            <Text style={styles.saldo}>
              Pendiente: {item.total_saldo} · {item.tipos} tipo
              {item.tipos === 1 ? "" : "s"}
            </Text>
          </Pressable>
        )}
      />
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
  summary: { color: "#5B6B7C", marginBottom: 4 },
  card: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    marginBottom: 8,
    borderWidth: 1,
    borderColor: "#E5EAF0",
  },
  name: { fontWeight: "600", color: "#0B3A5C", fontSize: 16 },
  meta: { fontSize: 13, color: "#5B6B7C", marginTop: 2 },
  saldo: { marginTop: 6, fontWeight: "700", color: "#0B3A5C" },
});
