import { supabase } from "./supabase";
import { NAV_SECTIONS, type NavSection } from "./nav";

export const APP_ROLES = [
  "admin",
  "gerente",
  "despachador",
  "vendedor",
  "chofer",
  "cobrador",
] as const;

export type AppRole = (typeof APP_ROLES)[number];

export type AppProfile = {
  id: string;
  nombre_completo: string;
  rol: AppRole | string;
};

const LEGACY_ROL_ALIASES: Record<string, AppRole> = {
  chofer_cobrador: "chofer",
};

const ROLE_ALLOWED_HREFS: Record<AppRole, string[] | "*"> = {
  admin: "*",
  gerente: [
    "/",
    "/visita",
    "/ordenes",
    "/autoventas",
    "/radar",
    "/clientes",
    "/rutas",
    "/proveedores",
    "/camiones",
    "/productos",
    "/choferes",
    "/inventario-almacen",
    "/inventario-movil",
    "/rendiciones",
    "/rendiciones/por-liquidar",
    "/rendiciones/formas-pago",
    "/contenedores",
    "/facturas-compras",
    "/pagos-proveedores",
    "/tasas-cambio",
    "/cuentas-bancarias",
    "/usuarios",
    "/impresora",
    "/cuenta",
  ],
  despachador: [
    "/radar",
    "/ordenes",
    "/autoventas",
    "/contenedores",
    "/impresora",
    "/cuenta",
  ],
  vendedor: [
    "/",
    "/visita",
    "/ordenes",
    "/autoventas",
    "/radar",
    "/clientes",
    "/rutas",
    "/rendiciones",
    "/rendiciones/por-liquidar",
    "/contenedores",
    "/impresora",
    "/cuenta",
  ],
  chofer: ["/ordenes", "/inventario-movil", "/impresora", "/cuenta"],
  cobrador: [
    "/visita",
    "/rendiciones",
    "/rendiciones/por-liquidar",
    "/contenedores",
    "/clientes",
    "/impresora",
    "/cuenta",
  ],
};

export function normalizeRolNombre(
  rol: string | null | undefined,
): AppRole | null {
  if (!rol) return null;
  if ((APP_ROLES as readonly string[]).includes(rol)) return rol as AppRole;
  return LEGACY_ROL_ALIASES[rol] ?? null;
}

export function isAppRole(rol: string | null | undefined): rol is AppRole {
  return normalizeRolNombre(rol) != null;
}

export function roleLabel(rol: string): string {
  switch (normalizeRolNombre(rol) ?? rol) {
    case "admin":
      return "Administrador";
    case "gerente":
      return "Gerente";
    case "despachador":
      return "Despachador";
    case "vendedor":
      return "Vendedor";
    case "chofer":
      return "Chofer";
    case "cobrador":
      return "Cobrador";
    default:
      return rol;
  }
}

export function getNavSectionsForRole(
  rol: string | null | undefined,
): NavSection[] {
  const r = normalizeRolNombre(rol);

  if (r === "despachador") {
    return [
      {
        title: "Ruta",
        items: [
          {
            href: "/radar",
            label: "Radar",
            route: "/(app)/radar",
          },
          {
            href: "/autoventas",
            label: "AutoVentas (venta en ruta)",
            route: "/(app)/autoventas",
          },
        ],
      },
      {
        title: "Consulta",
        items: [
          {
            href: "/ordenes",
            label: "Órdenes de distribución",
            route: "/(app)/ordenes",
          },
          {
            href: "/contenedores",
            label: "Consulta de contenedores",
            route: "/(app)/contenedores",
          },
        ],
      },
      {
        title: "Campo",
        items: [
          {
            href: "/impresora",
            label: "Impresora Bluetooth",
            route: "/(app)/impresora",
          },
          { href: "/cuenta", label: "Cuenta", route: "/(app)/cuenta" },
        ],
      },
    ];
  }

  if (r === "cobrador") {
    return [
      {
        title: "Cobranzas",
        items: [
          {
            href: "/rendiciones/por-liquidar",
            label: "Órdenes por liquidar",
            route: "/(app)/rendiciones/por-liquidar",
          },
          {
            href: "/rendiciones",
            label: "Cobranzas",
            route: "/(app)/rendiciones",
          },
          {
            href: "/contenedores",
            label: "Consulta de contenedores",
            route: "/(app)/contenedores",
          },
        ],
      },
      {
        title: "Maestros",
        items: [
          { href: "/clientes", label: "Clientes", route: "/(app)/clientes" },
        ],
      },
      {
        title: "Campo",
        items: [
          {
            href: "/impresora",
            label: "Impresora Bluetooth",
            route: "/(app)/impresora",
          },
          { href: "/cuenta", label: "Cuenta", route: "/(app)/cuenta" },
        ],
      },
    ];
  }

  const allowed = r ? ROLE_ALLOWED_HREFS[r] : ROLE_ALLOWED_HREFS.vendedor;
  if (allowed === "*") return [...NAV_SECTIONS];

  const allowedSet = new Set(allowed);
  // Campo items always filtered by allowed list (impresora/cuenta included for field roles)
  return NAV_SECTIONS.map((section) => ({
    ...section,
    items: section.items.filter(
      (item) =>
        allowedSet.has(item.href) ||
        (section.title === "Campo" &&
          (item.href === "/impresora" || item.href === "/cuenta") &&
          allowedSet.has(item.href)),
    ),
  })).filter((section) => section.items.length > 0);
}

