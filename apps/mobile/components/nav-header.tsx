import { useNavigation, useRouter, type Href } from "expo-router";
import { Pressable, StyleSheet, Text, View } from "react-native";

const HOME: Href = "/(app)/home";

type NavWithDrawer = {
  openDrawer?: () => void;
  getParent?: () => NavWithDrawer | undefined;
};

function openNearestDrawer(navigation: NavWithDrawer) {
  let nav: NavWithDrawer | undefined = navigation;
  while (nav) {
    if (typeof nav.openDrawer === "function") {
      nav.openDrawer();
      return;
    }
    nav = nav.getParent?.();
  }
}

export function HeaderMenuButton() {
  const navigation = useNavigation();
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel="Abrir menú"
      hitSlop={8}
      style={styles.btn}
      onPress={() => openNearestDrawer(navigation as NavWithDrawer)}
    >
      <Text style={styles.btnText}>Menú</Text>
    </Pressable>
  );
}

export function HeaderBackButton() {
  const router = useRouter();
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel="Volver atrás"
      hitSlop={8}
      style={styles.btn}
      onPress={() => {
        if (router.canGoBack()) router.back();
        else router.replace(HOME);
      }}
    >
      <Text style={styles.btnText}>‹ Atrás</Text>
    </Pressable>
  );
}

export function HeaderHomeButton() {
  const router = useRouter();
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel="Ir a inicio"
      hitSlop={8}
      style={styles.btn}
      onPress={() => router.replace(HOME)}
    >
      <Text style={styles.btnText}>Inicio</Text>
    </Pressable>
  );
}

/** Izquierda en pantallas raíz de módulo: Menú + Atrás. */
export function HeaderLeftRoot() {
  return (
    <View style={styles.row}>
      <HeaderMenuButton />
      <HeaderBackButton />
    </View>
  );
}

/** Izquierda en detalle / formularios: solo Atrás. */
export function HeaderLeftBack() {
  return <HeaderBackButton />;
}

/** Derecha: Inicio. */
export function HeaderRightHome() {
  return <HeaderHomeButton />;
}

/** Opciones base de header (Drawer y Stacks). */
export const appHeaderScreenOptions = {
  headerStyle: { backgroundColor: "#0B3A5C" },
  headerTintColor: "#fff",
  headerTitleStyle: { fontWeight: "600" as const },
  headerBackTitle: "Atrás",
  headerTitleAlign: "center" as const,
};

/** Stack index (lista): Menú + Atrás | Inicio */
export function stackIndexOptions(title: string) {
  return {
    title,
    headerLeft: () => <HeaderLeftRoot />,
    headerRight: () => <HeaderRightHome />,
  };
}

/** Stack hijo (detalle/form): Atrás | Inicio */
export function stackChildOptions(title: string) {
  return {
    title,
    headerLeft: () => <HeaderLeftBack />,
    headerRight: () => <HeaderRightHome />,
  };
}

/** Drawer top-level (home / cuenta / impresora). */
export function drawerTopOptions(title: string, opts?: { showHome?: boolean }) {
  const showHome = opts?.showHome !== false;
  return {
    title,
    headerShown: true,
    headerLeft: () => <HeaderMenuButton />,
    headerRight: showHome ? () => <HeaderRightHome /> : undefined,
  };
}

const styles = StyleSheet.create({
  row: { flexDirection: "row", alignItems: "center", gap: 4 },
  btn: {
    paddingHorizontal: 8,
    paddingVertical: 6,
    marginHorizontal: 2,
  },
  btnText: {
    color: "#fff",
    fontSize: 15,
    fontWeight: "600",
  },
});
