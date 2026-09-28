export type ColorSchemeName = "light" | "dark";

export interface ThemeColors {
  brand: string;
  brandMuted: string;
  accent: string;
  background: string;
  surface: string;
  surfaceElevated: string;
  border: string;
  text: string;
  textSecondary: string;
  textInverse: string;
  success: string;
  successBg: string;
  warning: string;
  warningBg: string;
  danger: string;
  dangerBg: string;
  info: string;
  infoBg: string;
  skeleton: string;
  overlay: string;
}

export interface ThemeSpacing {
  xs: number;
  sm: number;
  md: number;
  lg: number;
  xl: number;
  xxl: number;
}

export interface ThemeRadii {
  sm: number;
  md: number;
  lg: number;
  xl: number;
  full: number;
}

export interface ThemeTypography {
  title: number;
  subtitle: number;
  body: number;
  caption: number;
  tracking: number;
}

export interface AppTheme {
  scheme: ColorSchemeName;
  colors: ThemeColors;
  spacing: ThemeSpacing;
  radii: ThemeRadii;
  typography: ThemeTypography;
}

export const spacing: ThemeSpacing = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 20,
  xxl: 28,
};

export const radii: ThemeRadii = {
  sm: 8,
  md: 12,
  lg: 16,
  xl: 20,
  full: 999,
};

export const typography: ThemeTypography = {
  title: 22,
  subtitle: 16,
  body: 15,
  caption: 12,
  tracking: 18,
};

const lightColors: ThemeColors = {
  brand: "#0B3A5C",
  brandMuted: "#1A4F73",
  accent: "#E85D4C",
  background: "#F2F5F8",
  surface: "#FFFFFF",
  surfaceElevated: "#FFFFFF",
  border: "#E2E8F0",
  text: "#132033",
  textSecondary: "#64748B",
  textInverse: "#FFFFFF",
  success: "#15803D",
  successBg: "#DCFCE7",
  warning: "#B45309",
  warningBg: "#FEF3C7",
  danger: "#B91C1C",
  dangerBg: "#FEE2E2",
  info: "#1D4ED8",
  infoBg: "#DBEAFE",
  skeleton: "#E2E8F0",
  overlay: "rgba(19, 32, 51, 0.45)",
};

const darkColors: ThemeColors = {
  brand: "#5BA4D6",
  brandMuted: "#3D7AA8",
  accent: "#F07164",
  background: "#0F172A",
  surface: "#1E293B",
  surfaceElevated: "#273449",
  border: "#334155",
  text: "#F1F5F9",
  textSecondary: "#94A3B8",
  textInverse: "#0F172A",
  success: "#4ADE80",
  successBg: "#14532D",
  warning: "#FBBF24",
  warningBg: "#78350F",
  danger: "#F87171",
  dangerBg: "#7F1D1D",
  info: "#60A5FA",
  infoBg: "#1E3A8A",
  skeleton: "#334155",
  overlay: "rgba(0, 0, 0, 0.55)",
};

export function createTheme(scheme: ColorSchemeName): AppTheme {
  return {
    scheme,
    colors: scheme === "dark" ? darkColors : lightColors,
    spacing,
    radii,
    typography,
  };
}

/** Altura fija de tarjeta de envío (para getItemLayout). */
export const ORDEN_CARD_HEIGHT = 118;
export const ORDEN_CARD_GAP = 10;
