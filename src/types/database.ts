export type OrdenEstado =
  | "borrador"
  | "aprobada"
  | "lista_para_carga" // legado pre-migración DB-000
  | "en_transito"
  | "despachada"
  | "por_liquidar"
  | "liquidada"
  | "anulada";

export type EstadoEntrega =
  | "pendiente"
  | "entregado"
  | "entregado_parcial"
  | "rechazado";

export type CamionEstado =
  | "disponible"
  | "en_ruta"
  | "mantenimiento"
  | "inactivo";

export type ChoferEstado = "disponible" | "en_ruta" | "libre" | "suspendido";

export type RendicionEstado = "revision" | "aprobada" | "con_discrepancia";

export type MetodoPagoRendicion =
  | "efectivo_usd"
  | "efectivo_bs"
  | "transferencia"
  | "pago_movil";

export type EstadoPagoFactura =
  | "pendiente"
  | "pago_parcial"
  | "pagada"
  | "vencida";

export type FormaPagoProveedor = "transferencia" | "efectivo" | "cheque";

export interface Rol {
  id: string;
  nombre: string;
  descripcion: string | null;
  created_at: string;
}

export interface Permiso {
  id: string;
  codigo: string;
  descripcion: string | null;
  created_at: string;
}

export interface PerfilUsuario {
  id: string;
  rol_id: string | null;
  nombre_completo: string;
  telefono: string | null;
  activo: boolean;
  /** Ruta relativa en Storage (`/usuarios/...`). DB-025. */
  imagen_path?: string | null;
  updated_at: string;
  roles?: Rol | null;
}

export interface Ruta {
  id_ruta: string;
  nombre_ruta: string;
  descripcion_ruta: string | null;
  created_at: string;
}

export type DespachadorListaRpc = {
  id: string;
  nombre_completo: string;
  telefono: string | null;
};

export interface Cliente {
  id: string;
  rif_nit: string;
  razon_social: string;
  direccion_fiscal: string;
  telefono: string | null;
  movil1: string | null;
  movil2: string | null;
  movil3: string | null;
  correo_e: string | null;
  cond_liq: number | null;
  max_liq: number | null;
  /** Vendedor asignado (DB-014). */
  vendedor_id?: string | null;
  /** Despachador preferente — schema DB admin; combo vía `retorna_usuarios_despachadores`. */
  despachador_id?: string | null;
  /** Ruta — schema DB admin; combo vía `retorna_lista_rutas`. */
  id_ruta?: string | null;
  activo: boolean;
  created_at: string;
  perfiles_usuario?: PerfilUsuario | null;
}

/** Tasa BCV por fecha (tabla `tasa_cambio`). */
export interface TasaCambio {
  fecha_tasa: string;
  tasa_cambio: number;
  created_at?: string | null;
}

export interface Proveedor {
  id: string;
  rif_nit: string;
  razon_social: string;
  direccion_fiscal: string | null;
  telefono: string | null;
  movil1: string | null;
  movil2: string | null;
  movil3: string | null;
  correo_e: string | null;
  activo: boolean;
  created_at: string;
}

export interface Camion {
  id: string;
  placa: string;
  modelo: string;
  capacidad_kg: number;
  volumen_m3: number | null;
  estado: CamionEstado;
  created_at: string;
}

/** Fila de `retorna_lista_camiones` (emisión de órdenes / listados). */
export type CamionListaRpc = Pick<
  Camion,
  "id" | "placa" | "modelo" | "capacidad_kg" | "volumen_m3" | "estado" | "created_at"
>;

export interface Chofer {
  perfil_id: string;
  cedula_licencia: string;
  movil1: string | null;
  movil2: string | null;
  movil3: string | null;
  estado: ChoferEstado;
  created_at: string;
  perfiles_usuario?: PerfilUsuario | null;
}

export interface Producto {
  id: string;
  codigo_producto?: string | null;
  codigo_barras: string | null;
  nombre: string;
  descripcion: string | null;
  unidad_medida: string;
  peso_unitario_kg: number;
  cant_unidad_medida: number;
  /** Empaque/contenedor retornable (opcional). */
  contenedor_id?: string | null;
  /** Unidades de producto por 1 contenedor (default 1). */
  unidades_por_contenedor?: number | null;
  precio_lista1?: number | null;
  precio_lista2?: number | null;
  precio_lista3?: number | null;
  /** Ruta relativa en Storage (`/productos/...`). DB-025. */
  imagen_path?: string | null;
  created_at: string;
}

export interface InventarioAlmacen {
  id: string;
  producto_id: string;
  stock_disponible: number;
  stock_comprometido: number;
  ubicacion_pasillo: string | null;
  updated_at: string;
  productos?: Producto | null;
}

