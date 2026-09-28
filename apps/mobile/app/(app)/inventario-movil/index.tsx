import { useCallback, useState } from "react";
import {
  FlatList,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { useFocusEffect } from "expo-router";
import { listarCamiones, type CamionOption } from "@/lib/catalogos";
import {
  listInventarioMovil,
  type InventarioMovilItem,
} from "@/lib/inventario";
import { formatNumber } from "@/lib/format";
import { EmptyState, ErrorText, LoadingBlock } from "@/components/ui";

export default function InventarioMovilScreen() {
  const [camiones, setCamiones] = useState<CamionOption[]>([]);
  const [camionId, setCamionId] = useState<string | null>(null);
  const [items, setItems] = useState<InventarioMovilItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pickerOpen, setPickerOpen] = useState(false);

  const load = useCallback(async () => {
    setError(null);
    const [cRes, iRes] = await Promise.all([
      listarCamiones(),
      listInventarioMovil(camionId),
    ]);
    if (!cRes.ok) setError(cRes.error);
    else setCamiones(cRes.camiones);
    if (!iRes.ok) {
      setError(iRes.error);
      setItems([]);
    } else {
      setItems(iRes.items);
    }
    setLoading(false);
    setRefreshing(false);
  }, [camionId]);

  useFocusEffect(
    useCallback(() => {
      setLoading(true);
      void load();
    }, [load]),
  );

  const selected = camiones.find((c) => c.id === camionId);

  return (
    <View style={styles.root}>
      <Text style={styles.label}>Filtrar por camión</Text>
      <Pressable style={styles.select} onPress={() => setPickerOpen((v) => !v)}>
        <Text style={styles.selectText}>
          {selected?.placa ?? "Todos los camiones"}
        </Text>
      </Pressable>
      {pickerOpen ? (
        <View style={styles.picker}>
          <Pressable
            style={styles.option}
            onPress={() => {
              setCamionId(null);
              setPickerOpen(false);
            }}
          >
            <Text style={styles.optionText}>Todos</Text>
          </Pressable>
          {camiones.map((c) => (
            <Pressable
              key={c.id}
              style={styles.option}
              onPress={() => {
                setCamionId(c.id);
                setPickerOpen(false);
              }}
            >
              <Text style={styles.optionText}>{c.placa}</Text>
            </Pressable>
          ))}
        </View>
      ) : null}

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
            <EmptyState message="No hay inventario móvil para este filtro." />
          }
          renderItem={({ item }) => (
            <View style={styles.row}>
              <Text style={styles.title}>{item.producto_nombre}</Text>
              <Text style={styles.meta}>Camión {item.camion_placa}</Text>
              <Text style={styles.meta}>
                Cargada {formatNumber(item.cantidad_cargada)} · Entregada{" "}
                {formatNumber(item.cantidad_entregada)}
              </Text>
            </View>
          )}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F6F8", padding: 16 },
  label: {
    fontSize: 12,
    color: "#5B6B7C",
    textTransform: "uppercase",
    marginBottom: 6,
  },
  select: {
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 12,
    padding: 14,
    marginBottom: 8,
  },
  selectText: { color: "#0B3A5C", fontSize: 16 },
  picker: {
    backgroundColor: "#fff",
    borderRadius: 12,
    marginBottom: 12,
    borderWidth: 1,
    borderColor: "#E5EAF0",
    maxHeight: 200,
  },
  option: {
    padding: 12,
    borderBottomWidth: 1,
    borderBottomColor: "#E5EAF0",
  },
  optionText: { color: "#0B3A5C" },
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
