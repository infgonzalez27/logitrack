import { useCallback, useState } from "react";
import {
  FlatList,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { useFocusEffect, useRouter } from "expo-router";
import {
  listFacturasCompras,
  type FacturaCompraItem,
} from "@/lib/compras";
import { formatDate, formatMoney } from "@/lib/format";
import { EmptyState, ErrorText, LoadingBlock } from "@/components/ui";

export default function FacturasComprasScreen() {
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [facturas, setFacturas] = useState<FacturaCompraItem[]>([]);

  const load = useCallback(async () => {
    setError(null);
    const res = await listFacturasCompras();
    if (!res.ok) {
      setError(res.error);
      setFacturas([]);
    } else {
      setFacturas(res.facturas);
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

  return (
    <View style={styles.root}>
      <Pressable
        style={styles.btn}
        onPress={() => router.push("/(app)/facturas-compras/nuevo")}
      >
        <Text style={styles.btnText}>Nueva factura</Text>
      </Pressable>
      <ErrorText message={error} />
      {loading ? (
        <LoadingBlock />
      ) : (
        <FlatList
          data={facturas}
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
          ListEmptyComponent={
            <EmptyState message="No hay facturas de compra." />
          }
          renderItem={({ item }) => (
            <View style={styles.row}>
              <View style={styles.rowTop}>
                <Text style={styles.title}>{item.numero_factura}</Text>
                <Text style={styles.badge}>{item.estado_pago}</Text>
              </View>
              <Text style={styles.meta}>{item.proveedor_nombre}</Text>
              <Text style={styles.meta}>
                {formatDate(item.fecha_emision)} · $
                {formatMoney(item.monto_total)}
              </Text>
            </View>
          )}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F6F8", padding: 16 },
  btn: {
    backgroundColor: "#0B3A5C",
    borderRadius: 12,
    paddingVertical: 12,
    alignItems: "center",
    marginBottom: 12,
  },
  btnText: { color: "#fff", fontWeight: "600" },
  row: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    marginBottom: 8,
    borderWidth: 1,
    borderColor: "#E5EAF0",
  },
  rowTop: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  title: { fontSize: 16, fontWeight: "700", color: "#0B3A5C" },
  badge: {
    fontSize: 11,
    fontWeight: "600",
    color: "#0B3A5C",
    backgroundColor: "#E8EEF3",
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 999,
    textTransform: "capitalize",
  },
  meta: { fontSize: 13, color: "#5B6B7C", marginTop: 4 },
});
