import { useEffect, useMemo, useState } from "react";
import {
  Alert,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { useRouter } from "expo-router";
import { useAuth } from "@/lib/auth-context";
import { buscarClientesForProfile, type ClienteListaItem } from "@/lib/clientes";
import {
  MOVIMIENTO_CONCEPTOS,
  cargarDatosMovimiento,
  puedeMovimientosEspeciales,
  registrarMovimientoEspecial,
  type DatosMovimiento,
  type MovimientoInventario,
  type MovimientoTipo,
} from "@/lib/movimientos-inventario";
import { formatMoney, formatNumber } from "@/lib/format";
import {
  EmptyState,
  ErrorText,
  FormField,
  LoadingBlock,
  OptionChips,
  PrimaryButton,
  SectionTitle,
} from "@/components/ui";

type Linea = { productoId: string; cantidad: string; costo: string };

function normalizar(texto: string): string {
  return texto
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim();
}

function decimal(valor: string): number {
  const n = Number(valor.replace(",", "."));
  return Number.isFinite(n) ? n : NaN;
}

export default function NuevoMovimientoInventarioScreen() {
  const router = useRouter();
  const { profile } = useAuth();
  const [datos, setDatos] = useState<DatosMovimiento | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [tipo, setTipo] = useState<MovimientoTipo>("SALIDA");
  const [inventario, setInventario] = useState<MovimientoInventario>("ALMACEN");
  const [camionId, setCamionId] = useState("");
  const [concepto, setConcepto] = useState(MOVIMIENTO_CONCEPTOS[0].value);
  const [conceptoOtro, setConceptoOtro] = useState("");
  const [observaciones, setObservaciones] = useState("");
  const [lineas, setLineas] = useState<Linea[]>([]);
  const [busquedaProducto, setBusquedaProducto] = useState("");

  const [busquedaCliente, setBusquedaCliente] = useState("");
  const [clientes, setClientes] = useState<ClienteListaItem[]>([]);
  const [cliente, setCliente] = useState<ClienteListaItem | null>(null);

  useEffect(() => {
    void (async () => {
      const res = await cargarDatosMovimiento();
      if (!res.ok) setError(res.error);
      else setDatos(res.datos);
      setLoading(false);
    })();
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

  const nombres = useMemo(
    () => Object.fromEntries((datos?.productos ?? []).map((p) => [p.id, p.nombre])),
    [datos],
  );

  const resultadosProducto = useMemo(() => {
    const q = normalizar(busquedaProducto);
    if (!datos || q.length < 2) return [];
    return datos.productos
      .filter(
        (p) =>
          !lineas.some((l) => l.productoId === p.id) &&
          (normalizar(p.nombre).includes(q) || normalizar(p.codigo ?? "").includes(q)),
      )
      .slice(0, 15);
  }, [busquedaProducto, datos, lineas]);

  function disponible(productoId: string): number {
    if (!datos) return 0;
    if (inventario === "ALMACEN") return datos.stockAlmacen[productoId] ?? 0;
    return datos.stockMovil[camionId]?.[productoId] ?? 0;
  }

  function editarLinea(index: number, cambio: Partial<Linea>) {
    setLineas((prev) => prev.map((l, i) => (i === index ? { ...l, ...cambio } : l)));
  }

  const totalCosto = lineas.reduce((s, l) => {
    const c = decimal(l.costo);
    return s + (Number(l.cantidad) || 0) * (Number.isFinite(c) ? c : 0);
  }, 0);

  async function registrar(
    conceptoFinal: string,
    detalles: Array<{ producto_id: string; cantidad: number; costo_unitario: number }>,
  ) {
    setSaving(true);
    const res = await registrarMovimientoEspecial({
      tipo,
      concepto: conceptoFinal,
      inventario,
      camionId: inventario === "MOVIL" ? camionId : null,
      clienteId: cliente?.id ?? null,
      observaciones,
      detalles,
      nombresProducto: nombres,
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert("Listo", "Movimiento registrado.");
    router.back();
  }

  function onGuardar() {
    setError(null);
    const conceptoFinal = concepto === "OTRO" ? conceptoOtro.trim() : concepto;
    if (!conceptoFinal) return setError("Indica el concepto del movimiento.");
    if (inventario === "MOVIL" && !camionId) return setError("Selecciona el camión.");
    const detalles = lineas
      .map((l) => ({
        producto_id: l.productoId,
        cantidad: Number(l.cantidad) || 0,
        costo_unitario: decimal(l.costo),
      }))
      .filter((d) => d.cantidad > 0);
    if (!detalles.length) {
      return setError("Agrega al menos un producto con cantidad mayor a 0.");
    }
    if (detalles.some((d) => !(d.costo_unitario >= 0))) {
      return setError("Revisa los costos unitarios: deben ser números mayores o iguales a 0.");
    }
    if (tipo === "SALIDA") {
      const excede = detalles.find((d) => d.cantidad > disponible(d.producto_id));
      if (excede) {
        return setError(
          `${nombres[excede.producto_id] ?? "Producto"}: solo hay ${formatNumber(disponible(excede.producto_id))} disponible(s).`,
        );
      }
    }
    const destino =
      inventario === "ALMACEN"
        ? "el almacén"
        : `el camión ${datos?.camiones.find((c) => c.id === camionId)?.placa ?? ""}`;
    const unidades = detalles.reduce((s, d) => s + d.cantidad, 0);
    Alert.alert(
      tipo === "ENTRADA" ? "Registrar entrada" : "Registrar salida",
      `${formatNumber(unidades)} unidad(es) en ${destino}. ¿Continuar?`,
      [
        { text: "Cancelar", style: "cancel" },
        { text: "Registrar", onPress: () => void registrar(conceptoFinal, detalles) },
      ],
    );
  }

  if (!puedeMovimientosEspeciales(profile?.rol)) {
    return (
      <View style={styles.root}>
        <EmptyState message="Solo admin o gerente pueden registrar movimientos especiales." />
      </View>
    );
  }
  if (loading) return <LoadingBlock />;

  return (
    <ScrollView
      style={styles.root}
      contentContainerStyle={{ padding: 16, paddingBottom: 48 }}
      keyboardShouldPersistTaps="handled"
    >
      <OptionChips
        label="Tipo de movimiento"
        options={[
          { value: "SALIDA", label: "Salida" },
          { value: "ENTRADA", label: "Entrada" },
        ]}
        value={tipo}
        onChange={(v) => setTipo(v as MovimientoTipo)}
      />
      <OptionChips
        label="Inventario afectado"
        options={[
          { value: "ALMACEN", label: "Almacén" },
          { value: "MOVIL", label: "Camión" },
        ]}
        value={inventario}
        onChange={(v) => setInventario(v as MovimientoInventario)}
      />
      {inventario === "MOVIL" ? (
        <OptionChips
          label="Camión"
          options={(datos?.camiones ?? []).map((c) => ({ value: c.id, label: c.placa }))}
          value={camionId}
          onChange={setCamionId}
        />
      ) : null}
      <OptionChips
        label="Concepto"
        options={[...MOVIMIENTO_CONCEPTOS, { value: "OTRO", label: "Otro…" }]}
        value={concepto}
        onChange={setConcepto}
      />
      {concepto === "OTRO" ? (
        <FormField
          label="Concepto"
          value={conceptoOtro}
          onChangeText={setConceptoOtro}
          maxLength={100}
        />
      ) : null}

      <SectionTitle>Cliente (opcional)</SectionTitle>
      {cliente ? (
        <Pressable style={styles.seleccion} onPress={() => setCliente(null)}>
          <Text style={styles.seleccionText}>{cliente.razon_social}</Text>
          <Text style={styles.quitar}>Quitar</Text>
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
                <Pressable
                  key={c.id}
                  style={styles.option}
                  onPress={() => {
                    setCliente(c);
                    setBusquedaCliente("");
                    setClientes([]);
                  }}
                >
                  <Text style={styles.optionText}>{c.razon_social}</Text>
                  <Text style={styles.optionHint}>{c.rif_nit}</Text>
                </Pressable>
              ))
            : null}
        </>
      )}

      <SectionTitle>Productos</SectionTitle>
      {inventario === "MOVIL" && !camionId ? (
        <Text style={styles.hint}>Selecciona el camión para ver su disponible.</Text>
      ) : null}
      <TextInput
        style={styles.input}
        placeholder="Buscar producto (mín. 2 letras)"
        placeholderTextColor="#9AA6B2"
        value={busquedaProducto}
        onChangeText={setBusquedaProducto}
      />
      {resultadosProducto.map((p) => (
        <Pressable
          key={p.id}
          style={styles.option}
          onPress={() => {
            setLineas((prev) => [
              ...prev,
              {
                productoId: p.id,
                cantidad: "",
                costo: String(datos?.ultimoCosto[p.id] ?? 0),
              },
            ]);
            setBusquedaProducto("");
          }}
        >
          <Text style={styles.optionText}>{p.nombre}</Text>
          <Text style={styles.optionHint}>
            {p.codigo ? `${p.codigo} · ` : ""}Disp. {formatNumber(disponible(p.id))}
          </Text>
        </Pressable>
      ))}

      {lineas.map((l, i) => {
        const cant = Number(l.cantidad) || 0;
        const disp = disponible(l.productoId);
        const excede = tipo === "SALIDA" && cant > disp;
        return (
          <View key={l.productoId} style={styles.linea}>
            <View style={styles.lineaHeader}>
              <Text style={styles.lineaTitulo}>{nombres[l.productoId] ?? "Producto"}</Text>
              <Pressable
                onPress={() => setLineas((prev) => prev.filter((_, j) => j !== i))}
                hitSlop={8}
              >
                <Text style={styles.quitar}>Quitar</Text>
              </Pressable>
            </View>
            <Text style={[styles.hint, excede && styles.excede]}>
              Disponible: {formatNumber(disp)}
            </Text>
            <View style={styles.lineaCampos}>
              <View style={{ flex: 1 }}>
                <Text style={styles.campoLabel}>Cantidad</Text>
                <TextInput
                  style={[styles.input, excede && styles.inputExcede]}
                  keyboardType="number-pad"
                  value={l.cantidad}
                  onChangeText={(v) => editarLinea(i, { cantidad: v.replace(/\D/g, "") })}
                />
              </View>
              <View style={{ flex: 1 }}>
                <Text style={styles.campoLabel}>Costo unit. $</Text>
                <TextInput
                  style={styles.input}
                  keyboardType="decimal-pad"
                  value={l.costo}
                  onChangeText={(v) => editarLinea(i, { costo: v })}
                />
              </View>
            </View>
          </View>
        );
      })}
      {lineas.length ? (
        <Text style={styles.total}>Costo total ${formatMoney(totalCosto)}</Text>
      ) : null}

      <FormField
        label="Observaciones"
        value={observaciones}
        onChangeText={setObservaciones}
        multiline
      />
      <ErrorText message={error} />
      <PrimaryButton label="Registrar movimiento" loading={saving} onPress={onGuardar} />
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
  total: {
    color: "#0B3A5C",
    fontWeight: "700",
    fontSize: 16,
    textAlign: "right",
    marginVertical: 10,
  },
});
