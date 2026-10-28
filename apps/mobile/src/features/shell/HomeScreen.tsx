import React, { useCallback, useMemo, useState } from "react";
import {
  Pressable,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { useFocusEffect, useRouter, type Href } from "expo-router";
import { Ionicons } from "@expo/vector-icons";
import { useAuth } from "@/lib/auth-context";
import { getNavSectionsForRole, roleLabel, tabsForRole } from "@/lib/auth";
import { fetchHomeKpis, type HomeKpis } from "@/lib/kpis";
import { useTheme } from "@/src/theme/ThemeProvider";
import { BottomActionBar } from "@/src/ui/BottomActionBar";
import { SkeletonList } from "@/src/ui/Skeleton";

interface ShortcutItem {
  key: string;
  label: string;
  sub: string;
  icon: keyof typeof Ionicons.glyphMap;
  iconColor: string;
  iconBg: string;
  href: Href;
}

interface KpiTileProps {
  value: number;
  label: string;
  icon: keyof typeof Ionicons.glyphMap;
  iconColor: string;
  iconBg: string;
}

const KpiTile: React.FC<KpiTileProps> = React.memo(function KpiTile({
  value,
  label,
  icon,
  iconColor,
  iconBg,
}) {
  const { theme } = useTheme();
  return (
    <View
      style={[
        styles.kpi,
        {
          backgroundColor: theme.colors.surface,
          borderColor: theme.colors.border,
        },
      ]}
    >
      <View style={[styles.kpiIconWrap, { backgroundColor: iconBg }]}>
        <Ionicons name={icon} size={18} color={iconColor} />
      </View>
      <Text style={[styles.kpiNum, { color: theme.colors.text }]}>{value}</Text>
      <Text
        style={[styles.kpiLabel, { color: theme.colors.textSecondary }]}
        numberOfLines={1}
      >
        {label}
      </Text>
    </View>
  );
});

interface ShortcutRowProps {
  item: ShortcutItem;
  onPress: (href: Href) => void;
}

const ShortcutRow: React.FC<ShortcutRowProps> = React.memo(function ShortcutRow({
  item,
  onPress,
}) {
  const { theme } = useTheme();
  const handlePress = useCallback(() => {
    onPress(item.href);
  }, [item.href, onPress]);

  return (
    <Pressable
      onPress={handlePress}
      style={({ pressed }) => [
        styles.shortcut,
        {
          backgroundColor: theme.colors.surface,
          borderColor: theme.colors.border,
          opacity: pressed ? 0.9 : 1,
        },
      ]}
    >
      <View style={[styles.shortcutIcon, { backgroundColor: item.iconBg }]}>
        <Ionicons name={item.icon} size={22} color={item.iconColor} />
      </View>
      <View style={{ flex: 1, gap: 2 }}>
        <Text style={[styles.shortcutText, { color: theme.colors.text }]}>
          {item.label}
        </Text>
        <Text
          style={[styles.shortcutSub, { color: theme.colors.textSecondary }]}
        >
          {item.sub}
        </Text>
      </View>
      <Ionicons
        name="chevron-forward"
        size={18}
        color={theme.colors.textSecondary}
      />
    </Pressable>
  );
});

export const HomeScreen: React.FC = function HomeScreen() {
  const { profile } = useAuth();
  const router = useRouter();
  const { theme, toggleScheme, preference } = useTheme();
  const tabs = tabsForRole(profile?.rol);
  const sections = getNavSectionsForRole(profile?.rol);
  const [kpis, setKpis] = useState<HomeKpis | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async (mode: "initial" | "refresh") => {
    if (mode === "refresh") setRefreshing(true);
    else setLoading(true);
    const res = await fetchHomeKpis();
    if (res.ok) setKpis(res.kpis);
    setLoading(false);
    setRefreshing(false);
  }, []);

  useFocusEffect(
    useCallback(() => {
      void load("initial");
    }, [load]),
  );

  const ordenesActivas = useMemo(() => {
    if (!kpis) return 0;
    return Object.entries(kpis.ordenesPorEstado)
      .filter(([e]) => !["liquidada", "anulada", "devuelta"].includes(e))
      .reduce((s, [, n]) => s + n, 0);
  }, [kpis]);

  const shortcuts = useMemo(() => {
    const items: ShortcutItem[] = [];
    if (tabs.visita) {
      items.push({
        key: "visita",
        label: "Visita / cartera",
        sub: "Gestión de clientes y cobro",
        icon: "map-outline",
        iconColor: "#0284C7",
        iconBg: "#E0F2FE",
        href: "/(app)/visita" as Href,
      });
    }
    if (tabs.ordenes) {
      items.push({
        key: "ordenes",
        label: "Órdenes / envíos",
        sub: "Pedidos y despachos activos",
        icon: "document-text-outline",
        iconColor: "#2563EB",
        iconBg: "#DBEAFE",
        href: "/(app)/ordenes" as Href,
      });
    }
    if (tabs.radar) {
      items.push({
        key: "radar",
        label: "Radar del día",
        sub: "Mapa y geolocalización de rutas",
        icon: "radio-outline",
        iconColor: "#7C3AED",
        iconBg: "#EDE9FE",
        href: "/(app)/radar" as Href,
      });
    }
    if (tabs.autoventas) {
      items.push({
        key: "autoventas",
        label: "AutoVentas",
        sub: "Carga de camión y venta en ruta",
        icon: "car-outline",
        iconColor: "#EA580C",
        iconBg: "#FFEDD5",
        href: "/(app)/autoventas" as Href,
      });
    }
    items.push({
      key: "rendiciones",
      label: "Cobranzas",
      sub: "Registrar rendición de cobros",
      icon: "wallet-outline",
      iconColor: "#059669",
      iconBg: "#D1FAE5",
      href: "/(app)/rendiciones" as Href,
    });
    return items;
  }, [tabs]);

  const handleNavigate = useCallback(
    (href: Href) => {
      router.push(href);
    },
    [router],
  );

  const handleRefresh = useCallback(() => {
    void load("refresh");
  }, [load]);

  const handleNuevaOrden = useCallback(() => {
    router.push("/(app)/ordenes/nueva");
  }, [router]);

  const handleOpenOrdenes = useCallback(() => {
    router.push("/(app)/ordenes");
  }, [router]);

  const handleOpenRadar = useCallback(() => {
    router.push("/(app)/radar");
  }, [router]);

  // Iniciales para el avatar
  const initials = useMemo(() => {
    if (!profile?.nombre_completo) return "LT";
    const parts = profile.nombre_completo.trim().split(" ");
    if (parts.length >= 2) {
      return `${parts[0][0]}${parts[1][0]}`.toUpperCase();
    }
    return parts[0].slice(0, 2).toUpperCase();
  }, [profile?.nombre_completo]);

  return (
    <View style={[styles.root, { backgroundColor: theme.colors.background }]}>
      <ScrollView
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={handleRefresh}
            tintColor={theme.colors.brand}
          />
        }
      >
        {/* Cabecera del Usuario */}
        <View style={styles.header}>
          <View style={styles.avatar}>
            <Text style={styles.avatarText}>{initials}</Text>
          </View>

          <View style={{ flex: 1, gap: 2 }}>
            <Text style={[styles.hello, { color: theme.colors.textSecondary }]}>
              ¡Hola de nuevo!
            </Text>
            <Text
              style={[styles.title, { color: theme.colors.text }]}
              numberOfLines={1}
            >
              {profile?.nombre_completo ?? "…"}
            </Text>
            <View style={styles.roleBadge}>
              <Text style={styles.roleBadgeText}>
                {profile ? roleLabel(profile.rol) : "—"}
              </Text>
            </View>
          </View>

          <Pressable
            onPress={toggleScheme}
            style={[
              styles.themeBtn,
              {
                backgroundColor: theme.colors.surface,
                borderColor: theme.colors.border,
              },
            ]}
            accessibilityLabel="Cambiar tema"
          >
            <Ionicons
              name={theme.scheme === "dark" ? "sunny" : "moon"}
              size={18}
              color={theme.colors.brand}
            />
          </Pressable>
        </View>

        {/* KPIs de Rendimiento */}
        {loading && !kpis ? (
          <SkeletonList rows={2} />
        ) : kpis ? (
          <View style={styles.kpiRow}>
            <KpiTile
              value={ordenesActivas}
              label="Activas"
              icon="cube-outline"
              iconColor="#0284C7"
              iconBg="#E0F2FE"
            />
            <KpiTile
              value={kpis.clientesActivos}
              label="Clientes"
              icon="people-outline"
              iconColor="#4F46E5"
              iconBg="#EEF2FF"
            />
            <KpiTile
              value={kpis.rendicionesPendientes}
              label="Cobranzas"
              icon="cash-outline"
              iconColor="#059669"
              iconBg="#D1FAE5"
            />
          </View>
        ) : null}

        {/* Sección de Accesos Rápidos */}
        <Text style={[styles.section, { color: theme.colors.text }]}>
          Accesos Rápidos
        </Text>
        <View style={styles.shortcuts}>
          {shortcuts.map((item) => (
            <ShortcutRow key={item.key} item={item} onPress={handleNavigate} />
          ))}
        </View>

        <Text style={[styles.hint, { color: theme.colors.textSecondary }]}>
          {profile?.empresa_nombre ?? "LogiTrack"} · {sections.reduce((n, s) => n + s.items.length, 0)} módulos disponibles
        </Text>
      </ScrollView>

      <BottomActionBar
        actions={[
          {
            key: "ordenes",
            label: "Ver envíos",
            icon: "list-outline",
            variant: "secondary",
            onPress: handleOpenOrdenes,
          },
          ...(tabs.ordenes &&
          (profile?.rol === "vendedor" ||
            profile?.rol === "gerente" ||
            profile?.rol === "admin")
            ? [
                {
                  key: "nueva",
                  label: "Nueva orden",
                  icon: "add-circle-outline" as const,
                  variant: "primary" as const,
                  onPress: handleNuevaOrden,
                },
              ]
            : [
                {
                  key: "radar",
                  label: "Radar",
                  icon: "radio-outline" as const,
                  variant: "primary" as const,
                  onPress: handleOpenRadar,
                },
              ]),
        ]}
      />
    </View>
  );
};

