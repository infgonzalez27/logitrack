/**
 * Catálogo de logos registrados por código de empresa (tenant lt_*).
 */
export const EMPRESAS_LOGOS: Record<string, string> = {
  ramirez: "/logos/ramirez.png",
  berraco: "/logos/berraco.png",
  cgdemo: "/logos/cgdemo.png",
  igtest: "/logos/igtest.png",
};

/**
 * Obtiene la ruta del logo público para un código de empresa dado.
 */
export function getEmpresaLogo(
  codigoEmpresa?: string | null,
): string | null {
  if (!codigoEmpresa) return null;
  const normalizado = codigoEmpresa
    .trim()
    .toLowerCase()
    .replace(/^lt_/, "");

  return EMPRESAS_LOGOS[normalizado] ?? null;
}
