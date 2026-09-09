"use client";

import { useState, useTransition } from "react";
import {
  actualizarCuentaBancariaEmpresaAction,
  crearCuentaBancariaEmpresaAction,
} from "@/lib/actions/cuentas-bancarias";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { DataTable } from "@/components/ui/data-table";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import type { CuentaBancariaEmpresa } from "@/types/database";

export function CuentasBancariasClient({
  cuentasIniciales,
  puedeGestionar,
}: {
  cuentasIniciales: CuentaBancariaEmpresa[];
  puedeGestionar: boolean;
}) {
  const [cuentas, setCuentas] = useState(cuentasIniciales);
  const [editId, setEditId] = useState<string | null>(null);
  const [cuentaBancaria, setCuentaBancaria] = useState("");
  const [entidadBancaria, setEntidadBancaria] = useState("");
  const [statusCuenta, setStatusCuenta] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [okMsg, setOkMsg] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function limpiarFormulario() {
    setEditId(null);
    setCuentaBancaria("");
    setEntidadBancaria("");
    setStatusCuenta(true);
  }

  function cargarParaEditar(cuenta: CuentaBancariaEmpresa) {
    setEditId(cuenta.id);
    setCuentaBancaria(cuenta.cuenta_bancaria);
    setEntidadBancaria(cuenta.entidad_bancaria);
    setStatusCuenta(cuenta.status_cuenta);
    setError(null);
    setOkMsg(null);
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setOkMsg(null);

    startTransition(async () => {
      if (editId) {
        const result = await actualizarCuentaBancariaEmpresaAction({
          id: editId,
          cuenta_bancaria: cuentaBancaria,
          entidad_bancaria: entidadBancaria,
          status_cuenta: statusCuenta,
        });
        if (!result.ok) {
          setError(result.error);
          return;
        }
        setCuentas((prev) =>
          prev.map((c) => (c.id === result.cuenta.id ? result.cuenta : c)),
        );
        setOkMsg("Cuenta bancaria actualizada.");
        limpiarFormulario();
        return;
      }

      const result = await crearCuentaBancariaEmpresaAction({
        cuenta_bancaria: cuentaBancaria,
        entidad_bancaria: entidadBancaria,
      });
      if (!result.ok) {
        setError(result.error);
        return;
      }
      setCuentas((prev) => [...prev, result.cuenta]);
      setOkMsg("Cuenta bancaria registrada.");
      limpiarFormulario();
    });
  }

  const rows = cuentas.map((c) => ({
    id: c.id,
    cells: {
      entidad: c.entidad_bancaria,
      cuenta: c.cuenta_bancaria,
      estado: (
        <Badge tone={c.status_cuenta ? "success" : "warning"}>
          {c.status_cuenta ? "Activa" : "Suspendida"}
        </Badge>
      ),
      acciones: puedeGestionar ? (
        <Button
          type="button"
          variant="ghost"
          disabled={pending}
          onClick={() => cargarParaEditar(c)}
        >
          Modificar
        </Button>
      ) : (
        "—"
      ),
    },
  }));

  return (
    <div className="space-y-4">
      {puedeGestionar ? (
        <Card title={editId ? "Modificar cuenta" : "Registrar cuenta"}>
          <form onSubmit={handleSubmit} className="space-y-4">
            <Input
              label="Entidad bancaria"
              required
              value={entidadBancaria}
              onChange={(e) => setEntidadBancaria(e.target.value)}
              placeholder="Ej. Banco de Venezuela"
            />
            <Input
              label="Número de cuenta"
              required
              value={cuentaBancaria}
              onChange={(e) => setCuentaBancaria(e.target.value)}
              placeholder="Ej. 0102-0123-45-6789012345"
              maxLength={20}
            />
            {editId ? (
              <Select
                label="Estatus"
                options={[
                  { value: "true", label: "Activa" },
                  { value: "false", label: "Suspendida" },
                ]}
                value={statusCuenta ? "true" : "false"}
                onChange={(e) => setStatusCuenta(e.target.value === "true")}
              />
            ) : null}

            {error ? <p className="lt-alert-error">{error}</p> : null}
            {okMsg ? <p className="lt-alert-success">{okMsg}</p> : null}

            <div className="flex flex-wrap gap-2">
              <Button type="submit" disabled={pending}>
                {pending
                  ? "Guardando…"
                  : editId
                    ? "Guardar cambios"
                    : "Registrar"}
              </Button>
              {editId ? (
                <Button
                  type="button"
                  variant="secondary"
                  disabled={pending}
                  onClick={limpiarFormulario}
                >
                  Cancelar
                </Button>
              ) : null}
            </div>
          </form>
        </Card>
      ) : (
        <p className="text-sm text-lt-text-muted">
          Solo admin o gerente pueden registrar o modificar cuentas.
        </p>
      )}

      <Card title="Cuentas registradas">
        <DataTable
          columns={[
            { key: "entidad", label: "Entidad" },
            { key: "cuenta", label: "Cuenta" },
            { key: "estado", label: "Estatus" },
            { key: "acciones", label: "Acciones" },
          ]}
          rows={rows}
          emptyMessage="No hay cuentas bancarias registradas."
        />
      </Card>
    </div>
  );
}
