import { useCallback, useState } from "react";
import { Alert, ScrollView, StyleSheet } from "react-native";
import { useFocusEffect, useLocalSearchParams, useRouter } from "expo-router";
import { getProveedor, updateProveedor } from "@/lib/proveedores";
import {
  ErrorText,
  FormField,
  LoadingBlock,
  OptionChips,
  PrimaryButton,
  Screen,
} from "@/components/ui";

export default function EditarProveedorScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [rif, setRif] = useState("");
  const [razon, setRazon] = useState("");
  const [direccion, setDireccion] = useState("");
  const [telefono, setTelefono] = useState("");
  const [correo, setCorreo] = useState("");
  const [activo, setActivo] = useState("true");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      if (!id) return;
      setLoading(true);
      void getProveedor(id).then((res) => {
        if (!res.ok) setError(res.error);
        else {
          const p = res.proveedor;
          setRif(p.rif_nit);
          setRazon(p.razon_social);
          setDireccion(p.direccion_fiscal ?? "");
          setTelefono(p.telefono ?? "");
          setCorreo(p.correo_e ?? "");
          setActivo(p.activo ? "true" : "false");
        }
        setLoading(false);
      });
    }, [id]),
  );

  async function guardar() {
    if (!id) return;
    setSaving(true);
    setError(null);
    const res = await updateProveedor({
      id,
      rif_nit: rif,
      razon_social: razon,
      direccion_fiscal: direccion,
      telefono,
      correo_e: correo,
      activo: activo === "true",
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert("Listo", "Proveedor actualizado.");
    router.back();
  }

  if (loading) return <LoadingBlock />;

  return (
    <Screen>
      <ScrollView contentContainerStyle={styles.pad}>
        <ErrorText message={error} />
        <FormField label="RIF/NIT" value={rif} onChangeText={setRif} />
        <FormField
          label="Razón social"
          value={razon}
          onChangeText={setRazon}
        />
        <FormField
          label="Dirección fiscal"
          value={direccion}
          onChangeText={setDireccion}
        />
        <FormField
          label="Teléfono"
          value={telefono}
          onChangeText={setTelefono}
          keyboardType="phone-pad"
        />
        <FormField
          label="Correo"
          value={correo}
          onChangeText={setCorreo}
          keyboardType="email-address"
          autoCapitalize="none"
        />
        <OptionChips
          label="Estado"
          value={activo}
          onChange={setActivo}
          options={[
            { value: "true", label: "Activo" },
            { value: "false", label: "Inactivo" },
          ]}
        />
        <PrimaryButton
          label="Guardar cambios"
          onPress={() => void guardar()}
          loading={saving}
          disabled={!rif.trim() || !razon.trim()}
        />
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({ pad: { paddingBottom: 40 } });
