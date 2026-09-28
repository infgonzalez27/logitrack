import { useCallback, useState } from "react";
import {
  ActivityIndicator,
  FlatList,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { useFocusEffect, useRouter, type Href } from "expo-router";
import { useAuth } from "@/lib/auth-context";
import {
  listClientesForProfile,
  type ClienteListaItem,
} from "@/lib/clientes";

export default function ClientesScreen() {
  const { profile } = useAuth();
  const router = useRouter();
  const [q, setQ] = useState("");
  const [appliedQ, setAppliedQ] = useState("");
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [clientes, setClientes] = useState<ClienteListaItem[]>([]);

  const load = useCallback(
    async (term?: string) => {
      if (!profile) return;
      setError(null);
      const res = await listClientesForProfile(profile, term);
      if (!res.ok) {
        setError(res.error);
        setClientes([]);
      } else {
        setClientes(res.clientes);
      }
      setLoading(false);
      setRefreshing(false);
    },
    [profile],
  );

  useFocusEffect(
    useCallback(() => {
      setLoading(true);
      void load(appliedQ);
    }, [load, appliedQ]),
  );

  return (
    <View style={styles.root}>
      <Pressable
        style={styles.nuevoBtn}
        onPress={() => router.push("/(app)/clientes/nuevo" as Href)}
      >
        <Text style={styles.nuevoBtnText}>Nuevo cliente</Text>
      </Pressable>
      <View style={styles.searchRow}>
        <TextInput
          style={styles.search}
          placeholder="Buscar por razón social o RIF…"
          value={q}
          onChangeText={setQ}
          autoCapitalize="none"
          clearButtonMode="while-editing"
          onSubmitEditing={() => {
            setLoading(true);
            setAppliedQ(q.trim());
          }}
          returnKeyType="search"
        />
        <Pressable
          style={styles.searchBtn}
          onPress={() => {
            setLoading(true);
            setAppliedQ(q.trim());
          }}
        >
          <Text style={styles.searchBtnText}>Buscar</Text>
        </Pressable>
      </View>
      {error ? <Text style={styles.error}>{error}</Text> : null}
      {loading ? (
        <ActivityIndicator style={{ marginTop: 24 }} color="#0B3A5C" />
      ) : (
        <FlatList
          data={clientes}
          keyExtractor={(item) => item.id}
          refreshControl={
            <RefreshControl
              refreshing={refreshing}
              onRefresh={() => {
                setRefreshing(true);
                void load(appliedQ);
              }}
            />
          }
          ListEmptyComponent={
            <Text style={styles.empty}>No hay clientes en tu cartera.</Text>
          }
          renderItem={({ item }) => (
            <Pressable
              style={styles.row}
              onPress={() =>
                router.push(`/(app)/clientes/${item.id}` as Href)
              }
            >
              <Text style={styles.name}>{item.razon_social}</Text>
              <Text style={styles.meta}>{item.rif_nit}</Text>
            </Pressable>
          )}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F6F8", padding: 16 },
  nuevoBtn: {
    backgroundColor: "#0B3A5C",
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: "center",
    marginBottom: 12,
  },
  nuevoBtnText: { color: "#fff", fontWeight: "600", fontSize: 16 },
  searchRow: { flexDirection: "row", gap: 8, marginBottom: 12 },
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
  name: { fontSize: 16, fontWeight: "600", color: "#0B3A5C" },
  meta: { fontSize: 13, color: "#5B6B7C", marginTop: 4 },
  empty: { textAlign: "center", color: "#5B6B7C", marginTop: 32 },
  error: { color: "#B42318", marginBottom: 8 },
});
