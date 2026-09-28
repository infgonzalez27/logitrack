import "react-native-gesture-handler";
import { Stack, useRouter, useSegments } from "expo-router";
import { useEffect } from "react";
import { ActivityIndicator, Image, StyleSheet, View } from "react-native";
import { StatusBar } from "expo-status-bar";
import * as SplashScreen from "expo-splash-screen";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { AuthProvider, useAuth } from "@/lib/auth-context";
import { homeHrefForRole } from "@/lib/auth";
import { ThemeProvider, useTheme } from "@/src/theme/ThemeProvider";

void SplashScreen.preventAutoHideAsync().catch(() => undefined);

function BrandLoading() {
  return (
    <View style={styles.boot}>
      <Image
        source={require("../assets/images/icon.png")}
        style={styles.bootLogo}
        accessibilityLabel="LogiTrack"
      />
      <ActivityIndicator size="large" color="#FFFFFF" />
    </View>
  );
}

function AuthGate({ children }: { children: React.ReactNode }) {
  const { loading, profile, sessionUserId } = useAuth();
  const segments = useSegments();
  const router = useRouter();

  useEffect(() => {
    if (loading) return;
    void SplashScreen.hideAsync().catch(() => undefined);
    const inAuth = segments[0] === "login";
    if (!sessionUserId || !profile) {
      if (!inAuth) router.replace("/login");
      return;
    }
    if (inAuth) router.replace(homeHrefForRole(profile.rol) as never);
  }, [loading, sessionUserId, profile, segments, router]);

  if (loading) {
    return <BrandLoading />;
  }

  return <>{children}</>;
}

function ThemedStatusBar() {
  const { theme } = useTheme();
  return <StatusBar style={theme.scheme === "dark" ? "light" : "dark"} />;
}

export default function RootLayout() {
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <ThemeProvider>
        <AuthProvider>
          <ThemedStatusBar />
          <AuthGate>
            <Stack screenOptions={{ headerShown: false }}>
              <Stack.Screen name="login" />
              <Stack.Screen name="(app)" />
              <Stack.Screen name="index" />
            </Stack>
          </AuthGate>
        </AuthProvider>
      </ThemeProvider>
    </GestureHandlerRootView>
  );
}

const styles = StyleSheet.create({
  boot: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    gap: 20,
    backgroundColor: "#5D9CEC",
  },
  bootLogo: {
    width: 96,
    height: 96,
    borderRadius: 22,
  },
});
