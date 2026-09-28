import { useCallback, useState } from "react";
import { FlatList, Pressable, RefreshControl, StyleSheet, Text, View } from "react-native";
import { useFocusEffect, useRouter, type Href } from "expo-router";
import { listRutas, type Ruta } from "@/lib/rutas";
import { EmptyState, ErrorText, LoadingBlock, PrimaryButton } from "@/components/ui";

export default function RutasIndexScreen() {
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [rutas, setRutas] = useState<Ruta[]>([]);

  const load = useCallback(async () => {
    setError(null);
    const res = await listRutas();
    if (!res.ok) {
      setError(res.error);
      setRutas([]);
    } else {
      setRutas(res.rutas);
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
        label="Nueva ruta"
        onPress={() => router.push("/(app)/rutas/nuevo" as Href)}
      />
      <ErrorText message={error} />
      <FlatList
        style={{ marginTop: 12 }}
        data={rutas}
        keyExtractor={(item) => item.id_ruta}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={() => {
              setRefreshing(true);
              void load();
            }}
          />
        }
        ListEmptyComponent={<EmptyState message="No hay rutas registradas." />}
        renderItem={({ item }) => (
          <Pressable
            style={styles.row}
            onPress={() =>
              router.push(`/(app)/rutas/${item.id_ruta}` as Href)
            }
          >
            <Text style={styles.title}>{item.nombre_ruta}</Text>
            {item.descripcion_ruta ? (
              <Text style={styles.sub}>{item.descripcion_ruta}</Text>
            ) : null}
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
