-- Vendedor: opera AutoVentas (cargar camión, vender en ruta, devolver sobrante).
-- Las escrituras van por RPC SECURITY DEFINER; solo le faltaba leer camiones e
-- inventario móvil (camiones_select / inv_movil_select usan lt_is_staff).

DROP POLICY IF EXISTS camiones_select_vendedor ON public.camiones;
CREATE POLICY camiones_select_vendedor ON public.camiones
  FOR SELECT TO authenticated
  USING (public.lt_current_user_rol() = 'vendedor');

DROP POLICY IF EXISTS inv_movil_select_vendedor ON public.inventario_movil;
CREATE POLICY inv_movil_select_vendedor ON public.inventario_movil
  FOR SELECT TO authenticated
  USING (public.lt_current_user_rol() = 'vendedor');
