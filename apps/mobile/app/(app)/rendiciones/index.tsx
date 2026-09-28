import { useCallback, useState } from "react";
import { FlatList, Pressable, RefreshControl, StyleSheet, Text, View } from "react-native";
import { useFocusEffect, useRouter, type Href } from "expo-router";
import { listRendiciones, type RendicionListaItem } from "@/lib/rendiciones";
import { formatDate, formatMoney } from "@/lib/format";
import { EmptyState, ErrorText, LoadingBlock, PrimaryButton } from "@/components/ui";

export default function RendicionesListScreen() {
  const router = useRouter();
  const [items, setItems] = useState<RendicionListaItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const res = await listRendiciones();
    if (!res.ok) {
      setError(res.error);
      setItems([]);
    } else {
      setError(null);
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

  if (loading && !refreshing) return <LoadingBlock />;

  return (
    <View style={styles.root}>
      <PrimaryButton
        label="Nueva cobranza"
        onPress={() => router.push("/(app)/rendiciones/nueva" as Href)}
      />
      <Pressable
        style={styles.link}
        onPress={() => router.push("/(app)/rendiciones/por-liquidar" as Href)}
      >
        <Text style={styles.linkText}>Ver órdenes por liquidar →</Text>
      </Pressable>
      <ErrorText message={error} />
      <FlatList
        style={{ marginTop: 12 }}
        data={items}
        keyExtractor={(i) => i.id}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={() => {
              setRefreshing(true);
              void load();
            }}
          />
        }
        ListEmptyComponent={<EmptyState message="Sin rendiciones." />}
        renderItem={({ item }) => (
          <Pressable
            style={styles.card}
            onPress={() =>
              router.push(`/(app)/rendiciones/${item.id}` as Href)
            }
          >
            <Text style={styles.title}>{item.cliente_razon}</Text>
            <Text style={styles.meta}>
              {formatDate(item.fecha_rendicion)} · {item.estado} · $
              {formatMoney(item.total_recaudado_usd)}
            </Text>
          </Pressable>
        )}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F6F8", padding: 16 },
  link: { marginTop: 10 },
  linkText: { color: "#0B3A5C", fontWeight: "600" },
  card: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    marginBottom: 8,
    borderWidth: 1,
    borderColor: "#E5EAF0",
  },
  title: { fontWeight: "700", color: "#0B3A5C" },
  meta: { color: "#5B6B7C", marginTop: 4, fontSize: 13 },
});
