/** Preferir fotos de caja/empaque (Storage o fallback local en /public/productos). */
export function resolveProductoImage(nombre: string): string | null {
  const n = nombre.toLowerCase().normalize("NFD").replace(/\p{M}/gu, "");

  if (n.includes("ultra")) return "/productos/cardenal-ultra.webp";
  if (n.includes("munich") || (n.includes("cardenal") && n.includes("estilo"))) {
    return "/productos/cardenal-estilo-munich.webp";
  }
  if (n.includes("cardenal")) return "/productos/cardenal-estilo-munich.webp";

  if (n.includes("malta") && n.includes("morena")) {
    return "/productos/malta-morena.webp";
  }
  if (n.includes("malta") && n.includes("regional")) {
    return "/productos/malta-regional.webp";
  }

  if (n.includes("zulia")) return "/productos/zulia.webp";

  if (n.includes("morena") && n.includes("lager")) {
    return "/productos/morena-tipo-lager.webp";
  }
  if (n.includes("morena")) return "/productos/morena-tipo-pilsen.webp";

  if (n.includes("light")) return "/productos/regional-light.webp";
  if (n.includes("regional") || n.includes("pilsen")) {
    return "/productos/regional-clasica.webp";
  }

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

/** Catálogo canónico de cajas listo para bucket `productos` (imagen_path). */
export const PRODUCTO_STORAGE_IMAGES = [
  {
    etiqueta: "Cardenal Estilo Munich",
    imagen_path: "/productos/cardenal-estilo-munich.webp",
  },
  {
    etiqueta: "Cardenal Ultra",
    imagen_path: "/productos/cardenal-ultra.webp",
  },
  {
    etiqueta: "Malta Morena",
    imagen_path: "/productos/malta-morena.webp",
  },
  {
    etiqueta: "Malta Regional",
    imagen_path: "/productos/malta-regional.webp",
  },
  {
    etiqueta: "Morena Tipo Lager",
    imagen_path: "/productos/morena-tipo-lager.webp",
  },
  {
    etiqueta: "Morena Tipo Pilsen",
    imagen_path: "/productos/morena-tipo-pilsen.webp",
  },
  {
    etiqueta: "Regional clásica",
    imagen_path: "/productos/regional-clasica.webp",
  },
  {
    etiqueta: "Regional Light",
    imagen_path: "/productos/regional-light.webp",
  },
  {
    etiqueta: "Zulia",
    imagen_path: "/productos/zulia.webp",
  },
] as const;
