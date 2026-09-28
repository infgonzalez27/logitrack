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
  createFacturaCompra,
  listProveedoresActivos,
  type ProveedorOption,
} from "@/lib/compras";
import {
  ErrorText,
  FormField,
  LoadingBlock,
  PrimaryButton,
  SectionTitle,
} from "@/components/ui";

export default function NuevaFacturaCompraScreen() {
  const router = useRouter();
  const [proveedores, setProveedores] = useState<ProveedorOption[]>([]);
  const [proveedorId, setProveedorId] = useState("");
  const [numero, setNumero] = useState("");
  const [emision, setEmision] = useState("");
  const [vencimiento, setVencimiento] = useState("");
  const [subtotal, setSubtotal] = useState("");
  const [impuesto, setImpuesto] = useState("0");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pickerOpen, setPickerOpen] = useState(false);

  useEffect(() => {
    void (async () => {
      const res = await listProveedoresActivos();
      if (!res.ok) setError(res.error);
      else setProveedores(res.proveedores);
      setLoading(false);
    })();
  }, []);

  const selected = proveedores.find((p) => p.id === proveedorId);

  const submit = async () => {
    setSaving(true);
    setError(null);
    const res = await createFacturaCompra({
      proveedor_id: proveedorId,
      numero_factura: numero,
      fecha_emision: emision,
      fecha_vencimiento: vencimiento || null,
      monto_subtotal: Number(subtotal.replace(",", ".")) || 0,
      monto_impuesto: Number(impuesto.replace(",", ".")) || 0,
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert("Listo", "Factura registrada.");
    router.back();
  };

  if (loading) return <LoadingBlock />;

  return (
    <ScrollView
      style={styles.root}
      contentContainerStyle={{ padding: 16, paddingBottom: 40 }}
    >
      <SectionTitle>Proveedor</SectionTitle>
      <Pressable style={styles.select} onPress={() => setPickerOpen((v) => !v)}>
        <Text style={styles.selectText}>
          {selected?.razon_social ?? "Selecciona proveedor…"}
        </Text>
      </Pressable>
      {pickerOpen
        ? proveedores.map((p) => (
            <Pressable
              key={p.id}
              style={styles.option}
              onPress={() => {
                setProveedorId(p.id);
                setPickerOpen(false);
              }}
            >
              <Text style={styles.optionText}>{p.razon_social}</Text>
            </Pressable>
          ))
        : null}

      <FormField
        label="Nº factura"
        value={numero}
        onChangeText={setNumero}
        autoCapitalize="characters"
      />
      <FormField
        label="Fecha emisión (YYYY-MM-DD)"
        value={emision}
        onChangeText={setEmision}
        placeholder="2026-03-21"
        autoCapitalize="none"
      />
      <FormField
        label="Fecha vencimiento (opcional)"
        value={vencimiento}
        onChangeText={setVencimiento}
        placeholder="2026-04-21"
        autoCapitalize="none"
      />
      <FormField
        label="Subtotal"
        value={subtotal}
        onChangeText={setSubtotal}
        keyboardType="decimal-pad"
      />
      <FormField
        label="Impuesto"
        value={impuesto}
        onChangeText={setImpuesto}
        keyboardType="decimal-pad"
      />
      <ErrorText message={error} />
      <PrimaryButton
        label="Guardar factura"
        onPress={() => void submit()}
        loading={saving}
        disabled={!proveedorId || !numero || !emision}
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
