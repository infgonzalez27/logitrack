import { useCallback, useEffect, useMemo, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { useLocalSearchParams, useRouter } from "expo-router";
import { useAuth } from "@/lib/auth-context";
import { getClienteVisita } from "@/lib/clientes";
import { retornaUltimaTasa } from "@/lib/catalogos";
import {
  listarCuentasBancarias,
  listarFormasPago,
  registrarRendicion,
  solicitaAbonosCliente,
  type CuentaBancaria,
  type Fpago,
  type OrdenParaRendicion,
} from "@/lib/rendiciones";
import { esFormaPagoEnBs } from "@/lib/moneda";
import { formatDate, formatMoney } from "@/lib/format";

type PagoDraft = {
  key: string;
  fpago_id: string;
  monto: string;
  referencia: string;
  cuenta_id: string;
};

export default function NuevaRendicionScreen() {
  const { clienteId: clienteParam } = useLocalSearchParams<{
    clienteId?: string;
  }>();
  const { profile } = useAuth();
  const router = useRouter();

  const [clienteId] = useState(clienteParam ?? "");
  const [clienteNombre, setClienteNombre] = useState("");
  const [ordenes, setOrdenes] = useState<OrdenParaRendicion[]>([]);
  const [montos, setMontos] = useState<Record<string, string>>({});
  const [saldoFavor, setSaldoFavor] = useState(0);
  const [formas, setFormas] = useState<Fpago[]>([]);
  const [cuentas, setCuentas] = useState<CuentaBancaria[]>([]);
  const [pagos, setPagos] = useState<PagoDraft[]>([]);
  const [tasa, setTasa] = useState<number | null>(null);
  const [obs, setObs] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pickerPagoKey, setPickerPagoKey] = useState<string | null>(null);
  const [pickerCuentaKey, setPickerCuentaKey] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!profile || !clienteId) {
      setError("Falta el cliente. Abre la rendición desde Visita.");
      setLoading(false);
      return;
    }
    const [cRes, aRes, fRes, cuRes, tRes] = await Promise.all([
      getClienteVisita(clienteId, profile),
      solicitaAbonosCliente(clienteId),
      listarFormasPago(),
      listarCuentasBancarias(),
      retornaUltimaTasa(),
    ]);
    if (cRes.ok) setClienteNombre(cRes.cliente.razon_social);
    if (!aRes.ok) {
      setError(aRes.error);
    } else {
      setSaldoFavor(aRes.abonos.saldo_favor);
      setOrdenes(aRes.abonos.ordenes);
      const init: Record<string, string> = {};
      for (const o of aRes.abonos.ordenes) init[o.id] = "0";
      setMontos(init);
      if (aRes.abonos.tasa_oficial_actual) {
        setTasa(aRes.abonos.tasa_oficial_actual);
      }
    }
    if (fRes.ok) setFormas(fRes.formas);
    if (cuRes.ok) setCuentas(cuRes.cuentas);
    if (tRes.ok && tasa == null) setTasa(tRes.tasa);
    setLoading(false);
  }, [profile, clienteId, tasa]);

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps -- load once on mount
  }, []);

  const totalCobranzas = useMemo(
    () =>
      Object.entries(montos).reduce(
        (acc, [, v]) => acc + (Number(v.replace(",", ".")) || 0),
        0,
      ),
    [montos],
  );

  const totalPagosUsd = useMemo(() => {
    return pagos.reduce((acc, p) => {
      const forma = formas.find((f) => f.fpago_id === p.fpago_id);
      const monto = Number(p.monto.replace(",", ".")) || 0;
      if (!forma || monto <= 0) return acc;
      if (esFormaPagoEnBs(forma.fpago_concepto) && tasa && tasa > 0) {
        return acc + monto / tasa;
      }
      return acc + monto;
    }, 0);
  }, [pagos, formas, tasa]);

  const addPago = () => {
    const first = formas[0];
    if (!first) {
      setError("No hay formas de pago configuradas.");
      return;
    }
    setPagos((prev) => [
      ...prev,
      {
        key: `${Date.now()}`,
        fpago_id: first.fpago_id,
        monto: "",
        referencia: "",
        cuenta_id: cuentas[0]?.id ?? "",
      },
    ]);
  };

  const submit = async () => {
    if (!profile || !clienteId) return;
    const ordenesPayload = ordenes
      .map((o) => ({
        orden_id: o.id,
        monto_recaudado: Number((montos[o.id] ?? "0").replace(",", ".")) || 0,
      }))
      .filter((o) => o.monto_recaudado > 0);

    if (!ordenesPayload.length) {
      setError("Indica el monto a cobrar en al menos una orden.");
      return;
    }
    for (const o of ordenesPayload) {
      const max = ordenes.find((x) => x.id === o.orden_id)?.saldo_pendiente ?? 0;
      if (o.monto_recaudado > max + 0.009) {
        setError("Un monto supera el saldo pendiente de la orden.");
        return;
      }
    }
    if (!pagos.length) {
      setError("Agrega al menos una forma de pago.");
      return;
    }

    setSaving(true);
    setError(null);
    const res = await registrarRendicion({
      clienteId,
      userId: profile.id,
      observaciones: obs || undefined,
      tasaCambio: tasa,
      formas,
      ordenes: ordenesPayload,
      pagos: pagos.map((p) => {
        const forma = formas.find((f) => f.fpago_id === p.fpago_id);
        return {
          fpago_id: p.fpago_id,
          monto: Number(p.monto.replace(",", ".")) || 0,
          en_bs: forma ? esFormaPagoEnBs(forma.fpago_concepto) : false,
          fpago_info: !!forma?.fpago_info,
          referencia_bancaria: p.referencia,
          cuenta_bancaria_id: p.cuenta_id,
        };
      }),
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert(
      "Rendición registrada",
      `Pendiente de aprobación.\nSaldo favor usado: $${formatMoney(res.saldoFavorUsado)}\nGenerado: $${formatMoney(res.saldoFavorGenerado)}`,
      [{ text: "OK", onPress: () => router.back() }],
    );
  };

  if (loading) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color="#0B3A5C" />
      </View>
    );
  }

  if (pickerPagoKey) {
    return (
      <View style={styles.root}>
        <Pressable onPress={() => setPickerPagoKey(null)}>
          <Text style={styles.back}>← Volver</Text>
        </Pressable>
        <FlatList
          data={formas}
          keyExtractor={(f) => f.fpago_id}
          contentContainerStyle={{ padding: 16 }}
          renderItem={({ item }) => (
            <Pressable
              style={styles.card}
              onPress={() => {
                setPagos((prev) =>
                  prev.map((p) =>
                    p.key === pickerPagoKey
                      ? { ...p, fpago_id: item.fpago_id }
                      : p,
                  ),
                );
                setPickerPagoKey(null);
              }}
            >
              <Text style={styles.name}>{item.fpago_concepto}</Text>
              <Text style={styles.meta}>
                {esFormaPagoEnBs(item.fpago_concepto) ? "En Bs" : "En USD"}
                {item.fpago_info ? " · requiere referencia" : ""}
              </Text>
            </Pressable>
          )}
        />
      </View>
    );
  }

  if (pickerCuentaKey) {
    return (
      <View style={styles.root}>
        <Pressable onPress={() => setPickerCuentaKey(null)}>
          <Text style={styles.back}>← Volver</Text>
        </Pressable>
        <FlatList
          data={cuentas}
          keyExtractor={(c) => c.id}
          contentContainerStyle={{ padding: 16 }}
          ListEmptyComponent={
            <Text style={styles.meta}>No hay cuentas activas.</Text>
          }
          renderItem={({ item }) => (
            <Pressable
              style={styles.card}
              onPress={() => {
                setPagos((prev) =>
                  prev.map((p) =>
                    p.key === pickerCuentaKey
                      ? { ...p, cuenta_id: item.id }
                      : p,
                  ),
                );
                setPickerCuentaKey(null);
              }}
            >
              <Text style={styles.name}>{item.banco}</Text>
              <Text style={styles.meta}>
                {item.numero_cuenta ?? "—"}
                {item.titular ? ` · ${item.titular}` : ""}
              </Text>
            </Pressable>
          )}
        />
      </View>
    );
  }

  return (
    <FlatList
      style={styles.root}
      data={ordenes}
      keyExtractor={(o) => o.id}
      contentContainerStyle={{ padding: 16, gap: 10, paddingBottom: 48 }}
      ListHeaderComponent={
        <View style={{ gap: 10 }}>
          <Text style={styles.title}>{clienteNombre || "Cliente"}</Text>
          <Text style={styles.meta}>
            Saldo a favor ${formatMoney(saldoFavor)}
            {tasa != null ? ` · BCV ${formatMoney(tasa)}` : ""}
          </Text>
          {error ? <Text style={styles.error}>{error}</Text> : null}
          <Text style={styles.section}>Órdenes pendientes</Text>
          {ordenes.length === 0 ? (
            <Text style={styles.meta}>No hay saldos por liquidar.</Text>
          ) : null}
        </View>
      }
      renderItem={({ item }) => (
        <View style={styles.card}>
          <Text style={styles.name}>#{item.correlativo}</Text>
          <Text style={styles.meta}>
            {formatDate(item.fecha_despacho)}
            {item.dias_vencidos > 0 ? ` · ${item.dias_vencidos}d venc.` : ""}
          </Text>
          <Text style={styles.meta}>
            Saldo ${formatMoney(item.saldo_pendiente)}
          </Text>
          <View style={styles.row}>
            <TextInput
              style={[styles.input, { flex: 1 }]}
              keyboardType="decimal-pad"
              placeholder="Cobranza USD"
              value={montos[item.id] ?? "0"}
              onChangeText={(v) =>
                setMontos((prev) => ({ ...prev, [item.id]: v }))
              }
            />
            <Pressable
              style={styles.chip}
              onPress={() =>
                setMontos((prev) => ({
                  ...prev,
                  [item.id]: String(item.saldo_pendiente),
                }))
              }
            >
              <Text style={styles.chipText}>Total</Text>
            </Pressable>
          </View>
        </View>
      )}
      ListFooterComponent={
        <View style={{ gap: 10, marginTop: 8 }}>
          <Text style={styles.section}>Formas de pago</Text>
          {pagos.map((p) => {
            const forma = formas.find((f) => f.fpago_id === p.fpago_id);
            const enBs = forma
              ? esFormaPagoEnBs(forma.fpago_concepto)
              : false;
            const cuenta = cuentas.find((c) => c.id === p.cuenta_id);
            return (
              <View key={p.key} style={styles.card}>
                <Pressable onPress={() => setPickerPagoKey(p.key)}>
                  <Text style={styles.name}>
                    {forma?.fpago_concepto ?? "Forma de pago"}
                  </Text>
                  <Text style={styles.meta}>{enBs ? "Monto en Bs" : "Monto en USD"}</Text>
                </Pressable>
                <TextInput
                  style={styles.input}
                  keyboardType="decimal-pad"
                  placeholder={enBs ? "Monto Bs" : "Monto USD"}
                  value={p.monto}
                  onChangeText={(v) =>
                    setPagos((prev) =>
                      prev.map((x) =>
                        x.key === p.key ? { ...x, monto: v } : x,
                      ),
                    )
                  }
                />
                {forma?.fpago_info ? (
                  <>
                    <Pressable onPress={() => setPickerCuentaKey(p.key)}>
                      <Text style={styles.meta}>
                        Cuenta: {cuenta ? cuenta.banco : "Elegir…"}
                      </Text>
                    </Pressable>
                    <TextInput
                      style={styles.input}
                      placeholder="Referencia bancaria"
                      value={p.referencia}
                      onChangeText={(v) =>
                        setPagos((prev) =>
                          prev.map((x) =>
                            x.key === p.key ? { ...x, referencia: v } : x,
                          ),
                        )
                      }
                    />
                  </>
                ) : null}
                <Pressable
                  onPress={() =>
                    setPagos((prev) => prev.filter((x) => x.key !== p.key))
                  }
                >
                  <Text style={styles.remove}>Quitar</Text>
                </Pressable>
              </View>
            );
          })}
          <Pressable style={styles.btnGhost} onPress={addPago}>
            <Text style={styles.btnGhostText}>+ Forma de pago</Text>
          </Pressable>

          <Text style={styles.label}>Observaciones</Text>
          <TextInput
            style={styles.input}
            value={obs}
            onChangeText={setObs}
            placeholder="Opcional"
          />

          <View style={styles.totals}>
            <Text style={styles.meta}>
              Cobranzas ${formatMoney(totalCobranzas)}
            </Text>
            <Text style={styles.meta}>
              Pagos ≈ ${formatMoney(totalPagosUsd)}
            </Text>
          </View>

          <Pressable
            style={[styles.btn, saving && { opacity: 0.6 }]}
            disabled={saving || ordenes.length === 0}
            onPress={() => void submit()}
          >
            <Text style={styles.btnText}>
              {saving ? "Registrando…" : "Registrar rendición"}
            </Text>
          </Pressable>
        </View>
      }
    />
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F6F8" },
  center: { flex: 1, alignItems: "center", justifyContent: "center" },
  title: { fontSize: 20, fontWeight: "700", color: "#0B3A5C" },
  section: { fontSize: 16, fontWeight: "600", color: "#0B3A5C", marginTop: 4 },
  label: { fontSize: 12, color: "#5B6B7C", textTransform: "uppercase" },
  card: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 12,
    borderWidth: 1,
    borderColor: "#E5EAF0",
    gap: 6,
  },
  name: { fontWeight: "600", color: "#0B3A5C" },
  meta: { fontSize: 13, color: "#5B6B7C" },
  row: { flexDirection: "row", gap: 8, alignItems: "center" },
  input: {
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 16,
  },
  chip: {
    backgroundColor: "#E8EEF3",
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  chipText: { color: "#0B3A5C", fontWeight: "600" },
  btn: {
    backgroundColor: "#0B3A5C",
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: "center",
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
  totals: { gap: 2 },
  error: { color: "#B42318" },
  remove: { color: "#B42318", fontSize: 13, marginTop: 4 },
  back: { color: "#0B3A5C", fontWeight: "600", padding: 16 },
});
