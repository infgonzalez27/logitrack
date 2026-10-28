import { useCallback, useMemo, useState } from "react";
import {
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
  listClientesForProfile,
  type ClienteListaItem,
} from "@/lib/clientes";
import {
  retornaOrdenesPorLiquidar,
  type OrdenPorLiquidarCliente,
} from "@/lib/rendiciones";
import { formatMoney } from "@/lib/format";
import { ErrorText, LoadingBlock } from "@/components/ui";

type CarteraRow = {
  cliente_id: string;
  razon_social: string;
  rif_nit: string;
  monto_por_liquidar: number;
  cant_ordenes: number;
  dias_vencidos: number;
};

export default function VisitaCarteraScreen() {
  const { profile } = useAuth();
  const router = useRouter();
  const [q, setQ] = useState("");
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [cartera, setCartera] = useState<OrdenPorLiquidarCliente[]>([]);
  const [clientes, setClientes] = useState<ClienteListaItem[]>([]);
  const [mode, setMode] = useState<"cartera" | "todos">("cartera");

  const load = useCallback(async () => {
    if (!profile) return;
    setError(null);
    const [cRes, cliRes] = await Promise.all([
      retornaOrdenesPorLiquidar(),
      listClientesForProfile(profile),
    ]);
    if (!cRes.ok) setError(cRes.error);
    else setCartera(cRes.items);
    if (!cliRes.ok) setError((prev) => prev ?? cliRes.error);
    else setClientes(cliRes.clientes);
    setLoading(false);
    setRefreshing(false);
  }, [profile]);

  useFocusEffect(
    useCallback(() => {
      setLoading(true);
      void load();
    }, [load]),
  );

  // Búsqueda en vivo (Live filtering)
  const term = q.trim().toLowerCase();

  const carteraFiltered = useMemo(() => {
    let rows: CarteraRow[] = cartera.map((c) => ({
      cliente_id: c.cliente_id,
      razon_social: c.razon_social,
      rif_nit: c.rif_nit,
      monto_por_liquidar: c.monto_por_liquidar,
      cant_ordenes: c.cant_ordenes,
      dias_vencidos: c.dias_vencidos,
    }));

    if (profile?.rol === "vendedor") {
      const ids = new Set(clientes.map((c) => c.id));
      if (ids.size) {
        rows = rows.filter((r) => ids.has(r.cliente_id));
      }
    }

    if (term) {
      rows = rows.filter(
        (r) =>
          r.razon_social.toLowerCase().includes(term) ||
          r.rif_nit.toLowerCase().includes(term),
      );
    }
    return rows.filter((r) => r.monto_por_liquidar > 0);
  }, [cartera, clientes, term, profile?.rol]);

  const todosFiltered = useMemo(() => {
    if (!term) return clientes;
    return clientes.filter(
      (c) =>
        c.razon_social.toLowerCase().includes(term) ||
        c.rif_nit.toLowerCase().includes(term),
    );
  }, [clientes, term]);

  // Totales financieros de la cartera
  const metrics = useMemo(() => {
    const totalMonto = carteraFiltered.reduce(
      (acc, curr) => acc + (Number(curr.monto_por_liquidar) || 0),
      0,
    );
    const totalOrdenes = carteraFiltered.reduce(
      (acc, curr) => acc + (Number(curr.cant_ordenes) || 0),
      0,
    );
    return {
      totalMonto,
      totalOrdenes,
      clientesConDeuda: carteraFiltered.length,
    };
  }, [carteraFiltered]);

  function openCliente(clienteId: string) {
    router.push(`/(app)/clientes/${clienteId}` as Href);
  }

  function openRendicion(clienteId: string) {
    router.push({
      pathname: "/(app)/rendiciones/nueva",
      params: { clienteId },
    });
  }

  function openNuevaOrden(clienteId: string) {
    router.push({
      pathname: "/(app)/ordenes/nueva",
      params: { clienteId },
    });
  }

  if (loading) return <LoadingBlock />;

  return (
    <View style={styles.root}>
      {/* Barra de búsqueda interactiva en vivo */}
      <View style={styles.searchContainer}>
        <Ionicons name="search-outline" size={20} color="#64748B" />
        <TextInput
          style={styles.searchInput}
          placeholder="Buscar cliente por nombre o RIF…"
          placeholderTextColor="#94A3B8"
          value={q}
          onChangeText={setQ}
          autoCapitalize="none"
          autoCorrect={false}
          returnKeyType="search"
        />
        {q.length > 0 ? (
          <Pressable onPress={() => setQ("")} hitSlop={8}>
            <Ionicons name="close-circle" size={18} color="#94A3B8" />
          </Pressable>
        ) : null}
      </View>

      {/* Tabs segmentadas con badges */}
      <View style={styles.tabBar}>
        <Pressable
          style={[styles.tabItem, mode === "cartera" && styles.tabItemActive]}
          onPress={() => setMode("cartera")}
        >
          <Ionicons
            name="wallet-outline"
            size={16}
            color={mode === "cartera" ? "#0B3A5C" : "#64748B"}
          />
          <Text
            style={[
              styles.tabItemText,
              mode === "cartera" && styles.tabItemTextActive,
            ]}
          >
            Con Saldo
          </Text>
          <View
            style={[
              styles.tabBadge,
              mode === "cartera" ? styles.tabBadgeActive : styles.tabBadgeInactive,
            ]}
          >
            <Text
              style={[
                styles.tabBadgeText,
                mode === "cartera"
                  ? styles.tabBadgeTextActive
                  : styles.tabBadgeTextInactive,
              ]}
            >
              {carteraFiltered.length}
            </Text>
          </View>
        </Pressable>

        <Pressable
          style={[styles.tabItem, mode === "todos" && styles.tabItemActive]}
          onPress={() => setMode("todos")}
        >
          <Ionicons
            name="people-outline"
            size={16}
            color={mode === "todos" ? "#0B3A5C" : "#64748B"}
          />
          <Text
            style={[
              styles.tabItemText,
              mode === "todos" && styles.tabItemTextActive,
            ]}
          >
            Todos
          </Text>
          <View
            style={[
              styles.tabBadge,
              mode === "todos" ? styles.tabBadgeActive : styles.tabBadgeInactive,
            ]}
          >
            <Text
              style={[
                styles.tabBadgeText,
                mode === "todos"
                  ? styles.tabBadgeTextActive
                  : styles.tabBadgeTextInactive,
              ]}
            >
              {todosFiltered.length}
            </Text>
          </View>
        </Pressable>
      </View>

      <ErrorText message={error} />

      {mode === "cartera" ? (
        <FlatList
          data={carteraFiltered}
          keyExtractor={(item) => item.cliente_id}
          contentContainerStyle={styles.listContent}
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
          ListHeaderComponent={
            <View style={styles.metricsCard}>
              <View style={styles.metricsCol}>
                <Text style={styles.metricsLabel}>POR LIQUIDAR</Text>
                <Text style={styles.metricsValue}>
                  ${formatMoney(metrics.totalMonto)}
                </Text>
              </View>
              <View style={styles.metricsDivider} />
              <View style={styles.metricsCol}>
                <Text style={styles.metricsLabel}>CLIENTES</Text>
                <Text style={styles.metricsSubValue}>
                  {metrics.clientesConDeuda}
                </Text>
              </View>
              <View style={styles.metricsDivider} />
              <View style={styles.metricsCol}>
                <Text style={styles.metricsLabel}>ÓRDENES</Text>
                <Text style={styles.metricsSubValue}>
                  {metrics.totalOrdenes}
                </Text>
              </View>
            </View>
          }
          ListEmptyComponent={
            <View style={styles.emptyCard}>
              <Ionicons
                name="checkmark-circle-outline"
                size={44}
                color="#027A48"
              />
              <Text style={styles.emptyTitle}>¡Todo al día!</Text>
              <Text style={styles.emptySubtitle}>
                {q.length > 0
                  ? `No se encontraron clientes con saldo para "${q}".`
                  : "No tienes clientes pendientes de cobro en tu cartera."}
              </Text>
            </View>
          }
          renderItem={({ item }) => {
            const esVencido = item.dias_vencidos > 0;
            return (
              <View style={styles.clientCard}>
                {/* Cabecera del Cliente */}
                <Pressable
                  onPress={() => openCliente(item.cliente_id)}
                  style={styles.cardHeaderPressable}
                >
                  <View style={{ flex: 1, gap: 3 }}>
                    <Text style={styles.clientName} numberOfLines={1}>
                      {item.razon_social}
                    </Text>
                    <View style={styles.clientMetaRow}>
                      <View style={styles.rifBadge}>
                        <Text style={styles.rifBadgeText}>{item.rif_nit}</Text>
                      </View>
                      {esVencido ? (
                        <View style={styles.vencidoBadge}>
                          <Ionicons
                            name="alert-circle"
                            size={12}
                            color="#B42318"
                          />
                          <Text style={styles.vencidoBadgeText}>
                            {item.dias_vencidos}d vencido
                          </Text>
                        </View>
                      ) : (
                        <View style={styles.alDiaBadge}>
                          <Ionicons
                            name="checkmark-circle"
                            size={12}
                            color="#027A48"
                          />
                          <Text style={styles.alDiaBadgeText}>Al día</Text>
                        </View>
                      )}
                    </View>
                  </View>
                </Pressable>

                {/* Saldo y Órdenes */}
                <View style={styles.balanceRow}>
                  <View>
                    <Text style={styles.balanceLabel}>Saldo Pendiente</Text>
                    <Text style={styles.balanceAmount}>
                      ${formatMoney(item.monto_por_liquidar)}
                    </Text>
                  </View>
                  <View style={styles.ordersPill}>
                    <Ionicons
                      name="receipt-outline"
                      size={14}
                      color="#475569"
                    />
                    <Text style={styles.ordersPillText}>
                      {item.cant_ordenes} orden{item.cant_ordenes === 1 ? "" : "es"}
                    </Text>
                  </View>
                </View>

                {/* Botones de Acción */}
                <View style={styles.cardActions}>
                  <Pressable
                    style={styles.btnSecondary}
                    onPress={() => openCliente(item.cliente_id)}
                    hitSlop={4}
                  >
                    <Ionicons
                      name="person-outline"
                      size={16}
                      color="#0B3A5C"
                    />
                    <Text style={styles.btnSecondaryText}>Ficha</Text>
                  </Pressable>

                  <Pressable
                    style={styles.btnPrimary}
                    onPress={() => openRendicion(item.cliente_id)}
                    hitSlop={4}
                  >
                    <Ionicons name="flash" size={16} color="#FFFFFF" />
                    <Text style={styles.btnPrimaryText}>Cobrar</Text>
                  </Pressable>
                </View>
              </View>
            );
          }}
        />
      ) : (
        <FlatList
          data={todosFiltered}
          keyExtractor={(item) => item.id}
          contentContainerStyle={styles.listContent}
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
          ListEmptyComponent={
            <View style={styles.emptyCard}>
              <Ionicons name="search-outline" size={44} color="#94A3B8" />
              <Text style={styles.emptyTitle}>Sin resultados</Text>
              <Text style={styles.emptySubtitle}>
                No se encontraron clientes que coincidan con la búsqueda.
              </Text>
            </View>
          }
          renderItem={({ item }) => (
            <Pressable
              style={styles.allClientCard}
              onPress={() => openCliente(item.id)}
            >
              <View style={{ flex: 1, gap: 4 }}>
                <Text style={styles.clientName} numberOfLines={1}>
                  {item.razon_social}
                </Text>
                <View style={styles.rifBadge}>
                  <Text style={styles.rifBadgeText}>{item.rif_nit}</Text>
                </View>
              </View>

              <View style={{ flexDirection: "row", gap: 6 }}>
                <Pressable
                  style={styles.quickOrderBtn}
                  onPress={() => openNuevaOrden(item.id)}
                  hitSlop={6}
                >
                  <Ionicons name="add" size={18} color="#0B3A5C" />
                </Pressable>
                <Ionicons
                  name="chevron-forward"
                  size={18}
                  color="#94A3B8"
                  style={{ alignSelf: "center" }}
                />
              </View>
            </Pressable>
          )}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: "#F2F5F8",
    paddingHorizontal: 16,
    paddingTop: 12,
  },
  searchContainer: {
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: "#FFFFFF",
    borderRadius: 14,
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderWidth: 1.5,
    borderColor: "#E2E8F0",
    gap: 10,
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 3,
    elevation: 2,
    marginBottom: 12,
  },
  searchInput: {
    flex: 1,
    fontSize: 15,
    color: "#0F172A",
    padding: 0,
  },
  tabBar: {
    flexDirection: "row",
    backgroundColor: "#E2E8F0",
    borderRadius: 12,
    padding: 3,
    gap: 4,
    marginBottom: 12,
  },
  tabItem: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 6,
    paddingVertical: 8,
    borderRadius: 9,
  },
  tabItemActive: {
    backgroundColor: "#FFFFFF",
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.08,
    shadowRadius: 2,
    elevation: 2,
  },
  tabItemText: {
    fontSize: 13,
    fontWeight: "600",
    color: "#64748B",
  },
  tabItemTextActive: {
    color: "#0B3A5C",
    fontWeight: "700",
  },
  tabBadge: {
    paddingHorizontal: 7,
    paddingVertical: 1.5,
    borderRadius: 10,
  },
  tabBadgeActive: {
    backgroundColor: "#E0F2FE",
  },
  tabBadgeInactive: {
    backgroundColor: "#CBD5E1",
  },
  tabBadgeText: {
    fontSize: 11,
    fontWeight: "700",
  },
  tabBadgeTextActive: {
    color: "#0369A1",
  },
  tabBadgeTextInactive: {
    color: "#475569",
  },
  listContent: {
    paddingBottom: 24,
    gap: 10,
  },

  // Metrics Header Card
  metricsCard: {
    flexDirection: "row",
    backgroundColor: "#0B3A5C",
    borderRadius: 16,
    paddingVertical: 14,
    paddingHorizontal: 16,
    alignItems: "center",
    marginBottom: 4,
    shadowColor: "#0B3A5C",
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.25,
    shadowRadius: 8,
    elevation: 4,
  },
  metricsCol: {
    flex: 1,
    alignItems: "center",
  },
  metricsDivider: {
    width: 1,
    height: 30,
    backgroundColor: "rgba(255, 255, 255, 0.2)",
  },
  metricsLabel: {
    fontSize: 10,
    fontWeight: "700",
    color: "rgba(255, 255, 255, 0.7)",
    letterSpacing: 0.5,
  },
  metricsValue: {
    fontSize: 18,
    fontWeight: "800",
    color: "#FFFFFF",
    marginTop: 2,
  },
  metricsSubValue: {
    fontSize: 16,
    fontWeight: "700",
    color: "#FFFFFF",
    marginTop: 2,
  },

  // Client Cards
  clientCard: {
    backgroundColor: "#FFFFFF",
    borderRadius: 16,
    padding: 16,
    borderWidth: 1,
    borderColor: "#E2E8F0",
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.04,
    shadowRadius: 4,
    elevation: 2,
    gap: 12,
  },
  cardHeaderPressable: {
    flexDirection: "row",
    alignItems: "flex-start",
  },
  clientName: {
    fontSize: 16,
    fontWeight: "700",
    color: "#0F172A",
  },
  clientMetaRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    marginTop: 4,
  },
  rifBadge: {
    backgroundColor: "#F1F5F9",
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 6,
    alignSelf: "flex-start",
  },
  rifBadgeText: {
    fontSize: 11,
    fontWeight: "600",
    color: "#475569",
    fontFamily: "monospace",
  },
  vencidoBadge: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
    backgroundColor: "#FEE2E2",
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 6,
  },
  vencidoBadgeText: {
    fontSize: 11,
    fontWeight: "700",
    color: "#B42318",
  },
  alDiaBadge: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
    backgroundColor: "#ECFDF5",
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 6,
  },
  alDiaBadgeText: {
    fontSize: 11,
    fontWeight: "700",
    color: "#027A48",
  },
  balanceRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "flex-end",
    backgroundColor: "#F8FAFC",
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: "#EDF2F7",
  },
  balanceLabel: {
    fontSize: 11,
    fontWeight: "600",
    color: "#64748B",
    textTransform: "uppercase",
  },
  balanceAmount: {
    fontSize: 19,
    fontWeight: "800",
    color: "#B42318",
    marginTop: 1,
  },
  ordersPill: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
    backgroundColor: "#FFFFFF",
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: "#E2E8F0",
  },
  ordersPillText: {
    fontSize: 12,
    fontWeight: "600",
    color: "#334155",
  },
  cardActions: {
    flexDirection: "row",
    gap: 10,
  },
  btnSecondary: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 6,
    backgroundColor: "#FFFFFF",
    borderWidth: 1.5,
    borderColor: "#0B3A5C",
    borderRadius: 10,
    paddingVertical: 9,
  },
  btnSecondaryText: {
    fontSize: 13,
    fontWeight: "700",
    color: "#0B3A5C",
  },
  btnPrimary: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 6,
    backgroundColor: "#0B3A5C",
    borderRadius: 10,
    paddingVertical: 9,
    shadowColor: "#0B3A5C",
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.2,
    shadowRadius: 4,
    elevation: 3,
  },
  btnPrimaryText: {
    fontSize: 13,
    fontWeight: "700",
    color: "#FFFFFF",
  },

  // All Clients Cards
  allClientCard: {
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: "#FFFFFF",
    borderRadius: 14,
    padding: 14,
    borderWidth: 1,
    borderColor: "#E2E8F0",
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.04,
    shadowRadius: 3,
    elevation: 1,
  },
  quickOrderBtn: {
    width: 32,
    height: 32,
    borderRadius: 8,
    backgroundColor: "#F0F9FF",
    borderWidth: 1,
    borderColor: "#BAE6FD",
    alignItems: "center",
    justifyContent: "center",
  },

  // Empty State
  emptyCard: {
    backgroundColor: "#FFFFFF",
    borderRadius: 16,
    padding: 32,
    alignItems: "center",
    justifyContent: "center",
    gap: 8,
    marginTop: 20,
    borderWidth: 1,
    borderColor: "#E2E8F0",
  },
  emptyTitle: {
    fontSize: 17,
    fontWeight: "700",
    color: "#0F172A",
  },
  emptySubtitle: {
    fontSize: 13,
    color: "#64748B",
    textAlign: "center",
  },
});
