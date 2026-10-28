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
  listarEntidadesBancarias,
  listarFormasPago,
  registrarRendicion,
  solicitaAbonosCliente,
  type CuentaBancaria,
  type EntidadBancaria,
  type Fpago,
  type OrdenParaRendicion,
} from "@/lib/rendiciones";
import { esFormaPagoEnBs } from "@/lib/moneda";
import { formatDate, formatMoney } from "@/lib/format";

/** Parte de la cobranza que se aplica a la orden; el resto es saldo a favor. */
function montoAplicable(monto: number, saldoPendiente: number): number {
  const saldo = Number(saldoPendiente) || 0;
  return saldo > 0 ? Math.min(monto, saldo) : monto;
}

type PagoDraft = {
  key: string;
  fpago_id: string;
  monto: string;
  codigo_banco: string;
  referencia: string;
  cuenta_id: string;
};

export default function NuevaRendicionScreen() {
  const params = useLocalSearchParams<{
    clienteId?: string | string[];
  }>();
  const { profile } = useAuth();
  const router = useRouter();

  const rawParamId = Array.isArray(params.clienteId)
    ? params.clienteId[0]
    : params.clienteId;
  const [clienteId] = useState(rawParamId ?? "");
  const [clienteNombre, setClienteNombre] = useState("");
  const [ordenes, setOrdenes] = useState<OrdenParaRendicion[]>([]);
  const [montos, setMontos] = useState<Record<string, string>>({});
  const [saldoFavor, setSaldoFavor] = useState(0);
  const [formas, setFormas] = useState<Fpago[]>([]);
  const [cuentas, setCuentas] = useState<CuentaBancaria[]>([]);
  const [entidades, setEntidades] = useState<EntidadBancaria[]>([]);
  const [pagos, setPagos] = useState<PagoDraft[]>([]);
  const [tasa, setTasa] = useState<number | null>(null);
  const [obs, setObs] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pickerPagoKey, setPickerPagoKey] = useState<string | null>(null);
  const [pickerCuentaKey, setPickerCuentaKey] = useState<string | null>(null);
  const [pickerBancoKey, setPickerBancoKey] = useState<string | null>(null);
  const [filtroBanco, setFiltroBanco] = useState("");

  const load = useCallback(async () => {
    if (!profile || !clienteId) {
      setError("Falta el cliente. Abre la rendición desde Visita.");
      setLoading(false);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const [cRes, aRes, fRes, cuRes, ebRes, tRes] = await Promise.all([
        getClienteVisita(clienteId, profile),
        solicitaAbonosCliente(clienteId),
        listarFormasPago(),
        listarCuentasBancarias(),
        listarEntidadesBancarias(),
        retornaUltimaTasa(),
      ]);

      if (!cRes.ok) {
        setError(cRes.error);
      } else {
        setClienteNombre(cRes.cliente.razon_social);
      }

      if (!aRes.ok) {
        setError((prev) => prev ?? aRes.error);
      } else {
        setSaldoFavor(Number(aRes.abonos.saldo_favor) || 0);
        const ords = Array.isArray(aRes.abonos.ordenes) ? aRes.abonos.ordenes : [];
        setOrdenes(ords);
        const init: Record<string, string> = {};
        for (const o of ords) init[o.id] = "0";
        setMontos(init);
        if (aRes.abonos.tasa_oficial_actual) {
          setTasa(Number(aRes.abonos.tasa_oficial_actual) || null);
        }
      }

      if (fRes.ok) setFormas(Array.isArray(fRes.formas) ? fRes.formas : []);
      else setError((prev) => prev ?? fRes.error);

      if (cuRes.ok) setCuentas(Array.isArray(cuRes.cuentas) ? cuRes.cuentas : []);
      if (ebRes.ok) setEntidades(Array.isArray(ebRes.entidades) ? ebRes.entidades : []);
      if (tRes.ok && tasa == null) setTasa(tRes.tasa);
    } catch (err) {
      console.error("Error al cargar pantalla de rendición:", err);
      setError(
        err instanceof Error
          ? err.message
          : "Error inesperado al cargar la información del cliente.",
      );
    } finally {
      setLoading(false);
    }
  }, [profile, clienteId, tasa]);

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps -- load once on mount
  }, []);

  const totalCobranzas = useMemo(
    () =>
      Object.entries(montos).reduce(
        (acc, [, v]) => acc + (Number(String(v ?? "0").replace(",", ".")) || 0),
        0,
      ),
    [montos],
  );

  function montoDigitado(ordenId: string): number {
    return Number(String(montos[ordenId] ?? "0").replace(",", ".")) || 0;
  }

  const totalAplicado = useMemo(
    () =>
      ordenes.reduce(
        (acc, o) =>
          acc +
          montoAplicable(
            montoDigitado(o.id),
            Number(o.saldo_pendiente) || 0,
          ),
        0,
      ),
    [ordenes, montos],
  );

  const totalPagosUsd = useMemo(() => {
    return pagos.reduce((acc, p) => {
      const forma = formas.find((f) => f.fpago_id === p.fpago_id);
      const monto = Number(String(p.monto ?? "0").replace(",", ".")) || 0;
      if (!forma || monto <= 0) return acc;
      if (esFormaPagoEnBs(forma.fpago_concepto) && tasa && tasa > 0) {
        return acc + monto / tasa;
      }
      return acc + monto;
    }, 0);
  }, [pagos, formas, tasa]);

  const entidadesFiltradas = useMemo(() => {
    const q = (filtroBanco || "").toLowerCase().trim();
    if (!q) return entidades;
    return entidades.filter(
      (eb) =>
        (eb.codigo_eb || "").toLowerCase().includes(q) ||
        (eb.nombre_corto ? eb.nombre_corto.toLowerCase().includes(q) : false) ||
        (eb.nombre_eb || "").toLowerCase().includes(q),
    );
  }, [entidades, filtroBanco]);

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
        codigo_banco: entidades[0]?.codigo_eb ?? "0102",
        referencia: "",
        cuenta_id: cuentas[0]?.id ?? "",
      },
    ]);
  };

  const submit = async () => {
    if (!profile || !clienteId) return;
    try {
      const ordenesPayload = ordenes
        .map((o) => ({
          orden_id: o.id,
          monto_recaudado: montoAplicable(
            montoDigitado(o.id),
            Number(o.saldo_pendiente) || 0,
          ),
        }))
        .filter((o) => o.monto_recaudado > 0);

      if (!ordenesPayload.length) {
        setError("Indica el monto a cobrar en al menos una orden.");
        return;
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
            monto: Number(String(p.monto ?? "0").replace(",", ".")) || 0,
            en_bs: forma ? esFormaPagoEnBs(forma.fpago_concepto) : false,
            fpago_info: !!forma?.fpago_info,
            codigo_banco: p.codigo_banco,
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
    } catch (err) {
      console.error("Error al registrar rendición:", err);
      setError(
        err instanceof Error ? err.message : "Error inesperado al registrar cobranza.",
      );
      setSaving(false);
    }
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

  if (pickerBancoKey) {
    return (
      <View style={styles.root}>
        <View style={{ paddingHorizontal: 16, paddingTop: 16, gap: 8 }}>
          <Pressable
            onPress={() => {
              setPickerBancoKey(null);
              setFiltroBanco("");
            }}
          >
            <Text style={{ color: "#0B3A5C", fontWeight: "600", paddingVertical: 8 }}>
              ← Volver
            </Text>
          </Pressable>
          <Text style={styles.title}>Entidad bancaria emisora (BCV)</Text>
          <TextInput
            style={styles.input}
            placeholder="Buscar por código (ej. 0102) o nombre…"
            value={filtroBanco}
            onChangeText={setFiltroBanco}
            autoCapitalize="none"
            autoCorrect={false}
          />
        </View>
        <FlatList
          data={entidadesFiltradas}
          keyExtractor={(eb) => eb.codigo_eb}
          contentContainerStyle={{ padding: 16 }}
          ListEmptyComponent={
            <Text style={styles.meta}>
              {filtroBanco
                ? `No se encontró ningún banco con «${filtroBanco}».`
                : "No hay entidades bancarias activas."}
            </Text>
          }
          renderItem={({ item }) => (
            <Pressable
              style={styles.card}
              onPress={() => {
                setPagos((prev) =>
                  prev.map((p) =>
                    p.key === pickerBancoKey
                      ? { ...p, codigo_banco: item.codigo_eb }
                      : p,
                  ),
                );
                setPickerBancoKey(null);
                setFiltroBanco("");
              }}
            >
              <Text style={styles.name}>
                {item.codigo_eb} · {item.nombre_corto || item.nombre_eb}
              </Text>
              <Text style={styles.meta}>{item.nombre_eb}</Text>
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
          {montoDigitado(item.id) - item.saldo_pendiente > 0.009 &&
          item.saldo_pendiente > 0 ? (
            <Text style={styles.favor}>
              Se aplican ${formatMoney(item.saldo_pendiente)} a la orden y $
              {formatMoney(montoDigitado(item.id) - item.saldo_pendiente)}{" "}
              quedan como saldo a favor.
            </Text>
          ) : null}
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
            const entidad = entidades.find(
              (eb) => eb.codigo_eb === p.codigo_banco,
            );
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
                    <Text style={styles.label}>
                      Entidad bancaria emisora (BCV) *
                    </Text>
                    <Pressable
                      style={styles.selectBox}
                      onPress={() => setPickerBancoKey(p.key)}
                    >
                      <Text style={styles.selectBoxText}>
                        {entidad
                          ? `${entidad.codigo_eb} · ${entidad.nombre_corto || entidad.nombre_eb}`
                          : p.codigo_banco
                            ? `${p.codigo_banco} · Seleccionar banco emisor`
                            : "Seleccionar entidad bancaria emisora…"}
                      </Text>
                    </Pressable>

                    <Text style={styles.label}>
                      Cuenta bancaria destino (Empresa) *
                    </Text>
                    <Pressable
                      style={styles.selectBox}
                      onPress={() => setPickerCuentaKey(p.key)}
                    >
                      <Text style={styles.selectBoxText}>
                        {cuenta
                          ? `${cuenta.banco}${cuenta.numero_cuenta ? ` · ${cuenta.numero_cuenta}` : ""}`
                          : "Seleccionar cuenta destino…"}
                      </Text>
                    </Pressable>

                    <Text style={styles.label}>Referencia bancaria *</Text>
                    <TextInput
                      style={styles.input}
                      placeholder="Ej. 000225633"
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
            {totalPagosUsd - totalAplicado > 0.009 ? (
              <Text style={styles.favor}>
                Saldo a favor a generar ≈ $
                {formatMoney(totalPagosUsd - totalAplicado)}
              </Text>
            ) : null}
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
  favor: { fontSize: 12, color: "#027A48", marginTop: 6 },
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
  selectBox: {
    backgroundColor: "#F8FAFC",
    borderWidth: 1,
    borderColor: "#0B3A5C",
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 11,
  },
  selectBoxText: {
    color: "#0B3A5C",
    fontWeight: "600",
    fontSize: 14,
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
