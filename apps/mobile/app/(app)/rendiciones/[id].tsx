import { useCallback, useState } from "react";
import { Alert, ScrollView, StyleSheet, Text, View } from "react-native";
import { useFocusEffect, useLocalSearchParams, useRouter } from "expo-router";
import { useAuth } from "@/lib/auth-context";
import {
  aprobarRendicion,
  getRendicionDetalle,
  reversarRendicion,
  type RendicionDetalle,
} from "@/lib/rendiciones";
import { formatDate, formatMoney } from "@/lib/format";
import {
  ErrorText,
  LoadingBlock,
  PrimaryButton,
  SecondaryButton,
  SectionTitle,
} from "@/components/ui";

export default function RendicionDetalleScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { profile } = useAuth();
  const router = useRouter();
  const [item, setItem] = useState<RendicionDetalle | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const canApprove =
    profile?.rol === "gerente" || profile?.rol === "admin";
  const canReverse = profile?.rol === "gerente";

  const load = useCallback(async () => {
    if (!id) return;
    const res = await getRendicionDetalle(id);
    if (!res.ok) {
      setError(res.error);
      setItem(null);
    } else {
      setError(null);
      setItem(res.rendicion);
    }
    setLoading(false);
  }, [id]);

  useFocusEffect(
    useCallback(() => {
      setLoading(true);
      void load();
    }, [load]),
  );

  const onApprove = async () => {
    if (!profile || !id) return;
    setSaving(true);
    const res = await aprobarRendicion(id, profile.id);
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert("Aprobada", "La rendición fue aprobada.");
    void load();
  };

  const reversar = async () => {
    if (!id) return;
    setSaving(true);
    setError(null);
    const res = await reversarRendicion(id);
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert("Cobranza reversada", res.message);
    void load();
  };

  const onReverse = () => {
    Alert.alert(
      "Reversar cobranza",
      "Sus órdenes vuelven a «por liquidar» y se revierte el saldo a favor que haya movido. Esta acción no se puede deshacer. ¿Continuar?",
      [
        { text: "Cancelar", style: "cancel" },
        {
          text: "Reversar",
          style: "destructive",
          onPress: () => void reversar(),
        },
      ],
    );
  };

  if (loading) return <LoadingBlock />;
  if (!item) {
    return (
      <View style={styles.root}>
        <ErrorText message={error ?? "Sin datos"} />
        <SecondaryButton label="Volver" onPress={() => router.back()} />
      </View>
    );
  }

  return (
    <ScrollView style={styles.root} contentContainerStyle={{ paddingBottom: 40 }}>
      <Text style={styles.title}>{item.cliente_razon}</Text>
      <Text style={styles.meta}>
        {formatDate(item.fecha_rendicion)} · {item.estado}
      </Text>
      <Text style={styles.meta}>
        Total ${formatMoney(item.total_recaudado_usd)} · Efectivo $
        {formatMoney(item.total_efectivo_recaudado)} · Transfer $
        {formatMoney(item.total_transferencias_recaudado)}
      </Text>
      {item.observaciones ? (
        <Text style={styles.meta}>{item.observaciones}</Text>
      ) : null}

      <SectionTitle>Órdenes</SectionTitle>
      {item.ordenes.map((o) => (
        <Text key={o.id} style={styles.meta}>
          #{o.correlativo ?? "—"} · ${formatMoney(o.recaudado)}
        </Text>
      ))}

      <SectionTitle>Pagos</SectionTitle>
      {item.pagos.map((p) => (
        <Text key={p.id} style={styles.meta}>
          {p.fpago_concepto ?? "Pago"} · ${formatMoney(p.monto_usd ?? p.monto)}
        </Text>
      ))}

      <ErrorText message={error} />
      {canApprove &&
      item.estado !== "aprobada" &&
      item.estado !== "reversada" ? (
        <PrimaryButton
          label="Aprobar rendición"
          loading={saving}
          onPress={() => void onApprove()}
        />
      ) : null}
      {canReverse && item.estado === "aprobada" ? (
        <SecondaryButton
          label={saving ? "Reversando…" : "Reversar cobranza"}
          onPress={onReverse}
        />
      ) : null}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F6F8", padding: 16 },
  title: { fontSize: 20, fontWeight: "700", color: "#0B3A5C" },
  meta: { color: "#5B6B7C", fontSize: 14, marginTop: 4 },
});
