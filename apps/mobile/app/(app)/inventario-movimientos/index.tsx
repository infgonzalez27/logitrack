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
import { useAuth } from "@/lib/auth-context";
import {
  labelConcepto,
  listMovimientosEspeciales,
  puedeMovimientosEspeciales,
  type MovimientoEspecialItem,
} from "@/lib/movimientos-inventario";
import { formatDate, formatMoney, formatNumber } from "@/lib/format";
import { EmptyState, ErrorText, LoadingBlock } from "@/components/ui";

export default function MovimientosInventarioScreen() {
  const router = useRouter();
  const { profile } = useAuth();
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [items, setItems] = useState<MovimientoEspecialItem[]>([]);

  const load = useCallback(async () => {
    setError(null);
    const res = await listMovimientosEspeciales();
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

  if (!puedeMovimientosEspeciales(profile?.rol)) {
    return (
      <View style={styles.root}>
        <EmptyState message="Solo admin o gerente pueden ver los movimientos especiales." />
      </View>
    );
  }

  return (
    <View style={styles.root}>
      <Pressable
        style={styles.btn}
        onPress={() => router.push("/(app)/inventario-movimientos/nuevo" as Href)}
      >
        <Text style={styles.btnText}>Nuevo movimiento</Text>
      </Pressable>
      <ErrorText message={error} />
      {loading ? (
        <LoadingBlock />
      ) : (
        <FlatList
          data={items}
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
            <EmptyState message="Aún no hay movimientos especiales." />
          }
          renderItem={({ item }) => (
            <View style={styles.row}>
              <View style={styles.header}>
                <Text
                  style={[
                    styles.badge,
                    item.tipo === "ENTRADA" ? styles.entrada : styles.salida,
                  ]}
                >
                  {item.tipo === "ENTRADA" ? "Entrada" : "Salida"}
                </Text>
                <Text style={styles.title}>{labelConcepto(item.concepto)}</Text>
              </View>
              <Text style={styles.meta}>
                {formatDate(item.fecha)} ·{" "}
                {item.inventario === "MOVIL" ? `Camión ${item.camion}` : "Almacén"}
              </Text>
              {item.cliente ? (
                <Text style={styles.meta}>Cliente: {item.cliente}</Text>
              ) : null}
              {item.lineas.map((l, i) => (
                <Text key={`${item.id}-${i}`} style={styles.linea}>
                  {formatNumber(l.cantidad)} × {l.producto}
                </Text>
              ))}
              <Text style={styles.meta}>
                Costo total ${formatMoney(item.costo_total)}
              </Text>
              {item.observaciones ? (
                <Text style={styles.meta}>{item.observaciones}</Text>
              ) : null}
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
  header: { flexDirection: "row", alignItems: "center", gap: 8 },
  badge: {
    fontSize: 12,
    fontWeight: "700",
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 999,
    overflow: "hidden",
  },
  entrada: { backgroundColor: "#E3F5EA", color: "#1E7A45" },
  salida: { backgroundColor: "#FFF3E0", color: "#A65B00" },
  title: { fontSize: 16, fontWeight: "700", color: "#0B3A5C", flexShrink: 1 },
  meta: { fontSize: 13, color: "#5B6B7C", marginTop: 4 },
  linea: { fontSize: 14, color: "#1F2D3A", marginTop: 2 },
});
