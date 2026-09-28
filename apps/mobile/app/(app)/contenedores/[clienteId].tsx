import { useCallback, useState } from "react";
import {
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { useFocusEffect, useLocalSearchParams } from "expo-router";
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
      <Text style={styles.title}>
        {resumen.cliente?.razon_social ?? "Cliente"}
      </Text>
      <Text style={styles.meta}>{resumen.cliente?.rif_nit ?? ""}</Text>

      <SectionTitle>{`Saldos (${resumen.saldos.length})`}</SectionTitle>
      {resumen.saldos.length === 0 ? (
        <EmptyState message="Sin saldos de contenedores." />
      ) : (
        resumen.saldos.map((s) => (
          <View key={s.id} style={styles.card}>
            <Text style={styles.name}>
              {s.contenedor_codigo
                ? `${s.contenedor_codigo} — ${s.contenedor_nombre}`
                : s.contenedor_nombre}
            </Text>
            <Text style={styles.saldo}>Pendiente: {s.saldo_pendiente}</Text>
            {s.updated_at ? (
              <Text style={styles.meta}>Act. {formatDate(s.updated_at)}</Text>
            ) : null}
          </View>
        ))
      )}

      <SectionTitle>Movimientos</SectionTitle>
      {resumen.historicoError ? (
        <ErrorText message={resumen.historicoError} />
      ) : null}
      {historico ? (
        <View style={styles.card}>
          <Text style={styles.meta}>
            {historico.fecha_inicial} → {historico.fecha_limite}
          </Text>
          <Text style={styles.name}>
            Ant. {historico.saldo_anterior} · Ent.{" "}
            {historico.total_entregados} · Ret. {historico.total_retirados} ·
            Final {historico.saldo_final}
          </Text>
        </View>
      ) : null}

      {(historico?.movimientos ?? []).length === 0 ? (
        <EmptyState message="Sin movimientos en el rango." />
      ) : (
        (historico?.movimientos ?? []).map((m) => (
          <View key={m.id || `${m.fecha_movimiento}-${m.contenedor_id}`} style={styles.card}>
            <Text style={styles.name}>
              {m.nombre_contenedor ?? m.codigo_contenedor ?? "Contenedor"}
            </Text>
            <Text style={styles.meta}>
              {formatDate(m.fecha_movimiento)}
              {m.correlativo_orden != null
                ? ` · Orden #${m.correlativo_orden}`
                : ""}
            </Text>
            <Text style={styles.meta}>
              Ent. {m.cantidad_entregada} · Ret. {m.cantidad_retirada}
            </Text>
          </View>
        ))
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
  title: { fontSize: 22, fontWeight: "700", color: "#0B3A5C" },
  meta: { fontSize: 13, color: "#5B6B7C", marginTop: 2 },
  card: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    borderWidth: 1,
    borderColor: "#E5EAF0",
  },
  name: { fontWeight: "600", color: "#0B3A5C", fontSize: 16 },
  saldo: { marginTop: 4, fontWeight: "700", color: "#0B3A5C" },
});
