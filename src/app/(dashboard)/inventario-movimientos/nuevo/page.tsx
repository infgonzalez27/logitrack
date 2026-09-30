import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { joinOne } from "@/lib/supabase/join";
import { ROLES_MOVIMIENTOS_ESPECIALES } from "@/lib/inventario/movimientos-especiales";
import { PageHeader } from "@/components/layout/page-header";
import { MovimientoForm } from "./movimiento-form";

export default async function NuevoMovimientoInventarioPage() {
  const rol = getRoleNameFromProfile(await getCurrentProfile());
  if (!rol || !(ROLES_MOVIMIENTOS_ESPECIALES as readonly string[]).includes(rol)) {
    redirect("/");
  }

  const supabase = await createClient();
  const [productos, camiones, clientes, almacen, movil, compras] = await Promise.all([
    supabase
      .from("productos")
      .select("id, nombre, codigo_producto")
      .order("nombre", { ascending: true }),
    supabase
      .from("camiones")
      .select("id, placa, modelo")
      .neq("estado", "inactivo")
      .order("placa", { ascending: true }),
    supabase
      .from("clientes")
      .select("id, razon_social, rif_nit")
      .eq("activo", true)
      .order("razon_social", { ascending: true }),
    supabase.from("inventario_almacen").select("producto_id, stock_disponible"),
    supabase
      .from("inventario_movil")
      .select("camion_id, producto_id, cantidad_cargada, cantidad_entregada"),
    supabase
      .from("detalle_facturas_compras")
      .select("producto_id, precio_unitario_compra, facturas_compras(fecha_emision, created_at)")
      .limit(5000),
  ]);

  const ultimoCosto: Record<string, number> = {};
  const fechaCosto: Record<string, string> = {};
  for (const d of compras.data ?? []) {
    const f = joinOne(d.facturas_compras);
    const fecha = String(f?.fecha_emision ?? f?.created_at ?? "");
    const pid = String(d.producto_id ?? "");
    if (!pid) continue;
    if (!fechaCosto[pid] || fecha > fechaCosto[pid]) {
      fechaCosto[pid] = fecha;
      ultimoCosto[pid] = Number(d.precio_unitario_compra) || 0;
    }
  }

  const stockAlmacen: Record<string, number> = {};
  for (const r of almacen.data ?? []) {
    if (r.producto_id) stockAlmacen[r.producto_id] = Number(r.stock_disponible) || 0;
  }

  const stockMovil: Record<string, Record<string, number>> = {};
  for (const r of movil.data ?? []) {
    if (!r.camion_id || !r.producto_id) continue;
    (stockMovil[r.camion_id] ??= {})[r.producto_id] = Math.max(
      0,
      (Number(r.cantidad_cargada) || 0) - (Number(r.cantidad_entregada) || 0),
    );
  }

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <PageHeader
        title="Nuevo movimiento especial"
        description="Registra una entrada o salida de inventario que no viene de una compra ni de una distribución."
      />
      <MovimientoForm
        productos={(productos.data ?? []).map((p) => ({
          id: p.id,
          nombre: p.nombre,
          codigo: p.codigo_producto ?? null,
        }))}
        camiones={(camiones.data ?? []).map((c) => ({
          id: c.id,
          label: c.modelo ? `${c.placa} — ${c.modelo}` : c.placa,
        }))}
        clientes={(clientes.data ?? []).map((c) => ({
          value: c.id,
          label: c.razon_social,
          hint: c.rif_nit ?? null,
        }))}
        stockAlmacen={stockAlmacen}
        stockMovil={stockMovil}
        ultimoCosto={ultimoCosto}
      />
    </div>
  );
}
