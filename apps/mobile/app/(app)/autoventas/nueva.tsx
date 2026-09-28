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
import { listClientesForProfile, type ClienteListaItem } from "@/lib/clientes";
import { listarCamiones, retornaUltimaTasa, type CamionOption } from "@/lib/catalogos";
import {
  listarInventarioMovil,
  registrarVentaEnRuta,
  type InventarioMovilRow,
} from "@/lib/autoventas";
import { formatMoney } from "@/lib/format";

type Linea = {
  producto_id: string;
  nombre: string;
  cantidad: number;
  precio: number;
  disponible: number;
};

export default function AutoventaNuevaScreen() {
  const { camionId: camionParam } = useLocalSearchParams<{ camionId?: string }>();
  const { profile } = useAuth();
  const router = useRouter();

  const [clientes, setClientes] = useState<ClienteListaItem[]>([]);
  const [camiones, setCamiones] = useState<CamionOption[]>([]);
  const [inventario, setInventario] = useState<InventarioMovilRow[]>([]);
  const [clienteId, setClienteId] = useState("");
  const [clienteLabel, setClienteLabel] = useState("");
  const [camionId, setCamionId] = useState(camionParam ?? "");
  const [lineas, setLineas] = useState<Linea[]>([]);
  const [obs, setObs] = useState("");
  const [tasa, setTasa] = useState<number | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [picker, setPicker] = useState<"cliente" | "camion" | "producto" | null>(
    null,
  );

  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (!profile) return;
      const [cRes, camRes, tRes] = await Promise.all([
        listClientesForProfile(profile),
        listarCamiones(),
        retornaUltimaTasa(),
      ]);
      if (cancelled) return;
      if (cRes.ok) setClientes(cRes.clientes);
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

  const loadInv = useCallback(async (id: string) => {
    if (!id) return;
    const res = await listarInventarioMovil(id);
    if (res.ok) setInventario(res.rows);
  }, []);

  useEffect(() => {
    void loadInv(camionId);
  }, [camionId, loadInv]);

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
    const precio = Number(row.productos?.precio_lista1) || 0;
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
          disponible: row.disponible,
        },
      ];
    });
    setPicker(null);
  };

  const submit = async () => {
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
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert(
      "Venta registrada",
      `Orden ${res.correlativo != null ? `#${res.correlativo}` : ""} creada. Lista para rendición.`,
      [
        {
          text: "OK",
          onPress: () => router.replace("/(app)/autoventas" as Href),
        },
      ],
    );
  };

  if (loading) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color="#0B3A5C" />
      </View>
    );
  }

  if (picker === "cliente") {
    return (
      <View style={styles.root}>
        <Pressable onPress={() => setPicker(null)}>
          <Text style={styles.back}>← Volver</Text>
        </Pressable>
        <FlatList
          data={clientes}
          keyExtractor={(c) => c.id}
          contentContainerStyle={{ padding: 16 }}
          renderItem={({ item }) => (
            <Pressable
              style={styles.card}
              onPress={() => {
                setClienteId(item.id);
                setClienteLabel(item.razon_social);
                setPicker(null);
              }}
            >
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
      contentContainerStyle={{ padding: 16, gap: 10, paddingBottom: 40 }}
      ListHeaderComponent={
        <View style={{ gap: 10 }}>
          {error ? <Text style={styles.error}>{error}</Text> : null}
          <Text style={styles.label}>Cliente</Text>
          <Pressable style={styles.select} onPress={() => setPicker("cliente")}>
            <Text style={styles.selectText}>
              {clienteLabel || "Elegir cliente"}
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
          <Pressable
            style={[styles.btn, saving && { opacity: 0.6 }]}
            disabled={saving}
            onPress={() => void submit()}
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
