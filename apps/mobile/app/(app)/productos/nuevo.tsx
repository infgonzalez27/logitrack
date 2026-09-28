import { useState } from "react";
import { Alert, ScrollView, StyleSheet } from "react-native";
import { useRouter, type Href } from "expo-router";
import { createProducto } from "@/lib/productos";
import {
  ErrorText,
  FormField,
  PrimaryButton,
  Screen,
} from "@/components/ui";

export default function NuevoProductoScreen() {
  const router = useRouter();
  const [codigo, setCodigo] = useState("");
  const [nombre, setNombre] = useState("");
  const [barras, setBarras] = useState("");
  const [descripcion, setDescripcion] = useState("");
  const [precio, setPrecio] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function guardar() {
    setSaving(true);
    setError(null);
    const res = await createProducto({
      codigo_producto: codigo,
      nombre,
      codigo_barras: barras,
      descripcion,
      precio_lista1: precio.trim() ? Number(precio) : 0,
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert("Listo", "Producto creado.");
    router.replace(`/(app)/productos/${res.id}` as Href);
  }

  return (
    <Screen>
      <ScrollView contentContainerStyle={styles.pad}>
        <ErrorText message={error} />
        <FormField
          label="Código de producto"
          value={codigo}
          onChangeText={setCodigo}
          placeholder="Opcional (se genera si vacío)"
        />
        <FormField label="Nombre" value={nombre} onChangeText={setNombre} />
        <FormField
          label="Código de barras"
          value={barras}
          onChangeText={setBarras}
        />
        <FormField
          label="Descripción"
          value={descripcion}
          onChangeText={setDescripcion}
          multiline
        />
        <FormField
          label="Precio lista 1 (USD)"
          value={precio}
          onChangeText={setPrecio}
          keyboardType="decimal-pad"
        />
        <PrimaryButton
          label="Guardar"
          onPress={() => void guardar()}
          loading={saving}
          disabled={!nombre.trim()}
        />
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({ pad: { paddingBottom: 40 } });
