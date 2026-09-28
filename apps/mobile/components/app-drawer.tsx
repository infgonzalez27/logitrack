import { useMemo, useState } from "react";
import { usePathname, useRouter, type Href } from "expo-router";
import {
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { Ionicons } from "@expo/vector-icons";
import { useAuth } from "@/lib/auth-context";
import { getNavSectionsForRole, roleLabel } from "@/lib/auth";
import { useTheme } from "@/src/theme/ThemeProvider";

type DrawerNav = {
  closeDrawer?: () => void;
};

const ICON_BY_HREF: Record<string, keyof typeof Ionicons.glyphMap> = {
  "/visita": "map-outline",
  "/ordenes": "document-text-outline",
  "/autoventas": "car-outline",
  "/radar": "radio-outline",
  "/clientes": "people-outline",
  "/rutas": "git-branch-outline",
  "/proveedores": "business-outline",
  "/camiones": "bus-outline",
  "/productos": "cube-outline",
  "/choferes": "person-outline",
  "/inventario-almacen": "archive-outline",
  "/inventario-movil": "phone-portrait-outline",
  "/rendiciones": "wallet-outline",
  "/rendiciones/por-liquidar": "cash-outline",
  "/rendiciones/formas-pago": "card-outline",
  "/contenedores": "layers-outline",
  "/facturas-compras": "receipt-outline",
  "/pagos-proveedores": "swap-horizontal-outline",
  "/tasas-cambio": "trending-up-outline",
  "/cuentas-bancarias": "card-outline",
  "/usuarios": "people-circle-outline",
  "/usuarios/registrar": "person-add-outline",
  "/impresora": "print-outline",
  "/cuenta": "settings-outline",
};

function iconFor(href: string): keyof typeof Ionicons.glyphMap {
  return ICON_BY_HREF[href] ?? "ellipse-outline";
}

function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return "LT";
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return `${parts[0][0]}${parts[1][0]}`.toUpperCase();
}

function isActivePath(pathname: string, href: string, route: string): boolean {
  const clean = pathname.replace(/\/$/, "") || "/";
  if (href === "/" || route.endsWith("/home")) {
    return clean.endsWith("/home") || clean === "/" || clean === "/(app)";
  }
  return (
    clean.includes(href) ||
    clean.includes(route.replace("/(app)", "")) ||
    clean.startsWith(route)
  );
}

interface NavRowProps {
  label: string;
  icon: keyof typeof Ionicons.glyphMap;
  active: boolean;
  chevron?: boolean;
  onPress: () => void;
}

const NavRow: React.FC<NavRowProps> = function NavRow({
  label,
  icon,
  active,
  chevron,
  onPress,
}) {
  const { theme } = useTheme();
  return (
    <Pressable
      onPress={onPress}
      style={[
        styles.item,
        active && {
          backgroundColor: theme.colors.background,
        },
      ]}
    >
      {active ? (
        <View
          style={[styles.activeBar, { backgroundColor: theme.colors.accent }]}
        />
      ) : null}
      <View
        style={[
          styles.iconChip,
          {
            backgroundColor: active
              ? theme.colors.dangerBg
              : theme.colors.background,
          },
        ]}
      >
        <Ionicons
          name={icon}
          size={18}
          color={active ? theme.colors.accent : theme.colors.brand}
        />
      </View>
      <Text
        style={[
          styles.itemText,
          {
            color: theme.colors.text,
            fontWeight: active ? "700" : "500",
          },
        ]}
        numberOfLines={1}
      >
        {label}
      </Text>
      {chevron ? (
        <Ionicons
          name="chevron-forward"
          size={16}
          color={theme.colors.textSecondary}
        />
      ) : null}
    </Pressable>
  );
};

