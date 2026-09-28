import React, { memo } from "react";
import { StyleSheet, Text, View } from "react-native";
import { useTheme } from "@/src/theme/ThemeProvider";
import type { ThemeColors } from "@/src/theme/tokens";

export type StatusTone = "neutral" | "info" | "warning" | "success" | "danger";

export interface StatusBadgeProps {
  label: string;
  tone?: StatusTone;
}

function toneColors(
  colors: ThemeColors,
  tone: StatusTone,
): { fg: string; bg: string } {
  switch (tone) {
    case "success":
      return { fg: colors.success, bg: colors.successBg };
    case "warning":
      return { fg: colors.warning, bg: colors.warningBg };
    case "danger":
      return { fg: colors.danger, bg: colors.dangerBg };
    case "info":
      return { fg: colors.info, bg: colors.infoBg };
    default:
      return { fg: colors.textSecondary, bg: colors.background };
  }
}

export const StatusBadge: React.FC<StatusBadgeProps> = memo(
  function StatusBadge({ label, tone = "neutral" }) {
    const { theme } = useTheme();
    const palette = toneColors(theme.colors, tone);
    return (
      <View style={[styles.badge, { backgroundColor: palette.bg }]}>
        <Text style={[styles.text, { color: palette.fg }]} numberOfLines={1}>
          {label}
        </Text>
      </View>
    );
  },
);

const styles = StyleSheet.create({
  badge: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 999,
    maxWidth: 140,
  },
  text: {
    fontSize: 11,
    fontWeight: "700",
    textTransform: "capitalize",
  },
});
