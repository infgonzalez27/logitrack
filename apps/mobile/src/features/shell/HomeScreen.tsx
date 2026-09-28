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
  icon: keyof typeof Ionicons.glyphMap;
  href: Href;
}

interface KpiTileProps {
  value: number;
  label: string;
}

const KpiTile: React.FC<KpiTileProps> = React.memo(function KpiTile({
  value,
  label,
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
      <Text style={[styles.kpiNum, { color: theme.colors.brand }]}>{value}</Text>
      <Text style={[styles.kpiLabel, { color: theme.colors.textSecondary }]}>
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
      <View
        style={[styles.shortcutIcon, { backgroundColor: theme.colors.background }]}
      >
        <Ionicons name={item.icon} size={20} color={theme.colors.brand} />
      </View>
      <Text style={[styles.shortcutText, { color: theme.colors.text }]}>
        {item.label}
      </Text>
      <Ionicons
        name="chevron-forward"
        size={16}
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
        icon: "map-outline",
        href: "/(app)/visita" as Href,
      });
    }
    if (tabs.ordenes) {
      items.push({
        key: "ordenes",
        label: "Órdenes / envíos",
        icon: "document-text-outline",
        href: "/(app)/ordenes" as Href,
      });
    }
    if (tabs.radar) {
      items.push({
        key: "radar",
        label: "Radar del día",
        icon: "radio-outline",
        href: "/(app)/radar" as Href,
      });
    }
    if (tabs.autoventas) {
      items.push({
        key: "autoventas",
        label: "AutoVentas",
        icon: "car-outline",
        href: "/(app)/autoventas" as Href,
      });
    }
    items.push({
      key: "rendiciones",
      label: "Cobranzas",
      icon: "wallet-outline",
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

  return (
    <View style={[styles.root, { backgroundColor: theme.colors.background }]}>
      <ScrollView
        contentContainerStyle={styles.content}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={handleRefresh}
            tintColor={theme.colors.brand}
          />
        }
      >
        <View style={styles.header}>
          <View style={{ flex: 1 }}>
            <Text style={[styles.hello, { color: theme.colors.textSecondary }]}>
              Hola
            </Text>
            <Text style={[styles.title, { color: theme.colors.text }]}>
              {profile?.nombre_completo ?? "…"}
            </Text>
            <Text style={[styles.role, { color: theme.colors.textSecondary }]}>
              {profile ? roleLabel(profile.rol) : "—"}
            </Text>
          </View>
          <Pressable
            onPress={toggleScheme}
            style={[
              styles.themeBtn,
              { backgroundColor: theme.colors.surface, borderColor: theme.colors.border },
            ]}
            accessibilityLabel="Cambiar tema"
          >
            <Ionicons
              name={theme.scheme === "dark" ? "sunny-outline" : "moon-outline"}
              size={20}
              color={theme.colors.brand}
            />
          </Pressable>
        </View>

        {loading && !kpis ? (
          <SkeletonList rows={2} />
        ) : kpis ? (
          <View style={styles.kpiRow}>
            <KpiTile value={ordenesActivas} label="Activas" />
            <KpiTile value={kpis.clientesActivos} label="Clientes" />
            <KpiTile value={kpis.rendicionesPendientes} label="Cobranza" />
          </View>
        ) : null}

        <Text style={[styles.section, { color: theme.colors.text }]}>
          Accesos rápidos
        </Text>
        <View style={styles.shortcuts}>
          {shortcuts.map((item) => (
            <ShortcutRow key={item.key} item={item} onPress={handleNavigate} />
          ))}
        </View>

        <Text style={[styles.hint, { color: theme.colors.textSecondary }]}>
          Menú lateral: {sections.reduce((n, s) => n + s.items.length, 0)}{" "}
          opciones · tema {preference === "system" ? "sistema" : preference}
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
  content: { padding: 20, paddingBottom: 16, gap: 8 },
  header: { flexDirection: "row", alignItems: "flex-start", gap: 12 },
  hello: { fontSize: 13, fontWeight: "600" },
  title: { fontSize: 24, fontWeight: "800", marginTop: 2 },
  role: { fontSize: 14, marginTop: 4 },
  themeBtn: {
    width: 44,
    height: 44,
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: "center",
    justifyContent: "center",
  },
  kpiRow: { flexDirection: "row", gap: 8, marginTop: 16 },
  kpi: {
    flex: 1,
    borderRadius: 14,
    paddingVertical: 14,
    paddingHorizontal: 8,
    borderWidth: StyleSheet.hairlineWidth,
  },
  kpiNum: { fontSize: 22, fontWeight: "800", textAlign: "center" },
  kpiLabel: {
    fontSize: 11,
    fontWeight: "600",
    textAlign: "center",
    marginTop: 4,
  },
  section: {
    marginTop: 20,
    marginBottom: 8,
    fontSize: 16,
    fontWeight: "700",
  },
  shortcuts: { gap: 8 },
  shortcut: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
    borderRadius: 14,
    borderWidth: StyleSheet.hairlineWidth,
    paddingVertical: 12,
    paddingHorizontal: 12,
  },
  shortcutIcon: {
    width: 36,
    height: 36,
    borderRadius: 10,
    alignItems: "center",
    justifyContent: "center",
  },
  shortcutText: { flex: 1, fontSize: 15, fontWeight: "600" },
  hint: { marginTop: 16, fontSize: 12, lineHeight: 18 },
});
