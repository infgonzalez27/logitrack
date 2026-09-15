import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { retornaListaRadarsSegunRangoFechasAction } from "@/lib/actions/radar";
import { retornaUsuariosDespachadoresAction } from "@/lib/actions/rutas";
import { fechaHoyCaracas, fechaIsoDia, restarDiasIso } from "@/lib/dates";
import { PageHeader } from "@/components/layout/page-header";
import { RadarCrearForm } from "./radar-crear-form";
import { RadarFiltroEstado } from "./radar-filtro-estado";
import { RadarFiltroFechas } from "./radar-filtro-fechas";
import { RadarLista } from "./radar-lista";

function parseEstado(
  value: string | undefined,
): "pendiente" | "aprobado" | null {
  if (value === "pendiente" || value === "aprobado") return value;
  return null;
}

export default async function RadarPage({
  searchParams,
}: {
  searchParams: Promise<{
    fecha_inicial?: string;
    fecha_limite?: string;
    estado?: string;
  }>;
}) {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);

  if (
    rol !== "despachador" &&
    rol !== "gerente" &&
    rol !== "vendedor" &&
    rol !== "admin"
  ) {
    redirect("/");
  }

  const sp = await searchParams;
  const hoy = fechaHoyCaracas();
  const fechaLimite = fechaIsoDia(sp.fecha_limite) ?? hoy;
  const fechaInicial =
    fechaIsoDia(sp.fecha_inicial) ?? restarDiasIso(fechaLimite, 14);
  const estado = parseEstado(sp.estado) ?? "pendiente";

  const lista = await retornaListaRadarsSegunRangoFechasAction({
    fechaInicial,
    fechaLimite,
    estado,
  });

  const canCreate = rol === "admin" || rol === "gerente" || rol === "vendedor";
  const despachadores = canCreate
    ? await retornaUsuariosDespachadoresAction()
    : null;

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <PageHeader
        title="Radar"
        description="Consulta de radares por rango de fechas (últimos 15 días por defecto)."
      />

      <RadarFiltroFechas
        fechaInicial={fechaInicial}
        fechaLimite={fechaLimite}
        estado={estado}
      />

      {rol === "despachador" ? (
        <p className="text-sm text-lt-text-muted">
          Pulsa el ID del radar para ver las paradas y registrar entregas.
        </p>
      ) : null}

      {canCreate ? (
        !despachadores?.ok ? (
          <p className="lt-alert-error">
            {despachadores?.error ?? "No se pudieron cargar despachadores."}
          </p>
        ) : (
          <RadarCrearForm despachadores={despachadores.despachadores} />
        )
      ) : null}

      <div className="space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 className="text-base font-semibold text-lt-text">
            Radares ({fechaInicial} → {fechaLimite})
          </h2>
          <RadarFiltroEstado
            fechaInicial={fechaInicial}
            fechaLimite={fechaLimite}
            estado={estado}
          />
        </div>
        {!lista.ok ? (
          <p className="lt-alert-error">{lista.error}</p>
        ) : (
          <RadarLista items={lista.items} />
        )}
      </div>
    </div>
  );
}
