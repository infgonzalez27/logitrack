import { useState } from "react";
import {
  ActivityIndicator,
  Image,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { Ionicons } from "@expo/vector-icons";
import { signIn, signOut, fetchProfile, isAppRole } from "@/lib/auth";
import { useAuth } from "@/lib/auth-context";

export default function LoginScreen() {
  const { refresh } = useAuth();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onSubmit() {
    if (!email.trim() || !password) {
      setError("Por favor, ingresa tu correo y contraseña.");
      return;
    }
    setPending(true);
    setError(null);
    const result = await signIn(email.trim(), password);
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
      await signOut();
      setPending(false);
      return;
    }
    if (!isAppRole(profile.profile.rol)) {
      setError("Rol no autorizado para esta app.");
      await signOut();
      setPending(false);
      return;
    }
    await refresh();
    setPending(false);
  }

  return (
    <KeyboardAvoidingView
      style={styles.root}
      behavior={Platform.OS === "ios" ? "padding" : "height"}
      keyboardVerticalOffset={Platform.OS === "ios" ? 0 : 20}
    >
      <ScrollView
        contentContainerStyle={styles.scrollContent}
        keyboardShouldPersistTaps="handled"
        showsVerticalScrollIndicator={false}
      >
        <View style={styles.card}>
          <View style={styles.logoBadge}>
            <Image
              source={require("../assets/images/icon.png")}
              style={styles.logo}
              accessibilityLabel="LogiTrack"
            />
          </View>
          <Text style={styles.brand}>LogiTrack</Text>
          <Text style={styles.sub}>
            App de campo — vendedor, despachador, gerente
          </Text>

          <View style={styles.fieldGroup}>
            <Text style={styles.label}>Correo electrónico</Text>
            <TextInput
              style={styles.input}
              autoCapitalize="none"
              autoCorrect={false}
              keyboardType="email-address"
              placeholder="ejemplo@logitrack.com"
              placeholderTextColor="#94A3B8"
              value={email}
              onChangeText={setEmail}
              returnKeyType="next"
            />
          </View>

          <View style={styles.fieldGroup}>
            <Text style={styles.label}>Contraseña</Text>
            <View style={styles.passwordContainer}>
              <TextInput
                style={styles.passwordInput}
                secureTextEntry={!showPassword}
                placeholder="Ingresa tu contraseña"
                placeholderTextColor="#94A3B8"
                value={password}
                onChangeText={setPassword}
                autoCapitalize="none"
                autoCorrect={false}
                returnKeyType="go"
                onSubmitEditing={() => void onSubmit()}
              />
              <Pressable
                style={styles.eyeBtn}
                onPress={() => setShowPassword((prev) => !prev)}
                hitSlop={12}
                accessibilityLabel={
                  showPassword ? "Ocultar contraseña" : "Ver contraseña"
                }
              >
                <Ionicons
                  name={showPassword ? "eye-off-outline" : "eye-outline"}
                  size={22}
                  color="#64748B"
                />
              </Pressable>
            </View>
          </View>

          {error ? <Text style={styles.error}>{error}</Text> : null}

          <Pressable
            style={[styles.btn, pending && styles.btnDisabled]}
            disabled={pending}
            onPress={() => void onSubmit()}
          >
            {pending ? (
              <ActivityIndicator color="#fff" />
            ) : (
              <Text style={styles.btnText}>Iniciar sesión</Text>
            )}
          </Pressable>
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: "#0B3A5C",
  },
  scrollContent: {
    flexGrow: 1,
    justifyContent: "center",
    padding: 24,
    paddingVertical: 36,
  },
  card: {
    backgroundColor: "#fff",
    borderRadius: 20,
    padding: 24,
    gap: 14,
    alignItems: "center",
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.15,
    shadowRadius: 12,
    elevation: 8,
  },
  logoBadge: {
    padding: 3,
    backgroundColor: "#FFFFFF",
    borderRadius: 24,
    shadowColor: "#0B3A5C",
    shadowOffset: { width: 0, height: 6 },
    shadowOpacity: 0.18,
    shadowRadius: 10,
    elevation: 6,
    marginBottom: 4,
  },
  logo: {
    width: 82,
    height: 82,
    borderRadius: 21,
  },
  brand: {
    fontSize: 26,
    fontWeight: "700",
    color: "#0B3A5C",
    alignSelf: "stretch",
    textAlign: "center",
  },
  sub: {
    color: "#64748B",
    fontSize: 13,
    marginBottom: 4,
    alignSelf: "stretch",
    textAlign: "center",
  },
  fieldGroup: {
    alignSelf: "stretch",
    gap: 6,
  },
  label: {
    fontSize: 13,
    fontWeight: "600",
    color: "#334155",
  },
  input: {
    borderWidth: 1.5,
    borderColor: "#CBD5E1",
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 12,
    fontSize: 16,
    color: "#0F172A",
    backgroundColor: "#F8FAFC",
  },
  passwordContainer: {
    flexDirection: "row",
    alignItems: "center",
    borderWidth: 1.5,
    borderColor: "#CBD5E1",
    borderRadius: 12,
    backgroundColor: "#F8FAFC",
  },
  passwordInput: {
    flex: 1,
    paddingHorizontal: 14,
    paddingVertical: 12,
    fontSize: 16,
    color: "#0F172A",
  },
  eyeBtn: {
    paddingHorizontal: 14,
    paddingVertical: 12,
  },
  error: {
    color: "#B42318",
    fontSize: 13,
    alignSelf: "stretch",
    backgroundColor: "#FEF2F2",
    padding: 10,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: "#FCA5A5",
  },
  btn: {
    backgroundColor: "#0B3A5C",
    borderRadius: 12,
    paddingVertical: 15,
    alignItems: "center",
    alignSelf: "stretch",
    marginTop: 4,
  },
  btnDisabled: { opacity: 0.7 },
  btnText: { color: "#fff", fontWeight: "600", fontSize: 16 },
});
