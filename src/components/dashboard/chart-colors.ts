/** Paleta LogiTrack para gráficos Tremor (hex directo — no depende de Tailwind safelist). */
export const LT_CHART_PRIMARY = "#5b9bd5";
export const LT_CHART_SECONDARY = "#4a8ac4";
export const LT_CHART_ACCENT = "#7eb8e8";
export const LT_CHART_SOFT = "#b8d4f0";

export const LT_CHART_SERIES = [
  LT_CHART_PRIMARY,
  LT_CHART_SECONDARY,
  "#38bdf8", // sky
  "#2dd4bf", // teal
  "#818cf8", // indigo
] as const;

export const LT_DONUT_SERIES = [
  LT_CHART_PRIMARY,
  "#38bdf8",
  "#fbbf24", // amber — revisión
  "#f87171", // rose — discrepancia
  LT_CHART_SOFT,
] as const;

export const LT_AREA_FILL = LT_CHART_PRIMARY;
