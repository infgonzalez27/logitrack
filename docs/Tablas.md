## Table `roles`

### Columns

| Name | Type | Constraints |
|------|------|-------------|
| `id` | `uuid` | Primary |
| `nombre` | `text` |  Unique |
| `descripcion` | `text` |  Nullable |
| `created_at` | `timestamptz` |  Nullable |

## Table `permisos`

### Columns

| Name | Type | Constraints |
|------|------|-------------|
| `id` | `uuid` | Primary |
| `codigo` | `text` |  Unique |
| `descripcion` | `text` |  Nullable |
| `created_at` | `timestamptz` |  Nullable |

## Table `roles_permisos`

### Columns

| Name | Type | Constraints |
|------|------|-------------|
| `rol_id` | `uuid` | Primary |
| `permiso_id` | `uuid` | Primary |


## Table `perfiles_usuario`

### Columns

| Name | Type | Constraints |
|------|------|-------------|
| `id` | `uuid` | Primary |
| `rol_id` | `uuid` |  Nullable |
| `nombre_completo` | `text` |  |
| `telefono` | `text` |  Nullable |
| `activo` | `bool` |  Nullable |
| `updated_at` | `timestamptz` |  Nullable |

## Table `logs_auditoria`

### Columns

| Name | Type | Constraints |
|------|------|-------------|
| `id` | `uuid` | Primary |
| `usuario_id` | `uuid` |  Nullable |
| `tabla_afectada` | `text` |  |
| `accion` | `text` |  |
| `registro_id` | `uuid` |  |
| `valores_anteriores` | `jsonb` |  Nullable |
| `valores_nuevos` | `jsonb` |  Nullable |
| `fecha_registro` | `timestamptz` |  Nullable |

## Table `inventario_almacen`

### Columns

| Name | Type | Constraints |
|------|------|-------------|
| `id` | `uuid` | Primary |
| `producto_id` | `uuid` |  Nullable Unique |
| `stock_disponible` | `int4` |  |
| `stock_comprometido` | `int4` |  |
| `ubicacion_pasillo` | `text` |  Nullable |
| `updated_at` | `timestamptz` |  Nullable |

## Table `inventario_movil`

### Columns

| Name | Type | Constraints |
|------|------|-------------|
| `id` | `uuid` | Primary |
| `camion_id` | `uuid` |  Nullable |
| `producto_id` | `uuid` |  Nullable |
| `cantidad_cargada` | `int4` |  |
| `cantidad_entregada` | `int4` |  |
| `cantidad_devolucion` | `int4` |  |
| `updated_at` | `timestamptz` |  Nullable |

## Table `camiones`

### Columns

| Name | Type | Constraints |
|------|------|-------------|
| `id` | `uuid` | Primary |
| `placa` | `text` |  Unique |
| `modelo` | `text` |  |
| `capacidad_kg` | `numeric` |  |
| `volumen_m3` | `numeric` |  Nullable |
| `estado` | `text` |  Nullable |
| `created_at` | `timestamptz` |  Nullable |

## Table `productos`

### Columns

| Name | Type | Constraints |
|------|------|-------------|
| `id` | `uuid` | Primary |
| `codigo_barras` | `text` |  Nullable Unique |
| `nombre` | `text` |  |
| `descripcion` | `text` |  Nullable |
| `unidad_medida` | `text` |  Nullable |
| `peso_unitario_kg` | `numeric` |  Nullable |
| `cant_unidad_medida` | `numeric` |  Nullable |
| `created_at` | `timestamptz` |  Nullable |
| `codigo_producto` | `text` |  Nullable Unique |
| `precio_lista1` | `numeric` |  Nullable |
| `precio_lista2` | `numeric` |  Nullable |
| `precio_lista3` | `numeric` |  Nullable |

## Table `clientes`

### Columns

| Name | Type | Constraints |
|------|------|-------------|
| `id` | `uuid` | Primary |
| `rif_nit` | `text` |  Unique |
| `razon_social` | `text` |  |
| `direccion_fiscal` | `text` |  |
| `telefono` | `text` |  Nullable |
| `movil1` | `text` |  Nullable |
| `movil2` | `text` |  Nullable |
| `movil3` | `text` |  Nullable |
| `correo_e` | `text` |  Nullable |
| `cond_liq` | `numeric` |  Nullable |
| `max_liq` | `numeric` |  Nullable |
| `activo` | `bool` |  Nullable |
| `created_at` | `timestamptz` |  Nullable |

## Table `ordenes_distribucion`

### Columns

