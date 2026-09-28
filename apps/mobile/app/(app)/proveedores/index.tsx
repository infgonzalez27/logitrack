import { useCallback, useState } from "react";
import {
  FlatList,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { useFocusEffect, useRouter, type Href } from "expo-router";
import { listProveedores, type Proveedor } from "@/lib/proveedores";
import { EmptyState, ErrorText, LoadingBlock, PrimaryButton } from "@/components/ui";

export default function ProveedoresIndexScreen() {
  const router = useRouter();
  const [q, setQ] = useState("");
  const [applied, setApplied] = useState("");
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [items, setItems] = useState<Proveedor[]>([]);

  const load = useCallback(async (term?: string) => {
    setError(null);
    const res = await listProveedores(term);
    if (!res.ok) {
      setError(res.error);
      setItems([]);
    } else {
      setItems(res.proveedores);
    }
    setLoading(false);
    setRefreshing(false);
  }, []);

  useFocusEffect(
    useCallback(() => {
      setLoading(true);
      void load(applied);
    }, [load, applied]),
  );

  return (
    <View style={styles.root}>
      <PrimaryButton
        label="Nuevo proveedor"
        onPress={() => router.push("/(app)/proveedores/nuevo" as Href)}
      />
      <View style={styles.searchRow}>
        <TextInput
          style={styles.search}
          placeholder="Buscar razón social o RIF…"
          value={q}
          onChangeText={setQ}
          onSubmitEditing={() => {
            setLoading(true);
            setApplied(q.trim());
          }}
          returnKeyType="search"
        />
        <Pressable
          style={styles.searchBtn}
          onPress={() => {
            setLoading(true);
            setApplied(q.trim());
          }}
        >
          <Text style={styles.searchBtnText}>Buscar</Text>
        </Pressable>
      </View>
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
                void load(applied);
              }}
            />
          }
          ListEmptyComponent={
            <EmptyState message="No hay proveedores." />
          }
          renderItem={({ item }) => (
            <Pressable
              style={styles.row}
              onPress={() =>
                router.push(`/(app)/proveedores/${item.id}` as Href)
              }
            >
              <Text style={styles.title}>{item.razon_social}</Text>
              <Text style={styles.sub}>
                {item.rif_nit} · {item.activo ? "Activo" : "Inactivo"}
              </Text>
            </Pressable>
          )}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F6F8", padding: 16 },
  searchRow: { flexDirection: "row", gap: 8, marginVertical: 12 },
  search: {
    flex: 1,
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 12,
    fontSize: 16,
  },
  searchBtn: {
    backgroundColor: "#0B3A5C",
    borderRadius: 12,
    paddingHorizontal: 14,
    justifyContent: "center",
  },
  searchBtnText: { color: "#fff", fontWeight: "600" },
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
