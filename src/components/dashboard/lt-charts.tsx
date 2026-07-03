"use client";

import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import type { MoneyBarPoint, VentasMesPoint } from "@/lib/dashboard/charts";
import { LT_CHART_PRIMARY, LT_CHART_SERIES } from "@/components/dashboard/chart-colors";

const AXIS_TICK = { fill: "#5a7a9a", fontSize: 12 };
const GRID_STROKE = "#e2eef8";
const TOOLTIP_STYLE = {
  background: "#ffffff",
  border: "1px solid #e2eef8",
  borderRadius: "0.75rem",
  boxShadow: "0 4px 20px -4px rgba(30, 58, 95, 0.08)",
  color: "#1e3a5f",
  fontSize: "0.875rem",
};

function formatUsd(value: number): string {
  return new Intl.NumberFormat("es-VE", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: 0,
  }).format(value);
}

function formatUsdCompact(value: number): string {
  return new Intl.NumberFormat("es-VE", {
    style: "currency",
    currency: "USD",
    notation: "compact",
    maximumFractionDigits: 1,
  }).format(value);
}

export function LtVentasMesChart({ data }: { data: VentasMesPoint[] }) {
  return (
    <ResponsiveContainer width="100%" height={300}>
      <BarChart data={data} margin={{ top: 8, right: 12, left: 4, bottom: 4 }}>
        <CartesianGrid stroke={GRID_STROKE} strokeDasharray="3 3" vertical={false} />
        <XAxis dataKey="mes" tick={AXIS_TICK} axisLine={false} tickLine={false} />
        <YAxis
          tick={AXIS_TICK}
          axisLine={false}
          tickLine={false}
          width={72}
          tickFormatter={formatUsdCompact}
        />
        <Tooltip
          contentStyle={TOOLTIP_STYLE}
          formatter={(value: number) => [formatUsd(value), "Ventas"]}
          labelStyle={{ color: "#1e3a5f", fontWeight: 600 }}
        />
        <Bar dataKey="Ventas" fill={LT_CHART_PRIMARY} radius={[8, 8, 0, 0]} maxBarSize={52} />
      </BarChart>
    </ResponsiveContainer>
  );
}

export function LtMoneyHorizontalChart({
  data,
  valueLabel,
  barColor = LT_CHART_PRIMARY,
  multiColor = false,
}: {
  data: MoneyBarPoint[];
  valueLabel: string;
  barColor?: string;
  multiColor?: boolean;
}) {
  const chartHeight = Math.max(220, data.length * 44);

  return (
    <ResponsiveContainer width="100%" height={chartHeight}>
      <BarChart
        layout="vertical"
        data={data}
        margin={{ top: 4, right: 16, left: 4, bottom: 4 }}
      >
        <CartesianGrid stroke={GRID_STROKE} strokeDasharray="3 3" horizontal={false} />
        <XAxis
          type="number"
          tick={AXIS_TICK}
          axisLine={false}
          tickLine={false}
          tickFormatter={formatUsdCompact}
        />
        <YAxis
          type="category"
          dataKey="name"
          tick={AXIS_TICK}
          axisLine={false}
          tickLine={false}
          width={120}
        />
        <Tooltip
          contentStyle={TOOLTIP_STYLE}
          formatter={(value: number) => [formatUsd(value), valueLabel]}
          labelStyle={{ color: "#1e3a5f", fontWeight: 600 }}
        />
        <Bar dataKey="Monto" radius={[0, 8, 8, 0]} maxBarSize={28}>
          {data.map((entry, i) => (
            <Cell
              key={entry.name}
              fill={
                multiColor
                  ? LT_CHART_SERIES[i % LT_CHART_SERIES.length]
                  : barColor
              }
            />
          ))}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  );
}

export function ChartEmptyState({ message }: { message: string }) {
  return (
    <div className="flex h-56 items-center justify-center rounded-xl bg-lt-surface-muted px-4 text-center text-sm text-lt-text-muted">
      {message}
    </div>
  );
}
