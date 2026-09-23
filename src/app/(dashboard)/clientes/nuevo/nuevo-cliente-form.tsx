"use client";

import { useActionState, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClienteAction } from "@/lib/actions/entities";
import { DescuentosClientePanel } from "@/components/clientes/descuentos-cliente-panel";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Button } from "@/components/ui/button";

type Option = { value: string; label: string };
type FormState = { error?: string; success?: boolean; id?: string } | null;

export function NuevoClienteForm({
  vendedores,
  rutas,
  rutaUnica,
  despachadores,
  vendedoresError = null,
  rutasError = null,
  despachadoresError = null,
}: {
  vendedores: Option[];
  rutas: Option[];
  rutaUnica: Option | null;
  despachadores: Option[];
  vendedoresError?: string | null;
  rutasError?: string | null;
  despachadoresError?: string | null;
}) {
  const router = useRouter();
  const [clienteId, setClienteId] = useState<string | null>(null);
  const [razonSocial, setRazonSocial] = useState("");

  const [state, formAction, pending] = useActionState<FormState, FormData>(
    createClienteAction,
    null,
  );

  useEffect(() => {
    if (state?.success && state.id) {
      setClienteId(state.id);
    }
  }, [state]);

  if (clienteId) {
    return (
      <div className="space-y-6">
        <Card title="Cliente creado">
          <p className="text-sm text-lt-text">
            <span className="font-semibold">{razonSocial || "Cliente"}</span>{" "}
            quedó registrado. Ahora puedes asignar descuentos por producto.
          </p>
          <div className="mt-4 flex flex-wrap gap-2">
            <Button
              type="button"
              variant="secondary"
              onClick={() => router.push(`/clientes/${clienteId}`)}
            >
              Ir a la ficha completa
            </Button>
            <Button
              type="button"
              variant="secondary"
              onClick={() => router.push("/clientes")}
            >
              Volver al listado
            </Button>
          </div>
        </Card>

        <Card title="Descuentos por producto">
          <DescuentosClientePanel clienteId={clienteId} />
        </Card>
      </div>
    );
  }

  return (
    <form action={formAction} className="space-y-6">
      <Card title="Ficha del cliente">
        <div className="space-y-4">
          <Input label="RIF/NIT" name="rif_nit" required />
          <Input
            label="Razón social"
            name="razon_social"
            required
            value={razonSocial}
            onChange={(e) => setRazonSocial(e.target.value)}
          />
          <Input label="Dirección fiscal" name="direccion_fiscal" required />
          <Input label="Teléfono" name="telefono" />
          <Input label="Móvil" name="movil1" />
          <Input label="Correo" name="correo_e" type="email" />
          <Select
            label="Vendedor asignado"
            name="vendedor_id"
            placeholder="Sin asignar"
            options={vendedores}
          />

          {rutasError ? (
            <p className="text-sm text-lt-danger-text">{rutasError}</p>
          ) : rutas.length === 0 ? (
            <p className="text-sm text-amber-700">
              No hay rutas disponibles en la licencia. El administrador de BD
              debe provisionarlas antes de asignar.
            </p>
          ) : rutaUnica ? (
            <div className="space-y-1.5">
              <input type="hidden" name="id_ruta" value={rutaUnica.value} />
              <Input label="Ruta" readOnly value={rutaUnica.label} />
              <p className="text-xs text-lt-text-muted">
                Asignada automáticamente (solo hay 1 ruta en la licencia).
              </p>
            </div>
          ) : (
            <Select
              label="Ruta"
              name="id_ruta"
              required
              placeholder="Selecciona ruta"
              options={rutas}
            />
          )}

          <Select
            label="Despachador"
            name="despachador_id"
            required
            placeholder="Selecciona despachador"
            options={despachadores}
          />
          {vendedoresError ? (
            <p className="text-sm text-lt-danger-text">{vendedoresError}</p>
          ) : null}
          {despachadoresError ? (
            <p className="text-sm text-lt-danger-text">{despachadoresError}</p>
          ) : null}
          {!despachadoresError && despachadores.length === 0 ? (
            <p className="text-sm text-amber-700">
              No hay usuarios con rol despachador activos.
            </p>
          ) : null}
        </div>
      </Card>

      <Card title="Políticas de crédito y despacho">
        <div className="space-y-4">
          <Input
            label="Límite de crédito"
            name="limite_credito"
            type="number"
            min={0}
            step="0.01"
            defaultValue="0"
          />
          <Input
            label="Máx. facturas vencidas"
            name="max_facturas_vencidas"
            type="number"
            min={0}
            step={1}
            defaultValue="0"
          />
          <Select
            label="Permiso de despacho manual"
            name="permiso_despacho_manual"
            options={[
              { value: "true", label: "Permitido" },
              { value: "false", label: "No permitido" },
            ]}
            defaultValue="false"
          />
        </div>
      </Card>

      <Card title="Descuentos por producto">
        <p className="text-sm text-lt-text-muted">
          Primero guarda el cliente. Después de crearlo podrás asignar aquí los
          productos con descuento o precio pactado.
        </p>
      </Card>

      {state?.error ? <p className="lt-alert-error">{state.error}</p> : null}
      {pending ? (
        <p className="text-sm text-lt-text-muted">Guardando…</p>
      ) : null}

      <Button type="submit" disabled={pending}>
        {pending ? "Guardando…" : "Guardar cliente"}
      </Button>
    </form>
  );
}
