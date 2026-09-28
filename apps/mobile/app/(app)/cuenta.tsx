import { Pressable, StyleSheet, Text, View } from "react-native";
import { useRouter, type Href } from "expo-router";
import { useAuth } from "@/lib/auth-context";
import { roleLabel } from "@/lib/auth";

export default function CuentaScreen() {
  const { profile, signOut } = useAuth();
  const router = useRouter();

  return (
    <View style={styles.root}>
      <Text style={styles.title}>Cuenta</Text>
      <View style={styles.card}>
        <Text style={styles.label}>Nombre</Text>
        <Text style={styles.value}>{profile?.nombre_completo ?? "—"}</Text>
        <Text style={[styles.label, styles.mt]}>Rol</Text>
        <Text style={styles.value}>
          {profile ? roleLabel(profile.rol) : "—"}
        </Text>
      </View>
      <Pressable
        style={styles.btnSecondary}
        onPress={() => router.push("/(app)/impresora" as Href)}
      >
        <Text style={styles.btnSecondaryText}>Impresora Bluetooth</Text>
      </Pressable>
      <Pressable style={styles.btn} onPress={() => void signOut()}>
        <Text style={styles.btnText}>Cerrar sesión</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F6F8", padding: 20, gap: 16 },
  title: { fontSize: 20, fontWeight: "700", color: "#0B3A5C" },
  card: {
    backgroundColor: "#fff",
    borderRadius: 14,
    padding: 16,
    borderWidth: 1,
    borderColor: "#E5EAF0",
  },
  label: { fontSize: 12, color: "#5B6B7C", textTransform: "uppercase" },
  value: { fontSize: 16, color: "#0B3A5C", fontWeight: "600", marginTop: 4 },
  mt: { marginTop: 14 },
  btn: {
    backgroundColor: "#B42318",
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: "center",
  },
  btnText: { color: "#fff", fontWeight: "600", fontSize: 16 },
  btnSecondary: {
    backgroundColor: "#fff",
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: "center",
    borderWidth: 1,
    borderColor: "#0B3A5C",
  },
  btnSecondaryText: { color: "#0B3A5C", fontWeight: "600", fontSize: 16 },
});