| Name | Type | Constraints |
|------|------|-------------|
| `id` | `uuid` | Primary |
| `correlativo` | `int4` |  Unique |
| `cliente_id` | `uuid` |  Nullable |
| `camion_id` | `uuid` |  Nullable |
| `chofer_id` | `uuid` |  Nullable |
| `estado` | `text` |  Nullable |
| `fecha_despacho` | `timestamptz` |  Nullable |
| `peso_total_calculado` | `numeric` |  Nullable |
| `factura_origen_numero` | `varchar` |  |
| `creado_por` | `uuid` |  Nullable |
| `created_at` | `timestamptz` |  Nullable |

## Table `detalle_distribucion`

### Columns

| Name | Type | Constraints |
|------|------|-------------|
| `id` | `uuid` | Primary |
| `orden_id` | `uuid` |  Nullable |
| `producto_id` | `uuid` |  Nullable |
| `cantidad_solicitada` | `int4` |  |
| `cantidad_despachada` | `int4` |  Nullable |
| `valor_unitario_recaudar` | `numeric` |  |
| `subtotal_recaudar` | `numeric` |  |
| `secuencia_entrega` | `int4` |  Nullable |
| `estado_entrega` | `text` |  Nullable |
| `motivo_rechazo` | `text` |  Nullable |

## Table `clientes`

### Columns

| Name | Type | Constraints |
|------|------|-------------|
| `id` | `uuid` | Primary |
| `rif_nit` | `text` |  Unique |
| `razon_social` | `text` |  |
| `direccion_fiscal` | `text` |  |
| `telefono` | `text` |  Nullable |
| `movil1` | `text` |  Nullable |
| `movil2` | `text` |  Nullable |
| `movil3` | `text` |  Nullable |
| `correo_e` | `text` |  Nullable |
| `cond_liq` | `numeric` |  Nullable |
| `max_liq` | `numeric` |  Nullable |
| `activo` | `bool` |  Nullable |
| `created_at` | `timestamptz` |  Nullable |

## Table `proveedores`

### Columns

| Name | Type | Constraints |
|------|------|-------------|
| `id` | `uuid` | Primary |
| `rif_nit` | `text` |  Unique |
| `razon_social` | `text` |  |
| `direccion_fiscal` | `text` |  Nullable |
| `telefono` | `text` |  Nullable |
| `movil1` | `text` |  Nullable |
| `movil2` | `text` |  Nullable |
| `movil3` | `text` |  Nullable |
| `correo_e` | `text` |  Nullable |
| `activo` | `bool` |  Nullable |
| `created_at` | `timestamptz` |  Nullable |

## Table `facturas_compras`

### Columns

| Name | Type | Constraints |
|------|------|-------------|
| `id` | `uuid` | Primary |
| `proveedor_id` | `uuid` |  Nullable |
| `numero_factura` | `text` |  |
| `fecha_emision` | `date` |  |
| `fecha_vencimiento` | `date` |  Nullable |
| `monto_subtotal` | `numeric` |  |
| `monto_impuesto` | `numeric` |  Nullable |
| `monto_total` | `numeric` |  |
| `estado_pago` | `text` |  Nullable |
| `created_at` | `timestamptz` |  Nullable |

## Table `detalle_facturas_compras`

### Columns

| Name | Type | Constraints |
|------|------|-------------|
| `id` | `uuid` | Primary |
| `factura_id` | `uuid` |  Nullable |
| `producto_id` | `uuid` |  Nullable |
| `cantidad_comprada` | `int4` |  |
| `precio_unitario_compra` | `numeric` |  |
| `sub_total_compra` | `numeric` |  |
| `monto_linea` | `numeric` |  |

## Table `pagos_proveedores`

### Columns

| Name | Type | Constraints |
|------|------|-------------|
| `id` | `uuid` | Primary |
| `proveedor_id` | `uuid` |  Nullable |
| `fecha_pago` | `timestamptz` |  Nullable |
| `monto_total_pagado` | `numeric` |  |
| `glosa_concepto` | `text` |  Nullable |
| `ejecutado_por` | `uuid` |  Nullable |
| `created_at` | `timestamptz` |  Nullable |

## Table `detalle_pago_facturas`

### Columns

| Name | Type | Constraints |
|------|------|-------------|
| `id` | `uuid` | Primary |
| `pago_id` | `uuid` |  Nullable |
| `factura_id` | `uuid` |  Nullable |
| `monto_abonado` | `numeric` |  |

## Table `detalle_pago_metodos`

### Columns

| Name | Type | Constraints |
|------|------|-------------|
| `id` | `uuid` | Primary |
| `pago_id` | `uuid` |  Nullable |
| `banco_origen` | `text` |  |
| `forma_pago` | `text` |  |
| `monto_egreso` | `numeric` |  |
| `numero_referencia` | `text` |  Nullable |

