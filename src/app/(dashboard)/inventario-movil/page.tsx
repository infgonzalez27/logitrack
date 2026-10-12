import { createClient } from "@/lib/supabase/server";
import { joinOne } from "@/lib/supabase/join";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import {
  InventarioMovilTabla,
  type InventarioMovilFila,
  type CamionFiltro,
} from "./inventario-movil-tabla";

export default async function InventarioMovilPage({
  searchParams,
}: {
  searchParams?: Promise<{ camion_id?: string }>;
}) {
  const resolvedParams = searchParams ? await searchParams : {};
  const initialCamionId =
    typeof resolvedParams.camion_id === "string"
      ? resolvedParams.camion_id
      : "";

  const supabase = await createClient();

  const [{ data: camionesData }, { data: inventarioData }] = await Promise.all([
    supabase
      .from("camiones")
      .select("id, placa, modelo, estado")
      .order("placa", { ascending: true }),
    supabase
      .from("inventario_movil")
      .select("*, camiones(id, placa, modelo), productos(id, nombre, codigo_producto, codigo_barras)")
      .order("updated_at", { ascending: false }),
  ]);

  const camiones: CamionFiltro[] = (camionesData ?? []).map((c) => ({
    id: c.id,
    placa: c.placa,
    modelo: c.modelo ?? null,
    estado: c.estado ?? null,
  }));

  const filas: InventarioMovilFila[] = (inventarioData ?? []).map((row) => {
    const camion = joinOne(row.camiones);
    const prod = joinOne(row.productos);
    const cargada = Number(row.cantidad_cargada || 0);
    const entregada = Number(row.cantidad_entregada || 0);
    const devolucion = Number(row.cantidad_devolucion || 0);
    const disponible = Math.max(0, cargada - entregada);

    return {
      id: row.id,
      camion_id: String(row.camion_id),
      camion_placa: camion?.placa ?? "—",
      camion_modelo: camion?.modelo ?? null,
      producto_id: String(row.producto_id),
      producto_nombre: prod?.nombre ?? "—",
      codigo_producto: prod?.codigo_producto ?? null,
      codigo_barras: prod?.codigo_barras ?? null,
      cantidad_cargada: cargada,
      cantidad_entregada: entregada,
      cantidad_devolucion: devolucion,
      disponible,
    };
  });

  return (
    <div className="space-y-6">
      <PageHeader
        title="Inventario móvil"
        description="Consulta y gestión de stock cargado por unidad de transporte"
        action={
          <Button href={initialCamionId ? `/inventario-movil/nuevo?camion_id=${initialCamionId}` : "/inventario-movil/nuevo"}>
            Registrar carga
          </Button>
        }
      />
      <InventarioMovilTabla
        filas={filas}
        camiones={camiones}
        initialCamionId={initialCamionId}
      />
    </div>
  );
}
