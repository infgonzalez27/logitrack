import { useCallback, useMemo, useState } from "react";
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
import { Ionicons } from "@expo/vector-icons";
import { useAuth } from "@/lib/auth-context";
import {
  correspondeVisitaHoy,
  getDiaActualLabel,
  getDiaActualTexto,
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
  const [soloHoy, setSoloHoy] = useState(true);
  const diaHoy = useMemo(() => getDiaActualTexto(), []);
  const diaHoyLabel = useMemo(() => getDiaActualLabel(), []);

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

  const clientesFiltered = useMemo(() => {
    if (!soloHoy) return clientes;
    return clientes.filter((c) => correspondeVisitaHoy(c, diaHoy));
  }, [clientes, soloHoy, diaHoy]);

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

      <View style={styles.dayFilterRow}>
        <Pressable
          style={[styles.dayFilterChip, soloHoy && styles.dayFilterChipActive]}
          onPress={() => setSoloHoy(true)}
        >
          <Ionicons
            name="calendar-outline"
            size={15}
            color={soloHoy ? "#FFFFFF" : "#0B3A5C"}
          />
          <Text
            style={[
              styles.dayFilterText,
              soloHoy && styles.dayFilterTextActive,
            ]}
          >
            Ruta de hoy ({diaHoyLabel})
          </Text>
        </Pressable>
        <Pressable
          style={[styles.dayFilterChip, !soloHoy && styles.dayFilterChipActive]}
          onPress={() => setSoloHoy(false)}
        >
          <Ionicons
            name="globe-outline"
            size={15}
            color={!soloHoy ? "#FFFFFF" : "#0B3A5C"}
          />
          <Text
            style={[
              styles.dayFilterText,
              !soloHoy && styles.dayFilterTextActive,
            ]}
          >
            Todos ({clientes.length})
          </Text>
        </Pressable>
      </View>

      {error ? <Text style={styles.error}>{error}</Text> : null}
      {loading ? (
        <ActivityIndicator style={{ marginTop: 24 }} color="#0B3A5C" />
      ) : (
        <FlatList
          data={clientesFiltered}
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
            <Text style={styles.empty}>
              {soloHoy
                ? `No hay clientes asignados para hoy (${diaHoyLabel}). Pulsa "Todos" para ver la cartera completa.`
                : "No hay clientes en tu cartera."}
            </Text>
          }
          renderItem={({ item }) => (
            <Pressable
              style={styles.row}
              onPress={() =>
                router.push(`/(app)/clientes/${item.id}` as Href)
              }
            >
              <View style={styles.rowHeader}>
                <Text style={styles.name}>{item.razon_social}</Text>
                <Text style={styles.visitBadge}>
                  {item.visita_cualquier_dia || !item.dias_visita?.length
                    ? "Cualquier día"
                    : item.dias_visita.join(", ")}
                </Text>
              </View>
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
  searchRow: { flexDirection: "row", gap: 8, marginBottom: 10 },
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
  dayFilterRow: {
    flexDirection: "row",
    gap: 8,
    marginBottom: 12,
  },
  dayFilterChip: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 6,
    paddingVertical: 8,
    paddingHorizontal: 10,
    borderRadius: 10,
    backgroundColor: "#FFFFFF",
    borderWidth: 1,
    borderColor: "#CBD5E1",
  },
  dayFilterChipActive: {
    backgroundColor: "#0B3A5C",
    borderColor: "#0B3A5C",
  },
  dayFilterText: {
    fontSize: 12,
    fontWeight: "700",
    color: "#0B3A5C",
  },
  dayFilterTextActive: {
    color: "#FFFFFF",
  },
  row: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    marginBottom: 8,
    borderWidth: 1,
    borderColor: "#E5EAF0",
  },
  rowHeader: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 8,
  },
  name: { fontSize: 16, fontWeight: "600", color: "#0B3A5C", flex: 1 },
  visitBadge: {
    fontSize: 11,
    fontWeight: "600",
    color: "#0369A1",
    backgroundColor: "#E0F2FE",
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 6,
  },
  meta: { fontSize: 13, color: "#5B6B7C", marginTop: 4 },
  empty: { textAlign: "center", color: "#5B6B7C", marginTop: 32, paddingHorizontal: 16 },
  error: { color: "#B42318", marginBottom: 8 },
});
