-- Migración de Corrección de Seguridad: Habilitar RLS y políticas en las 4 tablas faltantes

-- 1. tipos_contenedores
ALTER TABLE public.tipos_contenedores ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS select_tipos_contenedores ON public.tipos_contenedores;
DROP POLICY IF EXISTS modify_tipos_contenedores ON public.tipos_contenedores;

CREATE POLICY select_tipos_contenedores ON public.tipos_contenedores
FOR SELECT TO authenticated USING (true);

CREATE POLICY modify_tipos_contenedores ON public.tipos_contenedores
FOR ALL TO authenticated
USING (public.user_has_role(ARRAY['admin', 'gerente', 'despachador']));


-- 2. saldo_contenedores_clientes
ALTER TABLE public.saldo_contenedores_clientes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS select_saldo_contenedores_clientes ON public.saldo_contenedores_clientes;
DROP POLICY IF EXISTS modify_saldo_contenedores_clientes ON public.saldo_contenedores_clientes;

CREATE POLICY select_saldo_contenedores_clientes ON public.saldo_contenedores_clientes
FOR SELECT TO authenticated USING (true);

CREATE POLICY modify_saldo_contenedores_clientes ON public.saldo_contenedores_clientes
FOR ALL TO authenticated
USING (public.user_has_role(ARRAY['admin', 'gerente', 'despachador', 'vendedor']));


-- 3. movimientos_contenedores
ALTER TABLE public.movimientos_contenedores ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS select_movimientos_contenedores ON public.movimientos_contenedores;
DROP POLICY IF EXISTS modify_movimientos_contenedores ON public.movimientos_contenedores;

CREATE POLICY select_movimientos_contenedores ON public.movimientos_contenedores
FOR SELECT TO authenticated USING (true);

CREATE POLICY modify_movimientos_contenedores ON public.movimientos_contenedores
FOR ALL TO authenticated
USING (public.user_has_role(ARRAY['admin', 'gerente', 'despachador', 'vendedor']));


-- 4. movimientos_saldo_favor
ALTER TABLE public.movimientos_saldo_favor ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS select_movimientos_saldo_favor ON public.movimientos_saldo_favor;
DROP POLICY IF EXISTS modify_movimientos_saldo_favor ON public.movimientos_saldo_favor;

CREATE POLICY select_movimientos_saldo_favor ON public.movimientos_saldo_favor
FOR SELECT TO authenticated USING (true);

CREATE POLICY modify_movimientos_saldo_favor ON public.movimientos_saldo_favor
FOR ALL TO authenticated
USING (public.user_has_role(ARRAY['admin', 'gerente', 'despachador', 'vendedor']));
