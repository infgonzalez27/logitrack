import { joinOne } from "@/lib/supabase/join";
import type { RolNombre } from "@/lib/auth/roles";

export type MoneyBarPoint = {
  name: string;
  Monto: number;
};

export type VentasMesPoint = {
  mes: string;
  Ventas: number;
};

/** true = solo órdenes emitidas por el vendedor */
export function isDashboardVendedorScope(rol: RolNombre | null): boolean {
  return rol === "vendedor";
}

export function ventaScopeLabel(rol: RolNombre | null): string {
  return isDashboardVendedorScope(rol)
    ? "tu cartera como vendedor"
    : "toda la empresa";
}

type DetalleLinea = { subtotal_recaudar: number | null };
type RendicionOrden = { recaudado: number | null };

export type OrdenFinanciera = {
  id: string;
  cliente_id: string;
  chofer_id: string | null;
  estado: string;
  created_at: string;
  fecha_despacho: string | null;
  clientes?: { razon_social: string } | { razon_social: string }[] | null;
  detalle_distribucion?: DetalleLinea[] | DetalleLinea | null;
  detalle_rendicion_ordenes?: RendicionOrden | RendicionOrden[] | null;
};

const MESES_CORTOS = [
  "Ene",
  "Feb",
  "Mar",
  "Abr",
  "May",
  "Jun",
  "Jul",
  "Ago",
  "Sep",
  "Oct",
  "Nov",
  "Dic",
] as const;

const ESTADOS_VENTA = new Set(["liquidada", "en_transito"]);
const ESTADOS_CXC = new Set([
  "lista_para_carga",
  "en_transito",
  "liquidada",
]);

export function ordenMontoVenta(orden: OrdenFinanciera): number {
  const lineas = Array.isArray(orden.detalle_distribucion)
    ? orden.detalle_distribucion
    : orden.detalle_distribucion
      ? [orden.detalle_distribucion]
      : [];
  return lineas.reduce((sum, l) => sum + Number(l.subtotal_recaudar ?? 0), 0);
}

export function ordenMontoCobrado(orden: OrdenFinanciera): number {
  const rend = joinOne(orden.detalle_rendicion_ordenes ?? null);
  return Number(rend?.recaudado ?? 0);
}

export function ordenSaldoPorCobrar(orden: OrdenFinanciera): number {
  if (!ESTADOS_CXC.has(orden.estado)) return 0;
  return Math.max(0, ordenMontoVenta(orden) - ordenMontoCobrado(orden));
}

export function clienteNombre(orden: OrdenFinanciera): string {
  const cliente = joinOne(orden.clientes ?? null);
  return cliente?.razon_social ?? "Sin cliente";
}

function truncateLabel(text: string, max = 22): string {
  if (text.length <= max) return text;
  return `${text.slice(0, max - 1)}…`;
}

function fechaOrden(orden: OrdenFinanciera): Date {
  return new Date(orden.fecha_despacho ?? orden.created_at);
}

function monthKey(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}

function monthLabel(key: string): string {
  const [year, month] = key.split("-");
  const idx = Number(month) - 1;
  return `${MESES_CORTOS[idx] ?? month} ${year.slice(2)}`;
}

/** Últimos 6 meses incluyendo el actual (aunque sea 0). */
function lastSixMonthKeys(): string[] {
  const keys: string[] = [];
  const now = new Date();
  for (let i = 5; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
    keys.push(monthKey(d));
  }
  return keys;
}

export function aggregateVentasPorMes(
  ordenes: OrdenFinanciera[],
): VentasMesPoint[] {
  const totals = new Map<string, number>();

  for (const orden of ordenes) {
    if (!ESTADOS_VENTA.has(orden.estado)) continue;
    const monto = ordenMontoVenta(orden);
    if (monto <= 0) continue;
    const key = monthKey(fechaOrden(orden));
    totals.set(key, (totals.get(key) ?? 0) + monto);
  }

  return lastSixMonthKeys().map((key) => ({
    mes: monthLabel(key),
    Ventas: totals.get(key) ?? 0,
  }));
}

export function aggregateVentasPorCliente(
  ordenes: OrdenFinanciera[],
  limit = 8,
): MoneyBarPoint[] {
  const totals = new Map<string, number>();

  for (const orden of ordenes) {
    if (!ESTADOS_VENTA.has(orden.estado)) continue;
    const monto = ordenMontoVenta(orden);
    if (monto <= 0) continue;
    const nombre = clienteNombre(orden);
    totals.set(nombre, (totals.get(nombre) ?? 0) + monto);
  }

  return [...totals.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, limit)
    .map(([name, Monto]) => ({
      name: truncateLabel(name),
      Monto,
    }));
}

export function aggregateCuentasPorCobrar(
  ordenes: OrdenFinanciera[],
  limit = 8,
): MoneyBarPoint[] {
  const totals = new Map<string, number>();

  for (const orden of ordenes) {
    const saldo = ordenSaldoPorCobrar(orden);
    if (saldo <= 0) continue;
    const nombre = clienteNombre(orden);
    totals.set(nombre, (totals.get(nombre) ?? 0) + saldo);
  }

  return [...totals.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, limit)
    .map(([name, Monto]) => ({
      name: truncateLabel(name),
      Monto,
    }));
}

export function sumVentasMesActual(ordenes: OrdenFinanciera[]): number {
  const now = new Date();
  const key = monthKey(now);
  let total = 0;
  for (const orden of ordenes) {
    if (!ESTADOS_VENTA.has(orden.estado)) continue;
    if (monthKey(fechaOrden(orden)) !== key) continue;
    total += ordenMontoVenta(orden);
  }
  return total;
}

export function sumCuentasPorCobrar(ordenes: OrdenFinanciera[]): number {
  return ordenes.reduce((sum, o) => sum + ordenSaldoPorCobrar(o), 0);
}

export function countClientesConSaldo(ordenes: OrdenFinanciera[]): number {
  const clientes = new Set<string>();
  for (const orden of ordenes) {
    if (ordenSaldoPorCobrar(orden) > 0) {
      clientes.add(orden.cliente_id);
    }
  }
  return clientes.size;
}
