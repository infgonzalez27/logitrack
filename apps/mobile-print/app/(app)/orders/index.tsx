import { useCallback, useState } from "react";
import {
  ActivityIndicator,
  FlatList,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { useFocusEffect, useRouter } from "expo-router";
import { useAuth } from "@/lib/auth-context";
import { listOrdenesForProfile, type OrdenListaItem } from "@/lib/orders";

export default function OrdersScreen() {
  const { profile, signOut } = useAuth();
  const router = useRouter();
  const [ordenes, setOrdenes] = useState<OrdenListaItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!profile) return;
    setLoading(true);
    setError(null);
    const result = await listOrdenesForProfile(profile);
    setLoading(false);
    if (!result.ok) {
      setError(result.error);
      return;
    }
    setOrdenes(result.ordenes);
  }, [profile]);

  useFocusEffect(
    useCallback(() => {
      void load();
    }, [load]),
  );

  return (
    <View style={styles.root}>
      <View style={styles.headerRow}>
        <View>
          <Text style={styles.hello}>{profile?.nombre_completo}</Text>
          <Text style={styles.role}>{profile?.rol}</Text>
        </View>
        <Pressable onPress={() => void signOut()}>
          <Text style={styles.logout}>Salir</Text>
        </Pressable>
      </View>

      {error ? <Text style={styles.error}>{error}</Text> : null}

      {loading && !ordenes.length ? (
        <ActivityIndicator style={{ marginTop: 40 }} color="#0B3A5C" />
      ) : (
        <FlatList
          data={ordenes}
          keyExtractor={(item) => item.id}
          refreshControl={
            <RefreshControl refreshing={loading} onRefresh={() => void load()} />
          }
          ListEmptyComponent={
            <Text style={styles.empty}>No hay órdenes para mostrar.</Text>
          }
          renderItem={({ item }) => (
            <Pressable
              style={styles.card}
              onPress={() => router.push(`/(app)/orders/${item.id}`)}
            >
              <Text style={styles.correlativo}>#{item.correlativo}</Text>
              <Text style={styles.cliente}>
                {item.cliente_razon_social ?? "Sin cliente"}
              </Text>
              <Text style={styles.meta}>
                {item.estado}
                {item.factura_origen_numero
                  ? ` · ${item.factura_origen_numero}`
                  : ""}
              </Text>
            </Pressable>
          )}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F7FA", padding: 16 },
  headerRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    marginBottom: 12,
  },
  hello: { fontSize: 18, fontWeight: "700", color: "#0B3A5C" },
  role: { color: "#5B6B7C", textTransform: "capitalize" },
  logout: { color: "#B42318", fontWeight: "600" },
  error: { color: "#B42318", marginBottom: 8 },
  empty: { textAlign: "center", marginTop: 40, color: "#5B6B7C" },
  card: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    marginBottom: 10,
    borderWidth: 1,
    borderColor: "#E5EAF0",
  },
  correlativo: { fontWeight: "700", fontSize: 16, color: "#0B3A5C" },
  cliente: { marginTop: 4, fontSize: 15 },
  meta: { marginTop: 4, color: "#5B6B7C", fontSize: 13 },
});
