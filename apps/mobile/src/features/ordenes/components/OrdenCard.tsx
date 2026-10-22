import React, { memo, useCallback } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { Ionicons } from "@expo/vector-icons";
import { useTheme } from "@/src/theme/ThemeProvider";
import { ORDEN_CARD_HEIGHT } from "@/src/theme/tokens";
import { StatusBadge } from "@/src/ui/StatusBadge";
import { formatDate, formatMoney } from "@/lib/format";
import type { OrdenListaItem } from "@/lib/ordenes";
import { mapOrdenStatus } from "../status";

export interface OrdenCardProps {
  item: OrdenListaItem;
  onPress: (id: string) => void;
  onPrint?: (id: string) => void;
}

export const OrdenCard: React.FC<OrdenCardProps> = memo(function OrdenCard({
  item,
  onPress,
  onPrint,
}) {
  const { theme } = useTheme();
  const status = mapOrdenStatus(item.estado);

  const handlePress = useCallback(() => {
    onPress(item.id);
  }, [item.id, onPress]);

  return (
    <Pressable
      onPress={handlePress}
      accessibilityRole="button"
      accessibilityLabel={`Orden ${item.correlativo}`}
      style={({ pressed }) => [
        styles.card,
        {
          backgroundColor: theme.colors.surface,
          borderColor: theme.colors.border,
          height: ORDEN_CARD_HEIGHT,
          opacity: pressed ? 0.92 : 1,
        },
      ]}
    >
      <View style={styles.top}>
        <View style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
          <Text style={[styles.tracking, { color: theme.colors.text }]}>
            #{item.correlativo}
          </Text>
          {onPrint ? (
            <Pressable
              onPress={(e) => {
                e.stopPropagation?.();
                onPrint(item.id);
              }}
              hitSlop={8}
              accessibilityRole="button"
              accessibilityLabel={`Imprimir orden ${item.correlativo}`}
              style={({ pressed }) => [
                {
                  padding: 4,
                  borderRadius: 6,
                  backgroundColor: pressed ? theme.colors.brandMuted : "transparent",
                },
              ]}
            >
              <Ionicons name="print-outline" size={18} color={theme.colors.brand} />
            </Pressable>
          ) : null}
        </View>
        <StatusBadge label={status.label} tone={status.tone} />
      </View>

      <Text
        style={[styles.client, { color: theme.colors.text }]}
        numberOfLines={1}
      >
        {item.cliente_razon_social ?? "Cliente sin nombre"}
      </Text>

      <View style={styles.metaRow}>
        <View style={styles.metaItem}>
          <Ionicons
            name="time-outline"
            size={14}
            color={theme.colors.textSecondary}
          />
          <Text style={[styles.meta, { color: theme.colors.textSecondary }]}>
            {formatDate(item.fecha_despacho ?? item.created_at)}
          </Text>
        </View>
        <Text style={[styles.amount, { color: theme.colors.brand }]}>
          ${formatMoney(item.total_recaudar_usd)}
        </Text>
      </View>
    </Pressable>
  );
});

const styles = StyleSheet.create({
  card: {
    borderRadius: 16,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 16,
    paddingVertical: 14,
    justifyContent: "center",
    gap: 6,
  },
  top: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 8,
  },
  tracking: {
    fontSize: 20,
    fontWeight: "800",
    letterSpacing: 0.3,
  },
  client: {
    fontSize: 14,
    fontWeight: "600",
  },
  metaRow: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    marginTop: 2,
  },
  metaItem: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
  },
  meta: {
    fontSize: 12,
  },
  amount: {
    fontSize: 15,
    fontWeight: "700",
  },
});
