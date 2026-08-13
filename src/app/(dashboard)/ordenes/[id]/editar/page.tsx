import { notFound, redirect } from "next/navigation";
import { getCurrentProfile, getSessionUser } from "@/lib/auth";
import { canEditarOrdenBorrador } from "@/lib/auth/orden-permissions";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { listarCamionesParaOrdenAction } from "@/lib/actions/entities";
import { retornaUsuariosDespachadoresAction } from "@/lib/actions/rutas";
import { retornaUltimaTasaCambioAction } from "@/lib/actions/tasa-cambio";
import { getOrdenDistribucionDetalle } from "@/lib/data/ordenes";
import { createClient } from "@/lib/supabase/server";
import { EditarOrdenForm } from "./editar-orden-form";
import type { ProductoListaRpc } from "@/types/database";

function toDatetimeLocal(value: string | null): string {
  if (!value) return "";
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return "";
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export default async function EditarOrdenPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const [user, profile] = await Promise.all([
    getSessionUser(),
    getCurrentProfile(),
  ]);
  const rol = getRoleNameFromProfile(profile);

  const orden = await getOrdenDistribucionDetalle(id, {
    userId: user?.id,
    rol,
  });
  if (!orden) notFound();

  const puedeEditar = canEditarOrdenBorrador(rol, orden.estado, {
    esCreador: !!user && orden.creado_por === user.id,
  });
  if (!puedeEditar) {
    redirect(`/ordenes/${orden.id}`);
  }

  const supabase = await createClient();
  const [
    { data: clientes },
    camionesResult,
    despachadoresResult,
    { data: productosRpc },
    tasaResult,
  ] = await Promise.all([
    supabase
      .from("clientes")
      .select("id, razon_social, despachador_id")
      .eq("activo", true)
      .order("razon_social"),
    listarCamionesParaOrdenAction(),
    retornaUsuariosDespachadoresAction(),
    supabase.rpc("retorna_lista_productos"),
    retornaUltimaTasaCambioAction(),
  ]);

  const despachadorNombrePorId = new Map(
    (despachadoresResult.ok ? despachadoresResult.despachadores : []).map(
      (d) => [d.id, d.nombre_completo],
    ),
  );

  const detalle = [...(orden.detalle_distribucion ?? [])].sort(
    (a, b) => (a.secuencia_entrega ?? 0) - (b.secuencia_entrega ?? 0),
  );

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <EditarOrdenForm
        correlativo={orden.correlativo}
        ordenId={orden.id}
        initial={{
          cliente_id: orden.cliente_id,
          camion_id: orden.camion_id,
          factura_origen_numero: orden.factura_origen_numero,
          fecha_despacho: toDatetimeLocal(orden.fecha_despacho),
          lineas: detalle.map((l) => ({
            producto_id: l.producto_id,
            cantidad_solicitada: l.cantidad_solicitada,
            valor_unitario_recaudar: Number(l.valor_unitario_recaudar),
          })),
        }}
        clientes={(clientes ?? []).map((c) => ({
          value: c.id,
          label: c.razon_social,
          despachador_id: c.despachador_id ?? null,
          despachador_nombre: c.despachador_id
            ? (despachadorNombrePorId.get(c.despachador_id) ?? null)
            : null,
        }))}
        camiones={
          camionesResult.ok
            ? camionesResult.camiones.map((c) => ({
                value: c.id,
                label: c.placa,
              }))
            : []
        }
        productos={(productosRpc ?? []) as ProductoListaRpc[]}
        tasaActual={tasaResult.ok ? tasaResult.tasa : null}
        ordenTasa={orden.tasa_cambio ?? null}
      />
    </div>
  );
}
