import { useEffect, useState } from "react";
import {
  Alert,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { useRouter, type Href } from "expo-router";
import {
  listRoles,
  registrarUsuario,
  type RolOption,
} from "@/lib/usuarios";
import {
  ErrorText,
  FormField,
  LoadingBlock,
  PrimaryButton,
  SectionTitle,
} from "@/components/ui";

export default function RegistrarUsuarioScreen() {
  const router = useRouter();
  const [roles, setRoles] = useState<RolOption[]>([]);
  const [nombre, setNombre] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [telefono, setTelefono] = useState("");
  const [rolNombre, setRolNombre] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pickerOpen, setPickerOpen] = useState(false);

  useEffect(() => {
    void (async () => {
      const res = await listRoles();
      if (!res.ok) setError(res.error);
      else {
        setRoles(res.roles);
        if (res.roles[0]) setRolNombre(res.roles[0].nombre);
      }
      setLoading(false);
    })();
  }, []);

  const selected = roles.find((r) => r.nombre === rolNombre);

  const submit = async () => {
    setSaving(true);
    setError(null);
    const res = await registrarUsuario({
      email,
      password,
      nombre_completo: nombre,
      telefono,
      rol_nombre: rolNombre,
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert("Listo", "Usuario registrado.");
    router.replace("/(app)/usuarios" as never);
  };

  if (loading) return <LoadingBlock />;

  return (
    <ScrollView
      style={styles.root}
      contentContainerStyle={{ padding: 16, paddingBottom: 40 }}
    >
      <FormField
        label="Nombre completo"
        value={nombre}
        onChangeText={setNombre}
      />
      <FormField
        label="Correo"
        value={email}
        onChangeText={setEmail}
        autoCapitalize="none"
        keyboardType="email-address"
      />
      <FormField
        label="Contraseña"
        value={password}
        onChangeText={setPassword}
        secureTextEntry
      />
      <FormField
        label="Teléfono"
        value={telefono}
        onChangeText={setTelefono}
        keyboardType="phone-pad"
      />

      <SectionTitle>Rol</SectionTitle>
      <Pressable style={styles.select} onPress={() => setPickerOpen((v) => !v)}>
        <Text style={styles.selectText}>
          {selected?.label ?? "Selecciona rol…"}
        </Text>
      </Pressable>
      {pickerOpen
        ? roles.map((r) => (
            <Pressable
              key={r.id}
              style={styles.option}
              onPress={() => {
                setRolNombre(r.nombre);
                setPickerOpen(false);
              }}
            >
              <Text style={styles.optionText}>{r.label}</Text>
            </Pressable>
          ))
        : null}

      <ErrorText message={error} />
      <PrimaryButton
        label="Registrar"
        onPress={() => void submit()}
        loading={saving}
        disabled={!nombre || !email || !password || !rolNombre}
      />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F6F8" },
  select: {
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 12,
    padding: 14,
    marginBottom: 8,
  },
  selectText: { color: "#0B3A5C", fontSize: 16 },
  option: {
    backgroundColor: "#fff",
    padding: 12,
    borderBottomWidth: 1,
    borderBottomColor: "#E5EAF0",
  },
  optionText: { color: "#0B3A5C" },
});
