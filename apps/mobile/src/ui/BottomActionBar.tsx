import React, { memo } from "react";
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { Ionicons } from "@expo/vector-icons";
import { useTheme } from "@/src/theme/ThemeProvider";

export interface BottomAction {
  key: string;
  label: string;
  icon: keyof typeof Ionicons.glyphMap;
  onPress: () => void;
  variant?: "primary" | "secondary" | "danger";
  loading?: boolean;
  disabled?: boolean;
}

export interface BottomActionBarProps {
  actions: BottomAction[];
}

export const BottomActionBar: React.FC<BottomActionBarProps> = memo(
  function BottomActionBar({ actions }) {
    const { theme } = useTheme();
    const insets = useSafeAreaInsets();

    return (
      <View
        style={[
          styles.bar,
          {
            backgroundColor: theme.colors.surfaceElevated,
            borderTopColor: theme.colors.border,
            paddingBottom: Math.max(insets.bottom, 12),
          },
        ]}
      >
        {actions.map((action) => {
          const isPrimary = action.variant === "primary" || !action.variant;
          const bg =
            action.variant === "danger"
              ? theme.colors.danger
              : isPrimary
                ? theme.colors.brand
                : theme.colors.background;
          const fg =
            action.variant === "secondary"
              ? theme.colors.text
              : theme.colors.textInverse;

          return (
            <Pressable
              key={action.key}
              accessibilityRole="button"
              accessibilityLabel={action.label}
              disabled={action.disabled || action.loading}
              onPress={action.onPress}
              style={[
                styles.btn,
                {
                  backgroundColor: bg,
                  opacity: action.disabled ? 0.5 : 1,
                  borderColor: theme.colors.border,
                  borderWidth: action.variant === "secondary" ? 1 : 0,
                },
              ]}
            >
              {action.loading ? (
                <ActivityIndicator color={fg} />
              ) : (
                <>
                  <Ionicons name={action.icon} size={18} color={fg} />
                  <Text style={[styles.label, { color: fg }]} numberOfLines={1}>
                    {action.label}
                  </Text>
                </>
              )}
            </Pressable>
          );
        })}
      </View>
    );
  },
);

const styles = StyleSheet.create({
  bar: {
    flexDirection: "row",
    gap: 8,
    paddingHorizontal: 12,
    paddingTop: 10,
    borderTopWidth: StyleSheet.hairlineWidth,
  },
  btn: {
    flex: 1,
    minHeight: 48,
    borderRadius: 14,
    alignItems: "center",
    justifyContent: "center",
    flexDirection: "row",
    gap: 6,
    paddingHorizontal: 8,
  },
  label: {
    fontSize: 13,
    fontWeight: "700",
  },
});
