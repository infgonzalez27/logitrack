/**
 * URL pública de un archivo en Storage a partir de `imagen_path`.
 * Prioriza `overrideBaseUrl` (del tenant activo en sesión) para evitar
 * apuntar a Central en entornos multi-tenant.
 */
export function storagePublicUrl(
  path: string | null | undefined,
  overrideBaseUrl?: string,
): string | null {
  if (!path) return null;
  const trimmed = path.trim();
  if (!trimmed) return null;
  if (/^https?:\/\//i.test(trimmed)) return trimmed;

  const supabaseFallback = process.env.NEXT_PUBLIC_SUPABASE_URL
    ? `${process.env.NEXT_PUBLIC_SUPABASE_URL.replace(/\/$/, "")}/storage/v1/object/public`
    : "";

  const base = (
    overrideBaseUrl ||
    process.env.NEXT_PUBLIC_STORAGE_BASE_URL ||
    supabaseFallback
  ).replace(/\/$/, "");

  const relative = trimmed.startsWith("/") ? trimmed : `/${trimmed}`;
  if (!base) {
    return relative;
  }

  return `${base}${relative}`;
}
