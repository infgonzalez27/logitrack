import { createClient } from "@/lib/supabase/server";
import { getCurrentProfile } from "@/lib/auth";
import { joinOne } from "@/lib/supabase/join";
import { PageHeader } from "@/components/layout/page-header";
import { AutoVentasClient } from "./autoventas-client";

export default async function AutoVentasPage() {
  const supabase = await createClient();
  const profile = await getCurrentProfile();

  // Fetch camiones, clientes, productos, contenedores, inventario_movil, y tasa_cambio en paralelo
  const [
    { data: camionesData },
    { data: clientesData },
    { data: productosData },
    { data: contenedoresData },
    { data: inventarioMovilData },
    { data: ordenesData },
    { data: tasaData },
  ] = await Promise.all([
    supabase
      .from("camiones")
      .select("id, placa, modelo, estado")
      .order("placa", { ascending: true }),
    supabase
      .from("clientes")
      .select("id, nombre_negocio, rif, direccion")
      .order("nombre_negocio", { ascending: true }),
    supabase
      .from("productos")
      .select("id, codigo, nombre, precio_lista1")
      .order("nombre", { ascending: true }),
    supabase
      .from("contenedores")
      .select("id, tipo, capacidad")
      .order("tipo", { ascending: true }),
    supabase
      .from("inventario_movil")
      .select("id, camion_id, producto_id, cantidad_cargada, cantidad_entregada, productos(codigo, nombre, precio_lista1)"),
    supabase
      .from("ordenes_distribucion")
      .select("id, correlativo, factura_origen_numero, estado, total_recaudar_usd, total_recaudar_bs, created_at, camion_id, es_autoventa, clientes(nombre_negocio)")
      .eq("es_autoventa", true)
      .order("created_at", { ascending: false }),
    supabase
      .from("tasa_cambio")
      .select("tasa_cambio")
      .order("fecha_tasa", { ascending: false })
      .order("created_at", { ascending: false })
      .limit(1),
  ]);

  const tasaOficial = Number(tasaData?.[0]?.tasa_cambio || 1.0);

  const inventarioMovilFormatted = (inventarioMovilData ?? []).map((row) => {
    const prod = joinOne(row.productos);
    return {
      id: row.id,
      camion_id: row.camion_id,
      producto_id: row.producto_id,
      cantidad_cargada: Number(row.cantidad_cargada || 0),
      cantidad_entregada: Number(row.cantidad_entregada || 0),
      productos: prod
        ? {
            codigo: prod.codigo,
            nombre: prod.nombre,
            precio_lista1: Number(prod.precio_lista1 || 0),
          }
        : null,
    };
  });

  const ordenesJornadaFormatted = (ordenesData ?? []).map((row) => {
    const cli = joinOne(row.clientes);
    return {
      id: row.id,
      correlativo: row.correlativo,
      factura_origen_numero: row.factura_origen_numero,
      estado: row.estado,
      total_recaudar_usd: Number(row.total_recaudar_usd || 0),
      total_recaudar_bs: Number(row.total_recaudar_bs || 0),
      created_at: row.created_at,
      clientes: cli ? { nombre_negocio: cli.nombre_negocio } : null,
    };
  });

  return (
    <div className="space-y-6">
      <PageHeader
        title="AutoVentas (Venta en Ruta)"
        description="Gestión de Almacén Móvil y Venta en Caliente sin Radar"
      />

      <AutoVentasClient
        camiones={camionesData ?? []}
        clientes={clientesData ?? []}
        productos={productosData ?? []}
        contenedores={contenedoresData ?? []}
        inventarioMovil={inventarioMovilFormatted}
        ordenesJornada={ordenesJornadaFormatted}
        vendedorId={profile?.id || ""}
        tasaOficial={tasaOficial}
      />
    </div>
  );
}