/** Tabs rápidos por rol (barra inferior). */
export function tabsForRole(rol: string | null | undefined): {
  home: boolean;
  visita: boolean;
  clientes: boolean;
  ordenes: boolean;
  radar: boolean;
  autoventas: boolean;
  impresora: boolean;
  cuenta: boolean;
} {
  const r = normalizeRolNombre(rol);
  if (!r) {
    return {
      home: false,
      visita: false,
      clientes: false,
      ordenes: false,
      radar: false,
      autoventas: false,
      impresora: false,
      cuenta: false,
    };
  }
  if (r === "despachador") {
    return {
      home: true,
      visita: false,
      clientes: false,
      ordenes: true,
      radar: true,
      autoventas: true,
      impresora: true,
      cuenta: true,
    };
  }
  if (r === "vendedor") {
    return {
      home: true,
      visita: true,
      clientes: true,
      ordenes: true,
      radar: true,
      autoventas: true,
      impresora: true,
      cuenta: true,
    };
  }
  if (r === "chofer") {
    return {
      home: true,
      visita: false,
      clientes: false,
      ordenes: true,
      radar: false,
      autoventas: false,
      impresora: true,
      cuenta: true,
    };
  }
  if (r === "cobrador") {
    return {
      home: true,
      visita: true,
      clientes: true,
      ordenes: false,
      radar: false,
      autoventas: false,
      impresora: true,
      cuenta: true,
    };
  }
  // gerente / admin — tabs principales + el resto en drawer
  return {
    home: true,
    visita: true,
    clientes: true,
    ordenes: true,
    radar: true,
    autoventas: true,
    impresora: true,
    cuenta: true,
  };
}

export function homeHrefForRole(rol: string | null | undefined): string {
  const r = normalizeRolNombre(rol);
  if (r === "despachador") return "/(app)/radar";
  if (r === "chofer") return "/(app)/ordenes";
  if (r === "cobrador") return "/(app)/rendiciones";
  return "/(app)/home";
}

export async function signIn(email: string, password: string) {
  const { data, error } = await supabase.auth.signInWithPassword({
    email: email.trim(),
    password,
  });
  if (error) return { ok: false as const, error: error.message };
  return { ok: true as const, session: data.session };
}

export async function signOut() {
  await supabase.auth.signOut();
}

export async function getSessionUserId(): Promise<string | null> {
  const { data } = await supabase.auth.getSession();
  return data.session?.user?.id ?? null;
}

export async function fetchProfile(
  userId: string,
): Promise<{ ok: true; profile: AppProfile } | { ok: false; error: string }> {
  const { data, error } = await supabase
    .from("perfiles_usuario")
    .select("id, nombre_completo, roles(nombre)")
    .eq("id", userId)
    .maybeSingle();

  if (error) return { ok: false, error: error.message };
  if (!data) return { ok: false, error: "Perfil no encontrado." };

  const roles = data.roles as
    | { nombre?: string }
    | { nombre?: string }[]
    | null;
  const rolNombre = Array.isArray(roles) ? roles[0]?.nombre : roles?.nombre;
  const normalized = normalizeRolNombre(rolNombre);

  if (!normalized) {
    return {
      ok: false,
      error:
        "Tu rol no puede usar esta app. Roles: admin, gerente, vendedor, despachador, chofer o cobrador.",
    };
  }

  return {
    ok: true,
    profile: {
      id: data.id,
      nombre_completo: data.nombre_completo ?? "Usuario",
      rol: normalized,
    },
  };
}
