import type {
  CamionEstado,
  ChoferEstado,
  EstadoEntrega,
  EstadoPagoFactura,
  FormaPagoProveedor,
  MetodoPagoRendicion,
  OrdenEstado,
  RendicionEstado,
} from "@/types/database";

export const ORDEN_ESTADOS: { value: OrdenEstado; label: string }[] = [
  { value: "borrador", label: "Borrador" },
  { value: "lista_para_carga", label: "Lista para carga" },
  { value: "en_transito", label: "En tránsito" },
  { value: "liquidada", label: "Liquidada" },
  { value: "anulada", label: "Anulada" },
];

export const ESTADO_ENTREGA: { value: EstadoEntrega; label: string }[] = [
  { value: "pendiente", label: "Pendiente" },
  { value: "entregado", label: "Entregado" },
  { value: "entregado_parcial", label: "Entregado parcial" },
  { value: "rechazado", label: "Rechazado" },
];

export const CAMION_ESTADOS: { value: CamionEstado; label: string }[] = [
  { value: "disponible", label: "Disponible" },
  { value: "en_ruta", label: "En ruta" },
  { value: "mantenimiento", label: "Mantenimiento" },
  { value: "inactivo", label: "Inactivo" },
];

export const CHOFER_ESTADOS: { value: ChoferEstado; label: string }[] = [
  { value: "disponible", label: "Disponible" },
  { value: "en_ruta", label: "En ruta" },
  { value: "libre", label: "Libre" },
  { value: "suspendido", label: "Suspendido" },
];

export const RENDICION_ESTADOS: { value: RendicionEstado; label: string }[] = [
  { value: "revision", label: "En revisión" },
  { value: "aprobada", label: "Aprobada" },
  { value: "con_discrepancia", label: "Con discrepancia" },
];

export const METODOS_PAGO_RENDICION: {
  value: MetodoPagoRendicion;
  label: string;
}[] = [
  { value: "efectivo_usd", label: "Efectivo USD" },
  { value: "efectivo_bs", label: "Efectivo Bs" },
  { value: "transferencia", label: "Transferencia" },
  { value: "pago_movil", label: "Pago móvil" },
];

export const ESTADO_PAGO_FACTURA: {
  value: EstadoPagoFactura;
  label: string;
}[] = [
  { value: "pendiente", label: "Pendiente" },
  { value: "pago_parcial", label: "Pago parcial" },
  { value: "pagada", label: "Pagada" },
  { value: "vencida", label: "Vencida" },
];

export const FORMAS_PAGO_PROVEEDOR: {
  value: FormaPagoProveedor;
  label: string;
}[] = [
  { value: "transferencia", label: "Transferencia" },
  { value: "efectivo", label: "Efectivo" },
  { value: "cheque", label: "Cheque" },
];

export const NAV_SECTIONS = [
  {
    title: "Distribución",
    items: [{ href: "/ordenes", label: "Órdenes de distribución" }],
  },
  {
    title: "Maestros",
    items: [
      { href: "/clientes", label: "Clientes" },
      { href: "/proveedores", label: "Proveedores" },
      { href: "/camiones", label: "Camiones" },
      { href: "/choferes", label: "Choferes" },
      { href: "/productos", label: "Productos" },
    ],
  },
  {
    title: "Inventario",
    items: [
      { href: "/inventario-almacen", label: "Almacén" },
      { href: "/inventario-movil", label: "Inventario móvil" },
    ],
  },
  {
    title: "Rendiciones",
    items: [{ href: "/rendiciones", label: "Rendición de cuentas" }],
  },
  {
    title: "Compras",
    items: [
      { href: "/facturas-compras", label: "Facturas de compra" },
      { href: "/pagos-proveedores", label: "Pagos a proveedores" },
    ],
  },
  {
    title: "Administración",
    items: [
      { href: "/usuarios", label: "Usuarios" },
      { href: "/usuarios/registrar", label: "Registrar usuario" },
    ],
  },
] as const;

export function labelOrdenEstado(estado: OrdenEstado): string {
  return ORDEN_ESTADOS.find((e) => e.value === estado)?.label ?? estado;
}

export function labelEstadoEntrega(estado: EstadoEntrega): string {
  return ESTADO_ENTREGA.find((e) => e.value === estado)?.label ?? estado;
}