export function AppDrawerContent({
  navigation,
}: {
  navigation?: DrawerNav;
}) {
  const { profile, signOut } = useAuth();
  const router = useRouter();
  const pathname = usePathname();
  const insets = useSafeAreaInsets();
  const { theme, toggleScheme } = useTheme();
  const [q, setQ] = useState("");
  const sections = getNavSectionsForRole(profile?.rol);

  const filtered = useMemo(() => {
    const term = q.trim().toLowerCase();
    if (!term) return sections;
    return sections
      .map((section) => ({
        ...section,
        items: section.items.filter(
          (item) =>
            item.label.toLowerCase().includes(term) ||
            item.href.toLowerCase().includes(term),
        ),
      }))
      .filter((section) => section.items.length > 0);
  }, [sections, q]);

  const go = (route: string) => {
    router.push(route as Href);
    navigation?.closeDrawer?.();
  };

  const onLogout = async () => {
    navigation?.closeDrawer?.();
    await signOut();
  };

  return (
    <View
      style={[
        styles.shell,
        {
          paddingTop: insets.top + 8,
          backgroundColor: theme.colors.surface,
        },
      ]}
    >
      <View style={styles.brandRow}>
        <View
          style={[styles.logoMark, { backgroundColor: theme.colors.brand }]}
        >
          <Text style={[styles.logoMarkText, { color: theme.colors.textInverse }]}>
            LT
          </Text>
        </View>
        <View style={{ flex: 1 }}>
          <Text style={[styles.brand, { color: theme.colors.text }]}>
            LogiTrack
          </Text>
          <Text style={[styles.brandSub, { color: theme.colors.textSecondary }]}>
            Operaciones en campo
          </Text>
        </View>
        <Pressable
          onPress={toggleScheme}
          style={[
            styles.themeChip,
            { backgroundColor: theme.colors.background },
          ]}
          accessibilityLabel="Cambiar tema"
        >
          <Ionicons
            name={theme.scheme === "dark" ? "sunny-outline" : "moon-outline"}
            size={18}
            color={theme.colors.brand}
          />
        </Pressable>
      </View>

      <View
        style={[styles.searchWrap, { backgroundColor: theme.colors.background }]}
      >
        <Ionicons
          name="search-outline"
          size={18}
          color={theme.colors.textSecondary}
        />
        <TextInput
          style={[styles.searchInput, { color: theme.colors.text }]}
          placeholder="Buscar…"
          placeholderTextColor={theme.colors.textSecondary}
          value={q}
          onChangeText={setQ}
          returnKeyType="search"
        />
      </View>

      <ScrollView
        style={styles.scroll}
        contentContainerStyle={{ paddingBottom: 16 }}
        showsVerticalScrollIndicator={false}
      >
        <View style={styles.section}>
          <Text
            style={[styles.sectionTitle, { color: theme.colors.textSecondary }]}
          >
            Menú
          </Text>
          <NavRow
            label="Inicio"
            icon="home-outline"
            active={isActivePath(pathname, "/", "/(app)/home")}
            onPress={() => go("/(app)/home")}
          />
        </View>

        {filtered.map((section) => (
          <View key={section.title} style={styles.section}>
            <Text
              style={[
                styles.sectionTitle,
                { color: theme.colors.textSecondary },
              ]}
            >
              {section.title}
            </Text>
            {section.items.map((item) => (
              <NavRow
                key={item.href}
                label={item.label}
                icon={iconFor(item.href)}
                active={isActivePath(pathname, item.href, item.route)}
                onPress={() => go(item.route)}
                chevron
              />
            ))}
          </View>
        ))}
      </ScrollView>

      <View
        style={[
          styles.footer,
          {
            paddingBottom: Math.max(insets.bottom, 12),
            borderTopColor: theme.colors.border,
          },
        ]}
      >
        <View
          style={[styles.avatar, { backgroundColor: theme.colors.brand }]}
        >
          <Text
            style={[styles.avatarText, { color: theme.colors.textInverse }]}
          >
            {initials(profile?.nombre_completo ?? "LT")}
          </Text>
        </View>
        <View style={{ flex: 1, minWidth: 0 }}>
          <Text
            style={[styles.footerName, { color: theme.colors.text }]}
            numberOfLines={1}
          >
            {profile?.nombre_completo ?? "Usuario"}
          </Text>
          <Text
            style={[styles.footerMeta, { color: theme.colors.textSecondary }]}
            numberOfLines={1}
          >
            {profile
              ? [roleLabel(profile.rol), profile.empresa_nombre]
                  .filter(Boolean)
                  .join(" · ")
              : "—"}
          </Text>
        </View>
        <Pressable
          accessibilityLabel="Cerrar sesión"
          style={[
            styles.logoutBtn,
            { backgroundColor: theme.colors.background },
          ]}
          onPress={() => void onLogout()}
        >
          <Ionicons
            name="log-out-outline"
            size={20}
            color={theme.colors.textSecondary}
          />
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  shell: { flex: 1, paddingHorizontal: 14 },
  brandRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
    paddingHorizontal: 4,
    marginBottom: 14,
  },
  logoMark: {
    width: 40,
    height: 40,
    borderRadius: 12,
    alignItems: "center",
    justifyContent: "center",
  },
  logoMarkText: { fontWeight: "800", fontSize: 14 },
  brand: { fontSize: 18, fontWeight: "700" },
  brandSub: { fontSize: 12, marginTop: 1 },
  themeChip: {
    width: 36,
    height: 36,
    borderRadius: 10,
    alignItems: "center",
    justifyContent: "center",
  },
  searchWrap: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
    marginBottom: 10,
  },
  searchInput: { flex: 1, fontSize: 15, padding: 0 },
  scroll: { flex: 1 },
  section: { marginTop: 10 },
  sectionTitle: {
    fontSize: 11,
    fontWeight: "700",
    textTransform: "uppercase",
    letterSpacing: 0.8,
    marginBottom: 6,
    paddingHorizontal: 8,
  },
  item: {
    flexDirection: "row",
    alignItems: "center",
    gap: 10,
    paddingVertical: 11,
    paddingHorizontal: 10,
    borderRadius: 12,
    marginBottom: 2,
    overflow: "hidden",
  },
  activeBar: {
    position: "absolute",
    left: 0,
    top: 8,
    bottom: 8,
    width: 3,
    borderRadius: 2,
  },
  iconChip: {
    width: 32,
    height: 32,
    borderRadius: 9,
    alignItems: "center",
    justifyContent: "center",
  },
  itemText: { flex: 1, fontSize: 14 },
  footer: {
    flexDirection: "row",
    alignItems: "center",
    gap: 10,
    borderTopWidth: StyleSheet.hairlineWidth,
    paddingTop: 12,
    marginTop: 4,
  },
  avatar: {
    width: 40,
    height: 40,
    borderRadius: 12,
    alignItems: "center",
    justifyContent: "center",
  },
  avatarText: { fontWeight: "700", fontSize: 13 },
  footerName: { fontWeight: "700", fontSize: 14 },
  footerMeta: { fontSize: 12, marginTop: 1 },
  logoutBtn: {
    width: 40,
    height: 40,
    borderRadius: 10,
    alignItems: "center",
    justifyContent: "center",
  },
});
