import Link from "next/link";

export type RadarEstadoFiltro = "pendiente" | "aprobado";

export function RadarFiltroEstado({
  fechaInicial,
  fechaLimite,
  estado,
}: {
  fechaInicial: string;
  fechaLimite: string;
  estado: RadarEstadoFiltro | null;
}) {
  function hrefFor(next: RadarEstadoFiltro) {
    const params = new URLSearchParams();
    params.set("fecha_inicial", fechaInicial);
    params.set("fecha_limite", fechaLimite);
    params.set("estado", next);
    return `/radar?${params.toString()}`;
  }

  const base =
    "inline-flex items-center justify-center rounded-xl border px-4 py-2 text-sm font-medium transition-colors";
  const idle =
    "border-lt-primary bg-lt-surface text-lt-primary hover:bg-lt-primary-muted";
  const active = "border-lt-primary bg-lt-primary text-white";

  return (
    <div className="flex flex-wrap gap-2">
      <Link
        href={hrefFor("pendiente")}
        className={`${base} ${estado === "pendiente" ? active : idle}`}
        aria-current={estado === "pendiente" ? "page" : undefined}
      >
        Pendientes
      </Link>
      <Link
        href={hrefFor("aprobado")}
        className={`${base} ${estado === "aprobado" ? active : idle}`}
        aria-current={estado === "aprobado" ? "page" : undefined}
      >
        Aprobados
      </Link>
    </div>
  );
}
