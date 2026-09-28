import { useCallback, useEffect, useMemo, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { useLocalSearchParams, useRouter } from "expo-router";
import { useAuth } from "@/lib/auth-context";
import {
  listClientesForProfile,
  getClienteVisita,
  type ClienteListaItem,
} from "@/lib/clientes";
import { listarCamiones, retornaUltimaTasa, type CamionOption } from "@/lib/catalogos";
import { listarProductos, precioNeto, type ProductoLista } from "@/lib/productos";
import { crearOrdenDistribucion } from "@/lib/ordenes";
import { defaultFechaDespachoLocal, formatMoney } from "@/lib/format";

type LineaDraft = {
  producto_id: string;
  nombre: string;
  codigo: string | null;
  cantidad: number;
  precio: number;
  pctDescuento: number;
};

export default function NuevaOrdenScreen() {
  const { clienteId: clienteIdParam } = useLocalSearchParams<{
    clienteId?: string;
  }>();
  const { profile } = useAuth();
  const router = useRouter();

  const [clientes, setClientes] = useState<ClienteListaItem[]>([]);
  const [clienteId, setClienteId] = useState(clienteIdParam ?? "");
  const [clienteLabel, setClienteLabel] = useState("");
  const [camionId, setCamionId] = useState("");
  const [camiones, setCamiones] = useState<CamionOption[]>([]);
  const [fechaDespacho, setFechaDespacho] = useState(defaultFechaDespachoLocal());
  const [tasa, setTasa] = useState<number | null>(null);
  const [search, setSearch] = useState("");
  const [productos, setProductos] = useState<ProductoLista[]>([]);
  const [lineas, setLineas] = useState<LineaDraft[]>([]);
  const [loadingInit, setLoadingInit] = useState(true);
  const [searching, setSearching] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [picker, setPicker] = useState<"cliente" | "camion" | "productos" | null>(
    null,
  );

  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (!profile) return;
      setLoadingInit(true);
      const [cRes, camRes, tRes] = await Promise.all([
        listClientesForProfile(profile),
        listarCamiones(),
        retornaUltimaTasa(),
      ]);
      if (cancelled) return;
      if (cRes.ok) setClientes(cRes.clientes);
      if (camRes.ok) setCamiones(camRes.camiones);
      if (tRes.ok) setTasa(tRes.tasa);

      if (clienteIdParam) {
        const visita = await getClienteVisita(clienteIdParam, profile);
        if (!cancelled && visita.ok) {
          setClienteId(visita.cliente.id);
          setClienteLabel(visita.cliente.razon_social);
        }
      }
      setLoadingInit(false);
    })();
    return () => {
      cancelled = true;
    };
  }, [profile, clienteIdParam]);

  const loadProductos = useCallback(
    async (term: string) => {
      if (!clienteId) {
        setError("Selecciona un cliente antes de buscar productos.");
        return;
      }
      setSearching(true);
      setError(null);
      const res = await listarProductos(term.trim() || ".F.", clienteId);
      if (!res.ok) setError(res.error);
      else setProductos(res.productos);
      setSearching(false);
    },
    [clienteId],
  );

  useEffect(() => {
    if (picker === "productos" && clienteId) {
      void loadProductos(search);
    }
  }, [picker, clienteId, loadProductos]);

  const total = useMemo(
    () => lineas.reduce((acc, l) => acc + l.cantidad * l.precio, 0),
    [lineas],
  );

  const addProducto = (p: ProductoLista) => {
    const precio = precioNeto(p);
    setLineas((prev) => {
      const existing = prev.find((l) => l.producto_id === p.id);
      if (existing) {
        return prev.map((l) =>
          l.producto_id === p.id ? { ...l, cantidad: l.cantidad + 1 } : l,
        );
      }
      return [
        ...prev,
        {
          producto_id: p.id,
          nombre: p.nombre,
          codigo: p.codigo_producto,
          cantidad: 1,
          precio,
          pctDescuento: Number(p.porcentaje_descuento ?? 0),
        },
      ];
    });
    setPicker(null);
  };

  const updateCantidad = (productoId: string, cantidad: number) => {
    setLineas((prev) =>
      prev
        .map((l) =>
          l.producto_id === productoId
            ? { ...l, cantidad: Math.max(0, cantidad) }
            : l,
        )
        .filter((l) => l.cantidad > 0),
    );
  };

  const submit = async () => {
    if (!profile) return;
    if (!clienteId) {
      setError("Selecciona un cliente.");
      return;
    }
    if (!camionId) {
      setError("Selecciona un camión.");
      return;
    }
    if (lineas.length === 0) {
      setError("Agrega al menos un producto.");
      return;
    }
    setSaving(true);
    setError(null);
    const fechaIso = new Date(fechaDespacho).toISOString();
    const res = await crearOrdenDistribucion({
      vendedorId: profile.id,
      clienteId,
      camionId,
      fechaDespachoIso: fechaIso,
      tasaCambio: tasa,
      lineas: lineas.map((l) => ({
        producto_id: l.producto_id,
        cantidad_solicitada: l.cantidad,
        valor_unitario_usd: l.precio,
      })),
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert("Orden creada", `Se creó la orden correctamente.`, [
      {
        text: "Ver detalle",
        onPress: () =>
          router.replace({
            pathname: "/(app)/ordenes/[id]",
            params: { id: res.ordenId },
          }),
      },
    ]);
  };

  if (loadingInit) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color="#0B3A5C" />
      </View>
    );
  }

  if (picker === "cliente") {
    return (
      <View style={styles.root}>
        <Pressable style={styles.back} onPress={() => setPicker(null)}>
          <Text style={styles.backText}>← Volver al formulario</Text>
        </Pressable>
        <FlatList
          data={clientes}
          keyExtractor={(c) => c.id}
          contentContainerStyle={{ padding: 16 }}
          renderItem={({ item }) => (
            <Pressable
              style={styles.row}
              onPress={() => {
                setClienteId(item.id);
                setClienteLabel(item.razon_social);
                setLineas([]);
                setProductos([]);
                setPicker(null);
              }}
            >
              <Text style={styles.rowTitle}>{item.razon_social}</Text>
              <Text style={styles.meta}>{item.rif_nit}</Text>
            </Pressable>
          )}
        />
      </View>
    );
  }

  if (picker === "camion") {
    return (
      <View style={styles.root}>
        <Pressable style={styles.back} onPress={() => setPicker(null)}>
          <Text style={styles.backText}>← Volver al formulario</Text>
        </Pressable>
        <FlatList
          data={camiones}
          keyExtractor={(c) => c.id}
          contentContainerStyle={{ padding: 16 }}
          ListEmptyComponent={
            <Text style={styles.meta}>No hay camiones disponibles.</Text>
          }
          renderItem={({ item }) => (
            <Pressable
              style={styles.row}
              onPress={() => {
                setCamionId(item.id);
                setPicker(null);
              }}
            >
              <Text style={styles.rowTitle}>{item.placa}</Text>
            </Pressable>
          )}
        />
      </View>
    );
  }

  if (picker === "productos") {
    return (
      <View style={styles.root}>
        <Pressable style={styles.back} onPress={() => setPicker(null)}>
          <Text style={styles.backText}>← Volver al formulario</Text>
        </Pressable>
        <View style={styles.searchRow}>
          <TextInput
            style={[styles.input, { flex: 1 }]}
            placeholder="Buscar producto…"
            value={search}
            onChangeText={setSearch}
            autoCapitalize="none"
          />
          <Pressable
            style={styles.searchBtn}
            onPress={() => void loadProductos(search)}
          >
            <Text style={styles.searchBtnText}>Buscar</Text>
          </Pressable>
        </View>
        {searching ? (
          <ActivityIndicator style={{ marginTop: 16 }} color="#0B3A5C" />
        ) : (
          <FlatList
            data={productos}
            keyExtractor={(p) => p.id}
            contentContainerStyle={{ padding: 16, paddingTop: 0 }}
            ListEmptyComponent={
              <Text style={styles.meta}>Sin resultados. Prueba otra búsqueda.</Text>
            }
            renderItem={({ item }) => {
              const neto = precioNeto(item);
              const pct = Number(item.porcentaje_descuento ?? 0);
              return (
                <Pressable style={styles.row} onPress={() => addProducto(item)}>
                  <Text style={styles.rowTitle}>{item.nombre}</Text>
                  <Text style={styles.meta}>
                    {item.codigo_producto ?? "—"} · stock{" "}
                    {item.stock_disponible}
                  </Text>
                  <Text style={styles.price}>
                    ${formatMoney(neto)}
                    {pct > 0 ? ` (−${pct}%)` : ""}
                  </Text>
                </Pressable>
              );
            }}
          />
        )}
      </View>
    );
  }

  const camionLabel =
    camiones.find((c) => c.id === camionId)?.placa ?? "Elegir camión";

  return (
    <FlatList
      style={styles.root}
      data={lineas}
      keyExtractor={(l) => l.producto_id}
      contentContainerStyle={{ padding: 16, gap: 10, paddingBottom: 40 }}
      ListHeaderComponent={
        <View style={{ gap: 10 }}>
          {error ? <Text style={styles.error}>{error}</Text> : null}

          <Text style={styles.label}>Cliente</Text>
          <Pressable style={styles.select} onPress={() => setPicker("cliente")}>
            <Text style={styles.selectText}>
              {clienteLabel || "Elegir cliente"}
            </Text>
          </Pressable>

          <Text style={styles.label}>Camión</Text>
          <Pressable style={styles.select} onPress={() => setPicker("camion")}>
            <Text style={styles.selectText}>{camionLabel}</Text>
          </Pressable>

          <Text style={styles.label}>Fecha despacho (local)</Text>
          <TextInput
            style={styles.input}
            value={fechaDespacho}
            onChangeText={setFechaDespacho}
            placeholder="YYYY-MM-DDTHH:mm"
            autoCapitalize="none"
          />

          {tasa != null ? (
            <Text style={styles.meta}>Tasa BCV: {formatMoney(tasa)}</Text>
          ) : null}

          <Pressable
            style={styles.btnSecondary}
            onPress={() => {
              if (!clienteId) {
                setError("Selecciona un cliente primero.");
                return;
              }
              setPicker("productos");
            }}
          >
            <Text style={styles.btnSecondaryText}>+ Agregar producto</Text>
          </Pressable>

          <Text style={styles.section}>Líneas</Text>
          {lineas.length === 0 ? (
            <Text style={styles.meta}>Aún no hay productos.</Text>
          ) : null}
        </View>
      }
      renderItem={({ item }) => (
        <View style={styles.line}>
          <Text style={styles.rowTitle}>{item.nombre}</Text>
          {item.codigo ? <Text style={styles.meta}>{item.codigo}</Text> : null}
          {item.pctDescuento > 0 ? (
            <Text style={styles.discount}>Descuento {item.pctDescuento}%</Text>
          ) : null}
          <View style={styles.qtyRow}>
            <Pressable
              style={styles.qtyBtn}
              onPress={() => updateCantidad(item.producto_id, item.cantidad - 1)}
            >
              <Text style={styles.qtyBtnText}>−</Text>
            </Pressable>
            <Text style={styles.qty}>{item.cantidad}</Text>
            <Pressable
              style={styles.qtyBtn}
              onPress={() => updateCantidad(item.producto_id, item.cantidad + 1)}
            >
              <Text style={styles.qtyBtnText}>+</Text>
            </Pressable>
            <Text style={styles.lineTotal}>
              ${formatMoney(item.cantidad * item.precio)}
            </Text>
          </View>
        </View>
      )}
      ListFooterComponent={
        <View style={{ gap: 12, marginTop: 8 }}>
          <Text style={styles.total}>Total ${formatMoney(total)}</Text>
          <Pressable
            style={[styles.btnPrimary, saving && { opacity: 0.6 }]}
            disabled={saving}
            onPress={() => void submit()}
          >
            {saving ? (
              <ActivityIndicator color="#fff" />
            ) : (
              <Text style={styles.btnPrimaryText}>Crear orden</Text>
            )}
          </Pressable>
        </View>
      }
    />
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F6F8" },
  center: { flex: 1, alignItems: "center", justifyContent: "center" },
  label: {
    fontSize: 12,
    color: "#5B6B7C",
    textTransform: "uppercase",
    marginTop: 4,
  },
  select: {
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 14,
  },
  selectText: { fontSize: 16, color: "#0B3A5C" },
  input: {
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 12,
    fontSize: 16,
  },
  searchRow: {
    flexDirection: "row",
    gap: 8,
    paddingHorizontal: 16,
    paddingBottom: 8,
  },
  searchBtn: {
    backgroundColor: "#0B3A5C",
    borderRadius: 12,
    paddingHorizontal: 14,
    justifyContent: "center",
  },
  searchBtnText: { color: "#fff", fontWeight: "600" },
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
    paddingVertical: 12,
    alignItems: "center",
    backgroundColor: "#fff",
  },
  btnSecondaryText: { color: "#0B3A5C", fontWeight: "600" },
  section: { fontSize: 16, fontWeight: "600", color: "#0B3A5C", marginTop: 8 },
  line: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 12,
    borderWidth: 1,
    borderColor: "#E5EAF0",
  },
  qtyRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
    marginTop: 8,
  },
  qtyBtn: {
    width: 36,
    height: 36,
    borderRadius: 8,
    backgroundColor: "#E8EEF3",
    alignItems: "center",
    justifyContent: "center",
  },
  qtyBtnText: { fontSize: 20, color: "#0B3A5C", fontWeight: "600" },
  qty: { fontSize: 16, fontWeight: "600", minWidth: 24, textAlign: "center" },
  lineTotal: { marginLeft: "auto", fontWeight: "700", color: "#0B3A5C" },
  total: { fontSize: 20, fontWeight: "700", color: "#0B3A5C", textAlign: "right" },
  row: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    marginBottom: 8,
    borderWidth: 1,
    borderColor: "#E5EAF0",
  },
  rowTitle: { fontWeight: "600", color: "#0B3A5C", fontSize: 15 },
  meta: { fontSize: 13, color: "#5B6B7C", marginTop: 2 },
  price: { marginTop: 4, fontWeight: "600", color: "#0B3A5C" },
  discount: { color: "#067647", fontSize: 12, marginTop: 2 },
  error: { color: "#B42318" },
  back: { padding: 16, paddingBottom: 8 },
  backText: { color: "#0B3A5C", fontWeight: "600" },
});
