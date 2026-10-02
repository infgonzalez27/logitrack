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
import { useLocalSearchParams, useRouter, type Href } from "expo-router";
import { useAuth } from "@/lib/auth-context";
import { buscarClientesForProfile, type ClienteListaItem } from "@/lib/clientes";
import { listarCamiones, retornaUltimaTasa, type CamionOption } from "@/lib/catalogos";
import {
  listarInventarioMovil,
  registrarVentaEnRuta,
  type InventarioMovilRow,
} from "@/lib/autoventas";
import {
  obtenerSaldosEnvasesCliente,
  type SaldoEnvaseCliente,
} from "@/lib/contenedores";
import { formatMoney } from "@/lib/format";
import { calcularEnvasesEntregados, textoResumenEnvases } from "@/lib/envases-venta";
import { obtenerDescuentosCliente, type DescuentoConProducto } from "@/lib/descuentos";

type Linea = {
  producto_id: string;
  nombre: string;
  cantidad: number;
  precio: number;
  disponible: number;
  contenedor_id: string | null;
  unidades_por_contenedor: number | null;
  pctDescuento: number;
};

type Envase = SaldoEnvaseCliente & { retirados: string };

function soloEnteros(texto: string): string {
  return texto.replace(/[^0-9]/g, "");
}

function aEntero(texto: string): number {
  const n = Number.parseInt(texto, 10);
  return Number.isFinite(n) && n > 0 ? n : 0;
}

