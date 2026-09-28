import { useCallback, useState } from "react";
import {
  ActivityIndicator,
  FlatList,
  Linking,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { useFocusEffect, useRouter } from "expo-router";
import { useAuth } from "@/lib/auth-context";
import {
  aprobarRadar,
  listarParadasRadar,
  listarRadarsHoy,
  paradaEstadoLabel,
  retornaRadarDespachador,
  type RadarListaItem,
  type RadarOrden,
  type RadarParadaResumen,
} from "@/lib/radar";
import { formatDate, formatMoney } from "@/lib/format";

export default function RadarScreen() {
  const { profile } = useAuth();
  const router = useRouter();
  const isDespachador = profile?.rol === "despachador";
  const canApprove =
    profile?.rol === "gerente" || profile?.rol === "admin";

  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [ordenes, setOrdenes] = useState<RadarOrden[]>([]);
  const [radars, setRadars] = useState<RadarListaItem[]>([]);
  const [selectedRadar, setSelectedRadar] = useState<RadarListaItem | null>(
    null,
  );
  const [paradas, setParadas] = useState<RadarParadaResumen[]>([]);
  const [approving, setApproving] = useState(false);

  const load = useCallback(async () => {
    setError(null);
    if (isDespachador) {
      const res = await retornaRadarDespachador();
      if (!res.ok) {
        setError(res.error);
        setOrdenes([]);
      } else {
        setOrdenes(res.ordenes);
      }
    } else {
      const res = await listarRadarsHoy();
      if (!res.ok) {
        setError(res.error);
        setRadars([]);
      } else {
        setRadars(res.radars);
      }
    }
    setLoading(false);
    setRefreshing(false);
  }, [isDespachador]);

  useFocusEffect(
    useCallback(() => {
      setLoading(true);
      setSelectedRadar(null);
      setParadas([]);
      void load();
    }, [load]),
  );

  const openRadar = async (radar: RadarListaItem) => {
    setSelectedRadar(radar);
    setLoading(true);
    const res = await listarParadasRadar(radar.id_radar);
    if (!res.ok) setError(res.error);
    else setParadas(res.paradas);
    setLoading(false);
  };

  const onApprove = async () => {
    if (!selectedRadar) return;
    setApproving(true);
    const res = await aprobarRadar(selectedRadar.id_radar);
    setApproving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    setSelectedRadar(null);
    setParadas([]);
    setRefreshing(true);
    void load();
  };

  if (loading && !refreshing) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color="#0B3A5C" />
      </View>
    );
  }

  if (isDespachador) {
    return (
      <View style={styles.root}>
        {error ? <Text style={styles.error}>{error}</Text> : null}
        <Text style={styles.subtitle}>
          {ordenes.length} paradas en tu ruta de hoy
        </Text>
        <FlatList
          data={ordenes}
          keyExtractor={(o) => o.orden_id}
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
            <Text style={styles.empty}>
              No hay despachos en tránsito para tus clientes.
            </Text>
          }
          renderItem={({ item }) => {
            const estado = paradaEstadoLabel(item.detalles ?? []);
            const pendientes = (item.detalles ?? []).some(
              (d) => (d.estado_entrega ?? "pendiente") === "pendiente",
            );
            const mapsUrl = item.cliente.direccion_fiscal
              ? `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(item.cliente.direccion_fiscal)}`
              : null;
            return (
              <View style={styles.card}>
                <View style={styles.rowTop}>
                  <Text style={styles.name}>{item.cliente.razon_social}</Text>
                  <Text
                    style={[
                      styles.badge,
                      estado.tone === "ok" && styles.badgeOk,
                      estado.tone === "danger" && styles.badgeDanger,
                    ]}
                  >
                    {estado.label}
                  </Text>
                </View>
                <Text style={styles.meta}>
                  Orden #{item.correlativo}
                  {item.cliente.nombre_ruta
                    ? ` · ${item.cliente.nombre_ruta}`
                    : ""}
                </Text>
                {item.cliente.direccion_fiscal ? (
                  <Text style={styles.meta}>{item.cliente.direccion_fiscal}</Text>
                ) : null}
                <Text style={styles.meta}>
                  ${formatMoney(item.total_recaudar_usd)} ·{" "}
                  {(item.detalles ?? []).length} SKU
                </Text>
                <View style={styles.actions}>
                  {mapsUrl ? (
                    <Pressable
                      style={styles.btnGhost}
                      onPress={() => void Linking.openURL(mapsUrl)}
                    >
                      <Text style={styles.btnGhostText}>Mapas</Text>
                    </Pressable>
                  ) : null}
                  {pendientes ? (
                    <Pressable
                      style={styles.btn}
                      onPress={() =>
                        router.push({
                          pathname: "/(app)/radar/entrega/[ordenId]",
                          params: { ordenId: item.orden_id },
                        })
                      }
                    >
                      <Text style={styles.btnText}>Entregar</Text>
                    </Pressable>
                  ) : null}
                </View>
              </View>
            );
          }}
        />
      </View>
    );
  }

  if (selectedRadar) {
    return (
      <View style={styles.root}>
        <Pressable
          onPress={() => {
            setSelectedRadar(null);
            setParadas([]);
          }}
        >
          <Text style={styles.back}>← Volver a radares</Text>
        </Pressable>
        {error ? <Text style={styles.error}>{error}</Text> : null}
        <Text style={styles.name}>
          Radar #{selectedRadar.correlativo} ·{" "}
          {formatDate(selectedRadar.fecha_despacho)}
        </Text>
        <Text style={styles.meta}>
          {selectedRadar.total_paradas} paradas ·{" "}
          {selectedRadar.status_radar ? "Aprobado" : "Pendiente"}
        </Text>
        {canApprove && !selectedRadar.status_radar ? (
          <Pressable
            style={[styles.btn, approving && { opacity: 0.6 }]}
            disabled={approving}
            onPress={() => void onApprove()}
          >
            <Text style={styles.btnText}>
              {approving ? "Aprobando…" : "Aprobar radar"}
            </Text>
          </Pressable>
        ) : null}
        <FlatList
          data={paradas}
          keyExtractor={(p) => p.id_orden_distribucion}
          ListEmptyComponent={
            <Text style={styles.empty}>Sin paradas en este radar.</Text>
          }
          renderItem={({ item }) => (
            <View style={styles.card}>
              <Text style={styles.name}>{item.razon_social}</Text>
              <Text style={styles.meta}>
                Orden #{item.correlativo}
                {item.ruta ? ` · ${item.ruta}` : ""}
              </Text>
              {item.direccion_fiscal ? (
                <Text style={styles.meta}>{item.direccion_fiscal}</Text>
              ) : null}
              <Text style={styles.meta}>
                {item.items} uds · {item.sku} SKU
              </Text>
            </View>
          )}
        />
      </View>
    );
  }

  return (
    <View style={styles.root}>
      {error ? <Text style={styles.error}>{error}</Text> : null}
      <Text style={styles.subtitle}>Radares de hoy</Text>
      <FlatList
        data={radars}
        keyExtractor={(r) => r.id_radar}
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
          <Text style={styles.empty}>No hay radares para hoy.</Text>
        }
        renderItem={({ item }) => (
          <Pressable style={styles.card} onPress={() => void openRadar(item)}>
            <View style={styles.rowTop}>
              <Text style={styles.name}>#{item.correlativo}</Text>
              <Text
                style={[
                  styles.badge,
                  item.status_radar ? styles.badgeOk : undefined,
                ]}
              >
                {item.status_radar ? "Aprobado" : "Pendiente"}
              </Text>
            </View>
            <Text style={styles.meta}>
              {item.total_paradas} paradas · {item.items} uds · {item.sku} SKU
            </Text>
          </Pressable>
        )}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F6F8", padding: 16 },
  center: { flex: 1, alignItems: "center", justifyContent: "center" },
  subtitle: { fontSize: 14, color: "#5B6B7C", marginBottom: 10 },
  card: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    marginBottom: 8,
    borderWidth: 1,
    borderColor: "#E5EAF0",
  },
  rowTop: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    gap: 8,
  },
  name: { fontSize: 16, fontWeight: "700", color: "#0B3A5C", flex: 1 },
  meta: { fontSize: 13, color: "#5B6B7C", marginTop: 3 },
  badge: {
    fontSize: 11,
    fontWeight: "600",
    color: "#0B3A5C",
    backgroundColor: "#E8EEF3",
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 999,
  },
  badgeOk: { backgroundColor: "#DCFAE6", color: "#067647" },
  badgeDanger: { backgroundColor: "#FEE4E2", color: "#B42318" },
  actions: { flexDirection: "row", gap: 8, marginTop: 10 },
  btn: {
    flex: 1,
    backgroundColor: "#0B3A5C",
    borderRadius: 10,
    paddingVertical: 10,
    alignItems: "center",
  },
  btnText: { color: "#fff", fontWeight: "600" },
  btnGhost: {
    flex: 1,
    borderWidth: 1,
    borderColor: "#0B3A5C",
    borderRadius: 10,
    paddingVertical: 10,
    alignItems: "center",
    backgroundColor: "#fff",
  },
  btnGhostText: { color: "#0B3A5C", fontWeight: "600" },
  empty: { textAlign: "center", color: "#5B6B7C", marginTop: 32 },
  error: { color: "#B42318", marginBottom: 8 },
  back: { color: "#0B3A5C", fontWeight: "600", marginBottom: 10 },
});
