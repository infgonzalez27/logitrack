-- Migración: Depuración masiva de tablas (Clientes, Choferes, Radars, etc) solicitada el 23-09-2026

TRUNCATE TABLE 
    public.clientes,
    public.choferes,
    public.cuentas_bancarias_empresa,
    public.movimientos_contenedores,
    public.movimientos_saldo_favor,
    public.radars
CASCADE;
