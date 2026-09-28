import { useEffect, useState } from "react";
import {
  Alert,
  Pressable,
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  View,
} from "react-native";
import { useLocalSearchParams, useRouter } from "expo-router";
import {
  actualizarPerfilUsuario,
  getPerfilUsuario,
  listRoles,
  cambiarContrasenaUsuario,
  type PerfilUsuarioEditar,
  type RolOption,
} from "@/lib/usuarios";
import { normalizeRolNombre } from "@/lib/auth";
import { useAuth } from "@/lib/auth-context";
import {
  ErrorText,
  FormField,
  LoadingBlock,
  PrimaryButton,
  SectionTitle,
} from "@/components/ui";

export default function EditarUsuarioScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const [perfil, setPerfil] = useState<PerfilUsuarioEditar | null>(null);
  const [roles, setRoles] = useState<RolOption[]>([]);
  const [nombre, setNombre] = useState("");
  const [telefono, setTelefono] = useState("");
  const [rolId, setRolId] = useState("");
  const [activo, setActivo] = useState(true);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pickerOpen, setPickerOpen] = useState(false);
  const { profile } = useAuth();
  const [password, setPassword] = useState("");
  const [passwordConfirmacion, setPasswordConfirmacion] = useState("");
  const [pwdSaving, setPwdSaving] = useState(false);
  const [pwdError, setPwdError] = useState<string | null>(null);

  useEffect(() => {
    void (async () => {
      if (!id) {
        setError("ID inválido.");
        setLoading(false);
        return;
      }
      const [pRes, rRes] = await Promise.all([
        getPerfilUsuario(id),
        listRoles(),
      ]);
      if (!pRes.ok) {
        setError(pRes.error);
        setLoading(false);
        return;
      }
      setPerfil(pRes.perfil);
      setNombre(pRes.perfil.nombre_completo);
      setTelefono(pRes.perfil.telefono);
      setRolId(pRes.perfil.rol_id);
      setActivo(pRes.perfil.activo);
      if (rRes.ok) setRoles(rRes.roles);
      setLoading(false);
    })();
  }, [id]);

  const selectedRol = roles.find((r) => r.id === rolId);

  const submit = async () => {
    if (!perfil) return;
    setSaving(true);
    setError(null);
    const res = await actualizarPerfilUsuario({
      id: perfil.id,
      rol_id: rolId,
      nombre_completo: nombre,
      telefono,
      activo,
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert("Listo", "Perfil actualizado.");
    router.back();
  };

  const cambiarPwd = async () => {
    if (!perfil) return;
    setPwdError(null);
    if (password !== passwordConfirmacion) {
      setPwdError("Las contraseñas no coinciden.");
      return;
    }
    setPwdSaving(true);
    const res = await cambiarContrasenaUsuario({ userId: perfil.id, password });
    setPwdSaving(false);
    if (!res.ok) {
      setPwdError(res.error);
      return;
    }
    setPassword("");
    setPasswordConfirmacion("");
    Alert.alert("Listo", "Contraseña actualizada. El usuario ya puede iniciar sesión con ella.");
  };

  const actorRol = normalizeRolNombre(profile?.rol);
  const destinoRol = normalizeRolNombre(perfil?.rol_nombre);
  const puedeCambiarPwd =
    actorRol === "admin" ||
    (actorRol === "gerente" && destinoRol !== null && destinoRol !== "admin");

  if (loading) return <LoadingBlock />;
  if (!perfil) {
    return (
      <View style={styles.root}>
        <ErrorText message={error ?? "Perfil no encontrado."} />
      </View>
    );
  }

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
        label="Teléfono"
        value={telefono}
        onChangeText={setTelefono}
        keyboardType="phone-pad"
      />

      <SectionTitle>Rol</SectionTitle>
      <Pressable style={styles.select} onPress={() => setPickerOpen((v) => !v)}>
        <Text style={styles.selectText}>
          {selectedRol?.label ?? perfil.rol_nombre ?? "Selecciona rol…"}
        </Text>
      </Pressable>
      {pickerOpen
        ? roles.map((r) => (
            <Pressable
              key={r.id}
              style={styles.option}
              onPress={() => {
                setRolId(r.id);
                setPickerOpen(false);
              }}
            >
              <Text style={styles.optionText}>{r.label}</Text>
            </Pressable>
          ))
        : null}

      <View style={styles.switchRow}>
        <Text style={styles.switchLabel}>Usuario activo</Text>
        <Switch
          value={activo}
          onValueChange={setActivo}
          trackColor={{ true: "#0B3A5C" }}
        />
      </View>

      <ErrorText message={error} />
      <PrimaryButton
        label="Guardar cambios"
        onPress={() => void submit()}
        loading={saving}
      />

      {puedeCambiarPwd ? (
        <>
          <SectionTitle>Contraseña de acceso</SectionTitle>
          <FormField
            label="Nueva contraseña"
            value={password}
            onChangeText={setPassword}
            secureTextEntry
            autoCapitalize="none"
            autoComplete="new-password"
          />
          <FormField
            label="Confirmar contraseña"
            value={passwordConfirmacion}
            onChangeText={setPasswordConfirmacion}
            secureTextEntry
            autoCapitalize="none"
            autoComplete="new-password"
          />
          <ErrorText message={pwdError} />
          <PrimaryButton
            label="Asignar nueva contraseña"
            onPress={() => void cambiarPwd()}
            loading={pwdSaving}
          />
        </>
      ) : null}
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
  switchRow: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    marginVertical: 12,
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    borderWidth: 1,
    borderColor: "#E5EAF0",
  },
  switchLabel: { color: "#0B3A5C", fontWeight: "600" },
});