export interface InventarioMovil {
  id: string;
  camion_id: string;
  producto_id: string;
  cantidad_cargada: number;
  cantidad_entregada: number;
  cantidad_devolucion: number;
  updated_at: string;
  camiones?: Camion | null;
  productos?: Producto | null;
}

export interface OrdenDistribucion {
  id: string;
  correlativo: number;
  cliente_id: string;
  camion_id: string;
  chofer_id: string;
  estado: OrdenEstado;
  fecha_despacho: string | null;
  peso_total_calculado: number;
  factura_origen_numero: string;
  tasa_cambio?: number | null;
  total_recaudar_bs?: number | null;
  total_recaudar_usd?: number | null;
  creado_por: string | null;
  created_at: string;
  clientes?: Cliente | null;
  camiones?: Camion | null;
  choferes?: Chofer | null;
  detalle_distribucion?: DetalleDistribucion[];
}

/** Fila de `retorna_ordenes_distribucion_segun_estado`. */
export type OrdenListaRpc = {
  id: string;
  correlativo: number;
  cliente_id: string;
  cliente_razon_social: string | null;
  cliente_vendedor_id: string | null;
  camion_id: string | null;
  chofer_id: string | null;
  estado: OrdenEstado;
  fecha_despacho: string | null;
  peso_total_calculado: number | null;
  factura_origen_numero: string;
  tasa_cambio: number | null;
  total_recaudar_bs: number | null;
  total_recaudar_usd: number | null;
  creado_por: string | null;
  created_at: string;
};

export interface DetalleDistribucion {
  id: string;
  orden_id: string;
  producto_id: string;
  cantidad_solicitada: number;
  cantidad_despachada: number;
  valor_unitario_recaudar: number;
  subtotal_recaudar: number;
  valor_unitario_usd?: number | null;
  subtotal_recaudar_usd?: number | null;
  secuencia_entrega: number | null;
  estado_entrega: EstadoEntrega;
  motivo_rechazo: string | null;
  productos?: Producto | null;
}

export interface RendicionCuentas {
  id: string;
  cliente_id: string;
  fecha_rendicion: string;
  total_efectivo_recaudado: number;
  total_transferencias_recaudado: number;
  total_devoluciones_valoradas: number;
  estado: RendicionEstado;
  observaciones: string | null;
  auditado_por: string | null;
  clientes?: Cliente | null;
}

export interface DetalleRendicionOrden {
  id: string;
  rendicion_id: string;
  orden_distribucion_id: string;
  recaudado: number;
  ordenes_distribucion?: OrdenDistribucion | null;
}

/** Catálogo de formas de pago (tabla `fpagos`). */
export interface Fpago {
  fpago_id: string;
  fpago_concepto: string;
  /** true = pide referencia/banco; false = efectivo (sin esos campos). */
  fpago_info: boolean;
}

export interface DetalleRendicionPago {
  id: string;
  rendicion_id: string;
  fpago_id: string;
  /** @deprecated Reemplazado por fpago_id (migración DB-010). */
  metodo_pago?: MetodoPagoRendicion | null;
  monto: number;
  referencia_bancaria: string | null;
  cuenta_bancaria: string | null;
  capture_url: string | null;
  fpagos?: Fpago | null;
}

export interface FacturaCompra {
  id: string;
  proveedor_id: string;
  numero_factura: string;
  fecha_emision: string;
  fecha_vencimiento: string | null;
  monto_subtotal: number;
  monto_impuesto: number;
  monto_total: number;
  estado_pago: EstadoPagoFactura;
  created_at: string;
  proveedores?: Proveedor | null;
}

export interface DetalleFacturaCompra {
  id: string;
  factura_id: string;
  producto_id: string;
  cantidad_comprada: number;
  precio_unitario_compra: number;
  sub_total_compra: number;
  monto_linea: number;
  productos?: Producto | null;
}

export interface PagoProveedor {
  id: string;
  proveedor_id: string;
  fecha_pago: string;
  monto_total_pagado: number;
  glosa_concepto: string | null;
  ejecutado_por: string | null;
  created_at: string;
  proveedores?: Proveedor | null;
}

export interface DetallePagoFactura {
  id: string;
  pago_id: string;
  factura_id: string;
  monto_abonado: number;
}

export interface DetallePagoMetodo {
  id: string;
  pago_id: string;
  banco_origen: string;
  forma_pago: FormaPagoProveedor;
  monto_egreso: number;
  numero_referencia: string | null;
}

type TableDef<T> = {
  Row: T;
  Insert: Partial<T>;
  Update: Partial<T>;
  Relationships: [];
};

export type ProductoOrdenRpc = {
  producto_id: string;
  cantidad: number;
  /** Compatibilidad con SP antiguo. */
  precio_unitario?: number;
  valor_unitario_recaudar?: number;
  valor_unitario_usd?: number | null;
};

