import { useCallback, useState } from "react";
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { useLocalSearchParams, useRouter } from "expo-router";
import { useFocusEffect } from "expo-router";
import {
  fetchEstadoCuentaVacios,
  getOrdenDetalle,
  resolveDespachadorNombre,
  type OrdenDetalle,
} from "@/lib/orders";
import { buildOrdenTicketText } from "@/lib/ticket-builder";
import {
  getPreferredPrinterMac,
  printTextToBluetooth,
} from "@/lib/bluetooth-print";

export default function OrderDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const [orden, setOrden] = useState<OrdenDetalle | null>(null);
  const [ticketText, setTicketText] = useState("");
  const [totalUsd, setTotalUsd] = useState(0);
  const [loading, setLoading] = useState(true);
  const [printing, setPrinting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!id) return;
    setLoading(true);
    setError(null);
    setMessage(null);
    const result = await getOrdenDetalle(id);
    if (!result.ok) {
      setError(result.error);
      setLoading(false);
      return;
    }
    const o = result.orden;
    setOrden(o);
    const [despachadorNombre, vacios] = await Promise.all([
      resolveDespachadorNombre(o.despachador_id),
      fetchEstadoCuentaVacios(o),
    ]);
    const detalle = [...(o.detalle_distribucion ?? [])].sort(
      (a, b) => (a.secuencia_entrega ?? 0) - (b.secuencia_entrega ?? 0),
    );
    const lineas = detalle.map((l) => {
      const unitarioUsd = Number(
        l.valor_unitario_usd != null && Number(l.valor_unitario_usd) > 0
          ? l.valor_unitario_usd
          : 0,
      );
      const subtotalUsd = Number(
        l.subtotal_recaudar_usd != null && Number(l.subtotal_recaudar_usd) > 0
          ? l.subtotal_recaudar_usd
          : unitarioUsd * Number(l.cantidad_solicitada ?? 0),
      );
      return {
        id: l.id,
        secuencia: l.secuencia_entrega ?? "·",
        codigo: l.productos?.codigo_producto ?? "-",
        producto: l.productos?.nombre ?? "Producto",
        cantidad: Number(l.cantidad_solicitada),
        unitario: unitarioUsd,
        subtotal: subtotalUsd,
      };
    });
    const total =
      o.total_recaudar_usd != null && Number(o.total_recaudar_usd) > 0
        ? Number(o.total_recaudar_usd)
        : lineas.reduce((s, l) => s + l.subtotal, 0);

    const text = buildOrdenTicketText({
      correlativo: o.correlativo,
      facturaOrigen: o.factura_origen_numero,
      estado: o.estado,
      creadaAt: o.created_at,
      clienteNombre: o.clientes?.razon_social ?? "-",
      clienteRif: o.clientes?.rif_nit ?? "-",
      clienteDireccion: o.clientes?.direccion_fiscal ?? "-",
      camionLabel: o.camiones
        ? `${o.camiones.placa}${o.camiones.modelo ? ` · ${o.camiones.modelo}` : ""}`
        : "-",
      despachadorNombre,
      pesoKg: Number(o.peso_total_calculado ?? 0),
      lineas,
      totalRecaudar: total,
      estadoCuentaVacios: vacios.lineas,
      estadoCuentaProvisional: vacios.provisional,
    });
    setTicketText(text);
    setTotalUsd(total);
    setLoading(false);
  }, [id]);

  useFocusEffect(
    useCallback(() => {
      void load();
    }, [load]),
  );

  async function onPrint() {
    setPrinting(true);
    setError(null);
    setMessage(null);
    const mac = await getPreferredPrinterMac();
    if (!mac) {
      setPrinting(false);
      setError(
        "No hay impresora guardada. Configurala en la pestana Impresora.",
      );
      router.push("/(app)/printers");
      return;
    }
    const result = await printTextToBluetooth(mac, ticketText);
    setPrinting(false);
    if (!result.ok) {
      setError(result.error);
      return;
    }
    setMessage("Ticket enviado a la impresora.");
  }

  if (loading) {
    return (
      <View style={styles.center}>
        <ActivityIndicator color="#0B3A5C" size="large" />
      </View>
    );
  }

  if (!orden) {
    return (
      <View style={styles.center}>
        <Text style={styles.error}>{error ?? "Orden no encontrada"}</Text>
      </View>
    );
  }

  return (
    <ScrollView style={styles.root} contentContainerStyle={{ padding: 16 }}>
      <Text style={styles.title}>Orden #{orden.correlativo}</Text>
      <Text style={styles.meta}>
        {orden.estado} · {orden.factura_origen_numero}
      </Text>
      <Text style={styles.meta}>Total: USD {totalUsd.toFixed(2)}</Text>

      <View style={styles.preview}>
        <Text style={styles.previewText}>{ticketText}</Text>
      </View>

      {error ? <Text style={styles.error}>{error}</Text> : null}
      {message ? <Text style={styles.ok}>{message}</Text> : null}

      <Pressable
        style={[styles.btn, printing && styles.btnDisabled]}
        disabled={printing}
        onPress={() => void onPrint()}
      >
        {printing ? (
          <ActivityIndicator color="#fff" />
        ) : (
          <Text style={styles.btnText}>Imprimir ticket</Text>
        )}
      </Pressable>

      <Pressable
        style={styles.secondary}
        onPress={() => router.push("/(app)/printers")}
      >
        <Text style={styles.secondaryText}>Elegir / probar impresora</Text>
      </Pressable>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F7FA" },
  center: { flex: 1, alignItems: "center", justifyContent: "center" },
  title: { fontSize: 22, fontWeight: "700", color: "#0B3A5C" },
  meta: { color: "#5B6B7C", marginBottom: 12 },
  preview: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 12,
    borderWidth: 1,
    borderColor: "#E5EAF0",
  },
  previewText: {
    fontFamily: "monospace",
    fontSize: 12,
    lineHeight: 18,
    color: "#111",
  },
  error: { color: "#B42318", marginTop: 12 },
  ok: { color: "#027A48", marginTop: 12 },
  btn: {
    marginTop: 16,
    backgroundColor: "#0B3A5C",
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: "center",
  },
  btnDisabled: { opacity: 0.7 },
  btnText: { color: "#fff", fontWeight: "700", fontSize: 16 },
  secondary: { marginTop: 12, alignItems: "center", padding: 12 },
  secondaryText: { color: "#0B3A5C", fontWeight: "600" },
});
