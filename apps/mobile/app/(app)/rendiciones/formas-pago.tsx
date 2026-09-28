import { useCallback, useState } from "react";
import {
  FlatList,
  RefreshControl,
  StyleSheet,
  Switch,
  Text,
  View,
} from "react-native";
import { useFocusEffect } from "expo-router";
import { useAuth } from "@/lib/auth-context";
import {
  reporteFormasPago,
  type ReporteFormasPagoData,
} from "@/lib/rendiciones";
import { formatDate, formatMoney } from "@/lib/format";
import {
  EmptyState,
  ErrorText,
  FormField,
  LoadingBlock,
  PrimaryButton,
  SectionTitle,
} from "@/components/ui";

function todayYmd(): string {
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function monthStartYmd(): string {
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  return `${y}-${m}-01`;
}

export default function FormasPagoReporteScreen() {
  const { profile } = useAuth();
  const canView =
    profile?.rol === "admin" || profile?.rol === "gerente";

  const [desde, setDesde] = useState(monthStartYmd());
  const [hasta, setHasta] = useState(todayYmd());
  const [soloBancarios, setSoloBancarios] = useState(false);
  const [loading, setLoading] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [data, setData] = useState<ReporteFormasPagoData | null>(null);

  const load = useCallback(async () => {
    if (!canView) {
      setError("Solo gerencia o admin pueden consultar este reporte.");
      setLoading(false);
      setRefreshing(false);
      return;
    }
    setError(null);
    setLoading(true);
    const res = await reporteFormasPago({
      fechaDesde: desde,
      fechaHasta: hasta,
      soloBancarios,
    });
    if (!res.ok) {
      setError(res.error);
      setData(null);
    } else {
      setData(res.data);
    }
    setLoading(false);
    setRefreshing(false);
  }, [canView, desde, hasta, soloBancarios]);

  useFocusEffect(
    useCallback(() => {
      void load();
    }, [load]),
  );

  if (!canView) {
    return (
      <View style={styles.root}>
        <ErrorText message="Solo gerencia o admin pueden consultar este reporte." />
      </View>
    );
  }

  return (
    <View style={styles.root}>
      <FormField
        label="Desde (YYYY-MM-DD)"
        value={desde}
        onChangeText={setDesde}
        autoCapitalize="none"
      />
      <FormField
        label="Hasta (YYYY-MM-DD)"
        value={hasta}
        onChangeText={setHasta}
        autoCapitalize="none"
      />
      <View style={styles.switchRow}>
        <Text style={styles.switchLabel}>Solo bancarios</Text>
        <Switch
          value={soloBancarios}
          onValueChange={setSoloBancarios}
          trackColor={{ true: "#0B3A5C" }}
        />
      </View>
      <PrimaryButton label="Consultar" onPress={() => void load()} loading={loading} />

      <ErrorText message={error} />

      {loading && !data ? (
        <LoadingBlock />
      ) : data ? (
        <FlatList
          style={{ marginTop: 8 }}
          data={data.movimientos}
          keyExtractor={(m, i) => `${m.rendicion_id}-${i}`}
          refreshControl={
            <RefreshControl
              refreshing={refreshing}
              onRefresh={() => {
                setRefreshing(true);
                void load();
              }}
            />
          }
          ListHeaderComponent={
            <View style={{ marginBottom: 8 }}>
              <SectionTitle>Totales</SectionTitle>
              <View style={styles.card}>
                <Text style={styles.meta}>
                  {data.fecha_desde} → {data.fecha_hasta}
                </Text>
                <Text style={styles.name}>
                  ${formatMoney(data.monto_total_usd)} ·{" "}
                  {formatMoney(data.monto_total_bs)} Bs
                </Text>
                <Text style={styles.meta}>
                  {data.total_registros} movimiento
                  {data.total_registros === 1 ? "" : "s"}
                </Text>
              </View>
              <SectionTitle>Movimientos</SectionTitle>
            </View>
          }
          ListEmptyComponent={
            <EmptyState message="Sin movimientos en el rango." />
          }
          renderItem={({ item }) => (
            <View style={styles.card}>
              <Text style={styles.name}>{item.cliente_nombre}</Text>
              <Text style={styles.meta}>
                {formatDate(item.fecha_rendicion)} · {item.fpago_concepto}
              </Text>
              <Text style={styles.meta}>
                ${formatMoney(item.monto_usd)}
                {item.monto_bs != null
                  ? ` · ${formatMoney(item.monto_bs)} Bs`
                  : ""}
              </Text>
              {item.referencia_bancaria ? (
                <Text style={styles.meta}>Ref. {item.referencia_bancaria}</Text>
              ) : null}
            </View>
          )}
        />
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F6F8", padding: 16 },
  switchRow: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    marginBottom: 12,
    paddingHorizontal: 4,
  },
  switchLabel: { color: "#0B3A5C", fontWeight: "600" },
  card: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    marginBottom: 8,
    borderWidth: 1,
    borderColor: "#E5EAF0",
  },
  name: { fontWeight: "600", color: "#0B3A5C", fontSize: 16 },
  meta: { fontSize: 13, color: "#5B6B7C", marginTop: 2 },
});
