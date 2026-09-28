import { useCallback, useState } from "react";
import {
  FlatList,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { useFocusEffect } from "expo-router";
import { useAuth } from "@/lib/auth-context";
import {
  crearCuentaBancariaEmpresa,
  listarCuentasBancariasEmpresa,
  toggleCuentaActiva,
  type CuentaBancariaEmpresa,
} from "@/lib/cuentas-bancarias";
import {
  EmptyState,
  ErrorText,
  FormField,
  LoadingBlock,
  PrimaryButton,
  SectionTitle,
} from "@/components/ui";

export default function CuentasBancariasScreen() {
  const { profile } = useAuth();
  const puedeGestionar =
    profile?.rol === "admin" || profile?.rol === "gerente";

  const [cuentas, setCuentas] = useState<CuentaBancariaEmpresa[]>([]);
  const [entidad, setEntidad] = useState("");
  const [cuenta, setCuenta] = useState("");
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [okMsg, setOkMsg] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError(null);
    const res = await listarCuentasBancariasEmpresa(false);
    if (!res.ok) {
      setError(res.error);
      setCuentas([]);
    } else {
      setCuentas(res.cuentas);
    }
    setLoading(false);
    setRefreshing(false);
  }, []);

  useFocusEffect(
    useCallback(() => {
      setLoading(true);
      void load();
    }, [load]),
  );

  const crear = async () => {
    setSaving(true);
    setError(null);
    setOkMsg(null);
    const res = await crearCuentaBancariaEmpresa({
      entidad_bancaria: entidad,
      cuenta_bancaria: cuenta,
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    setOkMsg("Cuenta registrada.");
    setEntidad("");
    setCuenta("");
    void load();
  };

  const toggle = async (c: CuentaBancariaEmpresa) => {
    setError(null);
    const res = await toggleCuentaActiva(c);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    setCuentas((prev) =>
      prev.map((x) => (x.id === res.cuenta.id ? res.cuenta : x)),
    );
  };

  if (loading) return <LoadingBlock />;

  return (
    <View style={styles.root}>
      {puedeGestionar ? (
        <View style={styles.card}>
          <SectionTitle>Registrar cuenta</SectionTitle>
          <FormField
            label="Entidad bancaria"
            value={entidad}
            onChangeText={setEntidad}
            placeholder="Ej. Banco de Venezuela"
          />
          <FormField
            label="Número de cuenta"
            value={cuenta}
            onChangeText={setCuenta}
            placeholder="0102-…"
            maxLength={34}
          />
          <ErrorText message={error} />
          {okMsg ? <Text style={styles.ok}>{okMsg}</Text> : null}
          <PrimaryButton
            label="Registrar"
            onPress={() => void crear()}
            loading={saving}
            disabled={!entidad.trim() || !cuenta.trim()}
          />
        </View>
      ) : (
        <Text style={styles.meta}>
          Solo admin o gerente pueden registrar o modificar cuentas.
        </Text>
      )}

      <SectionTitle>Cuentas registradas</SectionTitle>
      <FlatList
        data={cuentas}
        keyExtractor={(item) => item.id}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={() => {
              setRefreshing(true);
              void load();
            }}
          />
        }
        ListEmptyComponent={
          <EmptyState message="No hay cuentas bancarias registradas." />
        }
        renderItem={({ item }) => (
          <View style={styles.row}>
            <View style={{ flex: 1 }}>
              <Text style={styles.title}>{item.entidad_bancaria}</Text>
              <Text style={styles.meta}>{item.cuenta_bancaria}</Text>
              <Text
                style={[
                  styles.badge,
                  !item.status_cuenta && styles.badgeOff,
                ]}
              >
                {item.status_cuenta ? "Activa" : "Suspendida"}
              </Text>
            </View>
            {puedeGestionar ? (
              <Pressable
                style={styles.toggle}
                onPress={() => void toggle(item)}
              >
                <Text style={styles.toggleText}>
                  {item.status_cuenta ? "Suspender" : "Activar"}
                </Text>
              </Pressable>
            ) : null}
          </View>
        )}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F6F8", padding: 16 },
  card: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    marginBottom: 12,
    borderWidth: 1,
    borderColor: "#E5EAF0",
  },
  row: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    marginBottom: 8,
    borderWidth: 1,
    borderColor: "#E5EAF0",
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
  },
  title: { fontSize: 16, fontWeight: "700", color: "#0B3A5C" },
  meta: { fontSize: 13, color: "#5B6B7C", marginTop: 4 },
  badge: {
    alignSelf: "flex-start",
    marginTop: 6,
    fontSize: 11,
    fontWeight: "600",
    color: "#067647",
    backgroundColor: "#E8F5EF",
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 999,
  },
  badgeOff: { color: "#B54708", backgroundColor: "#FEF0C7" },
  toggle: {
    borderWidth: 1,
    borderColor: "#0B3A5C",
    borderRadius: 10,
    paddingHorizontal: 10,
    paddingVertical: 8,
  },
  toggleText: { color: "#0B3A5C", fontWeight: "600", fontSize: 12 },
  ok: { color: "#067647", marginBottom: 8 },
});