export type ProductoListaRpc = {
  id: string;
  nombre: string;
  codigo_producto?: string | null;
  codigo_barras: string | null;
  precio: number;
  precio_lista1?: number;
  precio_lista2?: number;
  precio_lista3?: number;
  stock_disponible: number;
  contenedor_id?: string | null;
  unidades_por_contenedor?: number | null;
  imagen_path?: string | null;
};

export type RadarCliente = {
  id: string;
  razon_social: string;
  rif_nit: string;
  direccion_fiscal: string | null;
  telefono: string | null;
  movil1: string | null;
  nombre_ruta: string | null;
};

export type RadarDetalle = {
  detalle_id: string;
  producto_id: string;
  codigo_producto: string | null;
  nombre_producto: string;
  imagen_path?: string | null;
  cantidad_solicitada: number;
  cantidad_despachada: number;
  valor_unitario_recaudar: number | null;
  subtotal_recaudar: number | null;
  valor_unitario_usd: number | null;
  subtotal_recaudar_usd: number | null;
  estado_entrega: EstadoEntrega | string;
  motivo_rechazo: string | null;
  contenedores_retirados: number;
  contenedor_id: string | null;
};

export type RadarSaldoContenedor = {
  contenedor_id: string;
  nombre_contenedor: string;
  saldo_pendiente: number;
};

export type RadarOrden = {
  orden_id: string;
  correlativo: number;
  estado: OrdenEstado | string;
  fecha_despacho: string | null;
  tasa_cambio: number | null;
  total_recaudar_bs: number | null;
  total_recaudar_usd: number | null;
  cliente: RadarCliente;
  detalles: RadarDetalle[];
  saldo_contenedores: RadarSaldoContenedor[];
};

export type ContenedorListaRpc = {
  id: string;
  nombre: string;
  codigo?: string | null;
};

export type PerfilUsuarioEditar = {
  id: string;
  email: string | null;
  nombre_completo: string;
  telefono: string;
  activo: boolean;
  rol_id: string;
  rol_nombre: string | null;
};

export type UsuarioListaRpc = {
  id: string;
  nombre_completo: string;
  rol_nombre?: string | null;
};

export type ActualizarProductoRpcInput = {
  id: string;
  codigo_producto: string;
  nombre: string;
  codigo_barras: string;
  precio_lista1: number;
  precio_lista2: number;
  precio_lista3: number;
  contenedor_id?: string | null;
  unidades_por_contenedor?: number | null;
  /** Ruta relativa Storage o URL pública (`/productos/...`). */
  imagen_path?: string | null;
};

export type ActualizarPerfilUsuarioRpcInput = {
  id: string;
  rol_id: string;
  nombre_completo: string;
  telefono: string;
  activo: boolean;
};

