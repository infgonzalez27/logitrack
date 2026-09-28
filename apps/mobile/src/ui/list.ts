import { StyleSheet } from "react-native";
import type { AppTheme } from "@/src/theme/tokens";
import { ORDEN_CARD_GAP, ORDEN_CARD_HEIGHT } from "@/src/theme/tokens";

/** Props de rendimiento recomendadas para FlatList de envíos. */
export const optimizedListProps = {
  removeClippedSubviews: true,
  maxToRenderPerBatch: 8,
  windowSize: 7,
  initialNumToRender: 8,
  updateCellsBatchingPeriod: 50,
} as const;

export function getOrdenItemLayout(
  _data: ArrayLike<unknown> | null | undefined,
  index: number,
): { length: number; offset: number; index: number } {
  const length = ORDEN_CARD_HEIGHT + ORDEN_CARD_GAP;
  return {
    length,
    offset: length * index,
    index,
  };
}

export function createSharedStyles(theme: AppTheme) {
  const { colors, spacing, radii, typography } = theme;
  return StyleSheet.create({
    screen: {
      flex: 1,
      backgroundColor: colors.background,
    },
    pad: {
      padding: spacing.lg,
    },
    title: {
      fontSize: typography.title,
      fontWeight: "700",
      color: colors.text,
    },
    subtitle: {
      fontSize: typography.subtitle,
      fontWeight: "600",
      color: colors.text,
    },
    caption: {
      fontSize: typography.caption,
      color: colors.textSecondary,
    },
    card: {
      backgroundColor: colors.surface,
      borderRadius: radii.lg,
      borderWidth: StyleSheet.hairlineWidth,
      borderColor: colors.border,
      padding: spacing.lg,
    },
  });
}
