import { callDbProcedure } from "@/lib/actions/db-rpc";
import { isOrdenStaff, ORDEN_ESTADOS_VALIDOS } from "@/lib/auth/orden-permissions";
import type { RolNombre } from "@/lib/auth/roles";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import type {
  OrdenDistribucion,
  OrdenEstado,
  OrdenListaRpc,
} from "@/types/database";

const ORDEN_DETALLE_SELECT = `
  *,
  clientes(razon_social, rif_nit, direccion_fiscal, vendedor_id, despachador_id),
  camiones(placa, modelo),
  choferes(perfil_id, cedula_licencia, perfiles_usuario(nombre_completo)),
  detalle_distribucion(*, productos(nombre, unidad_medida, codigo_producto))
`;

const ORDEN_LISTA_SELECT = `
  *,
  clientes(razon_social, despachador_id),
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
  if (rol === "despachador" && userId) {
    const cliente = Array.isArray(orden.clientes)
      ? orden.clientes[0]
      : orden.clientes;
    return cliente?.despachador_id === userId;
  }
  return false;
}

function filtrarOrdenesVisibles(
  ordenes: OrdenDistribucion[],
  userId: string | undefined,
  rol: RolNombre | null,
): OrdenDistribucion[] {
  return ordenes.filter((orden) => puedeVerOrdenDetalle(orden, userId, rol));
}

function mapOrdenTablaALista(orden: OrdenDistribucion): OrdenListaRpc {
  const cliente = Array.isArray(orden.clientes)
    ? orden.clientes[0]
    : orden.clientes;
  return {
    id: orden.id,
    correlativo: orden.correlativo,
    cliente_id: orden.cliente_id,
    cliente_razon_social: cliente?.razon_social ?? null,
    cliente_vendedor_id: cliente?.vendedor_id ?? null,
    camion_id: orden.camion_id,
    chofer_id: orden.chofer_id,
    estado: orden.estado,
    fecha_despacho: orden.fecha_despacho,
    peso_total_calculado: orden.peso_total_calculado,
    factura_origen_numero: orden.factura_origen_numero,
    tasa_cambio: orden.tasa_cambio ?? null,
    total_recaudar_bs: orden.total_recaudar_bs ?? null,
    total_recaudar_usd: orden.total_recaudar_usd ?? null,
    creado_por: orden.creado_por,
    created_at: orden.created_at,
  };
}

async function listarOrdenesLegacy(opts: {
  userId?: string;
  rol: RolNombre | null;
  estado?: OrdenEstado;
}): Promise<OrdenListaRpc[]> {
  const supabase = await createClient();
  const listaSelect =
    opts.rol === "despachador"
      ? `
  *,
  clientes!inner(razon_social, despachador_id),
  camiones(placa),
  choferes(perfil_id, perfiles_usuario(nombre_completo))
`
      : ORDEN_LISTA_SELECT;

  let query = supabase
    .from("ordenes_distribucion")
    .select(listaSelect)
    .order("correlativo", { ascending: false });

  if (opts.estado) {
    query = query.eq("estado", opts.estado);
  }
  if (opts.rol === "despachador" && opts.userId) {
    query = query.eq("clientes.despachador_id", opts.userId);
  }

  const { data, error } = await query;

  if (!error && data && data.length > 0) {
    return filtrarOrdenesVisibles(
      data as OrdenDistribucion[],
      opts.userId,
      opts.rol,
    ).map(mapOrdenTablaALista);
  }

  let adminQuery = createAdminClient()
    .from("ordenes_distribucion")
    .select(listaSelect)
    .order("correlativo", { ascending: false });

  if (opts.estado) {
    adminQuery = adminQuery.eq("estado", opts.estado);
  }
  if (opts.rol === "vendedor" && opts.userId) {
    adminQuery = adminQuery.eq("creado_por", opts.userId);
  } else if (opts.rol === "chofer" && opts.userId) {
    adminQuery = adminQuery.eq("chofer_id", opts.userId);
  } else if (opts.rol === "despachador" && opts.userId) {
    adminQuery = adminQuery.eq("clientes.despachador_id", opts.userId);
  }

  const { data: adminData, error: adminError } = await adminQuery;
  if (adminError || !adminData) {
    return filtrarOrdenesVisibles(
      (data as OrdenDistribucion[] | null) ?? [],
      opts.userId,
      opts.rol,
    ).map(mapOrdenTablaALista);
  }

  return filtrarOrdenesVisibles(
    adminData as OrdenDistribucion[],
    opts.userId,
    opts.rol,
  ).map(mapOrdenTablaALista);
}

async function listarPorEstadoRpc(
  estado: OrdenEstado,
): Promise<OrdenListaRpc[] | null> {
  const response = await callDbProcedure<OrdenListaRpc[]>(
    "retorna_ordenes_distribucion_segun_estado",
    { p_estado: estado },
  );

  if (!response.success) {
    return null;
  }

  return Array.isArray(response.data) ? response.data : [];
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
 * Listado vía RPC `retorna_ordenes_distribucion_segun_estado` (DB-018).
 * Chofer o fallo del RPC → fallback legacy.
 */
export async function listarOrdenesDistribucion(opts: {
  userId?: string;
  rol: RolNombre | null;
  estado?: OrdenEstado | "todos";
}): Promise<OrdenListaRpc[]> {
  const estadoFiltro =
    opts.estado && opts.estado !== "todos" ? opts.estado : undefined;

  if (opts.rol === "chofer" || opts.rol === "despachador") {
    return listarOrdenesLegacy({ ...opts, estado: estadoFiltro });
  }

  const estados: OrdenEstado[] = estadoFiltro
    ? [estadoFiltro]
    : ORDEN_ESTADOS_VALIDOS.filter((e) => e !== "lista_para_carga");

  const batches = await Promise.all(estados.map((estado) => listarPorEstadoRpc(estado)));

  if (batches.some((b) => b === null)) {
    return listarOrdenesLegacy({ ...opts, estado: estadoFiltro });
  }

  const byId = new Map<string, OrdenListaRpc>();
  for (const batch of batches) {
    for (const orden of batch ?? []) {
      byId.set(orden.id, orden);
    }
  }

  return [...byId.values()].sort((a, b) => b.correlativo - a.correlativo);
}
