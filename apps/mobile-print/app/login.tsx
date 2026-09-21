import { useState } from "react";
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { signIn, fetchProfile, isPrintRole } from "@/lib/auth";
import { supabase } from "@/lib/supabase";
import { useAuth } from "@/lib/auth-context";

export default function LoginScreen() {
  const { refresh } = useAuth();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onSubmit() {
    setPending(true);
    setError(null);
    const result = await signIn(email, password);
    if (!result.ok) {
      setError(result.error);
      setPending(false);
      return;
    }
    const userId = result.session?.user?.id;
    if (!userId) {
      setError("Sesión inválida.");
      setPending(false);
      return;
    }
    const profile = await fetchProfile(userId);
    if (!profile.ok) {
      setError(profile.error);
      await supabase.auth.signOut();
      setPending(false);
      return;
    }
    if (!isPrintRole(profile.profile.rol)) {
      setError("Rol no autorizado para imprimir.");
      await supabase.auth.signOut();
      setPending(false);
      return;
    }
    await refresh();
    setPending(false);
  }

  return (
    <KeyboardAvoidingView
      style={styles.root}
      behavior={Platform.OS === "ios" ? "padding" : undefined}
    >
      <View style={styles.card}>
        <Text style={styles.brand}>LogiTrack Print</Text>
        <Text style={styles.sub}>
          Impresión térmica Bluetooth — vendedor y gerente
        </Text>
        <TextInput
          style={styles.input}
          autoCapitalize="none"
          keyboardType="email-address"
          placeholder="Correo"
          value={email}
          onChangeText={setEmail}
        />
        <TextInput
          style={styles.input}
          secureTextEntry
          placeholder="Contraseña"
          value={password}
          onChangeText={setPassword}
        />
        {error ? <Text style={styles.error}>{error}</Text> : null}
        <Pressable
          style={[styles.btn, pending && styles.btnDisabled]}
          disabled={pending}
          onPress={() => void onSubmit()}
        >
          {pending ? (
            <ActivityIndicator color="#fff" />
          ) : (
            <Text style={styles.btnText}>Entrar</Text>
          )}
        </Pressable>
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: "#0B3A5C",
    justifyContent: "center",
    padding: 24,
  },
  card: {
    backgroundColor: "#fff",
    borderRadius: 16,
    padding: 20,
    gap: 12,
  },
  brand: {
    fontSize: 24,
    fontWeight: "700",
    color: "#0B3A5C",
  },
  sub: {
    color: "#5B6B7C",
    marginBottom: 8,
  },
  input: {
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 12,
    fontSize: 16,
  },
  error: {
    color: "#B42318",
    fontSize: 14,
  },
  btn: {
    backgroundColor: "#0B3A5C",
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: "center",
  },
  btnDisabled: { opacity: 0.7 },
  btnText: { color: "#fff", fontWeight: "600", fontSize: 16 },
});
