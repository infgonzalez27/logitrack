import { Stack, useRouter, useSegments } from "expo-router";
import { useEffect } from "react";
import { ActivityIndicator, View } from "react-native";
import { AuthProvider, useAuth } from "@/lib/auth-context";

function AuthGate({ children }: { children: React.ReactNode }) {
  const { loading, profile, sessionUserId } = useAuth();
  const segments = useSegments();
  const router = useRouter();

  useEffect(() => {
    if (loading) return;
    const inAuth = segments[0] === "login";
    if (!sessionUserId || !profile) {
      if (!inAuth) router.replace("/login");
      return;
    }
    if (inAuth) router.replace("/(app)/orders");
  }, [loading, sessionUserId, profile, segments, router]);

  if (loading) {
    return (
      <View style={{ flex: 1, alignItems: "center", justifyContent: "center" }}>
        <ActivityIndicator size="large" color="#0B3A5C" />
      </View>
    );
  }

  return <>{children}</>;
}

export default function RootLayout() {
  return (
    <AuthProvider>
      <AuthGate>
        <Stack screenOptions={{ headerShown: false }}>
          <Stack.Screen name="login" />
          <Stack.Screen name="(app)" />
          <Stack.Screen name="index" />
        </Stack>
      </AuthGate>
    </AuthProvider>
  );
}
