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
  listPagosProveedores,
  type PagoProveedorItem,
} from "@/lib/compras";
import { formatDate, formatMoney } from "@/lib/format";
import { EmptyState, ErrorText, LoadingBlock } from "@/components/ui";

export default function PagosProveedoresScreen() {
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pagos, setPagos] = useState<PagoProveedorItem[]>([]);

  const load = useCallback(async () => {
    setError(null);
    const res = await listPagosProveedores();
    if (!res.ok) {
      setError(res.error);
      setPagos([]);
    } else {
      setPagos(res.pagos);
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
        onPress={() => router.push("/(app)/pagos-proveedores/nuevo")}
      >
        <Text style={styles.btnText}>Nuevo pago</Text>
      </Pressable>
      <ErrorText message={error} />
      {loading ? (
        <LoadingBlock />
      ) : (
        <FlatList
          data={pagos}
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
            <EmptyState message="No hay pagos a proveedores." />
          }
          renderItem={({ item }) => (
            <View style={styles.row}>
              <Text style={styles.title}>{item.proveedor_nombre}</Text>
              <Text style={styles.meta}>
                {formatDate(item.fecha_pago)} · $
                {formatMoney(item.monto_total_pagado)}
              </Text>
              <Text style={styles.meta}>
                {item.glosa_concepto ?? "Sin concepto"}
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
  title: { fontSize: 16, fontWeight: "700", color: "#0B3A5C" },
  meta: { fontSize: 13, color: "#5B6B7C", marginTop: 4 },
});
