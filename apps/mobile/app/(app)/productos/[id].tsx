import { useCallback, useState } from "react";
import { Alert, ScrollView, StyleSheet } from "react-native";
import { useFocusEffect, useLocalSearchParams, useRouter } from "expo-router";
import { getProducto, updateProducto } from "@/lib/productos";
import {
  ErrorText,
  FormField,
  LoadingBlock,
  PrimaryButton,
  Screen,
} from "@/components/ui";

export default function EditarProductoScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [codigo, setCodigo] = useState("");
  const [nombre, setNombre] = useState("");
  const [barras, setBarras] = useState("");
  const [descripcion, setDescripcion] = useState("");
  const [precio1, setPrecio1] = useState("");
  const [precio2, setPrecio2] = useState("");
  const [precio3, setPrecio3] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      if (!id) return;
      setLoading(true);
      void getProducto(id).then((res) => {
        if (!res.ok) setError(res.error);
        else {
          const p = res.producto;
          setCodigo(p.codigo_producto ?? "");
          setNombre(p.nombre);
          setBarras(p.codigo_barras ?? "");
          setDescripcion(p.descripcion ?? "");
          setPrecio1(String(p.precio_lista1 ?? 0));
          setPrecio2(String(p.precio_lista2 ?? 0));
          setPrecio3(String(p.precio_lista3 ?? 0));
        }
        setLoading(false);
      });
    }, [id]),
  );

  async function guardar() {
    if (!id) return;
    setSaving(true);
    setError(null);
    const res = await updateProducto({
      id,
      codigo_producto: codigo,
      nombre,
      codigo_barras: barras,
      descripcion,
      precio_lista1: Number(precio1) || 0,
      precio_lista2: Number(precio2) || 0,
      precio_lista3: Number(precio3) || 0,
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert("Listo", "Producto actualizado.");
    router.back();
  }

  if (loading) return <LoadingBlock />;

  return (
    <Screen>
      <ScrollView contentContainerStyle={styles.pad}>
        <ErrorText message={error} />
        <FormField
          label="Código de producto"
          value={codigo}
          onChangeText={setCodigo}
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
          value={precio1}
          onChangeText={setPrecio1}
          keyboardType="decimal-pad"
        />
        <FormField
          label="Precio lista 2 (USD)"
          value={precio2}
          onChangeText={setPrecio2}
          keyboardType="decimal-pad"
        />
        <FormField
          label="Precio lista 3 (USD)"
          value={precio3}
          onChangeText={setPrecio3}
          keyboardType="decimal-pad"
        />
        <PrimaryButton
          label="Guardar cambios"
          onPress={() => void guardar()}
          loading={saving}
          disabled={!nombre.trim() || !codigo.trim()}
        />
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({ pad: { paddingBottom: 40 } });
