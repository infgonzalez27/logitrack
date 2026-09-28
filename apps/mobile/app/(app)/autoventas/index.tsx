import { useCallback, useMemo, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { useFocusEffect, useRouter } from "expo-router";
import { listarCamiones, type CamionOption } from "@/lib/catalogos";
import {
  cargarInventarioMovil,
  listarInventarioMovil,
  obtenerResumenAutoventas,
  reversarInventarioMovil,
  type InventarioMovilRow,
  type ResumenAutoVentaData,
} from "@/lib/autoventas";
import { listarProductos, type ProductoLista } from "@/lib/productos";
import { formatMoney } from "@/lib/format";
import { ErrorText, PrimaryButton, SectionTitle } from "@/components/ui";

type Tab = "resumen" | "carga" | "reverso";

export default function AutoventasScreen() {
  const router = useRouter();
  const [tab, setTab] = useState<Tab>("resumen");
  const [camiones, setCamiones] = useState<CamionOption[]>([]);
  const [camionId, setCamionId] = useState("");
  const [resumen, setResumen] = useState<ResumenAutoVentaData | null>(null);
  const [inventario, setInventario] = useState<InventarioMovilRow[]>([]);
  const [productos, setProductos] = useState<ProductoLista[]>([]);
  const [cantidadesCarga, setCantidadesCarga] = useState<Record<string, string>>(
    {},
  );
  const [cantidadesReverso, setCantidadesReverso] = useState<
    Record<string, string>
  >({});
  const [productoQ, setProductoQ] = useState("");
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [picking, setPicking] = useState(false);

  const loadResumen = useCallback(async (id: string) => {
    if (!id) {
      setResumen(null);
      setInventario([]);
      return;
    }
    const [res, inv] = await Promise.all([
      obtenerResumenAutoventas(id),
      listarInventarioMovil(id),
    ]);
    if (!res.ok) {
      setError(res.error);
      setResumen(null);
    } else {
      setError(null);
      setResumen(res.resumen);
    }
    if (inv.ok) {
      setInventario(inv.rows);
      const init: Record<string, string> = {};
      for (const r of inv.rows) {
        const disp =
          Math.max(0, Number(r.cantidad_cargada) - Number(r.cantidad_entregada)) ||
          0;
        init[r.producto_id] = disp > 0 ? String(disp) : "";
      }
      setCantidadesReverso(init);
    }
  }, []);

  const loadProductos = useCallback(async (term: string) => {
    const res = await listarProductos(term || ".F.");
    if (res.ok) setProductos(res.productos.slice(0, 80));
  }, []);

  const load = useCallback(async () => {
    const camRes = await listarCamiones();
    if (!camRes.ok) {
      setError(camRes.error);
      setCamiones([]);
    } else {
      setCamiones(camRes.camiones);
      const nextId = camionId || camRes.camiones[0]?.id || "";
      setCamionId(nextId);
      if (nextId) await loadResumen(nextId);
    }
    await loadProductos(productoQ);
    setLoading(false);
    setRefreshing(false);
  }, [camionId, loadResumen, loadProductos, productoQ]);

  useFocusEffect(
    useCallback(() => {
      setLoading(true);
      void load();
    }, [load]),
  );

  const productosFiltrados = useMemo(() => {
    const term = productoQ.trim().toLowerCase();
    if (!term) return productos;
    return productos.filter(
      (p) =>
        p.nombre.toLowerCase().includes(term) ||
        (p.codigo_producto ?? "").toLowerCase().includes(term),
    );
  }, [productos, productoQ]);

  async function onCargar() {
    if (!camionId) {
      setError("Selecciona un camión.");
      return;
    }
    const items = Object.entries(cantidadesCarga)
      .map(([producto_id, raw]) => ({
        producto_id,
        cantidad_solicitada: Number(String(raw).replace(",", ".")) || 0,
      }))
      .filter((p) => p.cantidad_solicitada > 0);

    if (!items.length) {
      setError("Indica cantidades a cargar.");
      return;
    }

    setSaving(true);
    setError(null);
    setMessage(null);
    const res = await cargarInventarioMovil({
      camionId,
      productos: items,
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    setMessage(res.message || "Inventario cargado.");
    setCantidadesCarga({});
    await loadResumen(camionId);
  }

  async function onReversar(todo = false) {
    if (!camionId) {
      setError("Selecciona un camión.");
      return;
    }

    let productosPayload:
      | Array<{ producto_id: string; cantidad_solicitada: number }>
      | undefined;

    if (!todo) {
      productosPayload = Object.entries(cantidadesReverso)
        .map(([producto_id, raw]) => ({
          producto_id,
          cantidad_solicitada: Number(String(raw).replace(",", ".")) || 0,
        }))
        .filter((p) => p.cantidad_solicitada > 0);
      if (!productosPayload.length) {
        setError("Indica cantidades a devolver, o usa «Devolver todo».");
        return;
      }
    }

    setSaving(true);
    setError(null);
    setMessage(null);
    const res = await reversarInventarioMovil({
      camionId,
      productos: productosPayload,
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    setMessage(res.message || "Inventario devuelto al almacén.");
    await loadResumen(camionId);
  }

  if (picking) {
    return (
      <View style={styles.root}>
        <Pressable onPress={() => setPicking(false)}>
          <Text style={styles.back}>← Volver</Text>
        </Pressable>
        <FlatList
          data={camiones}
          keyExtractor={(c) => c.id}
          renderItem={({ item }) => (
            <Pressable
              style={styles.card}
              onPress={() => {
                setCamionId(item.id);
                setPicking(false);
                setLoading(true);
                void loadResumen(item.id).finally(() => setLoading(false));
              }}
            >
              <Text style={styles.name}>{item.placa}</Text>
            </Pressable>
          )}
        />
      </View>
    );
  }

  const camionLabel =
    camiones.find((c) => c.id === camionId)?.placa ?? "Elegir camión";

  return (
    <View style={styles.root}>
      <Pressable style={styles.select} onPress={() => setPicking(true)}>
        <Text style={styles.selectText}>{camionLabel}</Text>
      </Pressable>

      <View style={styles.tabs}>
        {(
          [
            ["resumen", "Resumen"],
            ["carga", "Carga"],
            ["reverso", "Reverso"],
          ] as const
        ).map(([key, label]) => (
          <Pressable
            key={key}
            style={[styles.tab, tab === key && styles.tabActive]}
            onPress={() => setTab(key)}
          >
            <Text
              style={[styles.tabText, tab === key && styles.tabTextActive]}
            >
              {label}
            </Text>
          </Pressable>
        ))}
      </View>

      {tab === "resumen" ? (
        <Pressable
          style={styles.btn}
          onPress={() =>
            router.push({
              pathname: "/(app)/autoventas/nueva",
              params: { camionId },
            })
          }
        >
          <Text style={styles.btnText}>Nueva venta en ruta</Text>
        </Pressable>
      ) : null}

      <ErrorText message={error} />
      {message ? <Text style={styles.ok}>{message}</Text> : null}

      {loading ? (
        <ActivityIndicator style={{ marginTop: 24 }} color="#0B3A5C" />
      ) : tab === "resumen" ? (
        <FlatList
          data={resumen?.inventario_movil ?? []}
          keyExtractor={(i) => i.producto_id}
          refreshControl={
            <RefreshControl
              refreshing={refreshing}
              onRefresh={() => {
                setRefreshing(true);
                void loadResumen(camionId).finally(() =>
                  setRefreshing(false),
                );
              }}
            />
          }
          ListHeaderComponent={
            <View style={{ gap: 8, marginBottom: 8 }}>
              <Text style={styles.section}>Resumen del día</Text>
              <View style={styles.card}>
                <Text style={styles.meta}>
                  Ventas: {resumen?.total_ordenes_autoventa ?? 0}
                </Text>
                <Text style={styles.name}>
                  ${formatMoney(resumen?.total_facturado_usd)}
                </Text>
                <Text style={styles.meta}>
                  {formatMoney(resumen?.total_facturado_bs)} Bs
                </Text>
              </View>
              <Text style={styles.section}>Inventario en camión</Text>
              {(resumen?.inventario_movil?.length ?? 0) === 0 ? (
                <Text style={styles.empty}>Sin stock móvil en este camión.</Text>
              ) : null}
            </View>
          }
          renderItem={({ item }) => (
            <View style={styles.card}>
              <Text style={styles.name}>{item.nombre}</Text>
              <Text style={styles.meta}>{item.codigo}</Text>
              <Text style={styles.meta}>
                Disp. {item.cantidad_disponible} · Cargado{" "}
                {item.cantidad_cargada} · Entregado {item.cantidad_entregada}
              </Text>
            </View>
          )}
          ListFooterComponent={
            <View style={{ marginTop: 12, gap: 8 }}>
              <Text style={styles.section}>Ventas de hoy</Text>
              {(resumen?.ventas ?? []).length === 0 ? (
                <Text style={styles.empty}>Aún no hay ventas.</Text>
              ) : (
                (resumen?.ventas ?? []).map((v) => (
                  <View key={v.orden_id} style={styles.card}>
                    <Text style={styles.name}>
                      #{v.correlativo} · {v.cliente_nombre}
                    </Text>
                    <Text style={styles.meta}>
                      ${formatMoney(v.total_recaudar_usd)} · {v.estado}
                    </Text>
                  </View>
                ))
              )}
            </View>
          }
        />
      ) : tab === "carga" ? (
        <FlatList
          data={productosFiltrados}
          keyExtractor={(p) => p.id}
          ListHeaderComponent={
            <View style={{ marginBottom: 8, gap: 8 }}>
              <SectionTitle>Cargar desde almacén</SectionTitle>
              <TextInput
                style={styles.search}
                placeholder="Buscar producto…"
                value={productoQ}
                onChangeText={setProductoQ}
                onSubmitEditing={() => void loadProductos(productoQ)}
                returnKeyType="search"
              />
              <PrimaryButton
                label="Cargar al camión"
                loading={saving}
                onPress={() => void onCargar()}
              />
            </View>
          }
          renderItem={({ item }) => (
            <View style={styles.card}>
              <Text style={styles.name}>{item.nombre}</Text>
              <Text style={styles.meta}>
                {item.codigo_producto ?? ""} · Stock almacén{" "}
                {item.stock_disponible}
              </Text>
              <TextInput
                style={styles.qty}
                keyboardType="decimal-pad"
                placeholder="Cantidad"
                value={cantidadesCarga[item.id] ?? ""}
                onChangeText={(t) =>
                  setCantidadesCarga((prev) => ({ ...prev, [item.id]: t }))
                }
              />
            </View>
          )}
        />
      ) : (
        <FlatList
          data={inventario}
          keyExtractor={(r) => r.id}
          ListHeaderComponent={
            <View style={{ marginBottom: 8, gap: 8 }}>
              <SectionTitle>Devolver a almacén</SectionTitle>
              <PrimaryButton
                label="Devolver cantidades indicadas"
                loading={saving}
                onPress={() => void onReversar(false)}
              />
              <Pressable
                style={styles.btnGhost}
                onPress={() => {
                  Alert.alert(
                    "Devolver todo",
                    "¿Devolver todo el inventario disponible del camión al almacén?",
                    [
                      { text: "Cancelar", style: "cancel" },
                      {
                        text: "Devolver todo",
                        onPress: () => void onReversar(true),
                      },
                    ],
                  );
                }}
              >
                <Text style={styles.btnGhostText}>Devolver todo (RPC)</Text>
              </Pressable>
            </View>
          }
          ListEmptyComponent={
            <Text style={styles.empty}>Sin inventario móvil en este camión.</Text>
          }
          renderItem={({ item }) => {
            const disp = Math.max(
              0,
              Number(item.cantidad_cargada) - Number(item.cantidad_entregada),
            );
            return (
              <View style={styles.card}>
                <Text style={styles.name}>
                  {item.productos?.nombre ?? item.producto_id}
                </Text>
                <Text style={styles.meta}>
                  {item.productos?.codigo_producto ?? ""} · Disp. {disp}
                </Text>
                <TextInput
                  style={styles.qty}
                  keyboardType="decimal-pad"
                  placeholder="Cantidad a devolver"
                  value={cantidadesReverso[item.producto_id] ?? ""}
                  onChangeText={(t) =>
                    setCantidadesReverso((prev) => ({
                      ...prev,
                      [item.producto_id]: t,
                    }))
                  }
                />
              </View>
            );
          }}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F6F8", padding: 16 },
  select: {
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 12,
    padding: 14,
    marginBottom: 10,
  },
  selectText: { fontSize: 16, color: "#0B3A5C", fontWeight: "600" },
  tabs: { flexDirection: "row", gap: 6, marginBottom: 10 },
  tab: {
    flex: 1,
    paddingVertical: 10,
    borderRadius: 10,
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#E5EAF0",
    alignItems: "center",
  },
  tabActive: { backgroundColor: "#0B3A5C", borderColor: "#0B3A5C" },
  tabText: { color: "#0B3A5C", fontWeight: "600", fontSize: 13 },
  tabTextActive: { color: "#fff" },
  btn: {
    backgroundColor: "#0B3A5C",
    borderRadius: 12,
    paddingVertical: 12,
    alignItems: "center",
    marginBottom: 12,
  },
  btnText: { color: "#fff", fontWeight: "600" },
  btnGhost: {
    borderWidth: 1,
    borderColor: "#0B3A5C",
    borderRadius: 12,
    paddingVertical: 12,
    alignItems: "center",
    backgroundColor: "#fff",
  },
  btnGhostText: { color: "#0B3A5C", fontWeight: "600" },
  section: { fontSize: 16, fontWeight: "600", color: "#0B3A5C" },
  card: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 12,
    marginBottom: 8,
    borderWidth: 1,
    borderColor: "#E5EAF0",
  },
  name: { fontWeight: "600", color: "#0B3A5C" },
  meta: { fontSize: 13, color: "#5B6B7C", marginTop: 2 },
  empty: { color: "#5B6B7C", marginBottom: 8 },
  ok: { color: "#027A48", marginBottom: 8, fontWeight: "600" },
  back: { color: "#0B3A5C", fontWeight: "600", marginBottom: 10 },
  search: {
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 10,
    fontSize: 16,
    color: "#0B3A5C",
  },
  qty: {
    marginTop: 8,
    backgroundColor: "#F4F6F8",
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 8,
    color: "#0B3A5C",
  },
});
