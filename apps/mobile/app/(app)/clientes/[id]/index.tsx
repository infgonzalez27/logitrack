import { useCallback, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  Pressable,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { useLocalSearchParams, useRouter, useFocusEffect, type Href } from "expo-router";
import { Ionicons } from "@expo/vector-icons";
import { useAuth } from "@/lib/auth-context";
import {
  getClienteVisita,
  solicitaAbonosCliente,
  type AbonosCliente,
  type ClienteVisita,
} from "@/lib/clientes";
import { getOrdenDetalle } from "@/lib/ordenes";
import { buildTicketForOrden } from "@/lib/print-orden";
import { printToPreferredPrinter } from "@/lib/bluetooth-print";
import { formatMoney, formatDate } from "@/lib/format";

export default function ClienteVisitaScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { profile } = useAuth();
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [cliente, setCliente] = useState<ClienteVisita | null>(null);
  const [abonos, setAbonos] = useState<AbonosCliente | null>(null);
  const [imprimiendoId, setImprimiendoId] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!profile || !id) return;
    setError(null);
    const [cRes, aRes] = await Promise.all([
      getClienteVisita(id, profile),
      solicitaAbonosCliente(id),
    ]);
    if (!cRes.ok) {
      setError(cRes.error);
      setCliente(null);
      setAbonos(null);
    } else {
      setCliente(cRes.cliente);
      if (aRes.ok) setAbonos(aRes.abonos);
      else setAbonos(null);
    }
    setLoading(false);
    setRefreshing(false);
  }, [profile, id]);

  useFocusEffect(
    useCallback(() => {
      setLoading(true);
      void load();
    }, [load]),
  );

  const onImprimirOrden = async (ordenId: string, correlativo: number) => {
    setImprimiendoId(ordenId);
    try {
      const resDetalle = await getOrdenDetalle(ordenId);
      if (!resDetalle.ok) {
        Alert.alert(
          "Error",
          `No se pudo obtener el detalle de la orden #${correlativo}: ${resDetalle.error}`,
        );
        return;
      }
      const ticket = await buildTicketForOrden(resDetalle.orden);
      const printRes = await printToPreferredPrinter(ticket.text);
      if (!printRes.ok) {
        if (printRes.sinImpresora) {
          Alert.alert(
            "Sin impresora guardada",
            "Configura tu impresora Bluetooth para imprimir tickets.",
            [
              { text: "Cancelar", style: "cancel" },
              {
                text: "Configurar impresora",
                onPress: () => router.push("/(app)/impresora" as Href),
              },
            ],
          );
        } else {
          Alert.alert("Error de impresión", printRes.error);
        }
        return;
      }
      Alert.alert(
        "Ticket impreso",
        `Ticket de la orden #${correlativo} enviado a la impresora.`,
      );
    } catch (e) {
      Alert.alert(
        "Error",
        e instanceof Error ? e.message : "Error al procesar la impresión.",
      );
    } finally {
      setImprimiendoId(null);
    }
  };

  if (loading) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color="#0B3A5C" />
      </View>
    );
  }

  if (error || !cliente) {
    return (
      <View style={styles.center}>
        <Text style={styles.error}>{error ?? "Sin datos"}</Text>
        <Pressable onPress={() => router.back()}>
          <Text style={styles.link}>Volver</Text>
        </Pressable>
      </View>
    );
  }

  const pendientes =
    abonos?.ordenes.filter((o) => o.saldo_pendiente > 0) ?? [];
  const puedeCrearOrden =
    profile?.rol === "vendedor" ||
    profile?.rol === "gerente" ||
    profile?.rol === "admin";
  const puedeRendir =
    profile?.rol === "vendedor" ||
    profile?.rol === "gerente" ||
    profile?.rol === "admin";

  return (
    <ScrollView
      style={styles.root}
      contentContainerStyle={{ padding: 16, gap: 12 }}
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
      <Text style={styles.title}>{cliente.razon_social}</Text>
      <Text style={styles.meta}>{cliente.rif_nit}</Text>
      {cliente.direccion_fiscal ? (
        <Text style={styles.meta}>{cliente.direccion_fiscal}</Text>
      ) : null}

      <Pressable onPress={() => router.push("/(app)/visita" as Href)}>
        <Text style={styles.link}>← Volver a Visita / cartera</Text>
      </Pressable>

      <View style={styles.card}>
        <Text style={styles.cardLabel}>Saldo a favor</Text>
        <Text style={styles.cardValue}>
          ${formatMoney(abonos?.saldo_favor ?? 0)}
          {abonos?.saldo_favor_bs != null
            ? ` · ${formatMoney(abonos.saldo_favor_bs)} Bs`
            : ""}
        </Text>
      </View>

      <Pressable
        style={styles.btnSecondary}
        onPress={() =>
          router.push(`/(app)/clientes/${cliente.id}/editar` as Href)
        }
      >
        <Text style={styles.btnSecondaryText}>Editar / descuentos</Text>
      </Pressable>

      {puedeCrearOrden ? (
        <Pressable
          style={styles.btnPrimary}
          onPress={() =>
            router.push({
              pathname: "/(app)/ordenes/nueva",
              params: { clienteId: cliente.id },
            })
          }
        >
          <Text style={styles.btnPrimaryText}>Nueva orden</Text>
        </Pressable>
      ) : null}

      {puedeRendir && pendientes.length > 0 ? (
        <Pressable
          style={styles.btnSecondary}
          onPress={() =>
            router.push({
              pathname: "/(app)/rendiciones/nueva",
              params: { clienteId: cliente.id },
            })
          }
        >
          <Text style={styles.btnSecondaryText}>Cobrar / Rendición</Text>
        </Pressable>
      ) : null}

      {!cliente.despachador_id ? (
        <Text style={styles.warn}>
          Sin despachador asignado: no se puede crear orden hasta asignarlo en
          la web.
        </Text>
      ) : null}

      <Text style={styles.section}>
        Órdenes con saldo ({pendientes.length})
      </Text>
      {pendientes.length === 0 ? (
        <Text style={styles.empty}>No hay saldos pendientes.</Text>
      ) : (
        pendientes.map((o) => (
          <View key={o.id} style={styles.row}>
            <Pressable
              onPress={() =>
                router.push({
                  pathname: "/(app)/ordenes/[id]",
                  params: { id: o.id },
                })
              }
            >
              <View style={styles.rowTop}>
                <Text style={styles.rowTitle}>#{o.correlativo}</Text>
                <Text style={styles.saldo}>
                  Pendiente ${formatMoney(o.saldo_pendiente)}
                </Text>
              </View>
              <Text style={styles.meta}>
                {formatDate(o.fecha_despacho)}
                {o.dias_vencidos != null ? ` · ${o.dias_vencidos}d` : ""}
              </Text>
            </Pressable>

            <View style={styles.rowActions}>
              <Pressable
                style={styles.btnPrint}
                disabled={imprimiendoId === o.id}
                onPress={() => void onImprimirOrden(o.id, o.correlativo)}
              >
                {imprimiendoId === o.id ? (
                  <ActivityIndicator size="small" color="#fff" />
                ) : (
                  <>
                    <Ionicons name="print-outline" size={16} color="#fff" />
                    <Text style={styles.btnPrintText}>Imprimir</Text>
                  </>
                )}
              </Pressable>

              <Pressable
                style={styles.btnVer}
                onPress={() =>
                  router.push({
                    pathname: "/(app)/ordenes/[id]",
                    params: { id: o.id },
                  })
                }
              >
                <Ionicons name="eye-outline" size={16} color="#0B3A5C" />
                <Text style={styles.btnVerText}>Ver orden</Text>
              </Pressable>
            </View>
          </View>
        ))
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F6F8" },
  center: { flex: 1, alignItems: "center", justifyContent: "center", padding: 24 },
  title: { fontSize: 22, fontWeight: "700", color: "#0B3A5C" },
  meta: { fontSize: 14, color: "#5B6B7C" },
  card: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    borderWidth: 1,
    borderColor: "#E5EAF0",
  },
  cardLabel: { fontSize: 12, color: "#5B6B7C", textTransform: "uppercase" },
  cardValue: { fontSize: 20, fontWeight: "700", color: "#0B3A5C", marginTop: 4 },
  btnPrimary: {
    backgroundColor: "#0B3A5C",
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: "center",
  },
  btnPrimaryText: { color: "#fff", fontWeight: "600", fontSize: 16 },
  btnSecondary: {
    borderWidth: 1,
    borderColor: "#0B3A5C",
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: "center",
    backgroundColor: "#fff",
  },
  btnSecondaryText: { color: "#0B3A5C", fontWeight: "600", fontSize: 16 },
  warn: { color: "#B54708", fontSize: 13 },
  section: { marginTop: 8, fontSize: 16, fontWeight: "600", color: "#0B3A5C" },
  empty: { color: "#5B6B7C", fontSize: 14 },
  row: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    borderWidth: 1,
    borderColor: "#E5EAF0",
    gap: 8,
  },
  rowTop: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  rowTitle: { fontWeight: "700", fontSize: 16, color: "#0B3A5C" },
  saldo: { fontWeight: "700", fontSize: 15, color: "#B42318" },
  rowActions: {
    flexDirection: "row",
    gap: 10,
    marginTop: 6,
    borderTopWidth: 1,
    borderTopColor: "#F2F4F7",
    paddingTop: 8,
  },
  btnPrint: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 6,
    backgroundColor: "#0B3A5C",
    paddingVertical: 9,
    borderRadius: 8,
  },
  btnPrintText: {
    color: "#fff",
    fontWeight: "600",
    fontSize: 14,
  },
  btnVer: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 6,
    borderWidth: 1,
    borderColor: "#0B3A5C",
    backgroundColor: "#fff",
    paddingVertical: 9,
    borderRadius: 8,
  },
  btnVerText: {
    color: "#0B3A5C",
    fontWeight: "600",
    fontSize: 14,
  },
  error: { color: "#B42318", marginBottom: 12 },
  link: { color: "#0B3A5C", textDecorationLine: "underline" },
});
