import Link from "next/link";
import { getCurrentProfile } from "@/lib/auth";
import { canCreateOrden } from "@/lib/auth/orden-permissions";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { getNombresPerfilByIds } from "@/lib/data/perfiles";
import { createClient } from "@/lib/supabase/server";
import { joinOne } from "@/lib/supabase/join";
import { labelOrdenEstado } from "@/lib/constants";
import { formatDate } from "@/lib/format";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { DataTable } from "@/components/ui/data-table";
import { Badge, ordenEstadoTone } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";

export default async function OrdenesPage() {
  const supabase = await createClient();
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  const puedeCrear = canCreateOrden(rol);

  const { data: ordenes } = await supabase
    .from("ordenes_distribucion")
    .select(
      `
      *,
      clientes(razon_social),
      camiones(placa),
      choferes(perfil_id, perfiles_usuario(nombre_completo))
    `,
    )
    .order("correlativo", { ascending: false });

  const nombresChofer = await getNombresPerfilByIds(
    (ordenes ?? []).map((o) => o.chofer_id).filter(Boolean),
  );

  return (
    <div className="space-y-6">
      <PageHeader
        title="Órdenes de distribución"
        description="Módulo 3 — Despacho maestro-detalle"
        action={
          puedeCrear ? (
            <Button href="/ordenes/nuevo">Nueva orden</Button>
          ) : undefined
        }
      />
      <Card>
        <DataTable
          columns={[
            { key: "correlativo", label: "#" },
            { key: "factura", label: "Factura origen" },
            { key: "cliente", label: "Cliente" },
            { key: "camion", label: "Camión" },
            { key: "chofer", label: "Chofer" },
            { key: "estado", label: "Estado" },
            { key: "fecha", label: "Despacho" },
            { key: "acciones", label: "" },
          ]}
          rows={(ordenes ?? []).map((o) => ({
            id: o.id,
            cells: {
              correlativo: `#${o.correlativo}`,
              factura: o.factura_origen_numero,
              cliente: joinOne(o.clientes)?.razon_social ?? "—",
              camion: joinOne(o.camiones)?.placa ?? "—",
              chofer: (() => {
                const chofer = joinOne(o.choferes);
                const perfil = joinOne(chofer?.perfiles_usuario);
                return (
                  perfil?.nombre_completo ??
                  (o.chofer_id ? nombresChofer[o.chofer_id] : null) ??
                  "—"
                );
              })(),
              estado: (
                <Badge tone={ordenEstadoTone(o.estado)}>
                  {labelOrdenEstado(o.estado)}
                </Badge>
              ),
              fecha: formatDate(o.fecha_despacho),
              acciones: (
                <Link
                  href={`/ordenes/${o.id}`}
                  className="text-sm font-medium text-lt-primary underline hover:text-lt-primary-hover"
                >
                  Ver
                </Link>
              ),
            },
          }))}
          emptyMessage="No hay órdenes. Crea la primera orden de distribución."
        />
      </Card>
    </div>
  );
}
