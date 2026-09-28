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
  labelEstadoCamion,
  listCamiones,
  type Camion,
} from "@/lib/camiones";
import { EmptyState, ErrorText, LoadingBlock, PrimaryButton } from "@/components/ui";

export default function CamionesIndexScreen() {
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [items, setItems] = useState<Camion[]>([]);

  const load = useCallback(async () => {
    setError(null);
    const res = await listCamiones();
    if (!res.ok) {
      setError(res.error);
      setItems([]);
    } else {
      setItems(res.camiones);
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
        label="Nuevo camión"
        onPress={() => router.push("/(app)/camiones/nuevo" as Href)}
      />
      <ErrorText message={error} />
      <FlatList
        style={{ marginTop: 12 }}
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
        ListEmptyComponent={<EmptyState message="No hay camiones." />}
        renderItem={({ item }) => (
          <Pressable
            style={styles.row}
            onPress={() =>
              router.push(`/(app)/camiones/${item.id}` as Href)
            }
          >
            <Text style={styles.title}>{item.placa}</Text>
            <Text style={styles.sub}>
              {item.modelo} · {item.capacidad_kg} kg ·{" "}
              {labelEstadoCamion(item.estado)}
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
