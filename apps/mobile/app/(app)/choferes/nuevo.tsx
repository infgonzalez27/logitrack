import { useCallback, useState } from "react";
import { Alert, ScrollView, StyleSheet, Text } from "react-native";
import { useFocusEffect, useRouter, type Href } from "expo-router";
import {
  CHOFER_ESTADOS,
  createChofer,
  listPerfilesChoferDisponibles,
  type ChoferEstado,
  type PerfilChoferOption,
} from "@/lib/choferes";
import {
  ErrorText,
  FormField,
  LoadingBlock,
  OptionChips,
  PrimaryButton,
  Screen,
} from "@/components/ui";

export default function NuevoChoferScreen() {
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [perfiles, setPerfiles] = useState<PerfilChoferOption[]>([]);
  const [perfilId, setPerfilId] = useState("");
  const [licencia, setLicencia] = useState("");
  const [movil, setMovil] = useState("");
  const [estado, setEstado] = useState<ChoferEstado>("disponible");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      setLoading(true);
      void listPerfilesChoferDisponibles().then((res) => {
        if (!res.ok) setError(res.error);
        else {
          setPerfiles(res.perfiles);
          if (res.perfiles.length === 1) setPerfilId(res.perfiles[0].id);
        }
        setLoading(false);
      });
    }, []),
  );

  async function guardar() {
    setSaving(true);
    setError(null);
    const res = await createChofer({
      perfil_id: perfilId,
      cedula_licencia: licencia,
      movil1: movil,
      estado,
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert("Listo", "Chofer registrado.");
    router.replace(`/(app)/choferes/${res.id}` as Href);
  }

  if (loading) return <LoadingBlock />;

  return (
    <Screen>
      <ScrollView contentContainerStyle={styles.pad}>
        <ErrorText message={error} />
        {perfiles.length === 0 ? (
          <Text style={styles.warn}>
            No hay perfiles con rol chofer disponibles. Registra un usuario
            chofer en Administración.
          </Text>
        ) : (
          <OptionChips
            label="Perfil (usuario chofer)"
            value={perfilId}
            onChange={setPerfilId}
            options={perfiles.map((p) => ({
              value: p.id,
              label: p.nombre_completo,
            }))}
          />
        )}
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
          label="Guardar"
          onPress={() => void guardar()}
          loading={saving}
          disabled={!perfilId || !licencia.trim()}
        />
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  pad: { paddingBottom: 40 },
  warn: { color: "#B54708", marginBottom: 12 },
});
