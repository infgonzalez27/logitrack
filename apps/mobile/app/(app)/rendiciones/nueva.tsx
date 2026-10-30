import { useCallback, useEffect, useMemo, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  FlatList,
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { Ionicons } from "@expo/vector-icons";
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
import { convertirBsAUsd, convertirUsdABs, esFormaPagoEnBs } from "@/lib/moneda";
import { formatDate, formatMoney } from "@/lib/format";

/** Determina qué parte del monto digitado amortiza la orden y cuánto genera saldo a favor */
function montoAplicable(monto: number, saldoPendiente: number): number {
  const saldo = Number(saldoPendiente) || 0;
  return saldo > 0 ? Math.min(monto, saldo) : monto;
}

function getFormaIcon(concepto: string | undefined): keyof typeof Ionicons.glyphMap {
  const c = (concepto || "").toLowerCase();
  if (c.includes("efectivo") || c.includes("cash") || c.includes("dólar") || c.includes("usd")) {
    return "cash-outline";
  }
  if (c.includes("pago movil") || c.includes("móvil") || c.includes("movil")) {
    return "phone-portrait-outline";
  }
  if (c.includes("transferencia") || c.includes("banco")) {
    return "business-outline";
  }
  if (c.includes("zelle") || c.includes("binance") || c.includes("tarjeta")) {
    return "card-outline";
  }
  return "wallet-outline";
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
  const [clienteRif, setClienteRif] = useState("");
  const [ordenes, setOrdenes] = useState<OrdenParaRendicion[]>([]);
  const [selectedOrders, setSelectedOrders] = useState<Record<string, boolean>>({});
  const [partialMode, setPartialMode] = useState<Record<string, boolean>>({});
  const [montos, setMontos] = useState<Record<string, string>>({});
  const [saldoFavor, setSaldoFavor] = useState(0);
  const [formas, setFormas] = useState<Fpago[]>([]);
  const [cuentas, setCuentas] = useState<CuentaBancaria[]>([]);
  const [entidades, setEntidades] = useState<EntidadBancaria[]>([]);
  const [pagos, setPagos] = useState<PagoDraft[]>([]);
  const [tasa, setTasa] = useState<number | null>(null);
  const [fechaTasa, setFechaTasa] = useState<string | null>(null);
  const [obs, setObs] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Estados de modales (flotantes para no resetear posición de scroll)
  const [pickerPagoKey, setPickerPagoKey] = useState<string | null>(null);
  const [pickerCuentaKey, setPickerCuentaKey] = useState<string | null>(null);
  const [pickerBancoKey, setPickerBancoKey] = useState<string | null>(null);
  const [filtroBanco, setFiltroBanco] = useState("");

  const load = useCallback(async () => {
    if (!profile || !clienteId) {
      setError("Falta el cliente. Abre la cobranza desde Visita o Clientes.");
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
        setClienteRif(cRes.cliente.rif_nit);
      }

      // Priorizar la tasa BCV del scraping oficial
      let tasaFinal: number | null = null;
      let fechaFinal: string | null = null;
      if (tRes.ok && tRes.tasa && tRes.tasa > 0) {
        tasaFinal = tRes.tasa;
        fechaFinal = tRes.fecha;
      } else if (aRes.ok && aRes.abonos.tasa_oficial_actual) {
        tasaFinal = Number(aRes.abonos.tasa_oficial_actual) || null;
      }
      setTasa(tasaFinal);
      setFechaTasa(fechaFinal);

      const ords = aRes.ok && Array.isArray(aRes.abonos.ordenes)
        ? aRes.abonos.ordenes
        : [];

      if (!aRes.ok) {
        setError((prev) => prev ?? aRes.error);
      } else {
        setSaldoFavor(Number(aRes.abonos.saldo_favor) || 0);
        setOrdenes(ords);
        // Las órdenes inician listas para que el usuario pulse "Cobrar total"
        // o "Cobrar todas", acumulando la suma de manera limpia.
        setSelectedOrders({});
        setMontos({});
        setPartialMode({});
      }

      const formasList = fRes.ok && Array.isArray(fRes.formas) ? fRes.formas : [];
      setFormas(formasList);
      if (!fRes.ok) setError((prev) => prev ?? fRes.error);

      const cuentasList = cuRes.ok && Array.isArray(cuRes.cuentas) ? cuRes.cuentas : [];
      setCuentas(cuentasList);

      const entidadesList = ebRes.ok && Array.isArray(ebRes.entidades) ? ebRes.entidades : [];
      setEntidades(entidadesList);

      // Primer pago listo para auto-completar al totalizar órdenes
      if (formasList.length > 0) {
        const firstForma = formasList[0];
        setPagos([
          {
            key: `${Date.now()}`,
            fpago_id: firstForma.fpago_id,
            monto: "",
            codigo_banco: entidadesList[0]?.codigo_eb ?? "0102",
            referencia: "",
            cuenta_id: cuentasList[0]?.id ?? "",
          },
        ]);
      }
    } catch (err) {
      console.error("Error al cargar cobranza:", err);
      setError(
        err instanceof Error
          ? err.message
          : "Error inesperado al cargar la información del cliente.",
      );
    } finally {
      setLoading(false);
    }
  }, [profile, clienteId]);

  useEffect(() => {
    void load();
  }, [load]);

  // Total a cobrar según órdenes activas y montos seleccionados
  const totalCobrarUsd = useMemo(() => {
    return ordenes.reduce((acc, o) => {
      if (!selectedOrders[o.id]) return acc;
      const v = Number(String(montos[o.id] ?? "0").replace(",", ".")) || 0;
      return acc + montoAplicable(v, Number(o.saldo_pendiente) || 0);
    }, 0);
  }, [ordenes, selectedOrders, montos]);

  // Total de pagos registrados en equivalente USD
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

  // Cantidad de facturas seleccionadas
  const selectedCount = useMemo(() => {
    return ordenes.filter((o) => selectedOrders[o.id]).length;
  }, [ordenes, selectedOrders]);

  // Lista de bancos filtrada para el modal
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

  // Sincroniza automáticamente el pago único con el total actual según su moneda
  const syncPaymentWithTotal = (newTotalUsd: number) => {
    setPagos((prev) => {
      if (prev.length !== 1) return prev;
      const p = prev[0];
      const forma = formas.find((f) => f.fpago_id === p.fpago_id);
      const enBs = forma ? esFormaPagoEnBs(forma.fpago_concepto) : false;
      let valor = "";
      if (newTotalUsd > 0) {
        if (enBs && tasa && tasa > 0) {
          valor = String(convertirUsdABs(newTotalUsd, tasa));
        } else {
          valor = String(Math.round(newTotalUsd * 100) / 100);
        }
      }
      return [{ ...p, monto: valor }];
    });
  };

  const computeTotal = (
    ordersList: OrdenParaRendicion[],
    sel: Record<string, boolean>,
    m: Record<string, string>,
  ) => {
    return ordersList.reduce((acc, o) => {
      if (!sel[o.id]) return acc;
      const v = Number(String(m[o.id] ?? "0").replace(",", ".")) || 0;
      return acc + montoAplicable(v, Number(o.saldo_pendiente) || 0);
    }, 0);
  };

  // 1. Cobrar total de una orden individual (Acumula sucesivamente)
  const selectOrderTotal = (ordenId: string, saldoPendiente: number) => {
    setSelectedOrders((prevSel) => {
      const nextSel = { ...prevSel, [ordenId]: true };
      setPartialMode((prevPart) => ({ ...prevPart, [ordenId]: false }));
      setMontos((prevM) => {
        const nextM = { ...prevM, [ordenId]: String(saldoPendiente) };
        const nextTotal = computeTotal(ordenes, nextSel, nextM);
        syncPaymentWithTotal(nextTotal);
        return nextM;
      });
      return nextSel;
    });
  };

  // 2. Abono parcial de una orden (Permite ingresar monto específico)
  const selectOrderPartial = (ordenId: string, saldoPendiente: number) => {
    setSelectedOrders((prevSel) => {
      const nextSel = { ...prevSel, [ordenId]: true };
      setPartialMode((prevPart) => ({ ...prevPart, [ordenId]: true }));
      setMontos((prevM) => {
        const existing = prevM[ordenId];
        const initialPartial = existing && existing !== "0" ? existing : String(saldoPendiente);
        const nextM = { ...prevM, [ordenId]: initialPartial };
        const nextTotal = computeTotal(ordenes, nextSel, nextM);
        syncPaymentWithTotal(nextTotal);
        return nextM;
      });
      return nextSel;
    });
  };

  // 3. Quitar / Deseleccionar orden (Revierte la acumulación)
  const deselectOrder = (ordenId: string) => {
    setSelectedOrders((prevSel) => {
      const nextSel = { ...prevSel, [ordenId]: false };
      setPartialMode((prevPart) => ({ ...prevPart, [ordenId]: false }));
      setMontos((prevM) => {
        const nextM = { ...prevM, [ordenId]: "" };
        const nextTotal = computeTotal(ordenes, nextSel, nextM);
        syncPaymentWithTotal(nextTotal);
        return nextM;
      });
      return nextSel;
    });
  };

  // 4. Edición de monto parcial en vivo
  const handleOrderMontoChange = (ordenId: string, val: string) => {
    setMontos((prevM) => {
      const nextM = { ...prevM, [ordenId]: val };
      const nextTotal = computeTotal(ordenes, selectedOrders, nextM);
      syncPaymentWithTotal(nextTotal);
      return nextM;
    });
  };

  // 5. Cobrar todas las órdenes juntas con 1 tap
  const selectAllOrders = () => {
    const nextSel: Record<string, boolean> = {};
    const nextM: Record<string, string> = {};
    const nextPart: Record<string, boolean> = {};
    for (const o of ordenes) {
      nextSel[o.id] = true;
      nextM[o.id] = String(o.saldo_pendiente);
      nextPart[o.id] = false;
    }
    setSelectedOrders(nextSel);
    setMontos(nextM);
    setPartialMode(nextPart);
    const nextTotal = computeTotal(ordenes, nextSel, nextM);
    syncPaymentWithTotal(nextTotal);
  };

  // 6. Limpiar selección completa
  const clearAllOrders = () => {
    setSelectedOrders({});
    setMontos({});
    setPartialMode({});
    syncPaymentWithTotal(0);
  };

  // Selección de método de pago con conversión automática entre USD y Bolívares
  const onSelectPaymentMethod = (pKey: string, newFpagoId: string) => {
    setPagos((prev) =>
      prev.map((p) => {
        if (p.key !== pKey) return p;

        const oldForma = formas.find((f) => f.fpago_id === p.fpago_id);
        const newForma = formas.find((f) => f.fpago_id === newFpagoId);

        const oldEnBs = oldForma ? esFormaPagoEnBs(oldForma.fpago_concepto) : false;
        const newEnBs = newForma ? esFormaPagoEnBs(newForma.fpago_concepto) : false;

        let newMonto = p.monto;
        const montoNum = Number(String(p.monto ?? "0").replace(",", ".")) || 0;

        if (oldEnBs && !newEnBs) {
          // Cambió de Bolívares a Dólares
          if (tasa && tasa > 0 && montoNum > 0) {
            newMonto = String(convertirBsAUsd(montoNum, tasa));
          } else if (totalCobrarUsd > 0) {
            newMonto = String(Math.round(totalCobrarUsd * 100) / 100);
          }
        } else if (!oldEnBs && newEnBs) {
          // Cambió de Dólares a Bolívares
          if (tasa && tasa > 0 && montoNum > 0) {
            newMonto = String(convertirUsdABs(montoNum, tasa));
          } else if (totalCobrarUsd > 0 && tasa && tasa > 0) {
            newMonto = String(convertirUsdABs(totalCobrarUsd, tasa));
          }
        } else if (montoNum === 0 && totalCobrarUsd > 0) {
          newMonto = newEnBs && tasa && tasa > 0
            ? String(convertirUsdABs(totalCobrarUsd, tasa))
            : String(Math.round(totalCobrarUsd * 100) / 100);
        }

        return {
          ...p,
          fpago_id: newFpagoId,
          monto: newMonto,
        };
      }),
    );
    setPickerPagoKey(null);
  };

  // Agregar nuevo pago
  const addPago = () => {
    const first = formas[0];
    if (!first) {
      setError("No hay formas de pago configuradas en el sistema.");
      return;
    }
    const restanteUsd = Math.max(0, totalCobrarUsd - totalPagosUsd);
    const enBs = esFormaPagoEnBs(first.fpago_concepto);
    const montoSugerido = enBs && tasa && tasa > 0
      ? String(convertirUsdABs(restanteUsd, tasa))
      : restanteUsd > 0
        ? String(Math.round(restanteUsd * 100) / 100)
        : "";

    setPagos((prev) => [
      ...prev,
      {
        key: `${Date.now()}`,
        fpago_id: first.fpago_id,
        monto: montoSugerido,
        codigo_banco: entidades[0]?.codigo_eb ?? "0102",
        referencia: "",
        cuenta_id: cuentas[0]?.id ?? "",
      },
    ]);
  };

  // Llenar restante de pago
  const fillRemainingPayment = (pagoKey: string, enBs: boolean) => {
    const otrosPagosUsd = pagos.reduce((acc, p) => {
      if (p.key === pagoKey) return acc;
      const f = formas.find((item) => item.fpago_id === p.fpago_id);
      const m = Number(String(p.monto ?? "0").replace(",", ".")) || 0;
      if (!f || m <= 0) return acc;
      if (esFormaPagoEnBs(f.fpago_concepto) && tasa && tasa > 0) return acc + m / tasa;
      return acc + m;
    }, 0);

    const restanteUsd = Math.max(0, totalCobrarUsd - otrosPagosUsd);
    const valor = enBs && tasa && tasa > 0
      ? String(convertirUsdABs(restanteUsd, tasa))
      : String(Math.round(restanteUsd * 100) / 100);

    setPagos((prev) =>
      prev.map((p) => (p.key === pagoKey ? { ...p, monto: valor } : p)),
    );
  };

  const submit = async () => {
    if (!profile || !clienteId) return;
    try {
      const ordenesPayload = ordenes
        .filter((o) => selectedOrders[o.id])
        .map((o) => {
          const v = Number(String(montos[o.id] ?? "0").replace(",", ".")) || 0;
          return {
            orden_id: o.id,
            monto_recaudado: montoAplicable(v, Number(o.saldo_pendiente) || 0),
          };
        })
        .filter((o) => o.monto_recaudado > 0);

      if (!ordenesPayload.length) {
        setError("Selecciona al menos una orden e indica el monto a cobrar.");
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
        "Cobranza Registrada",
        `Cobranza registrada exitosamente.\n\n` +
          `• Total recaudado: $${formatMoney(totalPagosUsd)}\n` +
          `• Saldo a favor usado: $${formatMoney(res.saldoFavorUsado)}\n` +
          `• Saldo a favor generado: $${formatMoney(res.saldoFavorGenerado)}`,
        [{ text: "Aceptar", onPress: () => router.back() }],
      );
    } catch (err) {
      console.error("Error al registrar cobranza:", err);
      setError(
        err instanceof Error ? err.message : "Error inesperado al registrar la cobranza.",
      );
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color="#0B3A5C" />
        <Text style={{ marginTop: 12, color: "#64748B", fontSize: 14 }}>
          Cargando datos de cobranza...
        </Text>
      </View>
    );
  }

  const diferencia = totalPagosUsd - totalCobrarUsd;

  return (
    <KeyboardAvoidingView
      style={styles.root}
      behavior={Platform.OS === "ios" ? "padding" : undefined}
      keyboardVerticalOffset={Platform.OS === "ios" ? 88 : 0}
    >
      {/* ScrollView estable que retiene la posición sin saltar al inicio */}
      <ScrollView
        contentContainerStyle={styles.scrollContent}
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="on-drag"
        automaticallyAdjustKeyboardInsets={true}
      >
        {/* Banner Hero del Cliente */}
        <View style={styles.clientHero}>
          <View style={{ flex: 1 }}>
            <Text style={styles.clientHeroTitle} numberOfLines={1}>
              {clienteNombre || "Cliente"}
            </Text>
            <Text style={styles.clientHeroRif}>{clienteRif || "—"}</Text>
          </View>
          {tasa != null && tasa > 0 ? (
            <View style={styles.bcvBadge}>
              <View style={{ flexDirection: "row", alignItems: "center", gap: 4 }}>
                <Ionicons name="shield-checkmark" size={12} color="#6EE7B7" />
                <Text style={styles.bcvBadgeLabel}>Tasa BCV</Text>
              </View>
              <Text style={styles.bcvBadgeVal}>Bs {formatMoney(tasa)}</Text>
              {fechaTasa ? (
                <Text style={styles.bcvBadgeDate}>{formatDate(fechaTasa)}</Text>
              ) : null}
            </View>
          ) : null}
        </View>

        {/* Saldo a favor del cliente */}
        {saldoFavor > 0 ? (
          <View style={styles.creditBanner}>
            <Ionicons name="gift-outline" size={18} color="#027A48" />
            <Text style={styles.creditBannerText}>
              El cliente tiene un saldo a favor de ${formatMoney(saldoFavor)} USD.
            </Text>
          </View>
        ) : null}

        {error ? (
          <View style={styles.errorBox}>
            <Ionicons name="alert-circle" size={18} color="#B42318" />
            <Text style={styles.errorText}>{error}</Text>
          </View>
        ) : null}

        {/* SECCIÓN 1: ÓRDENES A COBRAR */}
        <View style={styles.sectionHeaderRow}>
          <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
            <Ionicons name="receipt-outline" size={18} color="#0B3A5C" />
            <Text style={styles.sectionTitle}>
              1. Órdenes a cobrar ({ordenes.length})
            </Text>
          </View>

          {ordenes.length > 0 ? (
            <View style={{ flexDirection: "row", gap: 8 }}>
              {selectedCount < ordenes.length ? (
                <Pressable
                  style={styles.quickHeaderBtn}
                  onPress={selectAllOrders}
                >
                  <Ionicons name="checkmark-done" size={14} color="#0B3A5C" />
                  <Text style={styles.quickHeaderBtnText}>Cobrar todas</Text>
                </Pressable>
              ) : null}

              {selectedCount > 0 ? (
                <Pressable
                  style={styles.quickHeaderBtnClear}
                  onPress={clearAllOrders}
                >
                  <Ionicons name="close" size={14} color="#64748B" />
                  <Text style={styles.quickHeaderBtnClearText}>Limpiar</Text>
                </Pressable>
              ) : null}
            </View>
          ) : null}
        </View>

        {ordenes.length === 0 ? (
          <View style={styles.emptyCard}>
            <Ionicons name="checkmark-done-circle-outline" size={36} color="#027A48" />
            <Text style={styles.emptyTitle}>¡Cliente al día!</Text>
            <Text style={styles.emptySubtitle}>No hay facturas ni órdenes con saldo pendiente.</Text>
          </View>
        ) : (
          <View style={{ gap: 10 }}>
            {ordenes.map((item) => {
              const isSelected = !!selectedOrders[item.id];
              const isPartial = !!partialMode[item.id];
              const montoDigitado = Number(String(montos[item.id] ?? "0").replace(",", ".")) || 0;
              const pendiente = Number(item.saldo_pendiente) || 0;
              const pendienteBs = tasa && tasa > 0 ? convertirUsdABs(pendiente, tasa) : null;

              return (
                <View
                  key={item.id}
                  style={[
                    styles.orderCard,
                    isSelected && styles.orderCardSelected,
                  ]}
                >
                  {/* Encabezado de la Orden */}
                  <View style={styles.orderTopRow}>
                    <Pressable
                      style={styles.orderHeaderPressable}
                      onPress={() => {
                        if (isSelected) {
                          deselectOrder(item.id);
                        } else {
                          selectOrderTotal(item.id, pendiente);
                        }
                      }}
                    >
                      <Ionicons
                        name={isSelected ? "checkbox" : "square-outline"}
                        size={24}
                        color={isSelected ? "#0B3A5C" : "#94A3B8"}
                      />
                      <View style={{ flex: 1 }}>
                        <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
                          <Text style={styles.orderNumber}>Orden #{item.correlativo}</Text>
                          {isSelected ? (
                            <View
                              style={[
                                styles.selectedBadge,
                                isPartial ? styles.badgePartial : styles.badgeTotal,
                              ]}
                            >
                              <Text
                                style={[
                                  styles.selectedBadgeText,
                                  isPartial ? styles.badgePartialText : styles.badgeTotalText,
                                ]}
                              >
                                {isPartial ? "Abono parcial" : "Total"}
                              </Text>
                            </View>
                          ) : null}
                        </View>
                        <Text style={styles.orderDate}>
                          {formatDate(item.fecha_despacho)}
                          {item.dias_vencidos > 0 ? (
                            <Text style={styles.orderVencida}> · {item.dias_vencidos}d vencida</Text>
                          ) : null}
                        </Text>
                      </View>
                    </Pressable>

                    <View style={{ alignItems: "flex-end" }}>
                      <Text style={styles.orderAmount}>${formatMoney(pendiente)}</Text>
                      {pendienteBs != null ? (
                        <Text style={styles.orderAmountBs}>Bs {formatMoney(pendienteBs)}</Text>
                      ) : null}
                    </View>
                  </View>

                  {/* Acciones de la Orden */}
                  {!isSelected ? (
                    // Estado no seleccionado: Botones directos para cobrar total o parcial
                    <View style={styles.orderUnselectedActions}>
                      <Pressable
                        style={styles.cobrarTotalPrimaryBtn}
                        onPress={() => selectOrderTotal(item.id, pendiente)}
                      >
                        <Ionicons name="add-circle" size={18} color="#FFFFFF" />
                        <Text style={styles.cobrarTotalPrimaryBtnText}>
                          Cobrar Total (${formatMoney(pendiente)})
                        </Text>
                      </Pressable>

                      <Pressable
                        style={styles.abonoParcialSecondaryBtn}
                        onPress={() => selectOrderPartial(item.id, pendiente)}
                      >
                        <Ionicons name="create-outline" size={16} color="#0B3A5C" />
                        <Text style={styles.abonoParcialSecondaryBtnText}>Abono parcial</Text>
                      </Pressable>
                    </View>
                  ) : (
                    // Estado seleccionado: Selector entre Total, Abono Parcial y opción de Quitar
                    <View style={styles.orderActionsContainer}>
                      <View style={styles.segmentedButtons}>
                        <Pressable
                          style={[styles.segmentBtn, !isPartial && styles.segmentBtnActive]}
                          onPress={() => selectOrderTotal(item.id, pendiente)}
                        >
                          <Text style={[styles.segmentBtnText, !isPartial && styles.segmentBtnTextActive]}>
                            Total (${formatMoney(pendiente)})
                          </Text>
                        </Pressable>

                        <Pressable
                          style={[styles.segmentBtn, isPartial && styles.segmentBtnActive]}
                          onPress={() => selectOrderPartial(item.id, pendiente)}
                        >
                          <Text style={[styles.segmentBtnText, isPartial && styles.segmentBtnTextActive]}>
                            Abono parcial
                          </Text>
                        </Pressable>

                        <Pressable
                          style={styles.segmentBtnDeselect}
                          onPress={() => deselectOrder(item.id)}
                          hitSlop={6}
                        >
                          <Ionicons name="close-circle-outline" size={16} color="#DC2626" />
                          <Text style={styles.segmentBtnDeselectText}>Quitar</Text>
                        </Pressable>
                      </View>

                      {isPartial ? (
                        <View style={styles.partialInputWrapper}>
                          <View style={styles.partialInputHeader}>
                            <Text style={styles.partialInputLabel}>Indica el monto a cobrar ($ USD):</Text>
                            {tasa && tasa > 0 && montoDigitado > 0 ? (
                              <Text style={styles.partialBsEquiv}>
                                ≈ Bs {formatMoney(convertirUsdABs(montoDigitado, tasa))}
                              </Text>
                            ) : null}
                          </View>
                          <View style={styles.inputWithPrefix}>
                            <Text style={styles.inputCurrencyPrefix}>$</Text>
                            <TextInput
                              style={styles.partialInput}
                              keyboardType="decimal-pad"
                              placeholder="0.00"
                              placeholderTextColor="#94A3B8"
                              value={montos[item.id] ?? ""}
                              onChangeText={(v) => handleOrderMontoChange(item.id, v)}
                              autoFocus
                            />
                          </View>
                          {montoDigitado - pendiente > 0.009 ? (
                            <Text style={styles.excessBadge}>
                              ℹ️ Se amortizan ${formatMoney(pendiente)} y ${formatMoney(montoDigitado - pendiente)} quedarán como saldo a favor.
                            </Text>
                          ) : null}
                        </View>
                      ) : null}
                    </View>
                  )}
                </View>
              );
            })}
          </View>
        )}

        {/* ============================================================ */}
        {/* TOTALIZADOR CENTRAL: TASA BCV, USD Y EQUIVALENTE EN BOLÍVARES */}
        {/* ============================================================ */}
        <View style={styles.totalizerCard}>
          <View style={styles.totalizerTopRow}>
            <View style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
              <View style={styles.totalizerIconBadge}>
                <Ionicons name="calculator-outline" size={20} color="#FFFFFF" />
              </View>
              <View>
                <Text style={styles.totalizerTitle}>Total a cobrar</Text>
                <Text style={styles.totalizerSubtitle}>
                  {selectedCount} de {ordenes.length} {ordenes.length === 1 ? "orden" : "órdenes"} seleccionada{selectedCount !== 1 ? "s" : ""}
                </Text>
              </View>
            </View>

            {tasa != null && tasa > 0 ? (
              <View style={styles.totalizerBcvPill}>
                <Ionicons name="stats-chart-outline" size={12} color="#CBD5E1" />
                <Text style={styles.totalizerBcvPillText}>
                  BCV: Bs {formatMoney(tasa)}
                </Text>
              </View>
            ) : null}
          </View>

          <View style={styles.totalizerAmountRow}>
            <View>
              <Text style={styles.totalizerCurrencyLabel}>En Divisas</Text>
              <Text style={styles.totalizerUsdText}>${formatMoney(totalCobrarUsd)}</Text>
            </View>

            <View style={styles.totalizerVerticalDivider} />

            <View style={{ alignItems: "flex-end" }}>
              <Text style={styles.totalizerCurrencyLabel}>En Bolívares (BCV)</Text>
              <Text style={styles.totalizerBsText}>
                {tasa && tasa > 0
                  ? `Bs ${formatMoney(convertirUsdABs(totalCobrarUsd, tasa))}`
                  : "—"}
              </Text>
            </View>
          </View>
        </View>

        {/* ============================================================ */}
        {/* SECCIÓN 2: FORMAS DE PAGO RECIBIDAS                         */}
        {/* ============================================================ */}
        <View style={styles.sectionHeaderRow}>
          <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
            <Ionicons name="wallet-outline" size={18} color="#0B3A5C" />
            <Text style={styles.sectionTitle}>2. Formas de pago recibidas</Text>
          </View>
        </View>

        {pagos.map((p, index) => {
          const forma = formas.find((f) => f.fpago_id === p.fpago_id);
          const enBs = forma ? esFormaPagoEnBs(forma.fpago_concepto) : false;
          const cuenta = cuentas.find((c) => c.id === p.cuenta_id);
          const entidad = entidades.find((eb) => eb.codigo_eb === p.codigo_banco);
          const montoActual = Number(String(p.monto ?? "0").replace(",", ".")) || 0;
          const montoEquivalenteUsd = enBs && tasa && tasa > 0 ? montoActual / tasa : montoActual;
          const montoEquivalenteBs = !enBs && tasa && tasa > 0 ? convertirUsdABs(montoActual, tasa) : montoActual;

          return (
            <View key={p.key} style={styles.paymentCard}>
              <View style={styles.paymentCardHeader}>
                <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
                  <Ionicons
                    name={getFormaIcon(forma?.fpago_concepto)}
                    size={18}
                    color="#0B3A5C"
                  />
                  <Text style={styles.paymentCardIndex}>Pago #{index + 1}</Text>
                  <View style={[styles.currencyPill, enBs ? styles.pillBs : styles.pillUsd]}>
                    <Text style={[styles.currencyPillText, enBs ? styles.pillBsText : styles.pillUsdText]}>
                      {enBs ? "Bolívares (Bs)" : "Dólares ($)"}
                    </Text>
                  </View>
                </View>

                {pagos.length > 1 ? (
                  <Pressable
                    style={styles.deletePaymentBtn}
                    onPress={() =>
                      setPagos((prev) => prev.filter((x) => x.key !== p.key))
                    }
                    hitSlop={8}
                  >
                    <Ionicons name="trash-outline" size={18} color="#B42318" />
                    <Text style={styles.deletePaymentText}>Quitar</Text>
                  </Pressable>
                ) : null}
              </View>

              {/* Selector de Método de Pago */}
              <Text style={styles.fieldLabel}>Método de pago *</Text>
              <Pressable
                style={styles.selectorTrigger}
                onPress={() => setPickerPagoKey(p.key)}
              >
                <View style={styles.selectorIconWrap}>
                  <Ionicons
                    name={getFormaIcon(forma?.fpago_concepto)}
                    size={20}
                    color="#0B3A5C"
                  />
                </View>
                <View style={{ flex: 1 }}>
                  <Text style={styles.selectorMainText}>
                    {forma?.fpago_concepto ?? "Seleccionar método de pago"}
                  </Text>
                  <Text style={styles.selectorSubText}>
                    {enBs ? "Monto en Bolívares (calculado a tasa oficial)" : "Monto en divisas USD"}
                    {forma?.fpago_info ? " · Requiere banco y referencia" : ""}
                  </Text>
                </View>
                <Ionicons name="chevron-down" size={20} color="#0B3A5C" />
              </Pressable>

              {/* Entrada de Monto con auto-conversión */}
              <View style={{ marginTop: 8 }}>
                <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "center" }}>
                  <Text style={styles.fieldLabel}>
                    {enBs ? "Monto a recibir en Bolívares (Bs) *" : "Monto a recibir en USD ($) *"}
                  </Text>
                  {totalCobrarUsd > 0 && Math.abs(totalCobrarUsd - totalPagosUsd) > 0.01 ? (
                    <Pressable onPress={() => fillRemainingPayment(p.key, enBs)}>
                      <Text style={styles.fillRemainingText}>
                        Llenar restante ({enBs && tasa ? `Bs ${formatMoney(convertirUsdABs(Math.max(0, totalCobrarUsd - totalPagosUsd), tasa))}` : `$${formatMoney(Math.max(0, totalCobrarUsd - totalPagosUsd))}`})
                      </Text>
                    </Pressable>
                  ) : null}
                </View>

                <View style={styles.inputWithPrefix}>
                  <Text style={styles.inputCurrencyPrefix}>{enBs ? "Bs" : "$"}</Text>
                  <TextInput
                    style={styles.amountInput}
                    keyboardType="decimal-pad"
                    placeholder="0.00"
                    placeholderTextColor="#94A3B8"
                    value={p.monto}
                    onChangeText={(v) =>
                      setPagos((prev) =>
                        prev.map((x) => (x.key === p.key ? { ...x, monto: v } : x)),
                      )
                    }
                  />
                </View>

                {/* Equivalencia en vivo según tasa oficial BCV */}
                {montoActual > 0 && tasa && tasa > 0 ? (
                  <View style={styles.conversionHelperRow}>
                    <Ionicons name="swap-horizontal" size={14} color="#0B3A5C" />
                    <Text style={styles.conversionHelper}>
                      {enBs
                        ? `≈ $${formatMoney(montoEquivalenteUsd)} USD (Tasa BCV Bs ${formatMoney(tasa)})`
                        : `≈ Bs ${formatMoney(montoEquivalenteBs)} (Tasa BCV Bs ${formatMoney(tasa)})`}
                    </Text>
                  </View>
                ) : null}
              </View>

              {/* Campos adicionales si requiere datos bancarios */}
              {forma?.fpago_info ? (
                <View style={styles.bankFieldsGroup}>
                  <Text style={styles.fieldLabel}>Banco emisor (BCV) *</Text>
                  <Pressable
                    style={styles.selectorTrigger}
                    onPress={() => {
                      setFiltroBanco("");
                      setPickerBancoKey(p.key);
                    }}
                  >
                    <View style={styles.selectorIconWrap}>
                      <Ionicons name="business-outline" size={20} color="#0B3A5C" />
                    </View>
                    <View style={{ flex: 1 }}>
                      <Text style={styles.selectorMainText} numberOfLines={1}>
                        {entidad
                          ? `${entidad.codigo_eb} · ${entidad.nombre_corto || entidad.nombre_eb}`
                          : p.codigo_banco
                            ? `${p.codigo_banco} · Banco seleccionado`
                            : "Toca para buscar banco emisor..."}
                      </Text>
                      <Text style={styles.selectorSubText}>
                        {entidad ? entidad.nombre_eb : "Selecciona la entidad bancaria del cliente"}
                      </Text>
                    </View>
                    <Ionicons name="chevron-down" size={20} color="#0B3A5C" />
                  </Pressable>

                  <Text style={styles.fieldLabel}>Cuenta bancaria destino (Empresa) *</Text>
                  <Pressable
                    style={styles.selectorTrigger}
                    onPress={() => setPickerCuentaKey(p.key)}
                  >
                    <View style={styles.selectorIconWrap}>
                      <Ionicons name="card-outline" size={20} color="#0B3A5C" />
                    </View>
                    <View style={{ flex: 1 }}>
                      <Text style={styles.selectorMainText} numberOfLines={1}>
                        {cuenta
                          ? `${cuenta.banco} ${cuenta.numero_cuenta ? `· ${cuenta.numero_cuenta}` : ""}`
                          : "Toca para seleccionar cuenta receptora..."}
                      </Text>
                      <Text style={styles.selectorSubText}>
                        {cuenta?.titular ? `Titular: ${cuenta.titular}` : "Cuenta donde cayó el pago"}
                      </Text>
                    </View>
                    <Ionicons name="chevron-down" size={20} color="#0B3A5C" />
                  </Pressable>

                  <Text style={styles.fieldLabel}>Número de referencia bancaria *</Text>
                  <TextInput
                    style={styles.standardInput}
                    placeholder="Ej. 00024895 (últimos dígitos o completa)"
                    placeholderTextColor="#94A3B8"
                    value={p.referencia}
                    onChangeText={(v) =>
                      setPagos((prev) =>
                        prev.map((x) =>
                          x.key === p.key ? { ...x, referencia: v } : x,
                        ),
                      )
                    }
                    autoCapitalize="characters"
                  />
                </View>
              ) : null}
            </View>
          );
        })}

        <Pressable style={styles.addPaymentButton} onPress={addPago}>
          <Ionicons name="add-circle-outline" size={20} color="#0B3A5C" />
          <Text style={styles.addPaymentButtonText}>+ Agregar otra forma de pago</Text>
        </Pressable>

        {/* Observaciones */}
        <View style={{ marginTop: 6 }}>
          <Text style={styles.fieldLabel}>Observaciones o notas (opcional)</Text>
          <TextInput
            style={styles.standardInput}
            value={obs}
            onChangeText={setObs}
            placeholder="Ej. Pago entregado a administración, cheque recibido, etc."
            placeholderTextColor="#94A3B8"
          />
        </View>

        {/* Caja de Cuadre y Balance Financiero */}
        <View style={styles.summaryCard}>
          <Text style={styles.summaryTitle}>Resumen de la cobranza</Text>

          <View style={styles.summaryRow}>
            <Text style={styles.summaryLabel}>Total facturas a cobrar:</Text>
            <Text style={styles.summaryValue}>
              ${formatMoney(totalCobrarUsd)}
              {tasa && tasa > 0 ? (
                <Text style={styles.summaryValueBs}> · Bs {formatMoney(convertirUsdABs(totalCobrarUsd, tasa))}</Text>
              ) : null}
            </Text>
          </View>

          <View style={styles.summaryRow}>
            <Text style={styles.summaryLabel}>Total pagos registrados:</Text>
            <Text style={[styles.summaryValue, { color: "#0B3A5C", fontWeight: "700" }]}>
              ≈ ${formatMoney(totalPagosUsd)}
              {tasa && tasa > 0 ? (
                <Text style={styles.summaryValueBs}> · Bs {formatMoney(convertirUsdABs(totalPagosUsd, tasa))}</Text>
              ) : null}
            </Text>
          </View>

          <View style={styles.summaryDivider} />

          {/* Badge de estado del balance */}
          {Math.abs(diferencia) <= 0.009 ? (
            <View style={[styles.balancePill, styles.balanceExact]}>
              <Ionicons name="checkmark-circle" size={18} color="#027A48" />
              <Text style={[styles.balanceText, { color: "#027A48" }]}>
                Montos cuadran exactamente ($0.00)
              </Text>
            </View>
          ) : diferencia > 0.009 ? (
            <View style={[styles.balancePill, styles.balanceExcess]}>
              <Ionicons name="information-circle" size={18} color="#026AA2" />
              <Text style={[styles.balanceText, { color: "#026AA2" }]}>
                Pago mayor al saldo: Generará ${formatMoney(diferencia)} de saldo a favor.
              </Text>
            </View>
          ) : (
            <View style={[styles.balancePill, styles.balancePending]}>
              <Ionicons name="alert-circle" size={18} color="#B54708" />
              <Text style={[styles.balanceText, { color: "#B54708" }]}>
                Faltan ${formatMoney(Math.abs(diferencia))} USD por cubrir.
              </Text>
            </View>
          )}
        </View>

        {/* Botón Principal para Registrar */}
        <Pressable
          style={[
            styles.submitBtn,
            (saving || totalCobrarUsd <= 0 || totalPagosUsd <= 0) && styles.submitBtnDisabled,
          ]}
          disabled={saving || totalCobrarUsd <= 0 || totalPagosUsd <= 0}
          onPress={() => void submit()}
        >
          {saving ? (
            <ActivityIndicator color="#FFFFFF" />
          ) : (
            <View style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
              <Ionicons name="checkmark-done" size={20} color="#FFFFFF" />
              <Text style={styles.submitBtnText}>
                Registrar Cobranza · ${formatMoney(totalCobrarUsd)} USD
                {tasa && tasa > 0 ? ` (Bs ${formatMoney(convertirUsdABs(totalCobrarUsd, tasa))})` : ""}
              </Text>
            </View>
          )}
        </Pressable>
      </ScrollView>

      {/* ============================================================ */}
      {/* MODAL 1: SELECCIONAR MÉTODO DE PAGO (BOTTOM SHEET OVERLAY)    */}
      {/* ============================================================ */}
      <Modal
        visible={pickerPagoKey !== null}
        animationType="fade"
        transparent
        onRequestClose={() => setPickerPagoKey(null)}
      >
        <Pressable
          style={styles.modalOverlay}
          onPress={() => setPickerPagoKey(null)}
        >
          <Pressable style={styles.modalSheet} onPress={(e) => e.stopPropagation()}>
            <View style={styles.modalHandle} />
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Seleccionar método de pago</Text>
              <Pressable onPress={() => setPickerPagoKey(null)} hitSlop={10}>
                <Ionicons name="close-circle" size={26} color="#94A3B8" />
              </Pressable>
            </View>

            <ScrollView contentContainerStyle={{ padding: 16, gap: 10 }}>
              {formas.map((item) => {
                const enBs = esFormaPagoEnBs(item.fpago_concepto);
                const currentPago = pagos.find((p) => p.key === pickerPagoKey);
                const isSelected = currentPago?.fpago_id === item.fpago_id;

                return (
                  <Pressable
                    key={item.fpago_id}
                    style={[styles.modalOptionCard, isSelected && styles.modalOptionSelected]}
                    onPress={() => onSelectPaymentMethod(pickerPagoKey!, item.fpago_id)}
                  >
                    <View style={styles.selectorIconWrap}>
                      <Ionicons
                        name={getFormaIcon(item.fpago_concepto)}
                        size={22}
                        color="#0B3A5C"
                      />
                    </View>
                    <View style={{ flex: 1 }}>
                      <Text style={styles.modalOptionTitle}>{item.fpago_concepto}</Text>
                      <Text style={styles.modalOptionSubtitle}>
                        {enBs ? "En Bolívares (Bs) a tasa oficial BCV" : "En Divisas USD ($)"}
                        {item.fpago_info ? " · Requiere banco y referencia" : ""}
                      </Text>
                    </View>
                    {isSelected ? (
                      <Ionicons name="checkmark-circle" size={22} color="#0B3A5C" />
                    ) : null}
                  </Pressable>
                );
              })}
            </ScrollView>
          </Pressable>
        </Pressable>
      </Modal>

      {/* ============================================================ */}
      {/* MODAL 2: SELECCIONAR BANCO EMISOR BCV (CON BUSCADOR)          */}
      {/* ============================================================ */}
      <Modal
        visible={pickerBancoKey !== null}
        animationType="fade"
        transparent
        onRequestClose={() => {
          setPickerBancoKey(null);
          setFiltroBanco("");
        }}
      >
        <Pressable
          style={styles.modalOverlay}
          onPress={() => {
            setPickerBancoKey(null);
            setFiltroBanco("");
          }}
        >
          <Pressable style={styles.modalSheet} onPress={(e) => e.stopPropagation()}>
            <View style={styles.modalHandle} />
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Entidad bancaria emisora (BCV)</Text>
              <Pressable
                onPress={() => {
                  setPickerBancoKey(null);
                  setFiltroBanco("");
                }}
                hitSlop={10}
              >
                <Ionicons name="close-circle" size={26} color="#94A3B8" />
              </Pressable>
            </View>

            <View style={styles.modalSearchBox}>
              <Ionicons name="search-outline" size={18} color="#64748B" />
              <TextInput
                style={styles.modalSearchInput}
                placeholder="Buscar por código (ej. 0102) o nombre..."
                placeholderTextColor="#94A3B8"
                value={filtroBanco}
                onChangeText={setFiltroBanco}
                autoCapitalize="none"
                autoCorrect={false}
              />
              {filtroBanco ? (
                <Pressable onPress={() => setFiltroBanco("")} hitSlop={8}>
                  <Ionicons name="close" size={18} color="#64748B" />
                </Pressable>
              ) : null}
            </View>

            <FlatList
              data={entidadesFiltradas}
              keyExtractor={(eb) => eb.codigo_eb}
              contentContainerStyle={{ padding: 16, gap: 8 }}
              keyboardShouldPersistTaps="handled"
              ListEmptyComponent={
                <Text style={styles.modalEmpty}>
                  {filtroBanco
                    ? `No se encontró ningún banco con «${filtroBanco}».`
                    : "No hay entidades bancarias activas."}
                </Text>
              }
              renderItem={({ item }) => {
                const currentPago = pagos.find((p) => p.key === pickerBancoKey);
                const isSelected = currentPago?.codigo_banco === item.codigo_eb;

                return (
                  <Pressable
                    style={[styles.modalOptionCard, isSelected && styles.modalOptionSelected]}
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
                    <View style={styles.codeBadge}>
                      <Text style={styles.codeBadgeText}>{item.codigo_eb}</Text>
                    </View>
                    <View style={{ flex: 1 }}>
                      <Text style={styles.modalOptionTitle}>
                        {item.nombre_corto || item.nombre_eb}
                      </Text>
                      <Text style={styles.modalOptionSubtitle} numberOfLines={1}>
                        {item.nombre_eb}
                      </Text>
                    </View>
                    {isSelected ? (
                      <Ionicons name="checkmark-circle" size={22} color="#0B3A5C" />
                    ) : null}
                  </Pressable>
                );
              }}
            />
          </Pressable>
        </Pressable>
      </Modal>

      {/* ============================================================ */}
      {/* MODAL 3: SELECCIONAR CUENTA DESTINO EMPRESA                  */}
      {/* ============================================================ */}
      <Modal
        visible={pickerCuentaKey !== null}
        animationType="fade"
        transparent
        onRequestClose={() => setPickerCuentaKey(null)}
      >
        <Pressable
          style={styles.modalOverlay}
          onPress={() => setPickerCuentaKey(null)}
        >
          <Pressable style={styles.modalSheet} onPress={(e) => e.stopPropagation()}>
            <View style={styles.modalHandle} />
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Cuenta bancaria receptora</Text>
              <Pressable onPress={() => setPickerCuentaKey(null)} hitSlop={10}>
                <Ionicons name="close-circle" size={26} color="#94A3B8" />
              </Pressable>
            </View>

            <FlatList
              data={cuentas}
              keyExtractor={(c) => c.id}
              contentContainerStyle={{ padding: 16, gap: 10 }}
              ListEmptyComponent={
                <Text style={styles.modalEmpty}>
                  No hay cuentas bancarias activas registradas en la empresa.
                </Text>
              }
              renderItem={({ item }) => {
                const currentPago = pagos.find((p) => p.key === pickerCuentaKey);
                const isSelected = currentPago?.cuenta_id === item.id;

                return (
                  <Pressable
                    style={[styles.modalOptionCard, isSelected && styles.modalOptionSelected]}
                    onPress={() => {
                      setPagos((prev) =>
                        prev.map((p) =>
                          p.key === pickerCuentaKey ? { ...p, cuenta_id: item.id } : p,
                        ),
                      );
                      setPickerCuentaKey(null);
                    }}
                  >
                    <View style={styles.selectorIconWrap}>
                      <Ionicons name="business-outline" size={20} color="#0B3A5C" />
                    </View>
                    <View style={{ flex: 1 }}>
                      <Text style={styles.modalOptionTitle}>{item.banco}</Text>
                      <Text style={styles.modalOptionSubtitle}>
                        {item.numero_cuenta ?? "—"}
                        {item.titular ? ` · ${item.titular}` : ""}
                      </Text>
                    </View>
                    {isSelected ? (
                      <Ionicons name="checkmark-circle" size={22} color="#0B3A5C" />
                    ) : null}
                  </Pressable>
                );
              }}
            />
          </Pressable>
        </Pressable>
      </Modal>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F1F5F9" },
  center: { flex: 1, alignItems: "center", justifyContent: "center", padding: 20 },
  scrollContent: { padding: 16, paddingBottom: 160, gap: 12 },

  // Header & Client Hero
  clientHero: {
    backgroundColor: "#0B3A5C",
    borderRadius: 16,
    padding: 16,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    shadowColor: "#0B3A5C",
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.15,
    shadowRadius: 8,
    elevation: 3,
  },
  clientHeroTitle: { fontSize: 18, fontWeight: "700", color: "#FFFFFF" },
  clientHeroRif: { fontSize: 13, color: "#94A3B8", marginTop: 2 },
  bcvBadge: {
    backgroundColor: "rgba(255,255,255,0.12)",
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 10,
    alignItems: "flex-end",
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.1)",
  },
  bcvBadgeLabel: { color: "#CBD5E1", fontSize: 10, fontWeight: "700", textTransform: "uppercase" },
  bcvBadgeVal: { color: "#FFFFFF", fontSize: 14, fontWeight: "700", marginTop: 1 },
  bcvBadgeDate: { color: "#94A3B8", fontSize: 9, marginTop: 1 },

  // Credit Banner & Errors
  creditBanner: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    backgroundColor: "#ECFDF5",
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: "#A7F3D0",
  },
  creditBannerText: { color: "#065F46", fontSize: 13, fontWeight: "600" },
  errorBox: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    backgroundColor: "#FEF2F2",
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: "#FCA5A5",
  },
  errorText: { color: "#B42318", fontSize: 13, flex: 1 },

  // Sections
  sectionHeaderRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    marginTop: 6,
    marginBottom: 2,
  },
  sectionTitle: { fontSize: 16, fontWeight: "700", color: "#0B3A5C" },
  quickHeaderBtn: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
    backgroundColor: "#E2E8F0",
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: 8,
  },
  quickHeaderBtnText: { color: "#0B3A5C", fontSize: 12, fontWeight: "700" },
  quickHeaderBtnClear: {
    flexDirection: "row",
    alignItems: "center",
    gap: 2,
    backgroundColor: "#F1F5F9",
    paddingHorizontal: 8,
    paddingVertical: 5,
    borderRadius: 8,
  },
  quickHeaderBtnClearText: { color: "#64748B", fontSize: 12, fontWeight: "600" },

  // Order Cards
  orderCard: {
    backgroundColor: "#FFFFFF",
    borderRadius: 14,
    padding: 14,
    borderWidth: 1.5,
    borderColor: "#E2E8F0",
    gap: 12,
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.05,
    shadowRadius: 4,
    elevation: 2,
  },
  orderCardSelected: {
    borderColor: "#0B3A5C",
    backgroundColor: "#F8FAFC",
  },
  orderTopRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  orderHeaderPressable: {
    flexDirection: "row",
    alignItems: "center",
    gap: 10,
    flex: 1,
  },
  orderNumber: { fontSize: 16, fontWeight: "700", color: "#0F172A" },
  orderDate: { fontSize: 12, color: "#64748B", marginTop: 2 },
  orderVencida: { color: "#DC2626", fontWeight: "600" },
  orderAmount: { fontSize: 17, fontWeight: "700", color: "#0B3A5C" },
  orderAmountBs: { fontSize: 12, color: "#64748B", fontWeight: "500", marginTop: 1 },

  selectedBadge: {
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 6,
  },
  badgeTotal: { backgroundColor: "#DBEAFE" },
  badgeTotalText: { color: "#1D4ED8", fontSize: 10, fontWeight: "700" },
  badgePartial: { backgroundColor: "#FEF3C7" },
  badgePartialText: { color: "#B45309", fontSize: 10, fontWeight: "700" },

  // Estado No Seleccionado: Botones de Acción Inmediata
  orderUnselectedActions: {
    flexDirection: "row",
    gap: 8,
    borderTopWidth: 1,
    borderTopColor: "#F1F5F9",
    paddingTop: 10,
  },
  cobrarTotalPrimaryBtn: {
    flex: 1.5,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 6,
    backgroundColor: "#0B3A5C",
    borderRadius: 10,
    paddingVertical: 9,
    shadowColor: "#0B3A5C",
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.15,
    shadowRadius: 4,
    elevation: 2,
  },
  cobrarTotalPrimaryBtnText: {
    color: "#FFFFFF",
    fontWeight: "700",
    fontSize: 13,
  },
  abonoParcialSecondaryBtn: {
    flex: 1,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 4,
    backgroundColor: "#F1F5F9",
    borderRadius: 10,
    paddingVertical: 9,
    borderWidth: 1,
    borderColor: "#CBD5E1",
  },
  abonoParcialSecondaryBtnText: {
    color: "#0B3A5C",
    fontWeight: "600",
    fontSize: 13,
  },

  // Estado Seleccionado: Segmented Controls
  orderActionsContainer: {
    borderTopWidth: 1,
    borderTopColor: "#E2E8F0",
    paddingTop: 10,
    gap: 10,
  },
  segmentedButtons: {
    flexDirection: "row",
    backgroundColor: "#E2E8F0",
    borderRadius: 10,
    padding: 3,
    gap: 4,
  },
  segmentBtn: {
    flex: 1,
    paddingVertical: 8,
    alignItems: "center",
    borderRadius: 8,
  },
  segmentBtnActive: {
    backgroundColor: "#0B3A5C",
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 3,
    elevation: 2,
  },
  segmentBtnText: { fontSize: 12, fontWeight: "600", color: "#475569" },
  segmentBtnTextActive: { color: "#FFFFFF" },
  segmentBtnDeselect: {
    flexDirection: "row",
    alignItems: "center",
    gap: 3,
    paddingHorizontal: 8,
    paddingVertical: 8,
    borderRadius: 8,
  },
  segmentBtnDeselectText: { fontSize: 12, fontWeight: "600", color: "#DC2626" },

  // Abono Parcial Input
  partialInputWrapper: {
    backgroundColor: "#FFFFFF",
    borderRadius: 10,
    borderWidth: 1,
    borderColor: "#CBD5E1",
    padding: 10,
    gap: 6,
  },
  partialInputHeader: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  partialInputLabel: { fontSize: 12, color: "#475569", fontWeight: "600" },
  partialBsEquiv: { fontSize: 12, color: "#0B3A5C", fontWeight: "700" },
  inputWithPrefix: {
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: "#F8FAFC",
    borderRadius: 8,
    borderWidth: 1,
    borderColor: "#CBD5E1",
    paddingHorizontal: 12,
  },
  inputCurrencyPrefix: { fontSize: 16, fontWeight: "700", color: "#0B3A5C", marginRight: 6 },
  partialInput: {
    flex: 1,
    fontSize: 16,
    fontWeight: "700",
    color: "#0F172A",
    paddingVertical: 8,
  },
  excessBadge: { fontSize: 11, color: "#026AA2", fontStyle: "italic", marginTop: 2 },

  // ============================================================
  // TOTALIZADOR CARD
  // ============================================================
  totalizerCard: {
    backgroundColor: "#0B3A5C",
    borderRadius: 16,
    padding: 16,
    gap: 12,
    shadowColor: "#0B3A5C",
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.25,
    shadowRadius: 10,
    elevation: 4,
    marginTop: 4,
  },
  totalizerTopRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  totalizerIconBadge: {
    width: 32,
    height: 32,
    borderRadius: 8,
    backgroundColor: "rgba(255,255,255,0.15)",
    alignItems: "center",
    justifyContent: "center",
  },
  totalizerTitle: { fontSize: 16, fontWeight: "700", color: "#FFFFFF" },
  totalizerSubtitle: { fontSize: 11, color: "#94A3B8" },
  totalizerBcvPill: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
    backgroundColor: "rgba(255,255,255,0.12)",
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 8,
  },
  totalizerBcvPillText: { color: "#FFFFFF", fontSize: 11, fontWeight: "700" },
  totalizerAmountRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    backgroundColor: "rgba(0,0,0,0.18)",
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderRadius: 12,
  },
  totalizerCurrencyLabel: { fontSize: 11, color: "#94A3B8", fontWeight: "600", textTransform: "uppercase" },
  totalizerUsdText: { fontSize: 20, fontWeight: "800", color: "#34D399", marginTop: 2 },
  totalizerBsText: { fontSize: 18, fontWeight: "800", color: "#FCD34D", marginTop: 2 },
  totalizerVerticalDivider: { width: 1, height: 32, backgroundColor: "rgba(255,255,255,0.15)" },

  // ============================================================
  // PAGOS
  // ============================================================
  paymentCard: {
    backgroundColor: "#FFFFFF",
    borderRadius: 16,
    padding: 16,
    borderWidth: 1.5,
    borderColor: "#CBD5E1",
    gap: 10,
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.05,
    shadowRadius: 6,
    elevation: 3,
  },
  paymentCardHeader: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    borderBottomWidth: 1,
    borderBottomColor: "#F1F5F9",
    paddingBottom: 8,
  },
  paymentCardIndex: { fontSize: 14, fontWeight: "700", color: "#0B3A5C" },
  currencyPill: {
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 6,
  },
  currencyPillText: {
    fontSize: 11,
    fontWeight: "700",
  },
  pillBs: { backgroundColor: "#FEF3C7" },
  pillBsText: { color: "#B45309", fontSize: 11, fontWeight: "700" },
  pillUsd: { backgroundColor: "#DCFCE7" },
  pillUsdText: { color: "#15803D", fontSize: 11, fontWeight: "700" },
  deletePaymentBtn: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
    paddingVertical: 4,
    paddingHorizontal: 6,
  },
  deletePaymentText: { color: "#B42318", fontSize: 12, fontWeight: "600" },

  // Form Fields & Selectors
  fieldLabel: {
    fontSize: 12,
    fontWeight: "600",
    color: "#475569",
    textTransform: "uppercase",
    marginBottom: 4,
  },
  selectorTrigger: {
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: "#F8FAFC",
    borderWidth: 1.5,
    borderColor: "#CBD5E1",
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
    gap: 10,
  },
  selectorIconWrap: {
    width: 36,
    height: 36,
    borderRadius: 10,
    backgroundColor: "#E2E8F0",
    alignItems: "center",
    justifyContent: "center",
  },
  selectorMainText: { fontSize: 14, fontWeight: "700", color: "#0B3A5C" },
  selectorSubText: { fontSize: 11, color: "#64748B", marginTop: 1 },

  fillRemainingText: {
    fontSize: 12,
    fontWeight: "600",
    color: "#0284C7",
    marginBottom: 4,
  },
  amountInput: {
    flex: 1,
    fontSize: 18,
    fontWeight: "700",
    color: "#0F172A",
    paddingVertical: 10,
  },
  conversionHelperRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 4,
    marginTop: 4,
  },
  conversionHelper: {
    fontSize: 12,
    color: "#0B3A5C",
    fontWeight: "600",
  },
  bankFieldsGroup: {
    backgroundColor: "#F8FAFC",
    padding: 12,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: "#E2E8F0",
    gap: 10,
    marginTop: 4,
  },
  standardInput: {
    backgroundColor: "#FFFFFF",
    borderWidth: 1.5,
    borderColor: "#CBD5E1",
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 12,
    fontSize: 15,
    color: "#0F172A",
  },

  // Add Payment Button
  addPaymentButton: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 8,
    backgroundColor: "#FFFFFF",
    borderWidth: 1.5,
    borderColor: "#0B3A5C",
    borderRadius: 12,
    paddingVertical: 13,
  },
  addPaymentButtonText: {
    color: "#0B3A5C",
    fontWeight: "700",
    fontSize: 14,
  },

  // Summary Card
  summaryCard: {
    backgroundColor: "#FFFFFF",
    borderRadius: 16,
    padding: 16,
    borderWidth: 1,
    borderColor: "#E2E8F0",
    gap: 8,
    marginTop: 6,
  },
  summaryTitle: { fontSize: 15, fontWeight: "700", color: "#0B3A5C", marginBottom: 4 },
  summaryRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  summaryLabel: { fontSize: 14, color: "#64748B" },
  summaryValue: { fontSize: 15, fontWeight: "600", color: "#0F172A" },
  summaryValueBs: { fontSize: 13, color: "#64748B", fontWeight: "500" },
  summaryDivider: { height: 1, backgroundColor: "#F1F5F9", marginVertical: 4 },

  balancePill: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 8,
  },
  balanceExact: { backgroundColor: "#ECFDF5" },
  balanceExcess: { backgroundColor: "#F0F9FF" },
  balancePending: { backgroundColor: "#FFFBEB" },
  balanceText: { fontSize: 12, fontWeight: "600", flex: 1 },

  // Submit Button
  submitBtn: {
    backgroundColor: "#0B3A5C",
    borderRadius: 14,
    paddingVertical: 16,
    alignItems: "center",
    justifyContent: "center",
    shadowColor: "#0B3A5C",
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.25,
    shadowRadius: 10,
    elevation: 5,
    marginTop: 4,
  },
  submitBtnDisabled: { opacity: 0.5 },
  submitBtnText: { color: "#FFFFFF", fontWeight: "700", fontSize: 15 },

  // Empty State
  emptyCard: {
    backgroundColor: "#FFFFFF",
    borderRadius: 16,
    padding: 24,
    alignItems: "center",
    justifyContent: "center",
    gap: 6,
    borderWidth: 1,
    borderColor: "#E2E8F0",
  },
  emptyTitle: { fontSize: 18, fontWeight: "700", color: "#027A48" },
  emptySubtitle: { fontSize: 13, color: "#64748B", textAlign: "center" },

  // Modales (Bottom Sheets)
  modalOverlay: {
    flex: 1,
    backgroundColor: "rgba(15, 23, 42, 0.65)",
    justifyContent: "flex-end",
  },
  modalSheet: {
    backgroundColor: "#FFFFFF",
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    maxHeight: "82%",
    paddingBottom: 24,
  },
  modalHandle: {
    width: 44,
    height: 5,
    borderRadius: 3,
    backgroundColor: "#CBD5E1",
    alignSelf: "center",
    marginTop: 10,
  },
  modalHeader: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    paddingHorizontal: 18,
    paddingVertical: 14,
    borderBottomWidth: 1,
    borderBottomColor: "#F1F5F9",
  },
  modalTitle: { fontSize: 16, fontWeight: "700", color: "#0B3A5C" },
  modalSearchBox: {
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: "#F1F5F9",
    marginHorizontal: 16,
    marginTop: 12,
    paddingHorizontal: 12,
    borderRadius: 10,
    gap: 8,
  },
  modalSearchInput: {
    flex: 1,
    paddingVertical: 10,
    fontSize: 14,
    color: "#0F172A",
  },
  modalOptionCard: {
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: "#F8FAFC",
    padding: 14,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: "#E2E8F0",
    gap: 12,
  },
  modalOptionSelected: {
    borderColor: "#0B3A5C",
    backgroundColor: "#F0F9FF",
  },
  modalOptionTitle: { fontSize: 14, fontWeight: "700", color: "#0F172A" },
  modalOptionSubtitle: { fontSize: 12, color: "#64748B", marginTop: 2 },
  modalEmpty: { color: "#64748B", textAlign: "center", paddingVertical: 24, fontSize: 13 },
  codeBadge: {
    backgroundColor: "#0B3A5C",
    paddingHorizontal: 8,
    paddingVertical: 6,
    borderRadius: 6,
  },
  codeBadgeText: { color: "#FFFFFF", fontWeight: "700", fontSize: 12, fontFamily: "monospace" },
});
