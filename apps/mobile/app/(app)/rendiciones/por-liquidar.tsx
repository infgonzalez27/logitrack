import { useCallback, useState } from "react";
import {
  FlatList,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  View,
} from "react-native";
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

export default function PorLiquidarScreen() {
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [items, setItems] = useState<OrdenPorLiquidarCliente[]>([]);

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

  if (loading) return <LoadingBlock />;

  return (
    <View style={styles.root}>
      <ErrorText message={error} />
      <SectionTitle>{`Clientes (${items.length})`}</SectionTitle>
      <FlatList
        data={items}
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
          <EmptyState message="No hay órdenes por liquidar." />
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
