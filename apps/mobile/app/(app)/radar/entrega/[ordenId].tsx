import { useCallback, useEffect, useMemo, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { useLocalSearchParams, useRouter } from "expo-router";
import { useAuth } from "@/lib/auth-context";
import {
  finalizarEntregaRadar,
  getOrdenRadarFromList,
  listarContenedores,
  reportarIncidenciaRadar,
  type ContenedorOption,
  type RadarOrden,
} from "@/lib/radar";

const INCIDENCIAS = [
  "Cliente cerrado",
  "Dirección incorrecta",
  "Cliente no disponible",
  "Otro",
];

export default function RadarEntregaScreen() {
  const { ordenId } = useLocalSearchParams<{ ordenId: string }>();
  const { profile } = useAuth();
  const router = useRouter();

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [orden, setOrden] = useState<RadarOrden | null>(null);
  const [contenedores, setContenedores] = useState<ContenedorOption[]>([]);
  const [cantidades, setCantidades] = useState<Record<string, string>>({});
  const [retiros, setRetiros] = useState<
    Array<{ key: string; contenedor_id: string; cantidad: string }>
  >([]);
  const [incidenciaOpen, setIncidenciaOpen] = useState(false);
  const [incidencia, setIncidencia] = useState(INCIDENCIAS[0]);

  const load = useCallback(async () => {
    if (!ordenId) return;
    setError(null);
    const [oRes, cRes] = await Promise.all([
      getOrdenRadarFromList(ordenId),
      listarContenedores(),
    ]);
    if (!oRes.ok) {
      setError(oRes.error);
      setOrden(null);
    } else {
      setOrden(oRes.orden);
      const init: Record<string, string> = {};
      for (const d of oRes.orden.detalles ?? []) {
        if ((d.estado_entrega ?? "pendiente") === "pendiente") {
          init[d.detalle_id] = String(d.cantidad_solicitada ?? 0);
        }
      }
      setCantidades(init);
    }
    if (cRes.ok) setContenedores(cRes.contenedores);
    setLoading(false);
  }, [ordenId]);

  useEffect(() => {
    void load();
  }, [load]);

  const pendientes = useMemo(
    () =>
      (orden?.detalles ?? []).filter(
        (d) => (d.estado_entrega ?? "pendiente") === "pendiente",
      ),
    [orden],
  );

  const contenedorOptions = useMemo(() => {
    if (contenedores.length) return contenedores;
    return (orden?.saldo_contenedores ?? []).map((c) => ({
      id: c.contenedor_id,
      codigo: null,
      nombre: `${c.nombre_contenedor} (saldo ${c.saldo_pendiente})`,
    }));
  }, [contenedores, orden]);

  const submit = async () => {
    if (!orden || !profile) return;
    setSaving(true);
    setError(null);
    const entregas = pendientes.map((d) => ({
      detalle_id: d.detalle_id,
      cantidad_asignada: Number(d.cantidad_solicitada) || 0,
      cantidad_entregada: Number(cantidades[d.detalle_id]) || 0,
    }));
    for (const e of entregas) {
      if (e.cantidad_entregada > e.cantidad_asignada) {
        setSaving(false);
        setError("La cantidad entregada no puede superar la asignada.");
        return;
      }
    }
    const res = await finalizarEntregaRadar({
      ordenId: orden.orden_id,
      clienteId: orden.cliente.id,
      userId: profile.id,
      entregas,
      retiros: retiros
        .filter((r) => r.contenedor_id && Number(r.cantidad) > 0)
        .map((r) => ({
          contenedor_id: r.contenedor_id,
          cantidad: Number(r.cantidad) || 0,
        })),
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert(
      res.deVuelta ? "Parada en devolución" : "Entrega registrada",
      res.deVuelta
        ? "Alguna línea quedó incompleta: toda la parada pasó a devolución."
        : "La parada se cerró correctamente.",
      [{ text: "OK", onPress: () => router.back() }],
    );
  };

  const submitIncidencia = async () => {
    if (!orden) return;
    setSaving(true);
    setError(null);
    const res = await reportarIncidenciaRadar({
      ordenId: orden.orden_id,
      detalleIds: pendientes.map((d) => d.detalle_id),
      motivo: incidencia,
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert("Incidencia registrada", "Líneas pendientes marcadas como rechazadas.", [
      { text: "OK", onPress: () => router.back() },
    ]);
  };

  if (loading) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color="#0B3A5C" />
      </View>
    );
  }

  if (!orden) {
    return (
      <View style={styles.center}>
        <Text style={styles.error}>{error ?? "Sin datos"}</Text>
        <Pressable onPress={() => router.back()}>
          <Text style={styles.link}>Volver</Text>
        </Pressable>
      </View>
    );
  }

  return (
    <ScrollView
      style={styles.root}
      contentContainerStyle={{ padding: 16, gap: 12, paddingBottom: 40 }}
    >
      <Text style={styles.title}>{orden.cliente.razon_social}</Text>
      <Text style={styles.meta}>Orden #{orden.correlativo}</Text>
      {error ? <Text style={styles.error}>{error}</Text> : null}

      <Text style={styles.section}>Productos pendientes</Text>
      {pendientes.length === 0 ? (
        <Text style={styles.meta}>No hay líneas pendientes.</Text>
      ) : (
        pendientes.map((d) => (
          <View key={d.detalle_id} style={styles.card}>
            <Text style={styles.name}>{d.nombre_producto}</Text>
            <Text style={styles.meta}>
              {d.codigo_producto ?? "—"} · asignado {d.cantidad_solicitada}
              {d.porcentaje_descuento > 0
                ? ` · −${d.porcentaje_descuento}%`
                : ""}
            </Text>
            {d.valor_unitario_usd != null ? (
              <Text style={styles.meta}>
                ${Number(d.valor_unitario_usd).toFixed(2)}
                {d.precio_lista_usd != null &&
                d.porcentaje_descuento > 0 &&
                Number(d.precio_lista_usd) !== Number(d.valor_unitario_usd)
                  ? ` (lista $${Number(d.precio_lista_usd).toFixed(2)})`
                  : ""}
              </Text>
            ) : null}
            <Text style={styles.label}>Cant. entregada</Text>
            <TextInput
              style={styles.input}
              keyboardType="numeric"
              value={cantidades[d.detalle_id] ?? "0"}
              onChangeText={(v) =>
                setCantidades((prev) => ({ ...prev, [d.detalle_id]: v }))
              }
            />
          </View>
        ))
      )}

      <Text style={styles.section}>Retiro de vacíos</Text>
      {retiros.map((r) => (
        <View key={r.key} style={styles.card}>
          <Text style={styles.label}>Contenedor</Text>
          <ScrollView horizontal showsHorizontalScrollIndicator={false}>
            <View style={{ flexDirection: "row", gap: 6 }}>
              {contenedorOptions.map((c) => (
                <Pressable
                  key={c.id}
                  style={[
                    styles.chip,
                    r.contenedor_id === c.id && styles.chipOn,
                  ]}
                  onPress={() =>
                    setRetiros((prev) =>
                      prev.map((x) =>
                        x.key === r.key ? { ...x, contenedor_id: c.id } : x,
                      ),
                    )
                  }
                >
                  <Text
                    style={[
                      styles.chipText,
                      r.contenedor_id === c.id && styles.chipTextOn,
                    ]}
                  >
                    {c.codigo ? `${c.codigo} ` : ""}
                    {c.nombre}
                  </Text>
                </Pressable>
              ))}
            </View>
          </ScrollView>
          <TextInput
            style={styles.input}
            keyboardType="numeric"
            placeholder="Cantidad"
            value={r.cantidad}
            onChangeText={(v) =>
              setRetiros((prev) =>
                prev.map((x) => (x.key === r.key ? { ...x, cantidad: v } : x)),
              )
            }
          />
        </View>
      ))}
      <Pressable
        style={styles.btnGhost}
        onPress={() =>
          setRetiros((prev) => [
            ...prev,
            {
              key: `${Date.now()}`,
              contenedor_id: contenedorOptions[0]?.id ?? "",
              cantidad: "1",
            },
          ])
        }
      >
        <Text style={styles.btnGhostText}>+ Agregar retiro</Text>
      </Pressable>

      {pendientes.length > 0 ? (
        <>
          <Pressable
            style={[styles.btn, saving && { opacity: 0.6 }]}
            disabled={saving}
            onPress={() => void submit()}
          >
            <Text style={styles.btnText}>
              {saving ? "Guardando…" : "Confirmar entrega"}
            </Text>
          </Pressable>

          <Pressable
            style={styles.btnGhost}
            onPress={() => setIncidenciaOpen((v) => !v)}
          >
            <Text style={styles.btnGhostText}>
              {incidenciaOpen ? "Cancelar incidencia" : "Reportar incidencia"}
            </Text>
          </Pressable>

          {incidenciaOpen ? (
            <View style={styles.card}>
              {INCIDENCIAS.map((opt) => (
                <Pressable
                  key={opt}
                  style={[styles.chip, incidencia === opt && styles.chipOn]}
                  onPress={() => setIncidencia(opt)}
                >
                  <Text
                    style={[
                      styles.chipText,
                      incidencia === opt && styles.chipTextOn,
                    ]}
                  >
                    {opt}
                  </Text>
                </Pressable>
              ))}
              <Pressable
                style={[styles.btnDanger, saving && { opacity: 0.6 }]}
                disabled={saving}
                onPress={() => void submitIncidencia()}
              >
                <Text style={styles.btnText}>Marcar devolución</Text>
              </Pressable>
            </View>
          ) : null}
        </>
      ) : null}

      <Text style={styles.hint}>
        Si alguna cantidad queda por debajo de la asignada, toda la parada pasa
        a devolución (misma regla que en la web).
      </Text>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F6F8" },
  center: { flex: 1, alignItems: "center", justifyContent: "center", padding: 24 },
  title: { fontSize: 20, fontWeight: "700", color: "#0B3A5C" },
  name: { fontWeight: "600", color: "#0B3A5C" },
  meta: { fontSize: 13, color: "#5B6B7C" },
  section: { marginTop: 8, fontSize: 16, fontWeight: "600", color: "#0B3A5C" },
  label: { fontSize: 12, color: "#5B6B7C", marginTop: 8, marginBottom: 4 },
  card: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 12,
    borderWidth: 1,
    borderColor: "#E5EAF0",
    gap: 6,
  },
  input: {
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 16,
  },
  btn: {
    backgroundColor: "#0B3A5C",
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: "center",
  },
  btnDanger: {
    backgroundColor: "#B42318",
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: "center",
    marginTop: 8,
  },
  btnText: { color: "#fff", fontWeight: "600" },
  btnGhost: {
    borderWidth: 1,
    borderColor: "#0B3A5C",
    borderRadius: 12,
    paddingVertical: 12,
    alignItems: "center",
    backgroundColor: "#fff",
  },
  btnGhostText: { color: "#0B3A5C", fontWeight: "600" },
  chip: {
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 6,
    marginRight: 4,
    marginBottom: 4,
    backgroundColor: "#fff",
  },
  chipOn: { backgroundColor: "#0B3A5C", borderColor: "#0B3A5C" },
  chipText: { color: "#0B3A5C", fontSize: 12 },
  chipTextOn: { color: "#fff" },
  error: { color: "#B42318" },
  link: { color: "#0B3A5C", textDecorationLine: "underline", marginTop: 8 },
  hint: { fontSize: 12, color: "#5B6B7C", lineHeight: 18 },
});
