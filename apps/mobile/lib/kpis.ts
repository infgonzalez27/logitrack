import { supabase } from "./supabase";

export type HomeKpis = {
  ordenesPorEstado: Record<string, number>;
  clientesActivos: number;
  rendicionesPendientes: number;
};

async function countExact(
  table: string,
  filters?: Record<string, string | boolean>,
): Promise<number> {
  let query = supabase.from(table).select("*", { count: "exact", head: true });
  if (filters) {
    for (const [k, v] of Object.entries(filters)) {
      query = query.eq(k, v);
    }
  }
  const { count, error } = await query;
  if (error) return 0;
  return count ?? 0;
}

const ESTADOS_ORDEN = [
  "borrador",
  "aprobada",
  "lista_para_carga",
  "en_transito",
  "despachada",
  "devuelta",
  "por_liquidar",
  "liquidada",
  "anulada",
] as const;

/** Conteos simples para home (consumidor posterior). */
export async function fetchHomeKpis(): Promise<
  { ok: true; kpis: HomeKpis } | { ok: false; error: string }
> {
  try {
    const estadoCounts = await Promise.all(
      ESTADOS_ORDEN.map(async (estado) => {
        const n = await countExact("ordenes_distribucion", { estado });
        return [estado, n] as const;
      }),
    );

    const ordenesPorEstado: Record<string, number> = {};
    for (const [estado, n] of estadoCounts) {
      if (n > 0) ordenesPorEstado[estado] = n;
    }

    const [clientesActivos, rendicionesPendientes] = await Promise.all([
      countExact("clientes", { activo: true }),
      countExact("rendiciones_cuentas", { estado: "revision" }),
    ]);

    return {
      ok: true,
      kpis: {
        ordenesPorEstado,
        clientesActivos,
        rendicionesPendientes,
      },
    };
  } catch (err) {
    return {
      ok: false,
      error: err instanceof Error ? err.message : "No se pudieron cargar KPIs.",
    };
  }
}
