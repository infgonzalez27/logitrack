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
  createPagoProveedor,
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

export default function NuevoPagoProveedorScreen() {
  const router = useRouter();
  const [proveedores, setProveedores] = useState<ProveedorOption[]>([]);
  const [proveedorId, setProveedorId] = useState("");
  const [monto, setMonto] = useState("");
  const [glosa, setGlosa] = useState("");
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
    const res = await createPagoProveedor({
      proveedor_id: proveedorId,
      monto_total_pagado: Number(monto.replace(",", ".")) || 0,
      glosa_concepto: glosa,
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert("Listo", "Pago registrado.");
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
        label="Monto total pagado"
        value={monto}
        onChangeText={setMonto}
        keyboardType="decimal-pad"
      />
      <FormField
        label="Glosa / concepto"
        value={glosa}
        onChangeText={setGlosa}
      />
      <ErrorText message={error} />
      <PrimaryButton
        label="Registrar pago"
        onPress={() => void submit()}
        loading={saving}
        disabled={!proveedorId || !monto}
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