export interface Database {
  public: {
    Tables: {
      roles: TableDef<Rol>;
      clientes: TableDef<Cliente>;
      proveedores: TableDef<Proveedor>;
      camiones: TableDef<Camion>;
      choferes: TableDef<Chofer>;
      productos: TableDef<Producto>;
      inventario_almacen: TableDef<InventarioAlmacen>;
      inventario_movil: TableDef<InventarioMovil>;
      ordenes_distribucion: TableDef<OrdenDistribucion>;
      detalle_distribucion: TableDef<DetalleDistribucion>;
      perfiles_usuario: TableDef<PerfilUsuario>;
      rendiciones_cuentas: TableDef<RendicionCuentas>;
      facturas_compras: TableDef<FacturaCompra>;
      pagos_proveedores: TableDef<PagoProveedor>;
    };
    Views: Record<string, never>;
    Functions: {
      registra_nuevo_usuario: {
        Args: {
          p_email: string;
          p_password: string;
          p_nombre_completo: string;
          p_telefono: string;
          p_rol_nombre: string;
        };
        Returns: {
          success: boolean;
          message?: string;
          user_id?: string;
        };
      };
      crear_orden_distribucion: {
        Args: {
          p_vendedor_id: string;
          p_chofer_id: string;
          p_cliente_id: string;
          p_camion_id: string;
          p_tasa_cambio?: number | null;
          p_productos_json: ProductoOrdenRpc[];
        };
        Returns: {
          success: boolean;
          message?: string;
          orden_id?: string;
        };
      };
      retorna_lista_contenedores: {
        Args: Record<string, never>;
        Returns: {
          success: boolean;
          data: ContenedorListaRpc[] | null;
          error: { code: string; message: string; details: string | null } | null;
        };
      };
      aprobar_orden_distribucion: {
        Args: { p_orden_id: string };
        Returns: Record<string, unknown>;
      };
      cargar_inventario_movil: {
        Args: { p_orden_id: string };
        Returns: Record<string, unknown>;
      };
      registrar_entrega_detalle: {
        Args: {
          p_detalle_id: string;
          p_cantidad_despachada: number;
          p_estado_entrega: string;
          p_motivo_rechazo: string | null;
        };
        Returns: Record<string, unknown>;
      };
      registrar_movimiento_contenedores: {
        Args: {
          p_cliente_id: string;
          p_orden_id: string;
          p_contenedor_id: string;
          p_cantidad_entregada: number;
          p_cantidad_retirada: number;
          p_creado_por: string;
        };
        Returns: Record<string, unknown>;
      };
      liquidar_orden_distribucion: {
        Args: { p_orden_id: string };
        Returns: Record<string, unknown>;
      };
      anular_orden_distribucion: {
        Args: { p_orden_id: string };
        Returns: Record<string, unknown>;
      };
      actualizar_estado_orden_distribucion: {
        Args: {
          p_orden_id: string;
          p_estado: string;
        };
        Returns: {
          success: boolean;
          message?: string;
        };
      };
      cargar_datos_demo_dashboard: {
        Args: Record<string, never>;
        Returns: {
          ordenes: number;
          rendiciones: number;
          camiones: number;
          facturas: number;
          choferId: string | null;
        };
      };
      retorna_lista_camiones: {
        Args: Record<string, never>;
        Returns: CamionListaRpc[];
      };
      retorna_lista_rutas: {
        Args: Record<string, never>;
        Returns: {
          success: boolean;
          total_registros?: number;
          data: Ruta[] | null;
          error: { code: string; message: string; details?: string | null } | null;
        };
      };
      retorna_usuarios_despachadores: {
        Args: Record<string, never>;
        Returns: {
          success: boolean;
          data: DespachadorListaRpc[] | null;
          error: { code: string; message: string; details?: string | null } | null;
        };
      };
      actualiza_registro_rutas_segun_uuid: {
        Args: {
          p_id_ruta: string;
          p_nombre_ruta: string;
          p_descripcion_ruta?: string | null;
        };
        Returns: {
          success: boolean;
          message?: string;
          data: Ruta | null;
          error?: { code: string; message: string; details?: string | null } | null;
        };
      };
      actualiza_registro_cliente_segun_uuid: {
        Args: {
          p_id: string;
          p_rif_nit?: string | null;
          p_razon_social?: string | null;
          p_direccion_fiscal?: string | null;
          p_telefono?: string | null;
          p_movil1?: string | null;
          p_movil2?: string | null;
          p_movil3?: string | null;
          p_correo_e?: string | null;
          p_cond_liq?: number | null;
          p_max_liq?: number | null;
          p_vendedor_id?: string | null;
          p_despachador_id?: string | null;
          p_id_ruta?: string | null;
          p_activo?: boolean | null;
        };
        Returns: {
          success: boolean;
          message?: string;
          data: Cliente | null;
          error?: { code: string; message: string; details?: string | null } | null;
        };
      };
      retorna_radar_despachador: {
        Args: Record<string, never>;
        Returns: {
          success: boolean;
          total_ordenes?: number;
          data: RadarOrden[] | null;
          error?: { code: string; message: string; details?: string | null } | null;
        };
      };
      registrar_despacho_cliente_radar: {
        Args: {
          p_orden_id: string;
          p_detalles_json: unknown;
        };
        Returns: {
          success: boolean;
          message?: string;
          data: { orden_id: string; nuevo_estado_orden: string } | null;
          error?: { code: string; message: string; details?: string | null } | null;
        };
      };
      aprobar_despacho_orden_distribucion: {
        Args: { p_orden_id: string };
        Returns: {
          success: boolean;
          message?: string;
          data: { orden_id: string; nuevo_estado: string } | null;
          error?: { code: string; message: string; details?: string | null } | null;
        };
      };
      retorna_lista_productos_segun_parametros: {
        Args: {
          p_parametro: string;
        };
        Returns: ProductoListaRpc[];
      };
      retorna_lista_usuarios_segun_parametros: {
        Args: {
          p_nombre: string;
          p_rol: string;
        };
        Returns: UsuarioListaRpc[];
      };
      actualizar_registro_perfil_usuarios_segun_id: {
        Args: {
          p_id: string;
          p_rol_id: string;
          p_nombre_completo: string;
          p_telefono: string;
          p_activo: boolean;
        };
        Returns: boolean;
      };
      actualizar_registro_productos_segun_id: {
        Args: {
          p_id: string;
          p_codigo_producto: string;
          p_nombre: string;
          p_codigo_barras: string;
          p_precio_lista1: number;
          p_precio_lista2: number;
          p_precio_lista3: number;
        };
        Returns: boolean;
      };
    };
    Enums: Record<string, never>;
  };
}
