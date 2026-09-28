import { useState } from "react";
import { Alert, ScrollView, StyleSheet } from "react-native";
import { useRouter, type Href } from "expo-router";
import { createProveedor } from "@/lib/proveedores";
import {
  ErrorText,
  FormField,
  PrimaryButton,
  Screen,
} from "@/components/ui";

export default function NuevoProveedorScreen() {
  const router = useRouter();
  const [rif, setRif] = useState("");
  const [razon, setRazon] = useState("");
  const [direccion, setDireccion] = useState("");
  const [telefono, setTelefono] = useState("");
  const [correo, setCorreo] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function guardar() {
    setSaving(true);
    setError(null);
    const res = await createProveedor({
      rif_nit: rif,
      razon_social: razon,
      direccion_fiscal: direccion,
      telefono,
      correo_e: correo,
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert("Listo", "Proveedor creado.");
    router.replace(`/(app)/proveedores/${res.id}` as Href);
  }

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
        <PrimaryButton
          label="Guardar"
          onPress={() => void guardar()}
          loading={saving}
          disabled={!rif.trim() || !razon.trim()}
        />
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({ pad: { paddingBottom: 40 } });
