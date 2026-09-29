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
import { Ionicons } from "@expo/vector-icons";
import { useFocusEffect, useRouter, type Href } from "expo-router";
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

function normalizar(texto: string): string {
  return texto
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim();
}

export default function PorLiquidarScreen() {
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [items, setItems] = useState<OrdenPorLiquidarCliente[]>([]);
  const [q, setQ] = useState("");

  const load = useCallback(async () => {
    setError(null);
    const res = await retornaOrdenesPorLiquidar();
    if (!res.ok) {
      setError(res.error);
      setItems([]);
    } else {
      setItems(res.items);
    }
    setLoading(false);
    setRefreshing(false);
  }, []);

  useFocusEffect(
    useCallback(() => {
      setLoading(true);
      void load();
    }, [load]),
  );

  const filtrados = useMemo(() => {
    const term = normalizar(q);
    if (!term) return items;
    return items.filter(
      (i) =>
        normalizar(i.razon_social ?? "").includes(term) ||
        normalizar(i.rif_nit ?? "").includes(term),
    );
  }, [items, q]);

  if (loading) return <LoadingBlock />;

  return (
    <View style={styles.root}>
      <View style={styles.searchBox}>
        <Ionicons name="search" size={18} color="#5B6B7C" />
        <TextInput
          style={styles.searchInput}
          placeholder="Buscar cliente o RIF…"
          value={q}
          onChangeText={setQ}
          autoCorrect={false}
          returnKeyType="search"
        />
        {q ? (
          <Pressable
            onPress={() => setQ("")}
            hitSlop={10}
            accessibilityLabel="Limpiar búsqueda"
          >
            <Ionicons name="close-circle" size={20} color="#5B6B7C" />
          </Pressable>
        ) : null}
      </View>
      <ErrorText message={error} />
      <SectionTitle>
        {q.trim()
          ? `Clientes (${filtrados.length} de ${items.length})`
          : `Clientes (${items.length})`}
      </SectionTitle>
      <FlatList
        data={filtrados}
        keyExtractor={(item) => item.cliente_id}
        keyboardShouldPersistTaps="handled"
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
          <EmptyState
            message={
              q.trim()
                ? "Ningún cliente coincide con la búsqueda."
                : "No hay órdenes por liquidar."
            }
          />
        }
        renderItem={({ item }) => (
          <View style={styles.card}>
            <Pressable
              onPress={() =>
                router.push(`/(app)/clientes/${item.cliente_id}` as Href)
              }
            >
              <Text style={styles.name}>{item.razon_social}</Text>
              <Text style={styles.meta}>
                {item.rif_nit}
                {item.dias_vencidos > 0
                  ? ` · ${item.dias_vencidos}d vencidos`
                  : ""}
              </Text>
              <Text style={styles.saldo}>
                ${formatMoney(item.monto_por_liquidar)} · {item.cant_ordenes}{" "}
                orden{item.cant_ordenes === 1 ? "" : "es"}
              </Text>
            </Pressable>
            <Pressable
              style={styles.btn}
              onPress={() =>
                router.push({
                  pathname: "/(app)/rendiciones/nueva",
                  params: { clienteId: item.cliente_id },
                })
              }
            >
              <Text style={styles.btnText}>Cobrar / Rendición</Text>
            </Pressable>
          </View>
        )}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F6F8", padding: 16 },
  searchBox: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 12,
    paddingHorizontal: 12,
    marginBottom: 8,
  },
  searchInput: {
    flex: 1,
    paddingVertical: 10,
    fontSize: 16,
    color: "#0B3A5C",
  },
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
  saldo: { marginTop: 6, fontWeight: "700", color: "#B42318" },
  btn: {
    marginTop: 10,
    backgroundColor: "#0B3A5C",
    borderRadius: 10,
    paddingVertical: 10,
    alignItems: "center",
  },
  btnText: { color: "#fff", fontWeight: "600" },
});
