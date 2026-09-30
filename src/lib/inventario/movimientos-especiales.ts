export type MovimientoTipo = "ENTRADA" | "SALIDA";
export type MovimientoInventario = "ALMACEN" | "MOVIL";

export const MOVIMIENTO_CONCEPTOS: { value: string; label: string }[] = [
  { value: "OBSEQUIO", label: "Obsequio" },
  { value: "CONSUMO_INTERNO", label: "Consumo interno" },
  { value: "EVENTOS", label: "Eventos" },
  { value: "MERMA", label: "Merma / daño" },
  { value: "AJUSTE", label: "Ajuste de inventario" },
];

export const ROLES_MOVIMIENTOS_ESPECIALES = ["admin", "gerente"] as const;

export function labelConcepto(value: string): string {
  return MOVIMIENTO_CONCEPTOS.find((c) => c.value === value)?.label ?? value;
}
