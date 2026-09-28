import React, { useCallback } from "react";
import {
  FlatList,
  RefreshControl,
  StyleSheet,
  View,
  type ListRenderItemInfo,
} from "react-native";
import { useRouter } from "expo-router";
import { useTheme } from "@/src/theme/ThemeProvider";
import { ORDEN_CARD_GAP } from "@/src/theme/tokens";
import { getOrdenItemLayout, optimizedListProps } from "@/src/ui/list";
import { SkeletonList } from "@/src/ui/Skeleton";
import { EmptyState, ErrorState } from "@/src/ui/EmptyState";
import { BottomActionBar } from "@/src/ui/BottomActionBar";
import type { OrdenListaItem } from "@/lib/ordenes";
import { OrdenCard } from "../components/OrdenCard";
import { useOrdenesList } from "../hooks/useOrdenesList";

function keyExtractor(item: OrdenListaItem): string {
  return item.id;
}

export const OrdenesListScreen: React.FC = function OrdenesListScreen() {
  const router = useRouter();
  const { theme } = useTheme();
  const {
    ordenes,
    loading,
    refreshing,
    error,
    puedeCrear,
    refresh,
    retry,
  } = useOrdenesList();

  const handleOpenOrden = useCallback(
    (id: string) => {
      router.push({
        pathname: "/(app)/ordenes/[id]",
        params: { id },
      });
    },
    [router],
  );

  const handleNuevaOrden = useCallback(() => {
    router.push("/(app)/ordenes/nueva");
  }, [router]);

  const handleRadar = useCallback(() => {
    router.push("/(app)/radar");
  }, [router]);

  const renderItem = useCallback(
    ({ item }: ListRenderItemInfo<OrdenListaItem>) => (
      <OrdenCard item={item} onPress={handleOpenOrden} />
    ),
    [handleOpenOrden],
  );

  const listEmpty = useCallback(() => {
    if (error) {
      return <ErrorState message={error} onRetry={retry} />;
    }
    return (
      <EmptyState
        title="Sin envíos"
        message="No hay órdenes visibles para tu rol."
        icon="file-tray-outline"
      />
    );
  }, [error, retry]);

  return (
    <View style={[styles.root, { backgroundColor: theme.colors.background }]}>
      {loading && !refreshing ? (
        <SkeletonList rows={6} />
      ) : (
        <FlatList
          data={ordenes}
          keyExtractor={keyExtractor}
          renderItem={renderItem}
          getItemLayout={getOrdenItemLayout}
          contentContainerStyle={styles.listContent}
          ItemSeparatorComponent={ItemSeparator}
          ListEmptyComponent={listEmpty}
          refreshControl={
            <RefreshControl
              refreshing={refreshing}
              onRefresh={refresh}
              tintColor={theme.colors.brand}
            />
          }
          {...optimizedListProps}
        />
      )}

      <BottomActionBar
        actions={[
          {
            key: "radar",
            label: "Radar",
            icon: "radio-outline",
            variant: "secondary",
            onPress: handleRadar,
          },
          ...(puedeCrear
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
                  key: "refresh",
                  label: "Actualizar",
                  icon: "refresh-outline" as const,
                  variant: "primary" as const,
                  onPress: refresh,
                },
              ]),
        ]}
      />
    </View>
  );
};

const ItemSeparator: React.FC = function ItemSeparator() {
  return <View style={{ height: ORDEN_CARD_GAP }} />;
};

const styles = StyleSheet.create({
  root: { flex: 1 },
  listContent: {
    padding: 16,
    paddingBottom: 8,
    flexGrow: 1,
  },
});
