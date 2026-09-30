/** Navegación espejo de NAV_SECTIONS web → rutas Expo. */

export type NavItem = {
  href: string;
  label: string;
  /** Ruta Expo Router bajo /(app) */
  route: string;
};

export type NavSection = {
  title: string;
  items: readonly NavItem[];
};

export const NAV_SECTIONS: NavSection[] = [
  {
    title: "Distribución",
    items: [
      { href: "/visita", label: "Visita / cartera", route: "/(app)/visita" },
      {
        href: "/ordenes",
        label: "Órdenes de distribución",
        route: "/(app)/ordenes",
      },
      {
        href: "/autoventas",
        label: "AutoVentas (venta en ruta)",
        route: "/(app)/autoventas",
      },
      { href: "/radar", label: "Radar", route: "/(app)/radar" },
    ],
  },
  {
    title: "Maestros",
    items: [
      { href: "/clientes", label: "Clientes", route: "/(app)/clientes" },
      { href: "/rutas", label: "Rutas", route: "/(app)/rutas" },
      {
        href: "/proveedores",
        label: "Proveedores",
        route: "/(app)/proveedores",
      },
      { href: "/camiones", label: "Camiones", route: "/(app)/camiones" },
      { href: "/productos", label: "Productos", route: "/(app)/productos" },
      { href: "/choferes", label: "Choferes", route: "/(app)/choferes" },
    ],
  },
  {
    title: "Inventario",
    items: [
      {
        href: "/inventario-almacen",
        label: "Almacén",
        route: "/(app)/inventario-almacen",
      },
      {
        href: "/inventario-movil",
        label: "Inventario móvil",
        route: "/(app)/inventario-movil",
      },
      {
        href: "/inventario-movimientos",
        label: "Movimientos especiales",
        route: "/(app)/inventario-movimientos",
      },
    ],
  },
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
        href: "/rendiciones/formas-pago",
        label: "Reporte formas de pago",
        route: "/(app)/rendiciones/formas-pago",
      },
      {
        href: "/contenedores",
        label: "Consulta de contenedores",
        route: "/(app)/contenedores",
      },
    ],
  },
  {
    title: "Compras",
    items: [
      {
        href: "/facturas-compras",
        label: "Facturas de compra",
        route: "/(app)/facturas-compras",
      },
      {
        href: "/pagos-proveedores",
        label: "Pagos a proveedores",
        route: "/(app)/pagos-proveedores",
      },
    ],
  },
  {
    title: "Administración",
    items: [
      {
        href: "/tasas-cambio",
        label: "Tasas de cambio",
        route: "/(app)/tasas-cambio",
      },
      {
        href: "/cuentas-bancarias",
        label: "Cuentas bancarias",
        route: "/(app)/cuentas-bancarias",
      },
      { href: "/usuarios", label: "Usuarios", route: "/(app)/usuarios" },
      {
        href: "/usuarios/registrar",
        label: "Registrar usuario",
        route: "/(app)/usuarios/registrar",
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
