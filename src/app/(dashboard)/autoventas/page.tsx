import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { listarProductosAction } from "@/lib/actions/productos";
import { joinOne } from "@/lib/supabase/join";
import { PageHeader } from "@/components/layout/page-header";
import { AutoVentasClient } from "./autoventas-client";

export default async function AutoVentasPage() {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (
    rol !== "admin" &&
    rol !== "gerente" &&
    rol !== "vendedor" &&
    rol !== "despachador"
  ) {
    redirect("/");
  }

  const supabase = await createClient();
  const hoy = new Date();
  const inicioDia = new Date(
    hoy.getFullYear(),
    hoy.getMonth(),
    hoy.getDate(),
  ).toISOString();

  const [
    { data: camionesData },
    { data: clientesData },
    productosResult,
    { data: contenedoresData },
    { data: inventarioMovilData },
    { data: ordenesData },
    { data: tasaData },
  ] = await Promise.all([
    supabase
      .from("camiones")
      .select("id, placa, modelo, estado")
      .in("estado", ["en_ruta", "asignado", "disponible"])
      .order("placa", { ascending: true }),
    supabase
      .from("clientes")
      .select("id, razon_social, rif_nit, direccion_fiscal")
      .eq("activo", true)
      .order("razon_social", { ascending: true }),
    listarProductosAction(),
    supabase
      .from("tipos_contenedores")
      .select("id, codigo, nombre")
      .order("nombre", { ascending: true }),
    supabase
      .from("inventario_movil")
      .select(
        "id, camion_id, producto_id, cantidad_cargada, cantidad_entregada, productos(codigo_producto, nombre, precio_lista1, imagen_path)",
      ),
    supabase
      .from("ordenes_distribucion")
      .select(
        "id, correlativo, factura_origen_numero, estado, total_recaudar_usd, total_recaudar_bs, created_at, camion_id, es_autoventa, clientes(razon_social)",
      )
      .eq("es_autoventa", true)
      .gte("created_at", inicioDia)
      .order("created_at", { ascending: false }),
    supabase
      .from("tasa_cambio")
      .select("tasa_cambio")
      .order("fecha_tasa", { ascending: false })
      .order("created_at", { ascending: false })
      .limit(1),
  ]);

  const tasaOficial = Number(tasaData?.[0]?.tasa_cambio || 1);
  const productos = productosResult.ok ? productosResult.productos : [];

  const inventarioMovil = (inventarioMovilData ?? []).map((row) => {
    const prod = joinOne(row.productos);
    return {
      id: String(row.id),
      camion_id: String(row.camion_id),
      producto_id: String(row.producto_id),
      cantidad_cargada: Number(row.cantidad_cargada || 0),
      cantidad_entregada: Number(row.cantidad_entregada || 0),
      productos: prod
        ? {
            codigo_producto: String(prod.codigo_producto ?? ""),
            nombre: String(prod.nombre ?? ""),
            precio_lista1: Number(prod.precio_lista1 || 0),
            imagen_path: prod.imagen_path
              ? String(prod.imagen_path)
              : null,
          }
        : null,
    };
  });

  const ordenesJornada = (ordenesData ?? []).map((row) => {
    const cli = joinOne(row.clientes);
    return {
      id: String(row.id),
      correlativo: Number(row.correlativo),
      factura_origen_numero: String(row.factura_origen_numero ?? ""),
      estado: String(row.estado ?? ""),
      total_recaudar_usd: Number(row.total_recaudar_usd || 0),
      total_recaudar_bs: Number(row.total_recaudar_bs || 0),
      created_at: String(row.created_at),
      camion_id: String(row.camion_id),
      clientes: cli
        ? { razon_social: String(cli.razon_social ?? "—") }
        : null,
    };
  });

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <PageHeader
        title="AutoVentas (venta en ruta)"
        description="Carga el camión, vende en caliente sin radar y liquida por rendición. Las órdenes con es_autoventa no entran al radar."
      />

      {!productosResult.ok ? (
        <p className="lt-alert-error">{productosResult.error}</p>
      ) : null}

      <AutoVentasClient
        camiones={(camionesData ?? []).map((c) => ({
          id: String(c.id),
          placa: String(c.placa ?? ""),
          modelo: c.modelo ? String(c.modelo) : null,
          estado: String(c.estado ?? ""),
        }))}
        clientes={(clientesData ?? []).map((c) => ({
          id: String(c.id),
          razon_social: String(c.razon_social ?? ""),
          rif_nit: String(c.rif_nit ?? ""),
          direccion_fiscal: c.direccion_fiscal
            ? String(c.direccion_fiscal)
            : null,
        }))}
        productos={productos}
        contenedores={(contenedoresData ?? []).map((t) => ({
          id: String(t.id),
          codigo: t.codigo ? String(t.codigo) : null,
          nombre: String(t.nombre ?? ""),
        }))}
        inventarioMovil={inventarioMovil}
        ordenesJornada={ordenesJornada}
        vendedorId={profile?.id || ""}
        tasaOficial={tasaOficial}
      />
    </div>
  );
}
