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
import { Ionicons } from "@expo/vector-icons";
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
      {/* Botón de Retiro Directo de Contenedores */}
      <Pressable
        style={styles.btnRetiro}
        onPress={() => router.push("/(app)/contenedores/retirar" as Href)}
      >
        <Ionicons name="add-circle" size={20} color="#fff" />
        <Text style={styles.btnRetiroText}>Retirar contenedores a cliente</Text>
      </Pressable>

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
        {clientes.length} cliente{clientes.length === 1 ? "" : "s"} · Saldo neto
        global: {total}
      </Text>
      <SectionTitle>Saldos de vacíos por cliente</SectionTitle>

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
        renderItem={({ item }) => {
          const esAFavor = item.total_saldo < 0;
          return (
            <Pressable
              style={styles.card}
              onPress={() =>
                router.push(
                  `/(app)/contenedores/${item.cliente_id}` as Href,
                )
              }
            >
              <View style={styles.cardHeader}>
                <View style={{ flex: 1 }}>
                  <Text style={styles.name}>{item.cliente_razon}</Text>
                  <Text style={styles.meta}>{item.cliente_rif}</Text>
                </View>
                <Ionicons name="chevron-forward" size={18} color="#9CA3AF" />
              </View>

              <View style={styles.cardFooter}>
                <Text
                  style={[
                    styles.saldo,
                    esAFavor ? styles.saldoFavor : styles.saldoDebe,
                  ]}
                >
                  {esAFavor
                    ? `A favor: ${Math.abs(item.total_saldo)}`
                    : `Pendiente: ${item.total_saldo}`}
                </Text>
                <Text style={styles.tipos}>
                  {item.tipos} tipo{item.tipos === 1 ? "" : "s"} de envase
                </Text>
              </View>
            </Pressable>
          );
        }}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F6F8", padding: 16 },
  btnRetiro: {
    backgroundColor: "#0B3A5C",
    borderRadius: 12,
    paddingVertical: 12,
    paddingHorizontal: 16,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 8,
    marginBottom: 12,
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
  },
  btnRetiroText: {
    color: "#fff",
    fontWeight: "700",
    fontSize: 15,
  },
  searchRow: { flexDirection: "row", gap: 8, marginBottom: 10 },
  search: {
    flex: 1,
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 10,
    fontSize: 15,
    color: "#0B3A5C",
  },
  searchBtn: {
    backgroundColor: "#0B3A5C",
    borderRadius: 12,
    paddingHorizontal: 14,
    justifyContent: "center",
  },
  searchBtnText: { color: "#fff", fontWeight: "600" },
  summary: { color: "#5B6B7C", marginBottom: 4, fontSize: 13 },
  card: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    marginBottom: 8,
    borderWidth: 1,
    borderColor: "#E5EAF0",
  },
  cardHeader: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
  },
  name: { fontWeight: "700", color: "#0B3A5C", fontSize: 16 },
  meta: { fontSize: 13, color: "#5B6B7C", marginTop: 2 },
  cardFooter: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    marginTop: 8,
    paddingTop: 8,
    borderTopWidth: 1,
    borderTopColor: "#F3F4F6",
  },
  saldo: { fontWeight: "700", fontSize: 14 },
  saldoDebe: { color: "#B91C1C" },
  saldoFavor: { color: "#059669" },
  tipos: { fontSize: 12, color: "#6B7280" },
});
