import { useState } from "react";
import { Alert, ScrollView, StyleSheet } from "react-native";
import { useRouter, type Href } from "expo-router";
import { createCamion } from "@/lib/camiones";
import {
  ErrorText,
  FormField,
  PrimaryButton,
  Screen,
} from "@/components/ui";

export default function NuevoCamionScreen() {
  const router = useRouter();
  const [placa, setPlaca] = useState("");
  const [modelo, setModelo] = useState("");
  const [capacidad, setCapacidad] = useState("");
  const [volumen, setVolumen] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function guardar() {
    setSaving(true);
    setError(null);
    const res = await createCamion({
      placa,
      modelo,
      capacidad_kg: Number(capacidad),
      volumen_m3: volumen.trim() ? Number(volumen) : null,
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert("Listo", "Camión creado.");
    router.replace(`/(app)/camiones/${res.id}` as Href);
  }

  return (
    <Screen>
      <ScrollView contentContainerStyle={styles.pad}>
        <ErrorText message={error} />
        <FormField
          label="Placa"
          value={placa}
          onChangeText={setPlaca}
          autoCapitalize="characters"
        />
        <FormField label="Modelo" value={modelo} onChangeText={setModelo} />
        <FormField
          label="Capacidad (kg)"
          value={capacidad}
          onChangeText={setCapacidad}
          keyboardType="decimal-pad"
        />
        <FormField
          label="Volumen (m³)"
          value={volumen}
          onChangeText={setVolumen}
          keyboardType="decimal-pad"
          placeholder="Opcional"
        />
        <PrimaryButton
          label="Guardar"
          onPress={() => void guardar()}
          loading={saving}
          disabled={!placa.trim() || !modelo.trim() || !capacidad.trim()}
        />
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({ pad: { paddingBottom: 40 } });
