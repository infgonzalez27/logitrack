import { useEffect, useState } from "react";
import {
  Alert,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { useRouter } from "expo-router";
import {
  listProductosOptions,
  upsertInventarioAlmacen,
  type ProductoOption,
} from "@/lib/inventario";
import {
  ErrorText,
  FormField,
  LoadingBlock,
  PrimaryButton,
  SectionTitle,
} from "@/components/ui";

export default function NuevoInventarioAlmacenScreen() {
  const router = useRouter();
  const [productos, setProductos] = useState<ProductoOption[]>([]);
  const [productoId, setProductoId] = useState("");
  const [stock, setStock] = useState("0");
  const [ubicacion, setUbicacion] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pickerOpen, setPickerOpen] = useState(false);

  useEffect(() => {
    void (async () => {
      const res = await listProductosOptions();
      if (!res.ok) setError(res.error);
      else setProductos(res.productos);
      setLoading(false);
    })();
  }, []);

  const selected = productos.find((p) => p.id === productoId);

  const submit = async () => {
    setSaving(true);
    setError(null);
    const res = await upsertInventarioAlmacen({
      producto_id: productoId,
      stock_disponible: Number(stock.replace(",", ".")) || 0,
      ubicacion_pasillo: ubicacion,
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert("Listo", "Stock registrado / actualizado.");
    router.back();
  };

  if (loading) return <LoadingBlock />;

  return (
    <ScrollView
      style={styles.root}
      contentContainerStyle={{ padding: 16, paddingBottom: 40 }}
    >
      <SectionTitle>Producto</SectionTitle>
      <Pressable style={styles.select} onPress={() => setPickerOpen((v) => !v)}>
        <Text style={styles.selectText}>
          {selected?.nombre ?? "Selecciona producto…"}
        </Text>
      </Pressable>
      {pickerOpen
        ? productos.map((p) => (
            <Pressable
              key={p.id}
              style={styles.option}
              onPress={() => {
                setProductoId(p.id);
                setPickerOpen(false);
              }}
            >
              <Text style={styles.optionText}>{p.nombre}</Text>
            </Pressable>
          ))
        : null}

      <FormField
        label="Stock disponible"
        value={stock}
        onChangeText={setStock}
        keyboardType="decimal-pad"
      />
      <FormField
        label="Ubicación / pasillo"
        value={ubicacion}
        onChangeText={setUbicacion}
      />
      <ErrorText message={error} />
      <PrimaryButton
        label="Guardar"
        onPress={() => void submit()}
        loading={saving}
        disabled={!productoId}
      />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F6F8" },
  select: {
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 12,
    padding: 14,
    marginBottom: 8,
  },
  selectText: { color: "#0B3A5C", fontSize: 16 },
  option: {
    backgroundColor: "#fff",
    padding: 12,
    borderBottomWidth: 1,
    borderBottomColor: "#E5EAF0",
  },
  optionText: { color: "#0B3A5C" },
});
