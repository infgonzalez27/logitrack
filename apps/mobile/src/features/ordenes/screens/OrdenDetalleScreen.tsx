import React, { useCallback, useMemo, useState } from "react";
import {
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from "react-native";
import {
  useFocusEffect,
  useLocalSearchParams,
  useRouter,
  type Href,
} from "expo-router";
import { getOrdenDetalle, type OrdenDetalle } from "@/lib/ordenes";
import { buildTicketForOrden } from "@/lib/print-orden";
import {
  getPreferredPrinterMac,
  printTextToBluetooth,
} from "@/lib/bluetooth-print";
import { formatDate, formatMoney } from "@/lib/format";
import { useTheme } from "@/src/theme/ThemeProvider";
import { StatusBadge } from "@/src/ui/StatusBadge";
import { SkeletonList } from "@/src/ui/Skeleton";
import { ErrorState } from "@/src/ui/EmptyState";
import { BottomActionBar } from "@/src/ui/BottomActionBar";
import { mapOrdenStatus } from "@/src/features/ordenes/status";

export const OrdenDetalleScreen: React.FC = function OrdenDetalleScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const { theme } = useTheme();
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [printing, setPrinting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [orden, setOrden] = useState<OrdenDetalle | null>(null);
  const [ticketText, setTicketText] = useState("");
  const [showPreview, setShowPreview] = useState(false);

  const load = useCallback(
    async (mode: "initial" | "refresh") => {
      if (!id) return;
      if (mode === "refresh") setRefreshing(true);
      else setLoading(true);
      setError(null);
      setMessage(null);
      const res = await getOrdenDetalle(id);
      if (!res.ok) {
        setError(res.error);
        setOrden(null);
        setTicketText("");
      } else {
        setOrden(res.orden);
        const ticket = await buildTicketForOrden(res.orden);
        setTicketText(ticket.text);
      }
      setLoading(false);
      setRefreshing(false);
    },
    [id],
  );

  useFocusEffect(
    useCallback(() => {
      void load("initial");
    }, [load]),
  );

  const onPrint = useCallback(async () => {
    if (!ticketText) return;
    setPrinting(true);
    setError(null);
    setMessage(null);
    const mac = await getPreferredPrinterMac();
    if (!mac) {
      setPrinting(false);
      setError("No hay impresora guardada. Configúrala en Impresora.");
      router.push("/(app)/impresora" as Href);
      return;
    }
    const result = await printTextToBluetooth(mac, ticketText);
    setPrinting(false);
    if (!result.ok) {
      setError(result.error);
      return;
    }
    setMessage("Ticket enviado a la impresora.");
  }, [ticketText, router]);

  const onEdit = useCallback(() => {
    if (!orden) return;
    router.push(`/(app)/ordenes/editar/${orden.id}` as Href);
  }, [orden, router]);

  const onOpenPrinter = useCallback(() => {
    router.push("/(app)/impresora" as Href);
  }, [router]);

  const onTogglePreview = useCallback(() => {
    setShowPreview((v) => !v);
  }, []);

  const onRefresh = useCallback(() => {
    void load("refresh");
  }, [load]);

  const onRetry = useCallback(() => {
    void load("initial");
  }, [load]);

  const status = useMemo(
    () => (orden ? mapOrdenStatus(orden.estado) : null),
    [orden],
  );

  const canEdit =
    orden?.estado === "borrador" || orden?.estado === "aprobada";

  if (loading && !orden) {
    return (
      <View style={[styles.root, { backgroundColor: theme.colors.background }]}>
        <SkeletonList rows={4} />
      </View>
    );
  }

  if (error && !orden) {
    return (
      <View style={[styles.root, { backgroundColor: theme.colors.background }]}>
        <ErrorState message={error} onRetry={onRetry} />
      </View>
    );
  }

  if (!orden || !status) {
    return (
      <View style={[styles.root, { backgroundColor: theme.colors.background }]}>
        <ErrorState message="Sin datos" onRetry={onRetry} />
      </View>
    );
  }

  return (
    <View style={[styles.root, { backgroundColor: theme.colors.background }]}>
      <ScrollView
        contentContainerStyle={styles.content}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={onRefresh}
            tintColor={theme.colors.brand}
          />
        }
      >
        <View style={styles.headerRow}>
          <Text style={[styles.tracking, { color: theme.colors.text }]}>
            #{orden.correlativo}
          </Text>
          <StatusBadge label={status.label} tone={status.tone} />
        </View>

        <View
          style={[
            styles.card,
            {
              backgroundColor: theme.colors.surface,
              borderColor: theme.colors.border,
            },
          ]}
        >
          <Text style={[styles.label, { color: theme.colors.textSecondary }]}>
            Cliente
          </Text>
          <Text style={[styles.value, { color: theme.colors.text }]}>
            {orden.clientes?.razon_social ?? "—"}
          </Text>
          {orden.clientes?.rif_nit ? (
            <Text style={[styles.meta, { color: theme.colors.textSecondary }]}>
              {orden.clientes.rif_nit}
            </Text>
          ) : null}
        </View>

        <View
          style={[
            styles.card,
            {
              backgroundColor: theme.colors.surface,
              borderColor: theme.colors.border,
            },
          ]}
        >
          <Text style={[styles.label, { color: theme.colors.textSecondary }]}>
            ETA / despacho
          </Text>
          <Text style={[styles.value, { color: theme.colors.text }]}>
            {formatDate(orden.fecha_despacho)}
          </Text>
          {orden.camiones ? (
            <Text style={[styles.meta, { color: theme.colors.textSecondary }]}>
              Camión {orden.camiones.placa}
              {orden.camiones.modelo ? ` · ${orden.camiones.modelo}` : ""}
            </Text>
          ) : null}
        </View>

        <View
          style={[
            styles.card,
            {
              backgroundColor: theme.colors.surface,
              borderColor: theme.colors.border,
            },
          ]}
        >
          <Text style={[styles.label, { color: theme.colors.textSecondary }]}>
            Total a recaudar
          </Text>
          <Text style={[styles.total, { color: theme.colors.brand }]}>
            ${formatMoney(orden.total_recaudar_usd)}
          </Text>
        </View>

        <Text style={[styles.section, { color: theme.colors.text }]}>
          Líneas ({orden.detalle_distribucion.length})
        </Text>
        {orden.detalle_distribucion.map((linea) => (
          <View
            key={linea.id}
            style={[
              styles.line,
              {
                backgroundColor: theme.colors.surface,
                borderColor: theme.colors.border,
              },
            ]}
          >
            <Text style={[styles.lineName, { color: theme.colors.text }]}>
              {linea.productos?.nombre ?? "Producto"}
            </Text>
            <Text style={[styles.meta, { color: theme.colors.textSecondary }]}>
              {linea.cantidad_solicitada} × $
              {formatMoney(linea.valor_unitario_usd)} = $
              {formatMoney(linea.subtotal_recaudar_usd)}
              {Number(linea.porcentaje_descuento) > 0
                ? ` · −${Number(linea.porcentaje_descuento)}%`
                : ""}
            </Text>
            {Number(linea.porcentaje_descuento) > 0 &&
            linea.precio_lista_usd != null ? (
              <Text style={[styles.meta, { color: theme.colors.textSecondary }]}>
                Lista ${formatMoney(linea.precio_lista_usd)}
                {linea.monto_descuento_usd != null
                  ? ` · desc. $${formatMoney(linea.monto_descuento_usd)}`
                  : ""}
              </Text>
            ) : null}
          </View>
        ))}

        {error ? (
          <Text style={{ color: theme.colors.danger }}>{error}</Text>
        ) : null}
        {message ? (
          <Text style={{ color: theme.colors.success }}>{message}</Text>
        ) : null}

        <Text
          onPress={onTogglePreview}
          style={[styles.previewToggle, { color: theme.colors.brand }]}
        >
          {showPreview ? "Ocultar vista previa" : "Ver vista previa del ticket"}
        </Text>
        {showPreview ? (
          <View
            style={[
              styles.preview,
              {
                backgroundColor: theme.colors.surface,
                borderColor: theme.colors.border,
              },
            ]}
          >
            <Text style={[styles.previewText, { color: theme.colors.text }]}>
              {ticketText}
            </Text>
          </View>
        ) : null}
      </ScrollView>

      <BottomActionBar
        actions={[
          {
            key: "printer",
            label: "Impresora",
            icon: "settings-outline",
            variant: "secondary",
            onPress: onOpenPrinter,
          },
          ...(canEdit
            ? [
                {
                  key: "edit",
                  label: "Editar",
                  icon: "create-outline" as const,
                  variant: "secondary" as const,
                  onPress: onEdit,
                },
              ]
            : []),
          {
            key: "print",
            label: "Imprimir",
            icon: "print-outline",
            variant: "primary",
            loading: printing,
            disabled: !ticketText,
            onPress: () => {
              void onPrint();
            },
          },
        ]}
      />
    </View>
  );
};

