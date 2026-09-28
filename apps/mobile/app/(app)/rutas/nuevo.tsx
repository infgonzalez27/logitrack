import { useState } from "react";
import { Alert, ScrollView, StyleSheet } from "react-native";
import { useRouter, type Href } from "expo-router";
import { createRuta } from "@/lib/rutas";
import {
  ErrorText,
  FormField,
  PrimaryButton,
  Screen,
} from "@/components/ui";

export default function NuevaRutaScreen() {
  const router = useRouter();
  const [nombre, setNombre] = useState("");
  const [descripcion, setDescripcion] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function guardar() {
    setSaving(true);
    setError(null);
    const res = await createRuta({
      nombre_ruta: nombre,
      descripcion_ruta: descripcion,
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert("Listo", "Ruta creada.");
    router.replace(`/(app)/rutas/${res.id}` as Href);
  }

  return (
    <Screen>
      <ScrollView contentContainerStyle={styles.pad}>
        <ErrorText message={error} />
        <FormField
          label="Nombre"
          value={nombre}
          onChangeText={setNombre}
          placeholder="Nombre de la ruta"
        />
        <FormField
          label="Descripción"
          value={descripcion}
          onChangeText={setDescripcion}
          placeholder="Opcional"
          multiline
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

const styles = StyleSheet.create({
  pad: { paddingBottom: 40 },
});
