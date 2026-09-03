import { NAV_SECTIONS } from "@/lib/constants";

import type { PerfilUsuario } from "@/types/database";



export const ROL_NOMBRES = [

  "admin",

  "gerente",

  "despachador",

  "vendedor",

  "chofer",

  "cobrador",

] as const;



export type RolNombre = (typeof ROL_NOMBRES)[number];



/** Alias de roles antiguos en BD o código legado. */

const LEGACY_ROL_ALIASES: Record<string, RolNombre> = {

  chofer_cobrador: "chofer",

};



const ROLE_LABELS: Record<RolNombre, string> = {

  admin: "Administrador",

  gerente: "Gerente",

  despachador: "Despachador",

  vendedor: "Vendedor",

  chofer: "Chofer",

  cobrador: "Cobrador",

};



/** Rutas permitidas por rol (`*` = todas las de NAV_SECTIONS). */

const ROLE_ALLOWED_HREFS: Record<RolNombre, string[] | "*"> = {

  admin: "*",

  gerente: [

    "/",

    "/ordenes",

    "/radar",

    "/clientes",

    "/rutas",

    "/proveedores",

    "/camiones",

    "/productos",

    "/inventario-almacen",

    "/inventario-movil",

    "/rendiciones",

    "/facturas-compras",

    "/pagos-proveedores",

    "/tasas-cambio",

    "/usuarios",

  ],

  despachador: ["/radar", "/ordenes"],

  vendedor: [
    "/",
    "/ordenes",
    "/radar",
    "/clientes",
    "/rutas",
    "/rendiciones",
  ],

  chofer: ["/ordenes", "/inventario-movil"],

  cobrador: ["/rendiciones"],

};



export function normalizeRolNombre(

  nombre: string | null | undefined,

): RolNombre | null {

  if (!nombre) return null;

  if (ROL_NOMBRES.includes(nombre as RolNombre)) {

    return nombre as RolNombre;

  }

  return LEGACY_ROL_ALIASES[nombre] ?? null;

}



export function getRoleNameFromProfile(

  profile: PerfilUsuario | null,

): RolNombre | null {

  return normalizeRolNombre(profile?.roles?.nombre);

}



export function labelRol(nombre: RolNombre | null): string {

  if (!nombre) return "Sin rol";

  return ROLE_LABELS[nombre] ?? nombre;

}



export function homeHrefForRole(rol: RolNombre | null): string {
  if (rol === "despachador") return "/radar";
  if (rol === "chofer") return "/ordenes";
  if (rol === "cobrador") return "/rendiciones";
  return "/";
}

export function getNavSectionsForRole(rol: RolNombre | null) {
  if (rol === "despachador") {
    return [
      { title: "Ruta", items: [{ href: "/radar", label: "Radar" }] },
      {
        title: "Consulta",
        items: [{ href: "/ordenes", label: "Órdenes de distribución" }],
      },
    ];
  }

  const allowed = rol ? ROLE_ALLOWED_HREFS[rol] : ROLE_ALLOWED_HREFS.vendedor;

  if (allowed === "*") {
    return [...NAV_SECTIONS];
  }

  const allowedSet = new Set(allowed);

  return NAV_SECTIONS.map((section) => ({
    ...section,
    items: section.items.filter((item) => allowedSet.has(item.href)),
  })).filter((section) => section.items.length > 0);
}

export function canAccessHref(rol: RolNombre | null, href: string): boolean {
  if (href === "/radar" || href.startsWith("/radar/")) {
    return (
      rol === "despachador" ||
      rol === "gerente" ||
      rol === "vendedor" ||
      rol === "admin"
    );
  }

  if (rol === "despachador") {
    if (href === "/" || href === "") return true;
    if (href === "/ordenes/nuevo" || href.startsWith("/ordenes/nuevo/")) {
      return false;
    }
    if (/^\/ordenes\/[^/]+\/editar/.test(href)) return false;
    return href === "/ordenes" || href.startsWith("/ordenes/");
  }

  const allowed = rol ? ROLE_ALLOWED_HREFS[rol] : ROLE_ALLOWED_HREFS.vendedor;
  if (allowed === "*") return true;

  return allowed.some(
    (item) => href === item || href.startsWith(`${item}/`),
  );
}


