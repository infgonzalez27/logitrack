/** URL pública de un archivo en Storage a partir de `imagen_path`. */
export function storagePublicUrl(path: string | null | undefined): string | null {
  if (!path) return null;
  const trimmed = path.trim();
  if (!trimmed) return null;
  if (/^https?:\/\//i.test(trimmed)) return trimmed;

  const base = (process.env.NEXT_PUBLIC_STORAGE_BASE_URL ?? "").replace(
    /\/$/,
    "",
  );
  if (!base) {
    return trimmed.startsWith("/") ? trimmed : `/${trimmed}`;
  }

  const relative = trimmed.startsWith("/") ? trimmed : `/${trimmed}`;
  return `${base}${relative}`;
}
