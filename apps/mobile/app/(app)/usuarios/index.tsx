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
import { useFocusEffect, useRouter } from "expo-router";
import {
  listUsuarios,
  type UsuarioListaItem,
} from "@/lib/usuarios";
import { roleLabel } from "@/lib/auth";
import { EmptyState, ErrorText, LoadingBlock } from "@/components/ui";

export default function UsuariosScreen() {
  const router = useRouter();
  const [q, setQ] = useState("");
  const [appliedQ, setAppliedQ] = useState("");
  const [usuarios, setUsuarios] = useState<UsuarioListaItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError(null);
    const res = await listUsuarios({ nombre: appliedQ });
    if (!res.ok) {
      setError(res.error);
      setUsuarios([]);
    } else {
      setUsuarios(res.usuarios);
    }
    setLoading(false);
    setRefreshing(false);
  }, [appliedQ]);

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
        onPress={() => router.push("/(app)/usuarios/registrar")}
      >
        <Text style={styles.btnText}>Registrar usuario</Text>
      </Pressable>

      <View style={styles.searchRow}>
        <TextInput
          style={styles.search}
          placeholder="Buscar por nombre…"
          value={q}
          onChangeText={setQ}
          onSubmitEditing={() => {
            setLoading(true);
            setAppliedQ(q.trim());
          }}
          returnKeyType="search"
          placeholderTextColor="#9AA6B2"
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

      <ErrorText message={error} />
      {loading ? (
        <LoadingBlock />
      ) : (
        <FlatList
          data={usuarios}
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
            <EmptyState message="No hay usuarios registrados." />
          }
          renderItem={({ item }) => (
            <Pressable
              style={styles.row}
              onPress={() =>
                router.push({
                  pathname: "/(app)/usuarios/[id]",
                  params: { id: item.id },
                })
              }
            >
              <Text style={styles.title}>{item.nombre_completo}</Text>
              <Text style={styles.meta}>
                {item.rol_nombre ? roleLabel(item.rol_nombre) : "Sin rol"}
                {item.activo === false ? " · Inactivo" : ""}
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
  btn: {
    backgroundColor: "#0B3A5C",
    borderRadius: 12,
    paddingVertical: 12,
    alignItems: "center",
    marginBottom: 12,
  },
  btnText: { color: "#fff", fontWeight: "600" },
  searchRow: { flexDirection: "row", gap: 8, marginBottom: 12 },
  search: {
    flex: 1,
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 10,
    color: "#0B3A5C",
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
  title: { fontSize: 16, fontWeight: "700", color: "#0B3A5C" },
  meta: { fontSize: 13, color: "#5B6B7C", marginTop: 4 },
});
