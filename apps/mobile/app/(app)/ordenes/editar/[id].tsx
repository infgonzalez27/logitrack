import { useCallback, useEffect, useMemo, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import {
  useFocusEffect,
  useLocalSearchParams,
  useRouter,
  type Href,
} from "expo-router";
import {
  actualizarOrdenDistribucion,
  aprobarOrdenDistribucion,
  getOrdenDetalle,
  type OrdenDetalle,
} from "@/lib/ordenes";
import { listarProductos, precioNeto, type ProductoLista } from "@/lib/productos";
import { formatDate, formatMoney } from "@/lib/format";
import { FechaDespachoPicker } from "@/components/FechaDespachoPicker";
import {
  ErrorText,
  FormField,
  LoadingBlock,
  PrimaryButton,
  SecondaryButton,
  SectionTitle,
} from "@/components/ui";

function toLocalInput(iso: string | null): string {
  if (!iso) return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso.slice(0, 16);
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  const hh = String(d.getHours()).padStart(2, "0");
  const mm = String(d.getMinutes()).padStart(2, "0");
  return `${y}-${m}-${day}T${hh}:${mm}`;
}

type LineaDraft = {
  producto_id: string;
  nombre: string;
  codigo: string | null;
  cantidad: number;
  precio: number;
  pctDescuento: number;
};

export default function EditarOrdenScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [orden, setOrden] = useState<OrdenDetalle | null>(null);
  const [fecha, setFecha] = useState("");
  const [factura, setFactura] = useState("");
  const [lineas, setLineas] = useState<LineaDraft[]>([]);
  const [picker, setPicker] = useState<"productos" | null>(null);
  const [search, setSearch] = useState("");
  const [productos, setProductos] = useState<ProductoLista[]>([]);
  const [searching, setSearching] = useState(false);

  const editable =
    orden?.estado === "borrador" || orden?.estado === "aprobada";
  const canAprobar = orden?.estado === "borrador";

  const total = useMemo(
    () => lineas.reduce((acc, l) => acc + l.cantidad * l.precio, 0),
    [lineas],
  );

  const load = useCallback(async () => {
    if (!id) return;
    setError(null);
    const res = await getOrdenDetalle(id);
    if (!res.ok) {
      setError(res.error);
      setOrden(null);
    } else {
      setOrden(res.orden);
      setFecha(toLocalInput(res.orden.fecha_despacho));
      setFactura(res.orden.factura_origen_numero ?? "");
      setLineas(
        (res.orden.detalle_distribucion ?? []).map((d) => ({
          producto_id: d.producto_id ?? "",
          nombre: d.productos?.nombre ?? "Producto",
          codigo: d.productos?.codigo_producto ?? null,
          cantidad: d.cantidad_solicitada,
          precio: Number(d.valor_unitario_usd ?? 0),
          pctDescuento: Number(d.porcentaje_descuento ?? 0),
        })),
      );
    }
    setLoading(false);
  }, [id]);

  useFocusEffect(
    useCallback(() => {
      setLoading(true);
      void load();
    }, [load]),
  );

  const loadProductos = useCallback(
    async (term: string) => {
      if (!orden?.cliente_id) {
        setError("La orden no tiene cliente asignado.");
        return;
      }
      setSearching(true);
      setError(null);
      const res = await listarProductos(term.trim() || ".F.", orden.cliente_id);
      if (!res.ok) setError(res.error);
      else setProductos(res.productos);
      setSearching(false);
    },
    [orden?.cliente_id],
  );

  useEffect(() => {
    if (picker === "productos" && orden?.cliente_id) {
      void loadProductos(search);
    }
  }, [picker, orden?.cliente_id, loadProductos]);

  function addProducto(p: ProductoLista) {
    const neto = precioNeto(p);
    setLineas((prev) => {
      const idx = prev.findIndex((l) => l.producto_id === p.id);
      if (idx >= 0) {
        const copy = [...prev];
        copy[idx] = { ...copy[idx], cantidad: copy[idx].cantidad + 1 };
        return copy;
      }
      return [
        ...prev,
        {
          producto_id: p.id,
          nombre: p.nombre,
          codigo: p.codigo_producto,
          cantidad: 1,
          precio: neto,
          pctDescuento: Number(p.porcentaje_descuento ?? 0),
        },
      ];
    });
    setPicker(null);
    setSearch("");
  }

  function updateCantidad(productoId: string, cantidad: number) {
    if (cantidad <= 0) {
      setLineas((prev) => prev.filter((l) => l.producto_id !== productoId));
      return;
    }
    setLineas((prev) =>
      prev.map((l) => (l.producto_id === productoId ? { ...l, cantidad } : l)),
    );
  }

  async function onSave() {
    if (!orden || !id || !fecha.trim()) {
      setError("La fecha de despacho es obligatoria.");
      return;
    }
    if (!lineas.length) {
      setError("Agrega al menos un producto a la orden.");
      return;
    }
    if (!orden.cliente_id) {
      setError("La orden no tiene cliente asignado.");
      return;
    }

    setSaving(true);
    setError(null);
    setMessage(null);

    const res = await actualizarOrdenDistribucion({
      correlativo: orden.correlativo,
      clienteId: orden.cliente_id,
      camionId: orden.camion_id,
      fechaDespachoIso: fecha.trim(),
      facturaOrigenNumero: factura,
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
    setMessage("Orden actualizada exitosamente.");
    void load();
  }

  async function onAprobar() {
    if (!id) return;
    setSaving(true);
    setError(null);
    setMessage(null);
    const res = await aprobarOrdenDistribucion(id);
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    setMessage(res.message || "Orden aprobada.");
    void load();
  }

  if (loading) return <LoadingBlock />;

  if (error && !orden) {
    return (
      <View style={styles.center}>
        <ErrorText message={error} />
      </View>
    );
  }

  if (!orden) {
    return (
      <View style={styles.center}>
        <ErrorText message="Sin datos" />
      </View>
    );
  }

  if (picker === "productos") {
    return (
      <View style={styles.root}>
        <View style={styles.pickerHeader}>
          <Text style={styles.pickerTitle}>Agregar producto</Text>
          <Pressable
            style={styles.closeBtn}
            onPress={() => {
              setPicker(null);
              setSearch("");
            }}
          >
            <Text style={styles.closeBtnText}>✕ Cerrar</Text>
          </Pressable>
        </View>

        <View style={styles.searchRow}>
          <TextInput
            style={[styles.input, { flex: 1 }]}
            placeholder="Buscar por nombre o código…"
            placeholderTextColor="#9AA6B2"
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
          <ActivityIndicator style={{ marginTop: 24 }} color="#0B3A5C" size="large" />
        ) : (
          <FlatList
            data={productos}
            keyExtractor={(p) => p.id}
            contentContainerStyle={{ padding: 16, paddingTop: 8, gap: 8 }}
            ListEmptyComponent={
              <Text style={styles.emptyText}>
                Sin resultados. Prueba otra búsqueda.
              </Text>
            }
            renderItem={({ item }) => {
              const neto = precioNeto(item);
              const pct = Number(item.porcentaje_descuento ?? 0);
              return (
                <Pressable
                  style={styles.productRow}
                  onPress={() => addProducto(item)}
                >
                  <View style={{ flex: 1 }}>
                    <Text style={styles.rowTitle}>{item.nombre}</Text>
                    <Text style={styles.meta}>
                      {item.codigo_producto ?? "—"} · Stock {item.stock_disponible}
                    </Text>
                  </View>
                  <View style={{ alignItems: "flex-end" }}>
                    <Text style={styles.price}>${formatMoney(neto)}</Text>
                    {pct > 0 ? (
                      <Text style={styles.discountBadge}>−{pct}%</Text>
                    ) : null}
                  </View>
                </Pressable>
              );
            }}
          />
        )}
      </View>
    );
  }

  return (
    <ScrollView
      style={styles.root}
      contentContainerStyle={{ padding: 16, gap: 12, paddingBottom: 40 }}
    >
      <Text style={styles.title}>#{orden.correlativo}</Text>
      <Text style={styles.meta}>
        {orden.clientes?.razon_social ?? "—"} · Estado: {orden.estado}
      </Text>
      <Text style={styles.meta}>
        Despacho actual: {formatDate(orden.fecha_despacho)}
      </Text>

      {!editable ? (
        <ErrorText message="Solo se editan órdenes en borrador o aprobada. Usa Radar para despacho en ruta." />
      ) : (
        <>
          <SectionTitle>Cabecera</SectionTitle>
          <FechaDespachoPicker
            label="Fecha despacho"
            value={fecha}
            onChange={setFecha}
            required
          />
          <FormField
            label="Factura origen"
            value={factura}
            onChangeText={setFactura}
            autoCapitalize="characters"
          />

          <SectionTitle>Productos de la orden</SectionTitle>

          <Pressable
            style={styles.btnSecondary}
            onPress={() => setPicker("productos")}
          >
            <Text style={styles.btnSecondaryText}>+ Agregar producto</Text>
          </Pressable>

          {lineas.length === 0 ? (
            <Text style={styles.emptyText}>
              No hay productos agregados a la orden.
            </Text>
          ) : (
            <View style={{ gap: 8 }}>
              {lineas.map((item) => (
                <View key={item.producto_id} style={styles.line}>
                  <View style={styles.lineHeader}>
                    <View style={{ flex: 1 }}>
                      <Text style={styles.rowTitle}>{item.nombre}</Text>
                      {item.codigo ? (
                        <Text style={styles.meta}>{item.codigo}</Text>
                      ) : null}
                      {item.pctDescuento > 0 ? (
                        <Text style={styles.discountBadge}>
                          Descuento {item.pctDescuento}%
                        </Text>
                      ) : null}
                    </View>
                    <Pressable
                      onPress={() => updateCantidad(item.producto_id, 0)}
                      hitSlop={8}
                    >
                      <Text style={styles.removeText}>Quitar</Text>
                    </Pressable>
                  </View>

                  <View style={styles.qtyRow}>
                    <Pressable
                      style={styles.qtyBtn}
                      onPress={() =>
                        updateCantidad(item.producto_id, item.cantidad - 1)
                      }
                    >
                      <Text style={styles.qtyBtnText}>−</Text>
                    </Pressable>
                    <Text style={styles.qty}>{item.cantidad}</Text>
                    <Pressable
                      style={styles.qtyBtn}
                      onPress={() =>
                        updateCantidad(item.producto_id, item.cantidad + 1)
                      }
                    >
                      <Text style={styles.qtyBtnText}>+</Text>
                    </Pressable>
                    <View style={{ flex: 1, alignItems: "flex-end" }}>
                      <Text style={styles.unitPrice}>
                        c/u ${formatMoney(item.precio)}
                      </Text>
                      <Text style={styles.lineTotal}>
                        ${formatMoney(item.cantidad * item.precio)}
                      </Text>
                    </View>
                  </View>
                </View>
              ))}
            </View>
          )}

          <View style={styles.totalRow}>
            <Text style={styles.totalLabel}>Total orden:</Text>
            <Text style={styles.totalValue}>${formatMoney(total)}</Text>
          </View>

          <PrimaryButton
            label="Guardar cambios"
            loading={saving}
            onPress={() => void onSave()}
          />
        </>
      )}

      {canAprobar ? (
        <PrimaryButton
          label="Aprobar orden"
          loading={saving}
          onPress={() => {
            Alert.alert(
              "Aprobar orden",
              "¿Aprobar esta orden de distribución?",
              [
                { text: "Cancelar", style: "cancel" },
                { text: "Aprobar", onPress: () => void onAprobar() },
              ],
            );
          }}
        />
      ) : null}

      <ErrorText message={error} />
      {message ? <Text style={styles.ok}>{message}</Text> : null}

      <SecondaryButton
        label="Ver detalle"
        onPress={() => router.push(`/(app)/ordenes/${id}` as Href)}
      />
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
  title: { fontSize: 24, fontWeight: "700", color: "#0B3A5C" },
  meta: { fontSize: 13, color: "#5B6B7C" },
  ok: { color: "#027A48", fontWeight: "600", fontSize: 14 },
  pickerHeader: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    padding: 16,
    backgroundColor: "#fff",
    borderBottomWidth: 1,
    borderBottomColor: "#E5EAF0",
  },
  pickerTitle: { fontSize: 18, fontWeight: "700", color: "#0B3A5C" },
  closeBtn: { padding: 4 },
  closeBtnText: { color: "#0B3A5C", fontWeight: "600", fontSize: 14 },
  searchRow: {
    flexDirection: "row",
    gap: 8,
    padding: 16,
    paddingBottom: 8,
  },
  input: {
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 10,
    fontSize: 15,
    color: "#0B3A5C",
  },
  searchBtn: {
    backgroundColor: "#0B3A5C",
    borderRadius: 12,
    paddingHorizontal: 16,
    justifyContent: "center",
  },
  searchBtnText: { color: "#fff", fontWeight: "600" },
  productRow: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    borderWidth: 1,
    borderColor: "#E5EAF0",
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  rowTitle: { fontSize: 15, fontWeight: "600", color: "#0B3A5C" },
  price: { fontSize: 15, fontWeight: "700", color: "#0B3A5C" },
  discountBadge: {
    fontSize: 11,
    color: "#B42318",
    fontWeight: "700",
    backgroundColor: "#FEF3F2",
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 6,
    marginTop: 2,
  },
  emptyText: {
    fontSize: 14,
    color: "#5B6B7C",
    textAlign: "center",
    marginVertical: 16,
  },
  btnSecondary: {
    borderWidth: 1,
    borderColor: "#0B3A5C",
    borderRadius: 12,
    paddingVertical: 12,
    alignItems: "center",
    backgroundColor: "#fff",
  },
  btnSecondaryText: { color: "#0B3A5C", fontWeight: "600", fontSize: 15 },
  line: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 12,
    borderWidth: 1,
    borderColor: "#E5EAF0",
  },
  lineHeader: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "flex-start",
  },
  removeText: { color: "#D92D20", fontWeight: "600", fontSize: 13 },
  qtyRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
    marginTop: 10,
  },
  qtyBtn: {
    width: 34,
    height: 34,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: "#D0D7DE",
    backgroundColor: "#F4F6F8",
    alignItems: "center",
    justifyContent: "center",
  },
  qtyBtnText: { fontSize: 18, fontWeight: "700", color: "#0B3A5C" },
  qty: { fontSize: 16, fontWeight: "700", minWidth: 24, textAlign: "center", color: "#0B3A5C" },
  unitPrice: { fontSize: 12, color: "#5B6B7C" },
  lineTotal: { fontSize: 15, fontWeight: "700", color: "#0B3A5C" },
  totalRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    paddingVertical: 8,
    borderTopWidth: 1,
    borderTopColor: "#E5EAF0",
    marginTop: 4,
  },
  totalLabel: { fontSize: 16, fontWeight: "600", color: "#5B6B7C" },
  totalValue: { fontSize: 20, fontWeight: "700", color: "#0B3A5C" },
});
