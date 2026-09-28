import { useCallback, useState } from "react";
import { Alert, ScrollView, StyleSheet } from "react-native";
import { useFocusEffect, useRouter, type Href } from "expo-router";
import {
  createCliente,
  listDespachadoresOptions,
  listVendedoresOptions,
  type CatalogOption,
} from "@/lib/clientes";
import { listRutas } from "@/lib/rutas";
import {
  ErrorText,
  FormField,
  LoadingBlock,
  OptionChips,
  PrimaryButton,
  Screen,
} from "@/components/ui";

export default function NuevoClienteScreen() {
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [rif, setRif] = useState("");
  const [razon, setRazon] = useState("");
  const [direccion, setDireccion] = useState("");
  const [telefono, setTelefono] = useState("");
  const [vendedorId, setVendedorId] = useState("");
  const [despachadorId, setDespachadorId] = useState("");
  const [rutaId, setRutaId] = useState("");
  const [activo, setActivo] = useState("true");
  const [vendedores, setVendedores] = useState<CatalogOption[]>([]);
  const [despachadores, setDespachadores] = useState<CatalogOption[]>([]);
  const [rutas, setRutas] = useState<CatalogOption[]>([]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      setLoading(true);
      void Promise.all([
        listVendedoresOptions(),
        listDespachadoresOptions(),
        listRutas(),
      ]).then(([vRes, dRes, rRes]) => {
        if (vRes.ok) setVendedores(vRes.options);
        if (dRes.ok) setDespachadores(dRes.options);
        if (rRes.ok) {
          const opts = rRes.rutas.map((r) => ({
            id: r.id_ruta,
            label: r.nombre_ruta,
          }));
          setRutas(opts);
          if (opts.length === 1) setRutaId(opts[0].id);
        }
        if (!vRes.ok) setError(vRes.error);
        else if (!dRes.ok) setError(dRes.error);
        else if (!rRes.ok) setError(rRes.error);
        setLoading(false);
      });
    }, []),
  );

  async function guardar() {
    setSaving(true);
    setError(null);
    const res = await createCliente({
      rif_nit: rif,
      razon_social: razon,
      direccion_fiscal: direccion,
      telefono,
      vendedor_id: vendedorId || null,
      despachador_id: despachadorId || null,
      id_ruta: rutaId || null,
      activo: activo === "true",
    });
    setSaving(false);
    if (!res.ok) {
      setError(res.error);
      return;
    }
    Alert.alert("Listo", "Cliente creado.");
    router.replace(`/(app)/clientes/${res.id}/editar` as Href);
  }

  if (loading) return <LoadingBlock />;

  return (
    <Screen>
      <ScrollView contentContainerStyle={styles.pad}>
        <ErrorText message={error} />
        <FormField label="RIF/NIT" value={rif} onChangeText={setRif} />
        <FormField
          label="Razón social"
          value={razon}
          onChangeText={setRazon}
        />
        <FormField
          label="Dirección fiscal"
          value={direccion}
          onChangeText={setDireccion}
        />
        <FormField
          label="Teléfono"
          value={telefono}
          onChangeText={setTelefono}
          keyboardType="phone-pad"
        />
        <OptionChips
          label="Vendedor"
          value={vendedorId}
          onChange={setVendedorId}
          allowEmpty
          emptyLabel="Sin asignar"
          options={vendedores.map((o) => ({
            value: o.id,
            label: o.label,
          }))}
        />
        <OptionChips
          label="Ruta"
          value={rutaId}
          onChange={setRutaId}
          options={rutas.map((o) => ({ value: o.id, label: o.label }))}
        />
        <OptionChips
          label="Despachador"
          value={despachadorId}
          onChange={setDespachadorId}
          options={despachadores.map((o) => ({
            value: o.id,
            label: o.label,
          }))}
        />
        <OptionChips
          label="Estado"
          value={activo}
          onChange={setActivo}
          options={[
            { value: "true", label: "Activo" },
            { value: "false", label: "Inactivo" },
          ]}
        />
        <PrimaryButton
          label="Guardar cliente"
          onPress={() => void guardar()}
          loading={saving}
          disabled={
            !rif.trim() ||
            !razon.trim() ||
            !direccion.trim() ||
            !rutaId ||
            !despachadorId
          }
        />
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({ pad: { paddingBottom: 40 } });
