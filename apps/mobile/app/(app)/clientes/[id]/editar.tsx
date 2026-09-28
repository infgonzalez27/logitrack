import { useCallback, useState } from "react";
import { Alert, ScrollView, StyleSheet } from "react-native";
import { useFocusEffect, useLocalSearchParams, useRouter } from "expo-router";
import {
  getClienteEditar,
  listDespachadoresOptions,
  listVendedoresOptions,
  updateCliente,
  type CatalogOption,
} from "@/lib/clientes";
import { listRutas } from "@/lib/rutas";
import { DescuentosClientePanel } from "@/components/descuentos-cliente-panel";
import {
  ErrorText,
  FormField,
  LoadingBlock,
  OptionChips,
  PrimaryButton,
  Screen,
} from "@/components/ui";

export default function EditarClienteScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
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
      if (!id) return;
      setLoading(true);
      void Promise.all([
        getClienteEditar(id),
        listVendedoresOptions(),
        listDespachadoresOptions(),
        listRutas(),
      ]).then(([cRes, vRes, dRes, rRes]) => {
        if (!cRes.ok) {
          setError(cRes.error);
        } else {
          const c = cRes.cliente;
          setRif(c.rif_nit);
          setRazon(c.razon_social);
          setDireccion(c.direccion_fiscal);
          setTelefono(c.telefono ?? "");
          setVendedorId(c.vendedor_id ?? "");
          setDespachadorId(c.despachador_id ?? "");
          setRutaId(c.id_ruta ?? "");
          setActivo(c.activo ? "true" : "false");
        }
        if (vRes.ok) setVendedores(vRes.options);
        if (dRes.ok) setDespachadores(dRes.options);
        if (rRes.ok) {
          const opts = rRes.rutas.map((r) => ({
            id: r.id_ruta,
            label: r.nombre_ruta,
          }));
          setRutas(opts);
          if (cRes.ok && !cRes.cliente.id_ruta && opts.length === 1) {
            setRutaId(opts[0].id);
          }
        }
        setLoading(false);
      });
    }, [id]),
  );

  async function guardar() {
    if (!id) return;
    setSaving(true);
    setError(null);
    const res = await updateCliente({
      id,
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
    Alert.alert("Listo", "Cliente actualizado.");
    router.back();
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
          label="Guardar cambios"
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
        {id ? <DescuentosClientePanel clienteId={id} /> : null}
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({ pad: { paddingBottom: 48 } });