const styles = StyleSheet.create({
  root: { flex: 1 },
  content: { padding: 18, paddingBottom: 24, gap: 10 },
  header: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
    marginBottom: 4,
  },
  avatar: {
    width: 48,
    height: 48,
    borderRadius: 16,
    backgroundColor: "#0B3A5C",
    alignItems: "center",
    justifyContent: "center",
    shadowColor: "#0B3A5C",
    shadowOffset: { width: 0, height: 3 },
    shadowOpacity: 0.25,
    shadowRadius: 5,
    elevation: 3,
  },
  avatarText: {
    color: "#FFFFFF",
    fontSize: 18,
    fontWeight: "800",
  },
  hello: { fontSize: 12, fontWeight: "600" },
  title: { fontSize: 20, fontWeight: "800" },
  roleBadge: {
    backgroundColor: "#E0F2FE",
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 6,
    alignSelf: "flex-start",
    marginTop: 2,
  },
  roleBadgeText: {
    color: "#0369A1",
    fontSize: 11,
    fontWeight: "700",
    textTransform: "capitalize",
  },
  themeBtn: {
    width: 40,
    height: 40,
    borderRadius: 12,
    borderWidth: 1,
    alignItems: "center",
    justifyContent: "center",
  },
  kpiRow: { flexDirection: "row", gap: 10, marginTop: 8 },
  kpi: {
    flex: 1,
    borderRadius: 16,
    paddingVertical: 14,
    paddingHorizontal: 10,
    borderWidth: 1,
    alignItems: "center",
    gap: 4,
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.04,
    shadowRadius: 3,
    elevation: 1,
  },
  kpiIconWrap: {
    width: 32,
    height: 32,
    borderRadius: 10,
    alignItems: "center",
    justifyContent: "center",
    marginBottom: 2,
  },
  kpiNum: { fontSize: 20, fontWeight: "800" },
  kpiLabel: {
    fontSize: 11,
    fontWeight: "600",
  },
  section: {
    marginTop: 14,
    marginBottom: 4,
    fontSize: 16,
    fontWeight: "700",
  },
  shortcuts: { gap: 10 },
  shortcut: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
    borderRadius: 16,
    borderWidth: 1,
    paddingVertical: 12,
    paddingHorizontal: 14,
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.04,
    shadowRadius: 3,
    elevation: 1,
  },
  shortcutIcon: {
    width: 44,
    height: 44,
    borderRadius: 12,
    alignItems: "center",
    justifyContent: "center",
  },
  shortcutText: { fontSize: 15, fontWeight: "700" },
  shortcutSub: { fontSize: 12, marginTop: 1 },
  hint: { marginTop: 14, fontSize: 12, textAlign: "center", opacity: 0.8 },
});
