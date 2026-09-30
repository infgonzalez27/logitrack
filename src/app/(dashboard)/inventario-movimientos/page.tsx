import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { getNombresPerfilByIds } from "@/lib/data/perfiles";
import {
  ROLES_MOVIMIENTOS_ESPECIALES,
  labelConcepto,
} from "@/lib/inventario/movimientos-especiales";
import { formatCurrency, formatDate, formatNumber } from "@/lib/format";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { DataTable } from "@/components/ui/data-table";

type MovimientoRow = {
  id: string;
  fecha_movimiento: string;
  tipo_movimiento: string;
  concepto: string;
  tipo_inventario_afectado: string;
  id_referencia_movil: string | null;
  id_cliente: string | null;
  autorizado_por: string | null;
  observaciones: string | null;
  movimientos_inventario_detalle: Array<{
    id_producto: string;
    cantidad: number;
    costo_unitario: number;
  }>;
};

export default async function MovimientosInventarioPage() {
  const rol = getRoleNameFromProfile(await getCurrentProfile());
  if (!rol || !(ROLES_MOVIMIENTOS_ESPECIALES as readonly string[]).includes(rol)) {
    redirect("/");
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("movimientos_inventario")
    .select(
      "id, fecha_movimiento, tipo_movimiento, concepto, tipo_inventario_afectado, id_referencia_movil, id_cliente, autorizado_por, observaciones, movimientos_inventario_detalle(id_producto, cantidad, costo_unitario)",
    )
    .order("fecha_movimiento", { ascending: false })
    .limit(100);

  const movimientos = (data ?? []) as MovimientoRow[];
  const productoIds = [
    ...new Set(movimientos.flatMap((m) => m.movimientos_inventario_detalle.map((d) => d.id_producto))),
  ];
  const camionIds = [
    ...new Set(movimientos.map((m) => m.id_referencia_movil).filter((v): v is string => !!v)),
  ];
  const clienteIds = [
    ...new Set(movimientos.map((m) => m.id_cliente).filter((v): v is string => !!v)),
  ];

  const [productosRes, camionesRes, clientesRes, autores] = await Promise.all([
    productoIds.length
      ? supabase.from("productos").select("id, nombre").in("id", productoIds)
      : Promise.resolve({ data: [] as { id: string; nombre: string }[] }),
    camionIds.length
      ? supabase.from("camiones").select("id, placa").in("id", camionIds)
      : Promise.resolve({ data: [] as { id: string; placa: string }[] }),
    clienteIds.length
      ? supabase.from("clientes").select("id, razon_social").in("id", clienteIds)
      : Promise.resolve({ data: [] as { id: string; razon_social: string }[] }),
    getNombresPerfilByIds(
      movimientos.map((m) => m.autorizado_por).filter((v): v is string => !!v),
    ),
  ]);

  const productos = new Map((productosRes.data ?? []).map((p) => [p.id, p.nombre]));
  const camiones = new Map((camionesRes.data ?? []).map((c) => [c.id, c.placa]));
  const clientes = new Map((clientesRes.data ?? []).map((c) => [c.id, c.razon_social]));

  return (
    <div className="space-y-6">
      <PageHeader
        title="Movimientos especiales de inventario"
        description="Entradas y salidas fuera de compras y distribución: obsequios, consumo interno, eventos, mermas."
        action={
          <Button href="/inventario-movimientos/nuevo">Nuevo movimiento</Button>
        }
      />
      {error ? <p className="lt-alert-error">{error.message}</p> : null}
      <Card>
        <DataTable
          emptyMessage="Aún no hay movimientos especiales registrados."
          columns={[
            { key: "fecha", label: "Fecha" },
            { key: "tipo", label: "Tipo" },
            { key: "concepto", label: "Concepto" },
            { key: "inventario", label: "Inventario" },
            { key: "productos", label: "Productos" },
            { key: "costo", label: "Costo total", className: "text-right" },
            { key: "detalle", label: "Cliente / autorizó" },
          ]}
          rows={movimientos.map((m) => {
            const costo = m.movimientos_inventario_detalle.reduce(
              (s, d) => s + Number(d.cantidad) * Number(d.costo_unitario),
              0,
            );
            return {
              id: m.id,
              cells: {
                fecha: formatDate(m.fecha_movimiento),
                tipo: (
                  <Badge tone={m.tipo_movimiento === "ENTRADA" ? "success" : "warning"}>
                    {m.tipo_movimiento === "ENTRADA" ? "Entrada" : "Salida"}
                  </Badge>
                ),
                concepto: (
                  <div>
                    <p>{labelConcepto(m.concepto)}</p>
                    {m.observaciones ? (
                      <p className="text-xs text-lt-text-muted">{m.observaciones}</p>
                    ) : null}
                  </div>
                ),
                inventario:
                  m.tipo_inventario_afectado === "MOVIL"
                    ? `Camión ${camiones.get(m.id_referencia_movil ?? "") ?? "—"}`
                    : "Almacén",
                productos: (
                  <ul className="space-y-0.5">
                    {m.movimientos_inventario_detalle.map((d, i) => (
                      <li key={`${d.id_producto}-${i}`}>
                        {formatNumber(Number(d.cantidad))} ×{" "}
                        {productos.get(d.id_producto) ?? "Producto"}
                      </li>
                    ))}
                  </ul>
                ),
                costo: formatCurrency(costo),
                detalle: (
                  <div className="text-xs">
                    {m.id_cliente ? <p>{clientes.get(m.id_cliente) ?? "—"}</p> : null}
                    <p className="text-lt-text-muted">
                      {autores[m.autorizado_por ?? ""] ?? "—"}
                    </p>
                  </div>
                ),
              },
            };
          })}
        />
      </Card>
    </div>
  );
}
