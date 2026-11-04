import { useCallback, useEffect, useMemo, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { useLocalSearchParams, useRouter, type Href } from "expo-router";
import { Ionicons } from "@expo/vector-icons";
import { useAuth } from "@/lib/auth-context";
import {
  listClientesForProfile,
  type ClienteListaItem,
} from "@/lib/clientes";
import {
  obtenerSaldosEnvasesCliente,
  registrarMovimientoContenedoresAClientes,
  type SaldoEnvaseCliente,
} from "@/lib/contenedores";
import { ErrorText, LoadingBlock, SectionTitle } from "@/components/ui";

export default function RetirarContenedoresScreen() {
  const router = useRouter();
  const { profile } = useAuth();
  const params = useLocalSearchParams<{ clienteId?: string }>();

  const [clienteSeleccionado, setClienteSeleccionado] =
    useState<ClienteListaItem | null>(null);
  const [busqueda, setBusqueda] = useState("");
  const [buscandoClientes, setBuscandoClientes] = useState(false);
  const [clientesEncontrados, setClientesEncontrados] = useState<
    ClienteListaItem[]
  >([]);

  const [cargandoEnvases, setCargandoEnvases] = useState(false);
  const [envases, setEnvases] = useState<SaldoEnvaseCliente[]>([]);
  const [cantidades, setCantidades] = useState<Record<string, number>>({});
  const [observaciones, setObservaciones] = useState("");
  const [guardando, setGuardando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Cargar cliente inicial si viene por query param
  useEffect(() => {
    let cancel = false;
    async function cargarInicial() {
      if (!params.clienteId || !profile) return;
      setCargandoEnvases(true);
      setError(null);
      const res = await listClientesForProfile(profile);
      if (cancel) return;
      if (res.ok) {
        const encontrado = res.clientes.find((c) => c.id === params.clienteId);
        if (encontrado) {
          setClienteSeleccionado(encontrado);
        }
      }
      setCargandoEnvases(false);
    }
    void cargarInicial();
    return () => {
      cancel = true;
    };
  }, [params.clienteId, profile]);

  // Cargar envases cuando haya un cliente seleccionado
  const cargarEnvasesCliente = useCallback(async (clienteId: string) => {
    setCargandoEnvases(true);
    setError(null);
    const res = await obtenerSaldosEnvasesCliente(clienteId);
    if (!res.ok) {
      setError(res.error);
      setEnvases([]);
    } else {
      setEnvases(res.envases);
      // Inicializar cantidades en 0
      const init: Record<string, number> = {};
      for (const e of res.envases) {
        init[e.contenedor_id] = 0;
      }
      setCantidades(init);
    }
    setCargandoEnvases(false);
  }, []);

  useEffect(() => {
    if (clienteSeleccionado) {
      void cargarEnvasesCliente(clienteSeleccionado.id);
    } else {
      setEnvases([]);
      setCantidades({});
    }
  }, [clienteSeleccionado, cargarEnvasesCliente]);

  // Buscar clientes
  const handleBuscarClientes = useCallback(async () => {
    if (!profile) return;
    setBuscandoClientes(true);
    const res = await listClientesForProfile(profile, busqueda);
    if (res.ok) {
      setClientesEncontrados(res.clientes);
    } else {
      Alert.alert("Error", res.error);
    }
    setBuscandoClientes(false);
  }, [profile, busqueda]);

  const handleSeleccionarCliente = useCallback((c: ClienteListaItem) => {
    setClienteSeleccionado(c);
    setClientesEncontrados([]);
    setBusqueda("");
  }, []);

  const handleCambiarCantidad = useCallback(
    (contenedorId: string, delta: number) => {
      setCantidades((prev) => {
        const actual = prev[contenedorId] || 0;
        const nuevo = Math.max(0, actual + delta);
        return { ...prev, [contenedorId]: nuevo };
      });
    },
    [],
  );

  const handleSetCantidadDirecta = useCallback(
    (contenedorId: string, texto: string) => {
      const limpia = texto.replace(/[^0-9]/g, "");
      const val = limpia === "" ? 0 : parseInt(limpia, 10);
      setCantidades((prev) => ({
        ...prev,
        [contenedorId]: isNaN(val) ? 0 : Math.max(0, val),
      }));
    },
    [],
  );

  const totalRetirar = useMemo(() => {
    return Object.values(cantidades).reduce((sum, v) => sum + (v || 0), 0);
  }, [cantidades]);

  const handleGuardar = useCallback(async () => {
    if (!clienteSeleccionado) {
      Alert.alert("Atención", "Debe seleccionar un cliente.");
      return;
    }

    const items = Object.entries(cantidades)
      .filter(([, cant]) => (cant || 0) > 0)
      .map(([contenedor_id, cantidad_retirada]) => ({
        contenedor_id,
        cantidad_entregada: 0,
        cantidad_retirada,
      }));

    if (items.length === 0) {
      Alert.alert(
        "Atención",
        "Debe indicar al menos una cantidad de contenedores a retirar.",
      );
      return;
    }

    setGuardando(true);
    setError(null);

    const res = await registrarMovimientoContenedoresAClientes({
      cliente_id: clienteSeleccionado.id,
      items,
      observaciones: observaciones.trim() || null,
      usuario_id: profile?.id || null,
    });

    setGuardando(false);

    if (!res.ok) {
      setError(res.error);
      Alert.alert("Error al registrar retiro", res.error);
      return;
    }

    Alert.alert(
      "Éxito",
      "Retiro de contenedores registrado correctamente.",
      [
        {
          text: "Ver detalle del cliente",
          onPress: () => {
            router.replace(
              `/(app)/contenedores/${clienteSeleccionado.id}` as Href,
            );
          },
        },
      ],
      { cancelable: false },
    );
  }, [clienteSeleccionado, cantidades, observaciones, profile?.id, router]);

  return (
    <KeyboardAvoidingView
      behavior={Platform.OS === "ios" ? "padding" : undefined}
      style={styles.keyboardContainer}
    >
      <ScrollView
        style={styles.root}
        contentContainerStyle={styles.scrollContent}
        keyboardShouldPersistTaps="handled"
      >
        <ErrorText message={error} />

        {/* Sección: Selección de Cliente */}
        <SectionTitle>Cliente</SectionTitle>
        {clienteSeleccionado ? (
          <View style={styles.cardCliente}>
            <View style={{ flex: 1 }}>
              <Text style={styles.clienteNombre}>
                {clienteSeleccionado.razon_social}
              </Text>
              <Text style={styles.clienteRif}>
                {clienteSeleccionado.rif_nit}
              </Text>
            </View>
            {!params.clienteId && (
              <Pressable
                onPress={() => setClienteSeleccionado(null)}
                style={styles.btnCambiarCliente}
              >
                <Text style={styles.btnCambiarClienteText}>Cambiar</Text>
              </Pressable>
            )}
          </View>
        ) : (
          <View style={styles.selectorCliente}>
            <View style={styles.searchRow}>
              <TextInput
                style={styles.search}
                placeholder="Buscar cliente por nombre o RIF…"
                value={busqueda}
                onChangeText={setBusqueda}
                onSubmitEditing={handleBuscarClientes}
                returnKeyType="search"
              />
              <Pressable
                style={styles.searchBtn}
                onPress={handleBuscarClientes}
                disabled={buscandoClientes}
              >
                {buscandoClientes ? (
                  <ActivityIndicator color="#fff" size="small" />
                ) : (
                  <Ionicons name="search" size={20} color="#fff" />
                )}
              </Pressable>
            </View>

            {clientesEncontrados.length > 0 && (
              <View style={styles.listaResultados}>
                {clientesEncontrados.map((c) => (
                  <Pressable
                    key={c.id}
                    style={styles.resultadoItem}
                    onPress={() => handleSeleccionarCliente(c)}
                  >
                    <Text style={styles.resultadoNombre}>{c.razon_social}</Text>
                    <Text style={styles.resultadoRif}>{c.rif_nit}</Text>
                  </Pressable>
                ))}
              </View>
            )}
          </View>
        )}

        {/* Sección: Tipos de Contenedores y Saldos */}
        {clienteSeleccionado && (
          <>
            <SectionTitle>Cantidades a Retirar</SectionTitle>
            <Text style={styles.helperText}>
              Ingrese la cantidad física recogida. El sistema permite saldos a
              favor del cliente si devuelve más de lo registrado.
            </Text>

            {cargandoEnvases ? (
              <LoadingBlock />
            ) : envases.length === 0 ? (
              <View style={styles.cardEmpty}>
                <Text style={styles.emptyText}>
                  No hay tipos de contenedores registrados en el catálogo.
                </Text>
              </View>
            ) : (
              envases.map((envase) => {
                const actual = envase.saldo;
                const aRetirar = cantidades[envase.contenedor_id] || 0;
                const proyectado = actual - aRetirar;

                return (
                  <View key={envase.contenedor_id} style={styles.envaseCard}>
                    <View style={styles.envaseHeader}>
                      <View style={{ flex: 1 }}>
                        <Text style={styles.envaseNombre}>{envase.nombre}</Text>
                        {envase.codigo ? (
                          <Text style={styles.envaseCodigo}>
                            Cód: {envase.codigo}
                          </Text>
                        ) : null}
                      </View>
                      <View style={styles.saldoActualPill}>
                        <Text style={styles.saldoActualLabel}>
                          {actual < 0
                            ? `A favor: ${Math.abs(actual)}`
                            : actual > 0
                              ? `Pendiente: ${actual}`
                              : "Saldo: 0"}
                        </Text>
                      </View>
                    </View>

                    {/* Controles de Entrada */}
                    <View style={styles.controlesRow}>
                      <Text style={styles.cantLabel}>Retirar:</Text>
                      <View style={styles.counterWrap}>
                        <Pressable
                          style={[
                            styles.btnCounter,
                            aRetirar <= 0 && styles.btnDisabled,
                          ]}
                          onPress={() =>
                            handleCambiarCantidad(envase.contenedor_id, -1)
                          }
                          disabled={aRetirar <= 0}
                        >
                          <Ionicons
                            name="remove"
                            size={20}
                            color={aRetirar <= 0 ? "#9CA3AF" : "#0B3A5C"}
                          />
                        </Pressable>

                        <TextInput
                          style={styles.inputCantidad}
                          keyboardType="numeric"
                          value={String(aRetirar)}
                          onChangeText={(t) =>
                            handleSetCantidadDirecta(envase.contenedor_id, t)
                          }
                          selectTextOnFocus
                        />

                        <Pressable
                          style={styles.btnCounter}
                          onPress={() =>
                            handleCambiarCantidad(envase.contenedor_id, 1)
                          }
                        >
                          <Ionicons name="add" size={20} color="#0B3A5C" />
                        </Pressable>
                      </View>
                    </View>

                    {/* Proyección del Saldo Resultante */}
                    {aRetirar > 0 && (
                      <View
                        style={[
                          styles.proyeccionRow,
                          proyectado < 0 && styles.proyeccionFavor,
                        ]}
                      >
                        <Ionicons
                          name={
                            proyectado < 0
                              ? "checkmark-circle-outline"
                              : "arrow-forward-outline"
                          }
                          size={16}
                          color={proyectado < 0 ? "#059669" : "#0B3A5C"}
                        />
                        <Text
                          style={[
                            styles.proyeccionText,
                            proyectado < 0 && styles.proyeccionFavorText,
                          ]}
                        >
                          {proyectado < 0
                            ? `Nuevo saldo: ${Math.abs(proyectado)} a favor del cliente`
                            : proyectado === 0
                              ? "Nuevo saldo: 0 (al día)"
                              : `Nuevo saldo: ${proyectado} pendientes`}
                        </Text>
                      </View>
                    )}
                  </View>
                );
              })
            )}

            {/* Observaciones */}
            <SectionTitle>Observaciones (Opcional)</SectionTitle>
            <TextInput
              style={styles.textArea}
              placeholder="Ej: Retiro en sede principal, contenedores limpios…"
              placeholderTextColor="#9CA3AF"
              multiline
              numberOfLines={3}
              value={observaciones}
              onChangeText={setObservaciones}
            />

            {/* Botón de Confirmación */}
            <Pressable
              style={[
                styles.btnSubmit,
                (totalRetirar <= 0 || guardando) && styles.btnSubmitDisabled,
              ]}
              onPress={handleGuardar}
              disabled={totalRetirar <= 0 || guardando}
            >
              {guardando ? (
                <ActivityIndicator color="#fff" />
              ) : (
                <>
                  <Ionicons name="checkmark-done" size={22} color="#fff" />
                  <Text style={styles.btnSubmitText}>
                    Confirmar Retiro ({totalRetirar})
                  </Text>
                </>
              )}
            </Pressable>
          </>
        )}
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  keyboardContainer: {
    flex: 1,
    backgroundColor: "#F4F6F8",
  },
  root: {
    flex: 1,
  },
  scrollContent: {
    padding: 16,
    gap: 12,
    paddingBottom: 60,
  },
  helperText: {
    fontSize: 13,
    color: "#6B7280",
    marginTop: -6,
    marginBottom: 4,
  },
  cardCliente: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    borderWidth: 1,
    borderColor: "#E5EAF0",
    flexDirection: "row",
    alignItems: "center",
  },
  clienteNombre: {
    fontSize: 16,
    fontWeight: "700",
    color: "#0B3A5C",
  },
  clienteRif: {
    fontSize: 13,
    color: "#6B7280",
    marginTop: 2,
  },
  btnCambiarCliente: {
    backgroundColor: "#EFF6FF",
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 8,
  },
  btnCambiarClienteText: {
    color: "#2563EB",
    fontWeight: "600",
    fontSize: 13,
  },
  selectorCliente: {
    gap: 8,
  },
  searchRow: {
    flexDirection: "row",
    gap: 8,
  },
  search: {
    flex: 1,
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 10,
    fontSize: 15,
    color: "#0B3A5C",
  },
  searchBtn: {
    backgroundColor: "#0B3A5C",
    borderRadius: 12,
    paddingHorizontal: 16,
    justifyContent: "center",
    alignItems: "center",
  },
  listaResultados: {
    backgroundColor: "#fff",
    borderRadius: 12,
    borderWidth: 1,
    borderColor: "#E5EAF0",
    overflow: "hidden",
  },
  resultadoItem: {
    padding: 12,
    borderBottomWidth: 1,
    borderBottomColor: "#F3F4F6",
  },
  resultadoNombre: {
    fontSize: 15,
    fontWeight: "600",
    color: "#0B3A5C",
  },
  resultadoRif: {
    fontSize: 12,
    color: "#6B7280",
    marginTop: 2,
  },
  cardEmpty: {
    backgroundColor: "#fff",
    padding: 16,
    borderRadius: 12,
    alignItems: "center",
  },
  emptyText: {
    color: "#6B7280",
    fontSize: 14,
  },
  envaseCard: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    borderWidth: 1,
    borderColor: "#E5EAF0",
    gap: 10,
  },
  envaseHeader: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
  },
  envaseNombre: {
    fontSize: 16,
    fontWeight: "600",
    color: "#0B3A5C",
  },
  envaseCodigo: {
    fontSize: 12,
    color: "#6B7280",
    marginTop: 2,
  },
  saldoActualPill: {
    backgroundColor: "#F3F4F6",
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 999,
  },
  saldoActualLabel: {
    fontSize: 12,
    fontWeight: "600",
    color: "#374151",
  },
  controlesRow: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingTop: 4,
  },
  cantLabel: {
    fontSize: 15,
    fontWeight: "600",
    color: "#0B3A5C",
  },
  counterWrap: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
  },
  btnCounter: {
    width: 38,
    height: 38,
    borderRadius: 8,
    backgroundColor: "#F3F4F6",
    alignItems: "center",
    justifyContent: "center",
    borderWidth: 1,
    borderColor: "#E5EAF0",
  },
  btnDisabled: {
    opacity: 0.4,
  },
  inputCantidad: {
    width: 60,
    height: 38,
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 8,
    textAlign: "center",
    fontSize: 16,
    fontWeight: "700",
    color: "#0B3A5C",
  },
  proyeccionRow: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
    backgroundColor: "#F0FDF4",
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 8,
  },
  proyeccionFavor: {
    backgroundColor: "#ECFDF5",
  },
  proyeccionText: {
    fontSize: 13,
    fontWeight: "600",
    color: "#0B3A5C",
  },
  proyeccionFavorText: {
    color: "#059669",
  },
  textArea: {
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 12,
    padding: 12,
    fontSize: 14,
    color: "#0B3A5C",
    textAlignVertical: "top",
    minHeight: 70,
  },
  btnSubmit: {
    backgroundColor: "#0B3A5C",
    borderRadius: 12,
    paddingVertical: 14,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 8,
    marginTop: 8,
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 2,
  },
  btnSubmitDisabled: {
    backgroundColor: "#9CA3AF",
    elevation: 0,
  },
  btnSubmitText: {
    color: "#fff",
    fontSize: 16,
    fontWeight: "700",
  },
});

