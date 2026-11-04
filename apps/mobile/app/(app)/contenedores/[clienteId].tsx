import { useCallback, useState } from "react";
import {
  Pressable,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { useFocusEffect, useLocalSearchParams, useRouter, type Href } from "expo-router";
import { Ionicons } from "@expo/vector-icons";
import {
  obtenerClienteContenedoresResumen,
  type ClienteContenedoresResumen,
} from "@/lib/contenedores";
import { formatDate } from "@/lib/format";
import {
  EmptyState,
  ErrorText,
  LoadingBlock,
  SectionTitle,
} from "@/components/ui";

export default function ContenedorClienteDetalleScreen() {
  const router = useRouter();
  const { clienteId } = useLocalSearchParams<{ clienteId: string }>();
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [resumen, setResumen] = useState<ClienteContenedoresResumen | null>(
    null,
  );

  const load = useCallback(async () => {
    if (!clienteId) return;
    setError(null);
    const res = await obtenerClienteContenedoresResumen(clienteId);
    if (!res.ok) {
      setError(res.error);
      setResumen(null);
    } else {
      setResumen(res.resumen);
    }
    setLoading(false);
    setRefreshing(false);
  }, [clienteId]);

  useFocusEffect(
    useCallback(() => {
      setLoading(true);
      void load();
    }, [load]),
  );

  if (loading) return <LoadingBlock />;

  if (error && !resumen) {
    return (
      <View style={styles.center}>
        <ErrorText message={error} />
      </View>
    );
  }

  if (!resumen) {
    return (
      <View style={styles.center}>
        <ErrorText message="Sin datos" />
      </View>
    );
  }

  const historico = resumen.historico;

  return (
    <ScrollView
      style={styles.root}
      contentContainerStyle={{ padding: 16, gap: 12, paddingBottom: 40 }}
      refreshControl={
        <RefreshControl
          refreshing={refreshing}
          onRefresh={() => {
            setRefreshing(true);
            void load();
          }}
        />
      }
    >
      {/* Cabecera del Cliente con Botón de Retiro */}
      <View style={styles.headerCard}>
        <View style={{ flex: 1 }}>
          <Text style={styles.title}>
            {resumen.cliente?.razon_social ?? "Cliente"}
          </Text>
          <Text style={styles.meta}>{resumen.cliente?.rif_nit ?? ""}</Text>
        </View>

        <Pressable
          style={styles.btnRetiro}
          onPress={() =>
            router.push(
              `/(app)/contenedores/retirar?clienteId=${clienteId}` as Href,
            )
          }
        >
          <Ionicons name="cube-outline" size={18} color="#fff" />
          <Text style={styles.btnRetiroText}>Retirar</Text>
        </Pressable>
      </View>

      <SectionTitle>{`Saldos por tipo de envase (${resumen.saldos.length})`}</SectionTitle>
      {resumen.saldos.length === 0 ? (
        <EmptyState message="Sin saldos de contenedores." />
      ) : (
        resumen.saldos.map((s) => {
          const aFavor = s.saldo_pendiente < 0;
          return (
            <View key={s.id} style={styles.card}>
              <View style={styles.cardTop}>
                <Text style={styles.name}>
                  {s.contenedor_codigo
                    ? `${s.contenedor_codigo} — ${s.contenedor_nombre}`
                    : s.contenedor_nombre}
                </Text>
                <View
                  style={[
                    styles.saldoBadge,
                    aFavor ? styles.saldoBadgeFavor : styles.saldoBadgePendiente,
                  ]}
                >
                  <Text
                    style={[
                      styles.saldoBadgeText,
                      aFavor
                        ? styles.saldoBadgeTextFavor
                        : styles.saldoBadgeTextPendiente,
                    ]}
                  >
                    {aFavor
                      ? `A favor: ${Math.abs(s.saldo_pendiente)}`
                      : s.saldo_pendiente === 0
                        ? "Al día (0)"
                        : `Pendiente: ${s.saldo_pendiente}`}
                  </Text>
                </View>
              </View>
              {s.updated_at ? (
                <Text style={styles.meta}>Act. {formatDate(s.updated_at)}</Text>
              ) : null}
            </View>
          );
        })
      )}

      <SectionTitle>Movimientos</SectionTitle>
      {resumen.historicoError ? (
        <ErrorText message={resumen.historicoError} />
      ) : null}
      {historico ? (
        <View style={styles.cardSummary}>
          <Text style={styles.meta}>
            Rango: {historico.fecha_inicial} → {historico.fecha_limite}
          </Text>
          <Text style={styles.summaryValues}>
            Ant. {historico.saldo_anterior} · Ent. {historico.total_entregados}{" "}
            · Ret. {historico.total_retirados} · Final {historico.saldo_final}
          </Text>
        </View>
      ) : null}

      {(historico?.movimientos ?? []).length === 0 ? (
        <EmptyState message="Sin movimientos en el rango." />
      ) : (
        (historico?.movimientos ?? []).map((m) => {
          const esDirecto = m.es_movimiento_directo || !m.orden_id;
          return (
            <View
              key={m.id || `${m.fecha_movimiento}-${m.contenedor_id}`}
              style={styles.card}
            >
              <View style={styles.cardTop}>
                <Text style={styles.name}>
                  {m.nombre_contenedor ?? m.codigo_contenedor ?? "Contenedor"}
                </Text>
                {esDirecto ? (
                  <View style={styles.tagDirecto}>
                    <Text style={styles.tagDirectoText}>Retiro directo</Text>
                  </View>
                ) : (
                  <Text style={styles.tagOrden}>
                    {m.correlativo_orden != null
                      ? `Orden #${m.correlativo_orden}`
                      : "Orden"}
                  </Text>
                )}
              </View>

              <Text style={styles.meta}>{formatDate(m.fecha_movimiento)}</Text>

              <View style={styles.movStatsRow}>
                <Text style={styles.movStat}>
                  Entregados: <Text style={{ fontWeight: "700" }}>{m.cantidad_entregada}</Text>
                </Text>
                <Text style={styles.movStat}>
                  Retirados: <Text style={{ fontWeight: "700" }}>{m.cantidad_retirada}</Text>
                </Text>
              </View>

              {m.saldo_anterior != null && m.saldo_actual != null ? (
                <Text style={styles.saldoTrace}>
                  Saldo: {m.saldo_anterior} → {m.saldo_actual}
                  {m.saldo_actual < 0 ? " (a favor)" : ""}
                </Text>
              ) : null}

              {m.observaciones ? (
                <View style={styles.obsBox}>
                  <Text style={styles.obsText}>Nota: {m.observaciones}</Text>
                </View>
              ) : null}
            </View>
          );
        })
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F6F8" },
  center: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    padding: 24,
  },
  headerCard: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 16,
    borderWidth: 1,
    borderColor: "#E5EAF0",
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 12,
  },
  title: { fontSize: 20, fontWeight: "700", color: "#0B3A5C" },
  meta: { fontSize: 13, color: "#5B6B7C", marginTop: 2 },
  btnRetiro: {
    backgroundColor: "#0B3A5C",
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderRadius: 10,
  },
  btnRetiroText: {
    color: "#fff",
    fontWeight: "600",
    fontSize: 14,
  },
  card: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    borderWidth: 1,
    borderColor: "#E5EAF0",
    gap: 6,
  },
  cardTop: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 8,
  },
  name: { fontWeight: "700", color: "#0B3A5C", fontSize: 15, flex: 1 },
  saldoBadge: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 999,
  },
  saldoBadgePendiente: {
    backgroundColor: "#FEE2E2",
  },
  saldoBadgeFavor: {
    backgroundColor: "#DCFCE7",
  },
  saldoBadgeText: {
    fontSize: 12,
    fontWeight: "700",
  },
  saldoBadgeTextPendiente: {
    color: "#B91C1C",
  },
  saldoBadgeTextFavor: {
    color: "#15803D",
  },
  cardSummary: {
    backgroundColor: "#EFF6FF",
    borderRadius: 12,
    padding: 12,
    borderWidth: 1,
    borderColor: "#DBEAFE",
  },
  summaryValues: {
    fontSize: 14,
    fontWeight: "600",
    color: "#1E40AF",
    marginTop: 4,
  },
  tagDirecto: {
    backgroundColor: "#FEF3C7",
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 6,
  },
  tagDirectoText: {
    color: "#B45309",
    fontSize: 11,
    fontWeight: "700",
  },
  tagOrden: {
    fontSize: 12,
    color: "#4B5563",
    fontWeight: "500",
  },
  movStatsRow: {
    flexDirection: "row",
    gap: 16,
    marginTop: 2,
  },
  movStat: {
    fontSize: 13,
    color: "#374151",
  },
  saldoTrace: {
    fontSize: 12,
    color: "#6B7280",
    fontStyle: "italic",
    marginTop: 2,
  },
  obsBox: {
    backgroundColor: "#F9FAFB",
    padding: 8,
    borderRadius: 8,
    marginTop: 4,
    borderLeftWidth: 3,
    borderLeftColor: "#D1D5DB",
  },
  obsText: {
    fontSize: 12,
    color: "#4B5563",
  },
});
