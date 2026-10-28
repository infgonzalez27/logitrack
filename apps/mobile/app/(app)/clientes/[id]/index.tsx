import { useCallback, useMemo, useState } from "react";
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

  const pendientes = useMemo(
    () => abonos?.ordenes.filter((o) => o.saldo_pendiente > 0) ?? [],
    [abonos?.ordenes],
  );

  const totalDeuda = useMemo(
    () => pendientes.reduce((acc, curr) => acc + (Number(curr.saldo_pendiente) || 0), 0),
    [pendientes],
  );

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
        <Ionicons name="alert-circle-outline" size={48} color="#B42318" />
        <Text style={styles.error}>{error ?? "No se encontró el cliente"}</Text>
        <Pressable
          style={styles.backBtn}
          onPress={() => router.push("/(app)/visita" as Href)}
        >
          <Ionicons name="arrow-back" size={16} color="#0B3A5C" />
          <Text style={styles.backBtnText}>Volver a Cartera</Text>
        </Pressable>
      </View>
    );
  }

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
      contentContainerStyle={styles.scrollContent}
      showsVerticalScrollIndicator={false}
      refreshControl={
        <RefreshControl
          refreshing={refreshing}
          onRefresh={() => {
            setRefreshing(true);
            void load();
          }}
          tintColor="#0B3A5C"
        />
      }
    >
      {/* Botón Volver */}
      <Pressable
        style={styles.topBackBar}
        onPress={() => router.push("/(app)/visita" as Href)}
        hitSlop={8}
      >
        <Ionicons name="arrow-back" size={18} color="#0B3A5C" />
        <Text style={styles.topBackText}>Volver a Visita / cartera</Text>
      </Pressable>

      {/* Tarjeta Hero del Cliente */}
      <View style={styles.heroCard}>
        <View style={styles.heroHeader}>
          <View style={styles.heroIconWrap}>
            <Ionicons name="business" size={24} color="#0B3A5C" />
          </View>
          <View style={{ flex: 1, gap: 4 }}>
            <Text style={styles.heroTitle}>{cliente.razon_social}</Text>
            <View style={styles.rifBadge}>
              <Text style={styles.rifBadgeText}>{cliente.rif_nit}</Text>
            </View>
          </View>
        </View>

        {cliente.direccion_fiscal ? (
          <View style={styles.addressRow}>
            <Ionicons name="location-outline" size={16} color="#64748B" />
            <Text style={styles.addressText}>{cliente.direccion_fiscal}</Text>
          </View>
        ) : null}
      </View>

      {/* Resumen Financiero de 2 Columnas */}
      <View style={styles.balanceGrid}>
        {/* Saldo a Favor */}
        <View style={styles.balanceBox}>
          <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
            <Ionicons name="arrow-down-circle" size={16} color="#027A48" />
            <Text style={styles.balanceBoxLabel}>Saldo a favor</Text>
          </View>
          <Text style={[styles.balanceBoxValue, { color: "#027A48" }]}>
            ${formatMoney(abonos?.saldo_favor ?? 0)}
          </Text>
          {abonos?.saldo_favor_bs != null ? (
            <Text style={styles.balanceBoxSub}>
              {formatMoney(abonos.saldo_favor_bs)} Bs
            </Text>
          ) : null}
        </View>

        {/* Deuda Pendiente */}
        <View style={styles.balanceBox}>
          <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
            <Ionicons name="alert-circle" size={16} color="#B42318" />
            <Text style={styles.balanceBoxLabel}>Por cobrar</Text>
          </View>
          <Text style={[styles.balanceBoxValue, { color: "#B42318" }]}>
            ${formatMoney(totalDeuda)}
          </Text>
          <Text style={styles.balanceBoxSub}>
            {pendientes.length} {pendientes.length === 1 ? "orden" : "órdenes"}
          </Text>
        </View>
      </View>

      {/* Acciones Rápidas */}
      <View style={styles.actionsContainer}>
        {puedeRendir && pendientes.length > 0 ? (
          <Pressable
            style={styles.btnCobrar}
            onPress={() =>
              router.push({
                pathname: "/(app)/rendiciones/nueva",
                params: { clienteId: cliente.id },
              })
            }
          >
            <Ionicons name="flash" size={18} color="#FFFFFF" />
            <Text style={styles.btnCobrarText}>
              Cobrar (${formatMoney(totalDeuda)})
            </Text>
          </Pressable>
        ) : null}

        <View style={styles.actionRowSecondary}>
          {puedeCrearOrden ? (
            <Pressable
              style={styles.btnNuevaOrden}
              onPress={() =>
                router.push({
                  pathname: "/(app)/ordenes/nueva",
                  params: { clienteId: cliente.id },
                })
              }
            >
              <Ionicons name="add-circle-outline" size={18} color="#0B3A5C" />
              <Text style={styles.btnNuevaOrdenText}>Nueva Orden</Text>
            </Pressable>
          ) : null}

          <Pressable
            style={styles.btnEditar}
            onPress={() =>
              router.push(`/(app)/clientes/${cliente.id}/editar` as Href)
            }
          >
            <Ionicons name="create-outline" size={18} color="#475569" />
            <Text style={styles.btnEditarText}>Editar / Descuentos</Text>
          </Pressable>
        </View>
      </View>

      {!cliente.despachador_id ? (
        <View style={styles.warnCard}>
          <Ionicons name="warning-outline" size={18} color="#B54708" />
          <Text style={styles.warnText}>
            Sin despachador asignado: no se puede crear orden hasta asignarlo en el panel web.
          </Text>
        </View>
      ) : null}

      {/* Listado de Órdenes Pendientes */}
      <View style={styles.sectionHeaderRow}>
        <Text style={styles.sectionTitle}>
          Órdenes pendientes ({pendientes.length})
        </Text>
        {pendientes.length > 0 ? (
          <Text style={styles.sectionSubtitle}>
            Total: ${formatMoney(totalDeuda)}
          </Text>
        ) : null}
      </View>

      {pendientes.length === 0 ? (
        <View style={styles.emptyCard}>
          <Ionicons name="checkmark-done-circle" size={40} color="#027A48" />
          <Text style={styles.emptyTitle}>¡Sin facturas pendientes!</Text>
          <Text style={styles.emptySubtitle}>
            Este cliente se encuentra totalmente al día con sus pagos.
          </Text>
        </View>
      ) : (
        pendientes.map((o) => {
          const esVencido = (o.dias_vencidos ?? 0) > 0;
          return (
            <View key={o.id} style={styles.orderCard}>
              <Pressable
                onPress={() =>
                  router.push({
                    pathname: "/(app)/ordenes/[id]",
                    params: { id: o.id },
                  })
                }
              >
                <View style={styles.orderTopRow}>
                  <View style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
                    <Text style={styles.orderNumber}>#{o.correlativo}</Text>
                    {esVencido ? (
                      <View style={styles.vencidoBadge}>
                        <Text style={styles.vencidoBadgeText}>
                          {o.dias_vencidos}d vencido
                        </Text>
                      </View>
                    ) : (
                      <View style={styles.alDiaBadge}>
                        <Text style={styles.alDiaBadgeText}>Al día</Text>
                      </View>
                    )}
                  </View>
                  <Text style={styles.orderAmount}>
                    ${formatMoney(o.saldo_pendiente)}
                  </Text>
                </View>

                <View style={styles.orderMetaRow}>
                  <Ionicons name="calendar-outline" size={14} color="#64748B" />
                  <Text style={styles.orderMetaText}>
                    Despacho: {formatDate(o.fecha_despacho)}
                  </Text>
                </View>
              </Pressable>

              <View style={styles.orderActionsRow}>
                <Pressable
                  style={styles.btnPrint}
                  disabled={imprimiendoId === o.id}
                  onPress={() => void onImprimirOrden(o.id, o.correlativo)}
                >
                  {imprimiendoId === o.id ? (
                    <ActivityIndicator size="small" color="#0B3A5C" />
                  ) : (
                    <>
                      <Ionicons name="print-outline" size={16} color="#0B3A5C" />
                      <Text style={styles.btnPrintText}>Imprimir</Text>
                    </>
                  )}
                </Pressable>

                <Pressable
                  style={styles.btnVerOrden}
                  onPress={() =>
                    router.push({
                      pathname: "/(app)/ordenes/[id]",
                      params: { id: o.id },
                    })
                  }
                >
                  <Ionicons name="eye-outline" size={16} color="#334155" />
                  <Text style={styles.btnVerOrdenText}>Ver Detalle</Text>
                </Pressable>
              </View>
            </View>
          );
        })
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F2F5F8" },
  scrollContent: { padding: 16, paddingBottom: 32, gap: 14 },
  center: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    padding: 24,
    gap: 12,
  },
  topBackBar: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
    paddingVertical: 4,
  },
  topBackText: {
    fontSize: 14,
    fontWeight: "700",
    color: "#0B3A5C",
  },

  // Hero Card
  heroCard: {
    backgroundColor: "#FFFFFF",
    borderRadius: 18,
    padding: 16,
    borderWidth: 1,
    borderColor: "#E2E8F0",
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.05,
    shadowRadius: 5,
    elevation: 2,
    gap: 10,
  },
  heroHeader: {
    flexDirection: "row",
    alignItems: "flex-start",
    gap: 12,
  },
  heroIconWrap: {
    width: 44,
    height: 44,
    borderRadius: 14,
    backgroundColor: "#E0F2FE",
    alignItems: "center",
    justifyContent: "center",
  },
  heroTitle: {
    fontSize: 18,
    fontWeight: "800",
    color: "#0F172A",
  },
  rifBadge: {
    backgroundColor: "#F1F5F9",
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 6,
    alignSelf: "flex-start",
  },
  rifBadgeText: {
    fontSize: 12,
    fontWeight: "600",
    color: "#475569",
    fontFamily: "monospace",
  },
  addressRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
    borderTopWidth: 1,
    borderTopColor: "#F1F5F9",
    paddingTop: 8,
  },
  addressText: {
    fontSize: 13,
    color: "#64748B",
    flex: 1,
  },

  // Balance Grid
  balanceGrid: {
    flexDirection: "row",
    gap: 10,
  },
  balanceBox: {
    flex: 1,
    backgroundColor: "#FFFFFF",
    borderRadius: 16,
    padding: 14,
    borderWidth: 1,
    borderColor: "#E2E8F0",
    gap: 3,
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.04,
    shadowRadius: 3,
    elevation: 1,
  },
  balanceBoxLabel: {
    fontSize: 11,
    fontWeight: "600",
    color: "#64748B",
    textTransform: "uppercase",
  },
  balanceBoxValue: {
    fontSize: 18,
    fontWeight: "800",
  },
  balanceBoxSub: {
    fontSize: 12,
    fontWeight: "600",
    color: "#64748B",
  },

  // Actions
  actionsContainer: {
    gap: 10,
  },
  btnCobrar: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 8,
    backgroundColor: "#059669",
    borderRadius: 14,
    paddingVertical: 14,
    shadowColor: "#059669",
    shadowOffset: { width: 0, height: 3 },
    shadowOpacity: 0.25,
    shadowRadius: 6,
    elevation: 3,
  },
  btnCobrarText: {
    fontSize: 15,
    fontWeight: "800",
    color: "#FFFFFF",
  },
  actionRowSecondary: {
    flexDirection: "row",
    gap: 10,
  },
  btnNuevaOrden: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 6,
    backgroundColor: "#FFFFFF",
    borderWidth: 1.5,
    borderColor: "#0B3A5C",
    borderRadius: 12,
    paddingVertical: 11,
  },
  btnNuevaOrdenText: {
    fontSize: 13,
    fontWeight: "700",
    color: "#0B3A5C",
  },
  btnEditar: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 6,
    backgroundColor: "#FFFFFF",
    borderWidth: 1.5,
    borderColor: "#CBD5E1",
    borderRadius: 12,
    paddingVertical: 11,
  },
  btnEditarText: {
    fontSize: 13,
    fontWeight: "700",
    color: "#334155",
  },

  warnCard: {
    flexDirection: "row",
    alignItems: "center",
    gap: 10,
    backgroundColor: "#FEF3C7",
    borderWidth: 1,
    borderColor: "#FCD34D",
    padding: 12,
    borderRadius: 12,
  },
  warnText: {
    flex: 1,
    fontSize: 12,
    fontWeight: "600",
    color: "#92400E",
  },

  // Section Header
  sectionHeaderRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    marginTop: 6,
  },
  sectionTitle: {
    fontSize: 16,
    fontWeight: "800",
    color: "#0F172A",
  },
  sectionSubtitle: {
    fontSize: 13,
    fontWeight: "700",
    color: "#B42318",
  },

  // Order Cards
  orderCard: {
    backgroundColor: "#FFFFFF",
    borderRadius: 16,
    padding: 14,
    borderWidth: 1,
    borderColor: "#E2E8F0",
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.04,
    shadowRadius: 3,
    elevation: 1,
    gap: 10,
  },
  orderTopRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  orderNumber: {
    fontSize: 16,
    fontWeight: "800",
    color: "#0B3A5C",
  },
  orderAmount: {
    fontSize: 17,
    fontWeight: "800",
    color: "#B42318",
  },
  vencidoBadge: {
    backgroundColor: "#FEE2E2",
    paddingHorizontal: 7,
    paddingVertical: 1.5,
    borderRadius: 6,
  },
  vencidoBadgeText: {
    fontSize: 11,
    fontWeight: "700",
    color: "#B42318",
  },
  alDiaBadge: {
    backgroundColor: "#ECFDF5",
    paddingHorizontal: 7,
    paddingVertical: 1.5,
    borderRadius: 6,
  },
  alDiaBadgeText: {
    fontSize: 11,
    fontWeight: "700",
    color: "#027A48",
  },
  orderMetaRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
    marginTop: 4,
  },
  orderMetaText: {
    fontSize: 12,
    color: "#64748B",
  },
  orderActionsRow: {
    flexDirection: "row",
    gap: 8,
    borderTopWidth: 1,
    borderTopColor: "#F1F5F9",
    paddingTop: 10,
  },
  btnPrint: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 6,
    backgroundColor: "#F0F9FF",
    borderWidth: 1,
    borderColor: "#BAE6FD",
    paddingVertical: 8,
    borderRadius: 9,
  },
  btnPrintText: {
    fontSize: 13,
    fontWeight: "700",
    color: "#0B3A5C",
  },
  btnVerOrden: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 6,
    backgroundColor: "#F8FAFC",
    borderWidth: 1,
    borderColor: "#E2E8F0",
    paddingVertical: 8,
    borderRadius: 9,
  },
  btnVerOrdenText: {
    fontSize: 13,
    fontWeight: "700",
    color: "#334155",
  },

  // Empty State
  emptyCard: {
    backgroundColor: "#FFFFFF",
    borderRadius: 16,
    padding: 24,
    alignItems: "center",
    justifyContent: "center",
    gap: 6,
    borderWidth: 1,
    borderColor: "#E2E8F0",
  },
  emptyTitle: {
    fontSize: 16,
    fontWeight: "700",
    color: "#027A48",
  },
  emptySubtitle: {
    fontSize: 12,
    color: "#64748B",
    textAlign: "center",
  },
  error: { color: "#B42318", fontSize: 14, textAlign: "center" },
  backBtn: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
    backgroundColor: "#E0F2FE",
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 10,
  },
  backBtnText: {
    fontSize: 14,
    fontWeight: "700",
    color: "#0B3A5C",
  },
});