const styles = StyleSheet.create({
  root: { flex: 1 },
  content: { padding: 16, gap: 12, paddingBottom: 24 },
  headerRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  tracking: { fontSize: 28, fontWeight: "800" },
  card: {
    borderRadius: 16,
    padding: 14,
    borderWidth: StyleSheet.hairlineWidth,
  },
  label: {
    fontSize: 11,
    textTransform: "uppercase",
    letterSpacing: 0.4,
    fontWeight: "700",
  },
  value: { fontSize: 16, fontWeight: "600", marginTop: 4 },
  total: { fontSize: 24, fontWeight: "800", marginTop: 4 },
  meta: { fontSize: 13, marginTop: 2 },
  section: { fontSize: 16, fontWeight: "700", marginTop: 4 },
  line: {
    borderRadius: 14,
    padding: 12,
    borderWidth: StyleSheet.hairlineWidth,
  },
  lineName: { fontWeight: "600" },
  previewToggle: {
    fontWeight: "600",
    textAlign: "center",
    marginTop: 4,
  },
  preview: {
    borderRadius: 12,
    padding: 12,
    borderWidth: StyleSheet.hairlineWidth,
  },
  previewText: {
    fontFamily: "monospace",
    fontSize: 12,
    lineHeight: 18,
  },
});