export default function AutoventaNuevaScreen() {
  const { camionId: camionParam } = useLocalSearchParams<{ camionId?: string }>();
  const { profile } = useAuth();
  const router = useRouter();

  const [camiones, setCamiones] = useState<CamionOption[]>([]);
  const [inventario, setInventario] = useState<InventarioMovilRow[]>([]);
  const [clienteId, setClienteId] = useState("");
  const [clienteLabel, setClienteLabel] = useState("");
  const [camionId, setCamionId] = useState(camionParam ?? "");
  const [lineas, setLineas] = useState<Linea[]>([]);
  const [envases, setEnvases] = useState<Envase[]>([]);
  const [envasesLoading, setEnvasesLoading] = useState(false);
  const [obs, setObs] = useState("");
  const [tasa, setTasa] = useState<number | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [descuentosCliente, setDescuentosCliente] = useState<DescuentoConProducto[]>([]);
  const [picker, setPicker] = useState<"cliente" | "camion" | "producto" | null>(
    null,
  );
  const [clienteQ, setClienteQ] = useState("");
  const [clienteResultados, setClienteResultados] = useState<ClienteListaItem[]>(
    [],
  );
  const [buscandoClientes, setBuscandoClientes] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (!profile) return;
      const [camRes, tRes] = await Promise.all([
        listarCamiones(),
        retornaUltimaTasa(),
      ]);
      if (cancelled) return;
      if (camRes.ok) {
        setCamiones(camRes.camiones);
        if (!camionId && camRes.camiones[0]) setCamionId(camRes.camiones[0].id);
      }
      if (tRes.ok) setTasa(tRes.tasa);
      setLoading(false);
    })();
    return () => {
      cancelled = true;
    };
  }, [profile, camionId]);

  useEffect(() => {
    if (picker !== "cliente" || !profile) return;
    const term = clienteQ.trim();
    if (term.length < 2) {
      setClienteResultados([]);
      setBuscandoClientes(false);
      return;
    }
    let cancelled = false;
    setBuscandoClientes(true);
    const timeout = setTimeout(() => {
      void buscarClientesForProfile(profile, term).then((res) => {
        if (cancelled) return;
        setBuscandoClientes(false);
        if (res.ok) setClienteResultados(res.clientes);
        else setError(res.error);
      });
    }, 300);
    return () => {
      cancelled = true;
      clearTimeout(timeout);
    };
  }, [clienteQ, picker, profile]);

  const loadInv = useCallback(async (id: string) => {
    if (!id) return;
    const res = await listarInventarioMovil(id);
    if (res.ok) setInventario(res.rows);
  }, []);

  useEffect(() => {
    void loadInv(camionId);
  }, [camionId, loadInv]);

  const elegirCliente = async (cliente: ClienteListaItem) => {
    setClienteId(cliente.id);
    setClienteLabel(cliente.razon_social);
    setPicker(null);
    setClienteQ("");
    setClienteResultados([]);
    setEnvases([]);
    setLineas([]);
    setEnvasesLoading(true);
    const [res, descRes] = await Promise.all([
      obtenerSaldosEnvasesCliente(cliente.id),
      obtenerDescuentosCliente(cliente.id),
    ]);
    setEnvasesLoading(false);
    
    if (descRes.ok) {
      setDescuentosCliente(descRes.descuentos);
    } else {
      setDescuentosCliente([]);
    }

    if (!res.ok) {
      setError(res.error);
      return;
    }
    setEnvases(
      res.envases.map((e) => ({ ...e, retirados: "" })),
    );
  };

  const actualizarRetirados = (contenedorId: string, valor: string) => {
    setEnvases((prev) =>
      prev.map((e) =>
        e.contenedor_id === contenedorId ? { ...e, retirados: soloEnteros(valor) } : e,
      ),
    );
  };

  const entregados = useMemo(() => calcularEnvasesEntregados(lineas), [lineas]);

  const disponible = useMemo(() => {
    return inventario
      .map((r) => {
        const disp = Math.max(
          0,
          Number(r.cantidad_cargada) - Number(r.cantidad_entregada),
        );
        return {
          ...r,
          disponible: disp,
        };
      })
      .filter((r) => r.disponible > 0);
  }, [inventario]);

  const total = useMemo(
    () => lineas.reduce((a, l) => a + l.cantidad * l.precio, 0),
    [lineas],
  );

  const addProducto = (row: InventarioMovilRow & { disponible: number }) => {
    const precioBase = Number(row.productos?.precio_lista1) || 0;
    const desc = descuentosCliente.find((d) => d.producto_id === row.producto_id);
    
    let precio = precioBase;
    let pctDescuento = 0;
    
    if (desc) {
      if (desc.precio_pactado_usd != null) {
        precio = desc.precio_pactado_usd;
        if (precioBase > 0 && precio < precioBase) {
           pctDescuento = Math.round((1 - precio / precioBase) * 100);
        }
      } else if (desc.porcentaje_descuento > 0) {
        pctDescuento = desc.porcentaje_descuento;
        precio = Number((precioBase * (1 - pctDescuento / 100)).toFixed(2));
      }
    }

    setLineas((prev) => {
      const existing = prev.find((l) => l.producto_id === row.producto_id);
      if (existing) {
        return prev.map((l) =>
          l.producto_id === row.producto_id
            ? {
                ...l,
                cantidad: Math.min(l.cantidad + 1, row.disponible),
              }
            : l,
        );
      }
      return [
        ...prev,
        {
          producto_id: row.producto_id,
          nombre: row.productos?.nombre ?? "Producto",
          cantidad: 1,
          precio,
          pctDescuento,
          disponible: row.disponible,
          contenedor_id: row.productos?.contenedor_id ?? null,
          unidades_por_contenedor:
            row.productos?.unidades_por_contenedor != null
              ? Number(row.productos.unidades_por_contenedor)
              : null,
        },
      ];
    });
    setPicker(null);
  };

  const registrar = async () => {
    if (!profile) return;
    setSaving(true);
    setError(null);
    const res = await registrarVentaEnRuta({
      vendedorId: profile.id,
      clienteId,
      camionId,
      tasaCambio: tasa,
      observaciones: obs || undefined,
      productos: lineas.map((l) => ({
        producto_id: l.producto_id,
        cantidad: l.cantidad,
        precio_unitario: l.precio,
      })),
      contenedores: envases
        .map((e) => ({
          contenedor_id: e.contenedor_id,
          cantidad_entregada: entregados[e.contenedor_id] ?? 0,
          cantidad_retirada: aEntero(e.retirados),
        }))
        .filter((e) => e.cantidad_entregada > 0 || e.cantidad_retirada > 0),
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert(
      "Venta registrada",
      [
        `Orden ${res.correlativo != null ? `#${res.correlativo}` : ""} creada. Lista para rendición.`,
        textoResumenEnvases(res.contenedores),
      ]
        .filter(Boolean)
        .join("\n\n"),
      [
        {
          text: "Listo",
          style: "cancel",
          onPress: () => router.replace("/(app)/autoventas" as Href),
        },
        {
          text: "Ver / imprimir ticket",
          onPress: () => router.replace(`/(app)/ordenes/${res.ordenId}` as Href),
        },
      ],
    );
  };

  const submit = () => {
    if (!profile) return;
    if (!clienteId) {
      setError("Selecciona un cliente.");
      return;
    }
    if (!camionId) {
      setError("Selecciona un camión.");
      return;
    }
    if (!lineas.length) {
      setError("Agrega al menos un producto del inventario móvil.");
      return;
    }
    const excedidos = envases.filter(
      (e) => aEntero(e.retirados) > e.saldo + (entregados[e.contenedor_id] ?? 0),
    );
    if (excedidos.length) {
      const detalle = excedidos
        .map((e) => `${e.nombre}: saldo ${e.saldo}, retira ${aEntero(e.retirados)}`)
        .join("\n");
      Alert.alert(
        "Retiro mayor al saldo",
        `El cliente tiene menos envases pendientes de los que se retiran:\n${detalle}\n\nSi continúas, el saldo quedará en 0.`,
        [
          { text: "Revisar", style: "cancel" },
          { text: "Registrar igual", onPress: () => void registrar() },
        ],
      );
      return;
    }
    void registrar();
  };

  if (loading) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color="#0B3A5C" />
      </View>
    );
  }

  if (picker === "cliente") {
    const term = clienteQ.trim();
    return (
      <View style={styles.root}>
        <Pressable onPress={() => setPicker(null)}>
          <Text style={styles.back}>← Volver</Text>
        </Pressable>
        <View style={styles.searchWrap}>
          <TextInput
            style={styles.input}
            placeholder="Nombre, razón social o RIF…"
            value={clienteQ}
            onChangeText={setClienteQ}
            autoFocus
            autoCorrect={false}
            autoCapitalize="characters"
            returnKeyType="search"
          />
        </View>
        <FlatList
          data={clienteResultados}
          keyExtractor={(c) => c.id}
          keyboardShouldPersistTaps="handled"
          contentContainerStyle={{ padding: 16, paddingTop: 8 }}
          ListEmptyComponent={
            buscandoClientes ? (
              <ActivityIndicator color="#0B3A5C" style={{ marginTop: 16 }} />
            ) : (
              <Text style={styles.meta}>
                {term.length < 2
                  ? "Escribe al menos 2 letras para buscar."
                  : "Sin clientes que coincidan."}
              </Text>
            )
          }
          renderItem={({ item }) => (
            <Pressable style={styles.card} onPress={() => void elegirCliente(item)}>
              <Text style={styles.name}>{item.razon_social}</Text>
              <Text style={styles.meta}>{item.rif_nit}</Text>
            </Pressable>
          )}
        />
      </View>
    );
  }

  if (picker === "camion") {
    return (
      <View style={styles.root}>
        <Pressable onPress={() => setPicker(null)}>
          <Text style={styles.back}>← Volver</Text>
        </Pressable>
        <FlatList
          data={camiones}
          keyExtractor={(c) => c.id}
          contentContainerStyle={{ padding: 16 }}
          renderItem={({ item }) => (
            <Pressable
              style={styles.card}
              onPress={() => {
                setCamionId(item.id);
                setLineas([]);
                setPicker(null);
              }}
            >
              <Text style={styles.name}>{item.placa}</Text>
            </Pressable>
          )}
        />
      </View>
    );
  }

  if (picker === "producto") {
    return (
      <View style={styles.root}>
        <Pressable onPress={() => setPicker(null)}>
          <Text style={styles.back}>← Volver</Text>
        </Pressable>
        <FlatList
          data={disponible}
          keyExtractor={(r) => r.producto_id}
          contentContainerStyle={{ padding: 16 }}
          ListEmptyComponent={
            <Text style={styles.meta}>
              No hay stock disponible en este camión. Carga inventario desde la
              web o AutoVentas.
            </Text>
          }
          renderItem={({ item }) => (
            <Pressable style={styles.card} onPress={() => addProducto(item)}>
              <Text style={styles.name}>
                {item.productos?.nombre ?? "Producto"}
              </Text>
              <Text style={styles.meta}>
                {item.productos?.codigo_producto ?? "—"} · disp.{" "}
                {item.disponible}
              </Text>
              <Text style={styles.meta}>
                ${formatMoney(item.productos?.precio_lista1)}
              </Text>
            </Pressable>
          )}
        />
      </View>
    );
  }

  const camionLabel =
    camiones.find((c) => c.id === camionId)?.placa ?? "Elegir camión";

  return (
    <FlatList
      style={styles.root}
      data={lineas}
      keyExtractor={(l) => l.producto_id}
      keyboardShouldPersistTaps="handled"
      contentContainerStyle={{ padding: 16, gap: 10, paddingBottom: 40 }}
      ListHeaderComponent={
        <View style={{ gap: 10 }}>
          {error ? <Text style={styles.error}>{error}</Text> : null}
          <Text style={styles.label}>Cliente</Text>
          <Pressable style={styles.select} onPress={() => setPicker("cliente")}>
            <Text style={styles.selectText}>
              {clienteLabel || "Buscar cliente"}
            </Text>
          </Pressable>
          <Text style={styles.label}>Camión</Text>
          <Pressable style={styles.select} onPress={() => setPicker("camion")}>
            <Text style={styles.selectText}>{camionLabel}</Text>
          </Pressable>
          {tasa != null ? (
            <Text style={styles.meta}>Tasa BCV: {formatMoney(tasa)}</Text>
          ) : null}
          <Text style={styles.label}>Observaciones</Text>
          <TextInput
            style={styles.input}
            value={obs}
            onChangeText={setObs}
            placeholder="Opcional"
          />
          <Pressable
            style={styles.btnGhost}
            onPress={() => {
              if (!camionId) {
                setError("Selecciona un camión primero.");
                return;
              }
              setPicker("producto");
            }}
          >
            <Text style={styles.btnGhostText}>+ Producto del camión</Text>
          </Pressable>
          <Text style={styles.section}>Líneas</Text>
          {lineas.length === 0 ? (
            <Text style={styles.meta}>Sin productos.</Text>
          ) : null}
        </View>
      }
      renderItem={({ item }) => (
        <View style={styles.card}>
          <Text style={styles.name}>{item.nombre}</Text>
          {item.pctDescuento > 0 ? (
            <Text style={styles.discount}>Descuento {item.pctDescuento}%</Text>
          ) : null}
          <View style={styles.qtyRow}>
            <Pressable
              style={styles.qtyBtn}
              onPress={() =>
                setLineas((prev) =>
                  prev
                    .map((l) =>
                      l.producto_id === item.producto_id
                        ? { ...l, cantidad: Math.max(0, l.cantidad - 1) }
                        : l,
                    )
                    .filter((l) => l.cantidad > 0),
                )
              }
            >
              <Text style={styles.qtyBtnText}>−</Text>
            </Pressable>
            <Text style={styles.qty}>{item.cantidad}</Text>
            <Pressable
              style={styles.qtyBtn}
              onPress={() =>
                setLineas((prev) =>
                  prev.map((l) =>
                    l.producto_id === item.producto_id
                      ? {
                          ...l,
                          cantidad: Math.min(l.disponible, l.cantidad + 1),
                        }
                      : l,
                  ),
                )
              }
            >
              <Text style={styles.qtyBtnText}>+</Text>
            </Pressable>
            <Text style={styles.lineTotal}>
              ${formatMoney(item.cantidad * item.precio)}
            </Text>
          </View>
        </View>
      )}
      ListFooterComponent={
        <View style={{ gap: 12, marginTop: 8 }}>
          <Text style={styles.total}>Total ${formatMoney(total)}</Text>

          {clienteId ? (
            <View style={{ gap: 8 }}>
              <Text style={styles.section}>Envases / vacíos</Text>
              {envasesLoading ? (
                <ActivityIndicator color="#0B3A5C" />
              ) : envases.length === 0 ? (
                <Text style={styles.meta}>No hay tipos de envase registrados.</Text>
              ) : (
                envases.map((e) => {
                  const ent = entregados[e.contenedor_id] ?? 0;
                  const saldoFinal = Math.max(0, e.saldo + ent - aEntero(e.retirados));
                  return (
                    <View key={e.contenedor_id} style={styles.card}>
                      <Text style={styles.name}>
                        {e.codigo ? `${e.codigo} · ` : ""}
                        {e.nombre}
                      </Text>
                      <Text style={styles.meta}>Saldo anterior: {e.saldo}</Text>
                      <View style={styles.envaseRow}>
                        <View style={styles.envaseCol}>
                          <Text style={styles.label}>Entregados</Text>
                          <Text style={styles.envaseAuto}>{ent}</Text>
                        </View>
                        <View style={styles.envaseCol}>
                          <Text style={styles.label}>Retirados</Text>
                          <TextInput
                            style={styles.input}
                            keyboardType="number-pad"
                            placeholder="0"
                            value={e.retirados}
                            onChangeText={(t) => actualizarRetirados(e.contenedor_id, t)}
                          />
                        </View>
                      </View>
                      <Text style={styles.saldoFinal}>Saldo actual: {saldoFinal}</Text>
                    </View>
                  );
                })
              )}
            </View>
          ) : null}

          <Pressable
            style={[styles.btn, saving && { opacity: 0.6 }]}
            disabled={saving}
            onPress={submit}
          >
            <Text style={styles.btnText}>
              {saving ? "Registrando…" : "Registrar venta"}
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
  label: { fontSize: 12, color: "#5B6B7C", textTransform: "uppercase" },
  select: {
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 12,
    padding: 14,
  },
  selectText: { fontSize: 16, color: "#0B3A5C" },
  input: {
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 12,
    fontSize: 16,
  },
  searchWrap: { paddingHorizontal: 16 },
  section: { fontSize: 16, fontWeight: "600", color: "#0B3A5C" },
  card: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 12,
    borderWidth: 1,
    borderColor: "#E5EAF0",
    marginBottom: 8,
  },
  name: { fontWeight: "600", color: "#0B3A5C" },
  meta: { fontSize: 13, color: "#5B6B7C", marginTop: 2 },
  envaseRow: { flexDirection: "row", gap: 10, marginTop: 10 },
  envaseCol: { flex: 1, gap: 4 },
  envaseAuto: { fontSize: 20, fontWeight: "700", color: "#0B3A5C", paddingVertical: 10 },
  saldoFinal: { marginTop: 10, fontWeight: "700", color: "#0B3A5C" },
  qtyRow: { flexDirection: "row", alignItems: "center", gap: 12, marginTop: 8 },
  qtyBtn: {
    width: 36,
    height: 36,
    borderRadius: 8,
    backgroundColor: "#E8EEF3",
    alignItems: "center",
    justifyContent: "center",
  },
  qtyBtnText: { fontSize: 20, color: "#0B3A5C", fontWeight: "600" },
  qty: { fontSize: 16, fontWeight: "600", minWidth: 24, textAlign: "center" },
  lineTotal: { marginLeft: "auto", fontWeight: "700", color: "#0B3A5C" },
  total: { fontSize: 20, fontWeight: "700", color: "#0B3A5C", textAlign: "right" },
  discount: { color: "#067647", fontSize: 12, marginTop: 2 },
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
  error: { color: "#B42318" },
  back: { color: "#0B3A5C", fontWeight: "600", padding: 16 },
});
