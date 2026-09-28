import { useCallback, useState } from "react";
import { Alert, ScrollView, StyleSheet } from "react-native";
import { useFocusEffect, useLocalSearchParams, useRouter } from "expo-router";
import { getRuta, updateRuta } from "@/lib/rutas";
import {
  ErrorText,
  FormField,
  LoadingBlock,
  PrimaryButton,
  Screen,
} from "@/components/ui";

export default function EditarRutaScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [nombre, setNombre] = useState("");
  const [descripcion, setDescripcion] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      if (!id) return;
      setLoading(true);
      void getRuta(id).then((res) => {
        if (!res.ok) setError(res.error);
        else {
          setNombre(res.ruta.nombre_ruta);
          setDescripcion(res.ruta.descripcion_ruta ?? "");
        }
        setLoading(false);
      });
    }, [id]),
  );

  async function guardar() {
    if (!id) return;
    setSaving(true);
    setError(null);
    const res = await updateRuta({
      id_ruta: id,
      nombre_ruta: nombre,
      descripcion_ruta: descripcion,
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert("Listo", "Ruta actualizada.");
    router.back();
  }

  if (loading) return <LoadingBlock />;

  return (
    <Screen>
      <ScrollView contentContainerStyle={styles.pad}>
        <ErrorText message={error} />
        <FormField
          label="Nombre"
          value={nombre}
          onChangeText={setNombre}
        />
        <FormField
          label="Descripción"
          value={descripcion}
          onChangeText={setDescripcion}
          multiline
        />
        <PrimaryButton
          label="Guardar cambios"
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
