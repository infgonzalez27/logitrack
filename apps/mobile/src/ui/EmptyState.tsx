import React, { memo } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { Ionicons } from "@expo/vector-icons";
import { useTheme } from "@/src/theme/ThemeProvider";

export interface EmptyStateProps {
  title: string;
  message?: string;
  icon?: keyof typeof Ionicons.glyphMap;
}

export const EmptyState: React.FC<EmptyStateProps> = memo(function EmptyState({
  title,
  message,
  icon = "cube-outline",
}) {
  const { theme } = useTheme();
  return (
    <View style={styles.wrap}>
      <View
        style={[
          styles.iconWrap,
          { backgroundColor: theme.colors.surface },
        ]}
      >
        <Ionicons name={icon} size={28} color={theme.colors.textSecondary} />
      </View>
      <Text style={[styles.title, { color: theme.colors.text }]}>{title}</Text>
      {message ? (
        <Text style={[styles.message, { color: theme.colors.textSecondary }]}>
          {message}
        </Text>
      ) : null}
    </View>
  );
});

export interface ErrorStateProps {
  message: string;
  onRetry?: () => void;
}

export const ErrorState: React.FC<ErrorStateProps> = memo(function ErrorState({
  message,
  onRetry,
}) {
  const { theme } = useTheme();
  return (
    <View style={styles.wrap}>
      <Ionicons name="alert-circle-outline" size={32} color={theme.colors.danger} />
      <Text style={[styles.title, { color: theme.colors.text }]}>
        No se pudo cargar
      </Text>
      <Text style={[styles.message, { color: theme.colors.textSecondary }]}>
        {message}
      </Text>
      {onRetry ? (
        <Pressable
          style={[styles.retry, { backgroundColor: theme.colors.brand }]}
          onPress={onRetry}
        >
          <Text style={[styles.retryText, { color: theme.colors.textInverse }]}>
            Reintentar
          </Text>
        </Pressable>
      ) : null}
    </View>
  );
});

const styles = StyleSheet.create({
  wrap: {
    alignItems: "center",
    justifyContent: "center",
    paddingHorizontal: 32,
    paddingVertical: 48,
    gap: 8,
  },
  iconWrap: {
    width: 56,
    height: 56,
    borderRadius: 16,
    alignItems: "center",
    justifyContent: "center",
    marginBottom: 8,
  },
  title: { fontSize: 17, fontWeight: "700", textAlign: "center" },
  message: { fontSize: 14, textAlign: "center", lineHeight: 20 },
  retry: {
    marginTop: 12,
    paddingHorizontal: 20,
    paddingVertical: 12,
    borderRadius: 12,
  },
  retryText: { fontWeight: "700", fontSize: 15 },
});
