import { useCallback, useState } from "react";
import {
  Alert,
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
import {
  actualizarFechaDespachoOrden,
  aprobarOrdenDistribucion,
  getOrdenDetalle,
  type OrdenDetalle,
} from "@/lib/ordenes";
import { formatDate } from "@/lib/format";
import {
  ErrorText,
  FormField,
  LoadingBlock,
  PrimaryButton,
  SecondaryButton,
  SectionTitle,
} from "@/components/ui";

function toLocalInput(iso: string | null): string {
  if (!iso) return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso.slice(0, 16);
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  const hh = String(d.getHours()).padStart(2, "0");
  const mm = String(d.getMinutes()).padStart(2, "0");
  return `${y}-${m}-${day}T${hh}:${mm}`;
}

export default function EditarOrdenScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [orden, setOrden] = useState<OrdenDetalle | null>(null);
  const [fecha, setFecha] = useState("");
  const [factura, setFactura] = useState("");

  const editable =
    orden?.estado === "borrador" || orden?.estado === "aprobada";
  const canAprobar = orden?.estado === "borrador";

  const load = useCallback(async () => {
    if (!id) return;
    setError(null);
    const res = await getOrdenDetalle(id);
    if (!res.ok) {
      setError(res.error);
      setOrden(null);
    } else {
      setOrden(res.orden);
      setFecha(toLocalInput(res.orden.fecha_despacho));
      setFactura(res.orden.factura_origen_numero ?? "");
    }
    setLoading(false);
  }, [id]);

  useFocusEffect(
    useCallback(() => {
      setLoading(true);
      void load();
    }, [load]),
  );

  async function onSave() {
    if (!id || !fecha.trim()) {
      setError("La fecha de despacho es obligatoria.");
      return;
    }
    setSaving(true);
    setError(null);
    setMessage(null);
    const res = await actualizarFechaDespachoOrden({
      ordenId: id,
      fechaDespachoIso: fecha.trim(),
      facturaOrigenNumero: factura,
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    setMessage("Orden actualizada.");
    void load();
  }

  async function onAprobar() {
    if (!id) return;
    setSaving(true);
    setError(null);
    setMessage(null);
    const res = await aprobarOrdenDistribucion(id);
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    setMessage(res.message || "Orden aprobada.");
    void load();
  }

  if (loading) return <LoadingBlock />;

  if (error && !orden) {
    return (
      <View style={styles.center}>
        <ErrorText message={error} />
      </View>
    );
  }

  if (!orden) {
    return (
      <View style={styles.center}>
        <ErrorText message="Sin datos" />
      </View>
    );
  }

  return (
    <ScrollView
      style={styles.root}
      contentContainerStyle={{ padding: 16, gap: 12, paddingBottom: 40 }}
    >
      <Text style={styles.title}>#{orden.correlativo}</Text>
      <Text style={styles.meta}>
        {orden.clientes?.razon_social ?? "—"} · Estado: {orden.estado}
      </Text>
      <Text style={styles.meta}>
        Despacho actual: {formatDate(orden.fecha_despacho)}
      </Text>

      {!editable ? (
        <ErrorText message="Solo se editan órdenes en borrador o aprobada. Usa Radar para despacho en ruta." />
      ) : (
        <>
          <SectionTitle>Campos básicos</SectionTitle>
          <FormField
            label="Fecha despacho (YYYY-MM-DDTHH:mm)"
            value={fecha}
            onChangeText={setFecha}
            autoCapitalize="none"
            placeholder="2026-09-21T08:00"
          />
          <FormField
            label="Factura origen"
            value={factura}
            onChangeText={setFactura}
            autoCapitalize="characters"
          />
          <PrimaryButton
            label="Guardar cambios"
            loading={saving}
            onPress={() => void onSave()}
          />
        </>
      )}

      {canAprobar ? (
        <PrimaryButton
          label="Aprobar orden"
          loading={saving}
          onPress={() => {
            Alert.alert(
              "Aprobar orden",
              "¿Aprobar esta orden de distribución?",
              [
                { text: "Cancelar", style: "cancel" },
                { text: "Aprobar", onPress: () => void onAprobar() },
              ],
            );
          }}
        />
      ) : null}

      <ErrorText message={error} />
      {message ? <Text style={styles.ok}>{message}</Text> : null}

      <SecondaryButton
        label="Ver detalle"
        onPress={() => router.push(`/(app)/ordenes/${id}` as Href)}
      />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F6F8" },
  center: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    padding: 24,
  },
  title: { fontSize: 24, fontWeight: "700", color: "#0B3A5C" },
  meta: { fontSize: 14, color: "#5B6B7C" },
  ok: { color: "#027A48", fontWeight: "600" },
});
