export type OrdenEstado =
  | "borrador"
  | "lista_para_carga"
  | "en_transito"
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
  updated_at: string;
  roles?: Rol | null;
}

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
  activo: boolean;
  created_at: string;
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
  codigo_barras: string | null;
  nombre: string;
  descripcion: string | null;
  unidad_medida: string;
  peso_unitario_kg: number;
  cant_unidad_medida: number;
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
  creado_por: string | null;
  created_at: string;
  clientes?: Cliente | null;
  camiones?: Camion | null;
  choferes?: Chofer | null;
  detalle_distribucion?: DetalleDistribucion[];
}

export interface DetalleDistribucion {
  id: string;
  orden_id: string;
  producto_id: string;
  cantidad_solicitada: number;
  cantidad_despachada: number;
  valor_unitario_recaudar: number;
  subtotal_recaudar: number;
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

export interface DetalleRendicionPago {
  id: string;
  rendicion_id: string;
  metodo_pago: MetodoPagoRendicion;
  monto: number;
  referencia_bancaria: string | null;
  cuenta_bancaria: string | null;
  capture_url: string | null;
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
        Returns: string;
      };
    };
    Enums: Record<string, never>;
  };
}
