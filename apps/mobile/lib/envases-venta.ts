/** Fila de `data.contenedores` en AutoVenta y Venta directa (`lt_asentar_contenedores_orden`). */
export type EnvaseResumenVenta = {
  contenedor_id: string;
  codigo: string | null;
  nombre: string;
  saldo_anterior: number;
  entregados: number;
  retirados: number;
  saldo_actual: number;
};

type LineaConEnvase = {
  cantidad: number;
  contenedor_id?: string | null;
  unidades_por_contenedor?: number | null;
};

/**
 * Envases que se entregan con la venta, por tipo de envase.
 * Misma fórmula que la BD: CEIL(cantidad / GREATEST(unidades_por_contenedor, 1)).
 */
export function calcularEnvasesEntregados(lineas: LineaConEnvase[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const l of lineas) {
    const id = l.contenedor_id?.trim();
    const cantidad = Number(l.cantidad) || 0;
    if (!id || cantidad <= 0) continue;
    const unidades = Math.max(1, Number(l.unidades_por_contenedor) || 1);
    out[id] = (out[id] ?? 0) + Math.ceil(cantidad / unidades);
  }
  return out;
}

export function parseEnvasesResumen(raw: unknown): EnvaseResumenVenta[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((r) => {
      const row = (r ?? {}) as Record<string, unknown>;
      return {
        contenedor_id: String(row.contenedor_id ?? ""),
        codigo: row.codigo == null ? null : String(row.codigo),
        nombre: String(row.nombre ?? "Envase"),
        saldo_anterior: Number(row.saldo_anterior) || 0,
        entregados: Number(row.entregados) || 0,
        retirados: Number(row.retirados) || 0,
        saldo_actual: Number(row.saldo_actual) || 0,
      };
    })
    .filter((r) => r.contenedor_id);
}

/** Texto corto para el Alert de confirmación. */
export function textoResumenEnvases(filas: EnvaseResumenVenta[]): string {
  if (!filas.length) return "";
  return [
    "Resumen de envases:",
    ...filas.map(
      (f) =>
        `${f.codigo || f.nombre}: anterior ${f.saldo_anterior} + entregados ${f.entregados} − retirados ${f.retirados} = ${f.saldo_actual}`,
    ),
  ].join("\n");
}
