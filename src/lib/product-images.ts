/** Mapeo de nombres de producto → imágenes oficiales (Cervecería Regional, centro de descargas). */
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

  if (n.includes("zulia") && (n.includes("lata") || n.includes("295"))) {
    return "/productos/zulia-lata.webp";
  }
  if (n.includes("zulia")) return "/productos/zulia-botella.webp";

  if (n.includes("morena") && (n.includes("lata") || n.includes("355"))) {
    return "/productos/morena-lata.webp";
  }
  if (n.includes("morena")) return "/productos/morena-botella.webp";

  if (n.includes("pilsen") && (n.includes("lata") || n.includes("355"))) {
    return "/productos/regional-pilsen-lata.webp";
  }
  if (n.includes("pilsen")) return "/productos/regional-pilsen-botella.webp";

  if (n.includes("regional") && (n.includes("lata") || n.includes("355"))) {
    return "/productos/regional-lata.webp";
  }
  if (n.includes("regional")) return "/productos/regional-botella.webp";

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
