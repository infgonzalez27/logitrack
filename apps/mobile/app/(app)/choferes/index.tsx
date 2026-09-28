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
  labelEstadoChofer,
  listChoferes,
  type Chofer,
} from "@/lib/choferes";
import { EmptyState, ErrorText, LoadingBlock, PrimaryButton } from "@/components/ui";

export default function ChoferesIndexScreen() {
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [items, setItems] = useState<Chofer[]>([]);

  const load = useCallback(async () => {
    setError(null);
    const res = await listChoferes();
    if (!res.ok) {
      setError(res.error);
      setItems([]);
    } else {
      setItems(res.choferes);
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
      <PrimaryButton
        label="Nuevo chofer"
        onPress={() => router.push("/(app)/choferes/nuevo" as Href)}
      />
      <ErrorText message={error} />
      <FlatList
        style={{ marginTop: 12 }}
        data={items}
        keyExtractor={(item) => item.perfil_id}
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
          <EmptyState message="No hay choferes. Registra un usuario con rol chofer." />
        }
        renderItem={({ item }) => (
          <Pressable
            style={styles.row}
            onPress={() =>
              router.push(`/(app)/choferes/${item.perfil_id}` as Href)
            }
          >
            <Text style={styles.title}>
              {item.nombre_completo ?? "Sin nombre"}
            </Text>
            <Text style={styles.sub}>
              {item.cedula_licencia} · {labelEstadoChofer(item.estado)}
            </Text>
          </Pressable>
        )}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F6F8", padding: 16 },
  row: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    marginBottom: 8,
    borderWidth: 1,
    borderColor: "#E5EAF0",
  },
  title: { fontSize: 16, fontWeight: "600", color: "#0B3A5C" },
  sub: { fontSize: 13, color: "#5B6B7C", marginTop: 4 },
});
