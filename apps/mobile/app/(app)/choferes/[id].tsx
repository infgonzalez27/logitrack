import { useCallback, useState } from "react";
import { Alert, ScrollView, StyleSheet, Text } from "react-native";
import { useFocusEffect, useLocalSearchParams, useRouter } from "expo-router";
import {
  CHOFER_ESTADOS,
  getChofer,
  updateChofer,
  type ChoferEstado,
} from "@/lib/choferes";
import {
  ErrorText,
  FormField,
  LoadingBlock,
  OptionChips,
  PrimaryButton,
  Screen,
} from "@/components/ui";

export default function EditarChoferScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [nombre, setNombre] = useState("");
  const [licencia, setLicencia] = useState("");
  const [movil, setMovil] = useState("");
  const [estado, setEstado] = useState<ChoferEstado>("disponible");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      if (!id) return;
      setLoading(true);
      void getChofer(id).then((res) => {
        if (!res.ok) setError(res.error);
        else {
          setNombre(res.chofer.nombre_completo ?? "");
          setLicencia(res.chofer.cedula_licencia);
          setMovil(res.chofer.movil1 ?? "");
          setEstado(res.chofer.estado);
        }
        setLoading(false);
      });
    }, [id]),
  );

  async function guardar() {
    if (!id) return;
    setSaving(true);
    setError(null);
    const res = await updateChofer({
      perfil_id: id,
      cedula_licencia: licencia,
      movil1: movil,
      estado,
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert("Listo", "Chofer actualizado.");
    router.back();
  }

  if (loading) return <LoadingBlock />;

  return (
    <Screen>
      <ScrollView contentContainerStyle={styles.pad}>
        <ErrorText message={error} />
        <Text style={styles.nombre}>{nombre || "Chofer"}</Text>
        <FormField
          label="Cédula / licencia"
          value={licencia}
          onChangeText={setLicencia}
        />
        <FormField
          label="Móvil"
          value={movil}
          onChangeText={setMovil}
          keyboardType="phone-pad"
        />
        <OptionChips
          label="Estado"
          value={estado}
          onChange={(v) => setEstado(v as ChoferEstado)}
          options={CHOFER_ESTADOS.map((e) => ({
            value: e.value,
            label: e.label,
          }))}
        />
        <PrimaryButton
          label="Guardar cambios"
          onPress={() => void guardar()}
          loading={saving}
          disabled={!licencia.trim()}
        />
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  pad: { paddingBottom: 40 },
  nombre: {
    fontSize: 18,
    fontWeight: "700",
    color: "#0B3A5C",
    marginBottom: 12,
  },
});
