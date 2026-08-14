/** Preferir fotos de caja/lata (no botella suelta). */
export function resolveProductoImage(nombre: string): string | null {
  const n = nombre.toLowerCase().normalize("NFD").replace(/\p{M}/gu, "");

  if (n.includes("ultra")) return "/productos/cardenal-ultra.webp";
  if (n.includes("cardenal")) return "/productos/cardenal-lata.webp";

  if (n.includes("malta") && n.includes("morena")) {
    return "/productos/malta-morena.webp";
  }
  if (n.includes("malta") && n.includes("regional")) {
    return "/productos/malta-regional.webp";
  }

  if (n.includes("zulia")) return "/productos/zulia-lata.webp";
  if (n.includes("morena")) return "/productos/morena-lata.webp";
  if (n.includes("pilsen")) return "/productos/regional-pilsen-lata.webp";
  if (n.includes("regional")) return "/productos/regional-lata.webp";

  return null;
}

export const PRODUCTO_MARCAS = [
  "Cardenal",
  "Morena",
  "Regional",
  "Zulia",
  "Malta",
] as const;

export type ProductoMarca = (typeof PRODUCTO_MARCAS)[number];

export function detectProductoMarca(nombre: string): ProductoMarca | null {
  const n = nombre.toLowerCase().normalize("NFD").replace(/\p{M}/gu, "");
  if (n.includes("malta")) return "Malta";
  if (n.includes("cardenal")) return "Cardenal";
  if (n.includes("zulia")) return "Zulia";
  if (n.includes("morena")) return "Morena";
  if (n.includes("regional") || n.includes("pilsen")) return "Regional";
  return null;
}
