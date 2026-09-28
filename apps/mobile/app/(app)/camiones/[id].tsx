import { useCallback, useState } from "react";
import { Alert, ScrollView, StyleSheet } from "react-native";
import { useFocusEffect, useLocalSearchParams, useRouter } from "expo-router";
import {
  CAMION_ESTADOS,
  getCamion,
  updateCamion,
  type CamionEstado,
} from "@/lib/camiones";
import {
  ErrorText,
  FormField,
  LoadingBlock,
  OptionChips,
  PrimaryButton,
  Screen,
} from "@/components/ui";

export default function EditarCamionScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [placa, setPlaca] = useState("");
  const [modelo, setModelo] = useState("");
  const [capacidad, setCapacidad] = useState("");
  const [volumen, setVolumen] = useState("");
  const [estado, setEstado] = useState<CamionEstado>("disponible");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      if (!id) return;
      setLoading(true);
      void getCamion(id).then((res) => {
        if (!res.ok) setError(res.error);
        else {
          const c = res.camion;
          setPlaca(c.placa);
          setModelo(c.modelo);
          setCapacidad(String(c.capacidad_kg));
          setVolumen(c.volumen_m3 != null ? String(c.volumen_m3) : "");
          setEstado(c.estado);
        }
        setLoading(false);
      });
    }, [id]),
  );

  async function guardar() {
    if (!id) return;
    setSaving(true);
    setError(null);
    const res = await updateCamion({
      id,
      placa,
      modelo,
      capacidad_kg: Number(capacidad),
      volumen_m3: volumen.trim() ? Number(volumen) : null,
      estado,
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert("Listo", "Camión actualizado.");
    router.back();
  }

  if (loading) return <LoadingBlock />;

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
        />
        <OptionChips
          label="Estado"
          value={estado}
          onChange={(v) => setEstado(v as CamionEstado)}
          options={CAMION_ESTADOS.map((e) => ({
            value: e.value,
            label: e.label,
          }))}
        />
        <PrimaryButton
          label="Guardar cambios"
          onPress={() => void guardar()}
          loading={saving}
          disabled={!placa.trim() || !modelo.trim() || !capacidad.trim()}
        />
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({ pad: { paddingBottom: 40 } });
