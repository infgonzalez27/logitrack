import { useCallback, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { useFocusEffect } from "expo-router";
import {
  eliminarDescuentoCliente,
  guardarDescuentoCliente,
  obtenerDescuentosCliente,
  type DescuentoConProducto,
} from "@/lib/descuentos";
import { listarProductos, type ProductoLista } from "@/lib/productos";
import { formatMoney } from "@/lib/format";
import {
  ErrorText,
  FormField,
  PrimaryButton,
  SectionTitle,
} from "@/components/ui";

export function DescuentosClientePanel({ clienteId }: { clienteId: string }) {
  const [descuentos, setDescuentos] = useState<DescuentoConProducto[]>([]);
  const [productos, setProductos] = useState<ProductoLista[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [okMsg, setOkMsg] = useState<string | null>(null);

  const [productoId, setProductoId] = useState("");
  const [productoLabel, setProductoLabel] = useState("");
  const [search, setSearch] = useState("");
  const [pct, setPct] = useState("");
  const [pactado, setPactado] = useState("");
  const [showPicker, setShowPicker] = useState(false);

  const load = useCallback(async () => {
    setError(null);
    const res = await obtenerDescuentosCliente(clienteId);
    if (!res.ok) setError(res.error);
    else setDescuentos(res.descuentos);
    setLoading(false);
  }, [clienteId]);

  useFocusEffect(
    useCallback(() => {
      setLoading(true);
      void load();
    }, [load]),
  );

  async function buscarProductos() {
    const res = await listarProductos(search.trim() || ".F.", clienteId);
    if (res.ok) {
      setProductos(res.productos);
      setShowPicker(true);
    } else {
      setError(res.error);
    }
  }

  async function guardar() {
    setError(null);
    setOkMsg(null);
    if (!productoId) {
      setError("Selecciona un producto.");
      return;
    }
    const pctNum = parseFloat(pct || "0");
    const pactadoNum = pactado.trim() ? parseFloat(pactado) : null;
    if (Number.isNaN(pctNum) || pctNum < 0 || pctNum > 100) {
      setError("El porcentaje debe ser un número entre 0 y 100.");
      return;
    }
    if (pactadoNum != null && (Number.isNaN(pactadoNum) || pactadoNum < 0)) {
      setError("El precio pactado debe ser positivo.");
      return;
    }
    if (pctNum <= 0 && pactadoNum == null) {
      setError("Indica un porcentaje o un precio pactado.");
      return;
    }

    setSaving(true);
    const res = await guardarDescuentoCliente({
      cliente_id: clienteId,
      producto_id: productoId,
      porcentaje_descuento: pctNum,
      precio_pactado_usd: pactadoNum,
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    setOkMsg("Descuento guardado.");
    setProductoId("");
    setProductoLabel("");
    setPct("");
    setPactado("");
    void load();
  }

  function eliminar(id: string) {
    Alert.alert("Eliminar descuento", "¿Confirmas eliminar este descuento?", [
      { text: "Cancelar", style: "cancel" },
      {
        text: "Eliminar",
        style: "destructive",
        onPress: () => {
          void (async () => {
            const res = await eliminarDescuentoCliente(id);
            if (!res.ok) setError(res.error);
            else {
              setOkMsg("Descuento eliminado.");
              setDescuentos((prev) => prev.filter((d) => d.id !== id));
            }
          })();
        },
      },
    ]);
  }

  if (loading) {
    return <ActivityIndicator color="#0B3A5C" style={{ marginVertical: 16 }} />;
  }

  return (
    <View style={styles.wrap}>
      <SectionTitle>Descuentos por producto</SectionTitle>
      <ErrorText message={error} />
      {okMsg ? <Text style={styles.ok}>{okMsg}</Text> : null}

      <FormField
        label="Buscar producto"
        value={search}
        onChangeText={setSearch}
        placeholder="Nombre o código…"
        onSubmitEditing={() => void buscarProductos()}
        returnKeyType="search"
      />
      <PrimaryButton label="Buscar" onPress={() => void buscarProductos()} />
      {productoLabel ? (
        <Text style={styles.selected}>Seleccionado: {productoLabel}</Text>
      ) : null}

      {showPicker ? (
        <View style={styles.picker}>
          {productos.length === 0 ? (
            <Text style={styles.empty}>Sin resultados.</Text>
          ) : (
            productos.slice(0, 12).map((p) => (
              <Pressable
                key={p.id}
                style={styles.pickerRow}
                onPress={() => {
                  setProductoId(p.id);
                  setProductoLabel(
                    `${p.nombre}${p.codigo_producto ? ` (${p.codigo_producto})` : ""}`,
                  );
                  setShowPicker(false);
                }}
              >
                <Text style={styles.pickerTitle}>{p.nombre}</Text>
                <Text style={styles.meta}>
                  {p.codigo_producto ?? "—"} · ${formatMoney(p.precio_lista1 ?? p.precio)}
                </Text>
              </Pressable>
            ))
          )}
        </View>
      ) : null}

      <FormField
        label="% Descuento"
        value={pct}
        onChangeText={setPct}
        keyboardType="decimal-pad"
        placeholder="0"
      />
      <FormField
        label="Precio pactado USD"
        value={pactado}
        onChangeText={setPactado}
        keyboardType="decimal-pad"
        placeholder="Opcional"
      />
      <PrimaryButton
        label="Guardar descuento"
        onPress={() => void guardar()}
        loading={saving}
      />

      <Text style={styles.listTitle}>
        Asignados ({descuentos.length})
      </Text>
      {descuentos.length === 0 ? (
        <Text style={styles.empty}>Sin descuentos.</Text>
      ) : (
        descuentos.map((d) => (
          <View key={d.id} style={styles.row}>
            <View style={{ flex: 1 }}>
              <Text style={styles.pickerTitle}>{d.producto_nombre}</Text>
              <Text style={styles.meta}>
                {d.producto_codigo}
                {d.porcentaje_descuento > 0
                  ? ` · ${d.porcentaje_descuento}%`
                  : ""}
                {d.precio_pactado_usd != null
                  ? ` · $${formatMoney(d.precio_pactado_usd)}`
                  : ""}
              </Text>
            </View>
            <Pressable onPress={() => eliminar(d.id)}>
              <Text style={styles.delete}>Eliminar</Text>
            </Pressable>
          </View>
        ))
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { marginTop: 8, gap: 4 },
  ok: { color: "#027A48", marginBottom: 8 },
  selected: { color: "#0B3A5C", fontWeight: "600", marginVertical: 8 },
  picker: {
    backgroundColor: "#fff",
    borderRadius: 12,
    borderWidth: 1,
    borderColor: "#E5EAF0",
    marginBottom: 8,
    maxHeight: 220,
  },
  pickerRow: {
    padding: 12,
    borderBottomWidth: 1,
    borderBottomColor: "#E5EAF0",
  },
  pickerTitle: { fontWeight: "600", color: "#0B3A5C" },
  meta: { fontSize: 13, color: "#5B6B7C", marginTop: 2 },
  listTitle: {
    marginTop: 16,
    fontSize: 15,
    fontWeight: "600",
    color: "#0B3A5C",
  },
  empty: { color: "#5B6B7C", marginTop: 8 },
  row: {
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 12,
    marginTop: 8,
    borderWidth: 1,
    borderColor: "#E5EAF0",
    gap: 8,
  },
  delete: { color: "#B42318", fontWeight: "600" },
});
