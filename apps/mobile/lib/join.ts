/** Normaliza joins PostgREST que pueden venir como objeto o arreglo. */
export function joinOne<T>(value: T | T[] | null | undefined): T | null {
  if (value == null) return null;
  return Array.isArray(value) ? (value[0] ?? null) : value;
}
