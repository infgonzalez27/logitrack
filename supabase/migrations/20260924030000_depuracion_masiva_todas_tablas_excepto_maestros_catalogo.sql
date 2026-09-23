-- Migración: Depuración masiva de todas las tablas (excepto catálogos maestros) solicitada el 23-09-2026

TRUNCATE TABLE 
    auth.users,
    public.empresas,
    public.usuarios_empresas,
    public.clientes,
    public.choferes,
    public.tasa_cambio,
    public.ordenes_distribucion,
    public.inventario_almacen,
    public.inventario_movil,
    public.radars,
    public.rendiciones_cuentas,
    public.descuentos_cliente_producto,
    public.cuentas_bancarias_empresa,
    public.movimientos_saldo_favor,
    public.saldo_contenedores_clientes
CASCADE;
