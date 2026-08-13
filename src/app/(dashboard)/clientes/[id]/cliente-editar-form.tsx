"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import {
  actualizarClienteAction,
  type ClienteEditarInput,
} from "@/lib/actions/clientes";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Button } from "@/components/ui/button";

type Option = { value: string; label: string };

export function ClienteEditarForm({
  cliente,
  vendedores,
  rutas,
  despachadores,
}: {
  cliente: ClienteEditarInput;
  vendedores: Option[];
  rutas: Option[];
  despachadores: Option[];
}) {
  const router = useRouter();
  const [rifNit, setRifNit] = useState(cliente.rif_nit);
  const [razonSocial, setRazonSocial] = useState(cliente.razon_social);
  const [direccionFiscal, setDireccionFiscal] = useState(
    cliente.direccion_fiscal,
  );
  const [telefono, setTelefono] = useState(cliente.telefono ?? "");
  const [movil1, setMovil1] = useState(cliente.movil1 ?? "");
  const [correoE, setCorreoE] = useState(cliente.correo_e ?? "");
  const [vendedorId, setVendedorId] = useState(cliente.vendedor_id ?? "");
  const [idRuta, setIdRuta] = useState(cliente.id_ruta ?? "");
  const [despachadorId, setDespachadorId] = useState(
    cliente.despachador_id ?? "",
  );
  const [activo, setActivo] = useState(cliente.activo);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setPending(true);
    setError(null);

    const result = await actualizarClienteAction({
      id: cliente.id,
      rif_nit: rifNit,
      razon_social: razonSocial,
      direccion_fiscal: direccionFiscal,
      telefono: telefono || null,
      movil1: movil1 || null,
      correo_e: correoE || null,
      vendedor_id: vendedorId || null,
      id_ruta: idRuta || null,
      despachador_id: despachadorId || null,
      activo,
    });

    if (!result.ok) {
      setError(result.error);
      setPending(false);
      return;
    }

    router.push("/clientes");
    router.refresh();
  }

  return (
    <Card title="Ficha del cliente">
      <form onSubmit={handleSubmit} className="space-y-4">
        <Input
          label="RIF/NIT"
          required
          value={rifNit}
          onChange={(e) => setRifNit(e.target.value)}
        />
        <Input
          label="Razón social"
          required
          value={razonSocial}
          onChange={(e) => setRazonSocial(e.target.value)}
        />
        <Input
          label="Dirección fiscal"
          required
          value={direccionFiscal}
          onChange={(e) => setDireccionFiscal(e.target.value)}
        />
        <Input
          label="Teléfono"
          value={telefono}
          onChange={(e) => setTelefono(e.target.value)}
        />
        <Input
          label="Móvil"
          value={movil1}
          onChange={(e) => setMovil1(e.target.value)}
        />
        <Input
          label="Correo"
          type="email"
          value={correoE}
          onChange={(e) => setCorreoE(e.target.value)}
        />
        <Select
          label="Vendedor asignado"
          placeholder="Sin asignar"
          options={vendedores}
          value={vendedorId}
          onChange={(e) => setVendedorId(e.target.value)}
        />
        {rutas.length === 0 ? (
          <p className="text-sm text-amber-700">
            No hay rutas disponibles en la licencia.
          </p>
        ) : (
          <Select
            label="Ruta"
            required
            placeholder="Selecciona ruta"
            options={rutas}
            value={idRuta}
            onChange={(e) => setIdRuta(e.target.value)}
          />
        )}
        <Select
          label="Despachador"
          required
          placeholder="Selecciona despachador"
          options={despachadores}
          value={despachadorId}
          onChange={(e) => setDespachadorId(e.target.value)}
        />
        <Select
          label="Estado"
          options={[
            { value: "true", label: "Activo" },
            { value: "false", label: "Inactivo" },
          ]}
          value={activo ? "true" : "false"}
          onChange={(e) => setActivo(e.target.value === "true")}
        />

        {error ? <p className="lt-alert-error">{error}</p> : null}

        <div className="flex gap-3">
          <Button type="submit" disabled={pending}>
            {pending ? "Guardando…" : "Guardar cambios"}
          </Button>
          <Button
            type="button"
            variant="secondary"
            onClick={() => router.push("/clientes")}
          >
            Cancelar
          </Button>
        </div>
      </form>
    </Card>
  );
}
