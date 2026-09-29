-- Vendedor: ver el detalle e imprimir el ticket de sus órdenes (AutoVentas / app).
-- productos_select y detalle_select usan lt_is_staff (no incluye vendedor).

DROP POLICY IF EXISTS productos_select_vendedor ON public.productos;
CREATE POLICY productos_select_vendedor ON public.productos
  FOR SELECT TO authenticated
  USING (public.lt_current_user_rol() = 'vendedor');

DROP POLICY IF EXISTS detalle_select_vendedor ON public.detalle_distribucion;
CREATE POLICY detalle_select_vendedor ON public.detalle_distribucion
  FOR SELECT TO authenticated
  USING (
    public.lt_current_user_rol() = 'vendedor'
    AND EXISTS (
      SELECT 1 FROM public.ordenes_distribucion o
      WHERE o.id = detalle_distribucion.orden_id
        AND (o.creado_por = auth.uid() OR o.vendedor_id = auth.uid())
    )
  );
