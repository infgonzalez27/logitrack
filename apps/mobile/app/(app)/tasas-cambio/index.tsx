import { useCallback, useState } from "react";
import {
  FlatList,
  RefreshControl,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { useFocusEffect } from "expo-router";
import { useAuth } from "@/lib/auth-context";
import {
  hoyIsoLocal,
  insertaTasaCambio,
  listTasasCambio,
  retornaUltimaTasaCambio,
  type TasaCambio,
} from "@/lib/tasas-cambio";
import { formatDate, formatNumber } from "@/lib/format";
import {
  EmptyState,
  ErrorText,
  FormField,
  LoadingBlock,
  PrimaryButton,
  SectionTitle,
} from "@/components/ui";

export default function TasasCambioScreen() {
  const { profile } = useAuth();
  const puedeGestionar =
    profile?.rol === "admin" || profile?.rol === "gerente";

  const [ultima, setUltima] = useState<TasaCambio | null>(null);
  const [tasas, setTasas] = useState<TasaCambio[]>([]);
  const [fecha, setFecha] = useState(hoyIsoLocal());
  const [tasa, setTasa] = useState("");
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [okMsg, setOkMsg] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError(null);
    const [uRes, lRes] = await Promise.all([
      retornaUltimaTasaCambio(),
      listTasasCambio(),
    ]);
    if (!uRes.ok) setError(uRes.error);
    else {
      setUltima(uRes.tasa);
      if (uRes.tasa && !tasa) setTasa(String(uRes.tasa.tasa_cambio));
    }
    if (!lRes.ok) setError(lRes.error);
    else setTasas(lRes.tasas);
    setLoading(false);
    setRefreshing(false);
  }, [tasa]);

  useFocusEffect(
    useCallback(() => {
      setLoading(true);
      void load();
      // eslint-disable-next-line react-hooks/exhaustive-deps -- load once on focus
    }, []),
  );

  const registrar = async () => {
    setSaving(true);
    setError(null);
    setOkMsg(null);
    const res = await insertaTasaCambio({
      fecha_tasa: fecha,
      tasa: Number(tasa.replace(",", ".")),
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    setOkMsg(`Tasa registrada: ${res.tasa.fecha_tasa}`);
    setUltima(res.tasa);
    void load();
  };

  if (loading) return <LoadingBlock />;

  return (
    <View style={styles.root}>
      <View style={styles.card}>
        <SectionTitle>Última tasa</SectionTitle>
        {ultima ? (
          <>
            <Text style={styles.big}>
              {formatNumber(ultima.tasa_cambio, 4)} Bs/USD
            </Text>
            <Text style={styles.meta}>{formatDate(ultima.fecha_tasa)}</Text>
          </>
        ) : (
          <Text style={styles.meta}>Aún no hay tasas registradas.</Text>
        )}
      </View>

      {puedeGestionar ? (
        <View style={styles.card}>
          <SectionTitle>Registrar tasa</SectionTitle>
          <FormField
            label="Fecha (YYYY-MM-DD)"
            value={fecha}
            onChangeText={setFecha}
            autoCapitalize="none"
          />
          <FormField
            label="Tasa Bs / USD"
            value={tasa}
            onChangeText={setTasa}
            keyboardType="decimal-pad"
          />
          <ErrorText message={error} />
          {okMsg ? <Text style={styles.ok}>{okMsg}</Text> : null}
          <PrimaryButton
            label="Guardar tasa"
            onPress={() => void registrar()}
            loading={saving}
          />
        </View>
      ) : (
        <Text style={styles.meta}>
          Solo admin o gerente pueden registrar tasas.
        </Text>
      )}

      <SectionTitle>Historial</SectionTitle>
      <FlatList
        data={tasas}
        keyExtractor={(item) => item.fecha_tasa}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={() => {
              setRefreshing(true);
              void load();
            }}
          />
        }
        ListEmptyComponent={<EmptyState message="Sin tasas en el historial." />}
        renderItem={({ item }) => (
          <View style={styles.row}>
            <Text style={styles.rowTitle}>{formatDate(item.fecha_tasa)}</Text>
            <Text style={styles.rowMeta}>
              {formatNumber(item.tasa_cambio, 4)}
            </Text>
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
  big: { fontSize: 22, fontWeight: "700", color: "#0B3A5C" },
  meta: { fontSize: 13, color: "#5B6B7C", marginTop: 4 },
  ok: { color: "#067647", marginBottom: 8 },
  row: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    marginBottom: 8,
    borderWidth: 1,
    borderColor: "#E5EAF0",
    flexDirection: "row",
    justifyContent: "space-between",
  },
  rowTitle: { fontWeight: "600", color: "#0B3A5C" },
  rowMeta: { color: "#5B6B7C" },
});
