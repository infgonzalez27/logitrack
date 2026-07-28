import { isOrdenStaff } from "@/lib/auth/orden-permissions";
import type { RolNombre } from "@/lib/auth/roles";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import type { OrdenDistribucion } from "@/types/database";

const ORDEN_DETALLE_SELECT = `
  *,
  clientes(razon_social, rif_nit, direccion_fiscal),
  camiones(placa, modelo),
  choferes(perfil_id, cedula_licencia, perfiles_usuario(nombre_completo)),
  detalle_distribucion(*, productos(nombre, unidad_medida, codigo_producto))
`;

const ORDEN_LISTA_SELECT = `
  *,
  clientes(razon_social),
  camiones(placa),
  choferes(perfil_id, perfiles_usuario(nombre_completo))
`;

function puedeVerOrdenDetalle(
  orden: OrdenDistribucion,
  userId: string | undefined,
  rol: RolNombre | null,
): boolean {
  if (isOrdenStaff(rol)) return true;
  if (userId && orden.creado_por === userId) return true;
  if (rol === "chofer" && userId && orden.chofer_id === userId) return true;
  return false;
}

function filtrarOrdenesVisibles(
  ordenes: OrdenDistribucion[],
  userId: string | undefined,
  rol: RolNombre | null,
): OrdenDistribucion[] {
  return ordenes.filter((orden) => puedeVerOrdenDetalle(orden, userId, rol));
}

/**
 * Detalle de orden para UI.
 * Tras crear, el redirect a `/ordenes/[id]` hacía 404 al vendedor: el SELECT con
 * joins a `camiones`/`choferes` no pasa RLS aunque la orden exista (RPC).
 */
export async function getOrdenDistribucionDetalle(
  id: string,
  opts: { userId?: string; rol: RolNombre | null },
): Promise<OrdenDistribucion | null> {
  const ordenId = id?.trim();
  if (!ordenId) return null;

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("ordenes_distribucion")
    .select(ORDEN_DETALLE_SELECT)
    .eq("id", ordenId)
    .maybeSingle();

  if (!error && data) {
    const orden = data as OrdenDistribucion;
    return puedeVerOrdenDetalle(orden, opts.userId, opts.rol) ? orden : null;
  }

  const { data: adminData, error: adminError } = await createAdminClient()
    .from("ordenes_distribucion")
    .select(ORDEN_DETALLE_SELECT)
    .eq("id", ordenId)
    .maybeSingle();

  if (adminError || !adminData) return null;

  const orden = adminData as OrdenDistribucion;
  return puedeVerOrdenDetalle(orden, opts.userId, opts.rol) ? orden : null;
}

/**
 * Listado de órdenes.
 * El SELECT con joins a `camiones`/`choferes` deja al vendedor con lista vacía
 * por RLS; se usa service role y se filtra por creador / rol.
 */
export async function listarOrdenesDistribucion(opts: {
  userId?: string;
  rol: RolNombre | null;
}): Promise<OrdenDistribucion[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("ordenes_distribucion")
    .select(ORDEN_LISTA_SELECT)
    .order("correlativo", { ascending: false });

  if (!error && data && data.length > 0) {
    return filtrarOrdenesVisibles(
      data as OrdenDistribucion[],
      opts.userId,
      opts.rol,
    );
  }

  // Sesión vacía/error (típico vendedor por RLS en embeds) → admin + filtro.
  let adminQuery = createAdminClient()
    .from("ordenes_distribucion")
    .select(ORDEN_LISTA_SELECT)
    .order("correlativo", { ascending: false });

  if (opts.rol === "vendedor" && opts.userId) {
    adminQuery = adminQuery.eq("creado_por", opts.userId);
  } else if (opts.rol === "chofer" && opts.userId) {
    adminQuery = adminQuery.eq("chofer_id", opts.userId);
  }

  const { data: adminData, error: adminError } = await adminQuery;
  if (adminError || !adminData) {
    return filtrarOrdenesVisibles(
      (data as OrdenDistribucion[] | null) ?? [],
      opts.userId,
      opts.rol,
    );
  }

  return filtrarOrdenesVisibles(
    adminData as OrdenDistribucion[],
    opts.userId,
    opts.rol,
  );
}
