-- Vendedor: puede registrar clientes (quedan asignados a él) y editar los suyos.
-- clientes_write_staff (lt_is_staff) no incluye al rol vendedor.

CREATE OR REPLACE FUNCTION public.lt_clientes_asignar_vendedor()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF public.lt_current_user_rol() = 'vendedor' THEN
    NEW.vendedor_id := auth.uid();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_clientes_asignar_vendedor ON public.clientes;
CREATE TRIGGER trg_clientes_asignar_vendedor
  BEFORE INSERT ON public.clientes
  FOR EACH ROW EXECUTE FUNCTION public.lt_clientes_asignar_vendedor();

DROP POLICY IF EXISTS clientes_insert_vendedor ON public.clientes;
CREATE POLICY clientes_insert_vendedor ON public.clientes
  FOR INSERT TO authenticated
  WITH CHECK (public.lt_current_user_rol() = 'vendedor' AND vendedor_id = auth.uid());

DROP POLICY IF EXISTS clientes_update_vendedor ON public.clientes;
CREATE POLICY clientes_update_vendedor ON public.clientes
  FOR UPDATE TO authenticated
  USING (public.lt_current_user_rol() = 'vendedor' AND vendedor_id = auth.uid())
  WITH CHECK (public.lt_current_user_rol() = 'vendedor' AND vendedor_id = auth.uid());
