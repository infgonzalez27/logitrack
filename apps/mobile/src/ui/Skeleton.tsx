import React, { memo } from "react";
import { StyleSheet, View } from "react-native";
import { useTheme } from "@/src/theme/ThemeProvider";
import { ORDEN_CARD_HEIGHT } from "@/src/theme/tokens";

export interface SkeletonListProps {
  rows?: number;
}

export const SkeletonCard: React.FC = memo(function SkeletonCard() {
  const { theme } = useTheme();
  return (
    <View
      style={[
        styles.card,
        {
          backgroundColor: theme.colors.surface,
          borderColor: theme.colors.border,
          height: ORDEN_CARD_HEIGHT,
        },
      ]}
    >
      <View style={[styles.lineLg, { backgroundColor: theme.colors.skeleton }]} />
      <View style={[styles.lineMd, { backgroundColor: theme.colors.skeleton }]} />
      <View style={[styles.lineSm, { backgroundColor: theme.colors.skeleton }]} />
    </View>
  );
});

export const SkeletonList: React.FC<SkeletonListProps> = memo(
  function SkeletonList({ rows = 5 }) {
    return (
      <View style={styles.list}>
        {Array.from({ length: rows }).map((_, i) => (
          <SkeletonCard key={i} />
        ))}
      </View>
    );
  },
);

const styles = StyleSheet.create({
  list: { gap: 10, padding: 16 },
  card: {
    borderRadius: 16,
    borderWidth: StyleSheet.hairlineWidth,
    padding: 16,
    justifyContent: "center",
    gap: 10,
  },
  lineLg: { height: 18, width: "42%", borderRadius: 6 },
  lineMd: { height: 14, width: "70%", borderRadius: 6 },
  lineSm: { height: 12, width: "55%", borderRadius: 6 },
});
