import { useEffect, useMemo, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  Pressable,
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  TextInput,
  View,
} from "react-native";
import { useRouter } from "expo-router";
import { useAuth } from "@/lib/auth-context";
import { buscarClientesForProfile, type ClienteListaItem } from "@/lib/clientes";
import { retornaUltimaTasa } from "@/lib/catalogos";
import { listarProductos, precioNeto, type ProductoLista } from "@/lib/productos";
import { crearVentaDirectaAlmacen, puedeVentaDirecta } from "@/lib/venta-directa";
import { obtenerSaldosEnvasesCliente, type SaldoEnvaseCliente } from "@/lib/contenedores";
import { calcularEnvasesEntregados, textoResumenEnvases } from "@/lib/envases-venta";
import { formatMoney, formatNumber } from "@/lib/format";
import { EmptyState, ErrorText, PrimaryButton, SectionTitle } from "@/components/ui";

type Linea = {
  producto: ProductoLista;
  cantidad: string;
  precio: number;
};

export default function VentaDirectaScreen() {
  const router = useRouter();
  const { profile } = useAuth();
  const [tasa, setTasa] = useState<number | null>(null);
  const [saving, setSaving] = useState(false);
  const [esCortesia, setEsCortesia] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [busquedaCliente, setBusquedaCliente] = useState("");
  const [clientes, setClientes] = useState<ClienteListaItem[]>([]);
  const [cliente, setCliente] = useState<ClienteListaItem | null>(null);

  const [busquedaProducto, setBusquedaProducto] = useState("");
  const [productos, setProductos] = useState<ProductoLista[]>([]);
  const [buscandoProductos, setBuscandoProductos] = useState(false);
  const [lineas, setLineas] = useState<Linea[]>([]);
  const [envases, setEnvases] = useState<SaldoEnvaseCliente[]>([]);
  const [envasesLoading, setEnvasesLoading] = useState(false);
  const [retirados, setRetirados] = useState<Record<string, string>>({});

  const entregados = useMemo(
    () =>
      calcularEnvasesEntregados(
        lineas.map((l) => ({
          cantidad: Number(l.cantidad) || 0,
          contenedor_id: l.producto.contenedor_id,
          unidades_por_contenedor: l.producto.unidades_por_contenedor,
        })),
      ),
    [lineas],
  );

  useEffect(() => {
    if (!cliente) {
      setEnvases([]);
      return;
    }
    let cancelled = false;
    setEnvasesLoading(true);
    void obtenerSaldosEnvasesCliente(cliente.id).then((res) => {
      if (cancelled) return;
      setEnvasesLoading(false);
      if (res.ok) setEnvases(res.envases);
      else setError(res.error);
    });
    return () => {
      cancelled = true;
    };
  }, [cliente]);

  useEffect(() => {
    void retornaUltimaTasa().then((res) => {
      if (res.ok) setTasa(res.tasa);
    });
  }, []);

  useEffect(() => {
    if (!profile || cliente) return;
    const texto = busquedaCliente;
    const t = setTimeout(() => {
      void buscarClientesForProfile(profile, texto).then((res) => {
        setClientes(res.ok ? res.clientes : []);
      });
    }, 300);
    return () => clearTimeout(t);
  }, [busquedaCliente, profile, cliente]);

  useEffect(() => {
    const q = busquedaProducto.trim();
    if (!cliente || q.length < 2) {
      setProductos([]);
      return;
    }
    const t = setTimeout(() => {
      setBuscandoProductos(true);
      void listarProductos(q, cliente.id).then((res) => {
        setBuscandoProductos(false);
        setProductos(res.ok ? res.productos.slice(0, 15) : []);
        if (!res.ok) setError(res.error);
      });
    }, 300);
    return () => clearTimeout(t);
  }, [busquedaProducto, cliente]);

  function seleccionarCliente(c: ClienteListaItem | null) {
    setCliente(c);
    setBusquedaCliente("");
    setClientes([]);
    setLineas([]);
    setBusquedaProducto("");
    setRetirados({});
  }

  function editarCantidad(index: number, valor: string) {
    setLineas((prev) =>
      prev.map((l, i) => (i === index ? { ...l, cantidad: valor.replace(/\D/g, "") } : l)),
    );
  }

  const total = esCortesia ? 0 : lineas.reduce((s, l) => s + (Number(l.cantidad) || 0) * l.precio, 0);

  async function registrar() {
    if (!profile || !cliente) return;
    setSaving(true);
    const res = await crearVentaDirectaAlmacen({
      vendedorId: profile.id,
      clienteId: cliente.id,
      tasaCambio: tasa,
      esCortesia,
      lineas: lineas.map((l) => ({
        producto_id: l.producto.id,
        cantidad: Number(l.cantidad),
        valor_unitario_usd: l.precio,
      })),
      retirados: Object.entries(retirados).map(([contenedor_id, v]) => ({
        contenedor_id,
        cantidad_retirada: Number(v) || 0,
      })),
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert(
      "Venta registrada",
      [
        `Orden #${res.venta.correlativo ?? "—"} por $${formatMoney(res.venta.totalUsd)}. Queda por liquidar hasta registrar el cobro.`,
        textoResumenEnvases(res.venta.contenedores),
      ]
        .filter(Boolean)
        .join("\n\n"),
      [
        {
          text: "Ver orden",
          onPress: () =>
            router.replace({ pathname: "/(app)/ordenes/[id]", params: { id: res.venta.ordenId } }),
        },
      ],
    );
  }

  function onGuardar() {
    setError(null);
    if (!cliente) return setError("Selecciona un cliente.");
    if (!lineas.length) return setError("Agrega al menos un producto.");
    for (const l of lineas) {
      const cant = Number(l.cantidad) || 0;
      if (cant <= 0) return setError(`${l.producto.nombre}: indica la cantidad.`);
      if (cant > l.producto.stock_disponible) {
        return setError(
          `${l.producto.nombre}: solo hay ${formatNumber(l.producto.stock_disponible)} en almacén.`,
        );
      }
    }
    const excedidos = envases.filter(
      (e) => (Number(retirados[e.contenedor_id]) || 0) > e.saldo + (entregados[e.contenedor_id] ?? 0),
    );
    Alert.alert(
      "Registrar venta",
      `${cliente.razon_social} por $${formatMoney(total)}. Se descontará del almacén.${
        excedidos.length
          ? `\n\nLos retirados superan el saldo en: ${excedidos.map((e) => e.nombre).join(", ")}. El saldo quedará en 0.`
          : ""
      }\n\n¿Continuar?`,
      [
        { text: "Cancelar", style: "cancel" },
        { text: "Registrar", onPress: () => void registrar() },
      ],
    );
  }

  if (!puedeVentaDirecta(profile?.rol)) {
    return (
      <View style={styles.root}>
        <EmptyState message="No tienes permiso para registrar ventas directas." />
      </View>
    );
  }

  return (
    <ScrollView
      style={styles.root}
      contentContainerStyle={{ padding: 16, paddingBottom: 48 }}
      keyboardShouldPersistTaps="handled"
    >
      <Text style={styles.hint}>
        Venta en mostrador: descuenta del almacén, sin camión ni radar.
        {tasa != null ? ` Tasa: ${formatMoney(tasa)}.` : " Sin tasa registrada."}
      </Text>

      <SectionTitle>Cliente</SectionTitle>
      {cliente ? (
        <Pressable style={styles.seleccion} onPress={() => seleccionarCliente(null)}>
          <Text style={styles.seleccionText}>{cliente.razon_social}</Text>
          <Text style={styles.quitar}>Cambiar</Text>
        </Pressable>
      ) : (
        <>
          <TextInput
            style={styles.input}
            placeholder="Buscar por nombre o RIF (mín. 2 letras)"
            placeholderTextColor="#9AA6B2"
            value={busquedaCliente}
            onChangeText={setBusquedaCliente}
          />
          {busquedaCliente.trim().length >= 2
            ? clientes.map((c) => (
                <Pressable key={c.id} style={styles.option} onPress={() => seleccionarCliente(c)}>
                  <Text style={styles.optionText}>{c.razon_social}</Text>
                  <Text style={styles.optionHint}>{c.rif_nit}</Text>
                </Pressable>
              ))
            : null}
        </>
      )}

      {cliente ? (
        <View style={styles.switchContainer}>
          <Text style={styles.switchLabel}>Marcar como orden de cortesía ($0.00)</Text>
          <Switch
            value={esCortesia}
            onValueChange={setEsCortesia}
            trackColor={{ false: "#D0D7DE", true: "#34C759" }}
            thumbColor="#fff"
          />
        </View>
      ) : null}

      {cliente ? (
        <>
          <SectionTitle>Productos</SectionTitle>
          <TextInput
            style={styles.input}
            placeholder="Buscar producto (mín. 2 letras)"
            placeholderTextColor="#9AA6B2"
            value={busquedaProducto}
            onChangeText={setBusquedaProducto}
          />
          {buscandoProductos ? <ActivityIndicator color="#0B3A5C" /> : null}
          {productos
            .filter((p) => !lineas.some((l) => l.producto.id === p.id))
            .map((p) => {
              const sinStock = p.stock_disponible <= 0;
              return (
                <Pressable
                  key={p.id}
                  style={[styles.option, sinStock && styles.optionDisabled]}
                  disabled={sinStock}
                  onPress={() => {
                    setLineas((prev) => [...prev, { producto: p, cantidad: "1", precio: precioNeto(p) }]);
                    setBusquedaProducto("");
                  }}
                >
                  <Text style={styles.optionText}>{p.nombre}</Text>
                  <Text style={styles.optionHint}>
                    ${formatMoney(precioNeto(p))} · Disp. {formatNumber(p.stock_disponible)}
                  </Text>
                </Pressable>
              );
            })}

          {lineas.map((l, i) => {
            const cant = Number(l.cantidad) || 0;
            const excede = cant > l.producto.stock_disponible;
            return (
              <View key={l.producto.id} style={styles.linea}>
                <View style={styles.lineaHeader}>
                  <Text style={styles.lineaTitulo}>{l.producto.nombre}</Text>
                  <Pressable
                    onPress={() => setLineas((prev) => prev.filter((_, j) => j !== i))}
                    hitSlop={8}
                  >
                    <Text style={styles.quitar}>Quitar</Text>
                  </Pressable>
                </View>
                <Text style={[styles.hint, excede && styles.excede]}>
                  Disponible: {formatNumber(l.producto.stock_disponible)} · ${formatMoney(esCortesia ? 0 : l.precio)} c/u
                </Text>
                <View style={styles.lineaCampos}>
                  <View style={{ flex: 1 }}>
                    <Text style={styles.campoLabel}>Cantidad</Text>
                    <TextInput
                      style={[styles.input, excede && styles.inputExcede]}
                      keyboardType="number-pad"
                      value={l.cantidad}
                      onChangeText={(v) => editarCantidad(i, v)}
                    />
                  </View>
                  <View style={{ flex: 1 }}>
                    <Text style={styles.campoLabel}>Subtotal</Text>
                    <Text style={styles.subtotal}>${formatMoney(esCortesia ? 0 : cant * l.precio)}</Text>
                  </View>
                </View>
              </View>
            );
          })}
          {lineas.length ? <Text style={styles.total}>Total ${formatMoney(total)}</Text> : null}

          <SectionTitle>Envases</SectionTitle>
          <Text style={styles.hint}>
            Los entregados se calculan con los productos. Indica solo los vacíos que devuelve el
            cliente.
          </Text>
          {envasesLoading ? (
            <ActivityIndicator color="#0B3A5C" />
          ) : envases.length === 0 ? (
            <Text style={styles.hint}>No hay tipos de envase registrados.</Text>
          ) : (
            envases.map((e) => {
              const ent = entregados[e.contenedor_id] ?? 0;
              const ret = Number(retirados[e.contenedor_id]) || 0;
              const saldoActual = Math.max(0, e.saldo + ent - ret);
              return (
                <View key={e.contenedor_id} style={styles.linea}>
                  <Text style={styles.lineaTitulo}>
                    {e.codigo ? `${e.codigo} · ` : ""}
                    {e.nombre}
                  </Text>
                  <Text style={styles.hint}>Saldo anterior: {formatNumber(e.saldo)}</Text>
                  <View style={styles.lineaCampos}>
                    <View style={{ flex: 1 }}>
                      <Text style={styles.campoLabel}>Entregados</Text>
                      <Text style={styles.subtotal}>{formatNumber(ent)}</Text>
                    </View>
                    <View style={{ flex: 1 }}>
                      <Text style={styles.campoLabel}>Retirados</Text>
                      <TextInput
                        style={styles.input}
                        keyboardType="number-pad"
                        placeholder="0"
                        placeholderTextColor="#9AA6B2"
                        value={retirados[e.contenedor_id] ?? ""}
                        onChangeText={(v) =>
                          setRetirados((prev) => ({
                            ...prev,
                            [e.contenedor_id]: v.replace(/\D/g, "").slice(0, 6),
                          }))
                        }
                      />
                    </View>
                  </View>
                  <Text style={[styles.subtotal, ret > e.saldo + ent && styles.excede]}>
                    Saldo actual: {formatNumber(saldoActual)}
                  </Text>
                </View>
              );
            })
          )}
        </>
      ) : null}

      <ErrorText message={error} />
      <PrimaryButton label="Registrar venta" loading={saving} onPress={onGuardar} />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F6F8" },
  input: {
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 15,
    color: "#0B3A5C",
    marginBottom: 8,
  },
  inputExcede: { borderColor: "#C62828" },
  option: {
    backgroundColor: "#fff",
    padding: 12,
    borderBottomWidth: 1,
    borderBottomColor: "#E5EAF0",
  },
  optionDisabled: { opacity: 0.45 },
  optionText: { color: "#0B3A5C", fontWeight: "600" },
  optionHint: { color: "#5B6B7C", fontSize: 12, marginTop: 2 },
  seleccion: {
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 12,
    padding: 12,
    marginBottom: 8,
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  seleccionText: { color: "#0B3A5C", fontWeight: "600", flexShrink: 1 },
  quitar: { color: "#C62828", fontWeight: "600" },
  hint: { color: "#5B6B7C", fontSize: 13, marginBottom: 6 },
  excede: { color: "#C62828", fontWeight: "600" },
  linea: {
    backgroundColor: "#fff",
    borderRadius: 12,
    borderWidth: 1,
    borderColor: "#E5EAF0",
    padding: 12,
    marginTop: 8,
  },
  lineaHeader: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    gap: 8,
  },
  lineaTitulo: { color: "#0B3A5C", fontWeight: "700", flexShrink: 1 },
  lineaCampos: { flexDirection: "row", gap: 8, marginTop: 4 },
  campoLabel: { color: "#5B6B7C", fontSize: 12, marginBottom: 4 },
  subtotal: { color: "#0B3A5C", fontWeight: "700", fontSize: 15, paddingVertical: 10 },
  total: {
    color: "#0B3A5C",
    fontWeight: "700",
    fontSize: 16,
    textAlign: "right",
    marginVertical: 10,
  },
  switchContainer: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#E5EAF0",
    borderRadius: 12,
    padding: 12,
    marginTop: 8,
    marginBottom: 8,
  },
  switchLabel: { color: "#0B3A5C", fontWeight: "600", flex: 1, marginRight: 8 },
});
