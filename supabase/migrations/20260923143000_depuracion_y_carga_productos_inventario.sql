-- Migración: Depuración de órdenes/tablas y carga masiva de productos desde INVENTARIO_260922_193808.xlsx

-- 1. Depurar tablas de órdenes e inventario dependientes de productos
TRUNCATE TABLE
    public.movimientos_contenedores,
    public.saldo_contenedores_clientes,
    public.radars,
    public.detalle_distribucion,
    public.ordenes_distribucion,
    public.inventario_movil,
    public.inventario_almacen,
    public.descuentos_cliente_producto,
    public.productos
RESTART IDENTITY CASCADE;

-- 2. Bloque PL/pgSQL para obtener el ID de contenedor y registrar productos únicos
DO $$
DECLARE
    v_contenedor_id UUID;
BEGIN
    -- Obtener el ID de contenedor por defecto disponible
    SELECT id INTO v_contenedor_id FROM public.tipos_contenedores ORDER BY created_at ASC LIMIT 1;

    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1045', 'REG. PILSEN 222ML BOT RT/ETQ-TF', 'UNID', 0.00, 1, v_contenedor_id);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1054', 'REG. PILSEN 355ML LT-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1086', 'ZULIA 222ML BOT RT/PIR-TF', 'UNID', 0.00, 1, v_contenedor_id);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1116', 'ZULIA 250ML NI BOT NR/PIR-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1139', 'CARDENAL ULTRA 250ML LT-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1157', 'MALTA REG. 207ML NI BOT NR/ETQ-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1158', 'MALTA REG. 250ML NI BOT NR/ETQ-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1175', 'MALTA REG. 222ML NI BOT RT/ETQ-TF', 'UNID', 0.00, 1, v_contenedor_id);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1187', 'ZULIA 295ML LT-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1226', 'MORENA 250ML LT-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1300', 'MALTA MORENA 222ML BOT RT/ETQ-TF', 'UNID', 0.00, 1, v_contenedor_id);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1304', 'MORENA 355ML LT-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1305', 'MALTA MORENA 250ML BOT NR/ETQ-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1306', 'MALTA MORENA 250ML LT-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1374', 'MALTA MORENA 207ML BOT NR/ETQ-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1396', 'CERVEZA REGIONAL 250ML LT-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1441', 'CERVEZA REGIONAL 222ML BOT RT/ETQ-TF', 'UNID', 0.00, 1, v_contenedor_id);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1472', 'CARDENAL 250ML LT-TF', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1625', 'LECHE EN POLVO COMP. SAN SIMON 12X400GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1626', 'LECHE EN POLVO COMP. SAN SIMON 12X900GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1627', 'BEBIDA LACTEA MONTANA FRESCA 24X125GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1628', 'BEBIDA LACTEA MONTANA FRESCA 12X400GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1629', 'BEBIDA LACTEA MONTANA FRESCA 12X900 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1631', 'LECHE LIQUIDA DESC. SAN SIMON 12X1L', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1702', 'ARROZ MARY DORADO 30x800 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1704', 'ARROZ MARY INTEGRAL 30x800 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1707', 'CREMA DE ARROZ MARY ENR. 24X450 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1714', 'CARAOTAS BLANCAS MARY 24x500 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1747', 'TOMATES PELADOS MARY 12x800 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1749', 'PASSATA DE TOMATE MARY 12x700 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1751', 'PALMITOS ENTEROS AL NATURAL 24x400 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1759', 'MARY LINGUINI PREMIUM 24x500 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1760', 'MARY VERMICELLI PREMIUM 24x500 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1761', 'MARY TORNILLOS PREMIUM 12x500 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1762', 'MARY PLUMITAS PREMIUM 12x500 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1763', 'MARY DEDAL PREMIUM 12x500 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1764', 'MARY MACARRON PREMIUM 12x500 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1766', 'MARY VERMICELLI SUPERIOR 12X1 KG', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1767', 'MARY TORNILLO SUPERIOR 12X1 KG', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1769', 'ACEITE OLIVA EXTRA VIRGEN MARY 12x500 ML', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1791', 'MARY PLUMA SUPERIOR 12X1 KG', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1797', 'MARY VERMICELLI TRADICIONAL 12x1 KG', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1799', 'HAR.TRIGO MARY TODO USO 20X900GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('1800', 'ARROZ MARY PREMIUM 24X900 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7200', 'KESITOS 12x25 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7201', 'KESITOS 5x85 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7203', 'BOLIKRUNCH 5x85 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7204', 'CHISKESITOS 12x45 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7232', 'TOCINETIKAS ORIGINAL 6x40 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7234', 'TOCINETIKAS PICANTE 6x40 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7264', 'SNACHOS MUNCHY 12X42GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7271', 'MARY VERMICELLI SUPERIOR 24X500 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7353', 'ARVEJAS VERDES PARTIDAS MARY 30X400 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7354', 'CARAOTAS NEGRAS MARY 30X400 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7355', 'LENTEJAS MARY 30X400 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7357', 'GALLETAS CHARMY MOKA 24X192 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7361', 'GALLETAS CHARMY FRESA 24X192 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7363', 'GALLETAS CHARMY CHOCOLATE 24X192 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7365', 'GALLETAS MARIA CALEDONIA 24X252GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7367', 'ARROZ MARY ESMERALDA 24X900 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7369', 'MARY PLUMA SUPERIOR 12X500 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7370', 'MARY TORNILLO SUPERIOR 12X500 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7388', 'GALLETAS MARIA CALEDONIA LIMON 24X150GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7389', 'GALLETAS TIP TOP MANI 24X96GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7390', 'GALLETAS TIP TOP CHOCO 24X96GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7391', 'GALLETAS TIP TOP CHOCOMANI 24X96GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7392', 'GALLETAS TIP TOP VAINILLA 24X96GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7393', 'GALLETAS TIP TOP COCO 24X96GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7468', 'GALLETAS TIPTOP CHOCO 8X18X16 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7472', 'GALLETAS CHARMY VAINI. ESTUCHE 8X18X16GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7473', 'GALLETA CHARMY CHOCO ESTU 8X18X16GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7474', 'GALLETA CHARMY MOKA ESTU 8X18X16GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7475', 'GALLETAS MARIA CALEDONIA CANELA 24X150GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7476', 'ARROZ MARY SUPERIOR TIPO I 24x900 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7477', 'ARROZ MARY TRADICIONAL TIPO I 24x900 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7480', 'GALLETAS CHARMY BROWNIE 24X192 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7481', 'GALLETAS CHARMY CHOCO MANIA 24X192 GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7482', 'HAR.MAIZ BLANCO MARY PREC.ENRIQ.20X900GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7483', 'HARINA DE TRIGO LEUDANTE MARY 20X900GR', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7485', 'HAR.MAIZ BLANCO PREC. ENRIQ. MARY 9X2KG', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7486', 'MAIZ PARA COTUFAS MARY 30X400G', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7851', 'RON PAMPERO ESPECIAL 12X700 ML 40GL NAC', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7852', 'VODKA GORDONS 12X700 ML 40GL NAC', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7853', 'VODKA GORDONS UVA 12X700 ML 30GL NAC', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7855', 'VODKA GORDONS PARCH. 12X700 ML 30GL NAC', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7856', 'GIN GORDONS 12X700 ML 40GL NAC', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7857', 'WHISKY BLACK AND WHITE 12X750ML 40GL IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7858', 'RON PAMPERO ANIVERSARIO 6X700ML 40GL NAC', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7859', 'RON PAMPERO SELECCION 6X700ML 40GL NAC', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7863', 'WHISKY BUCHANANS 12A 12X750ML 40GL IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7865', 'WHISKY OLD PARR 12A 12X750ML 40GL IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7866', 'CREMA WHISKY BAILEYS 12X750ML 17GL IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7867', 'GIN TANQUERAY LONDON 6X700ML 47,3GL IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7868', 'VODKA SMIRNOFF XXI 6X700 ML 40GL IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7871', 'WHISKY BUCHANANS 18A 6X750ML 40GL IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7872', 'WHISKY OLD PARR SILVER 12X750ML 40GL IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7882', 'WHISKY JW BLC. LB. 12A 12x700ML 40GL IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7887', 'WHISKY BLACK AND WHITE 12X1L 40GL IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7888', 'WHISKY BUCHANAN MASTER 12X750ML 40GL IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7889', 'VODKA SMIRNOFF SPICY TMR 6X700ML 30G IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7893', 'WHISKY OLD PARR TROPICAL12A 12X750ML IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7896', 'WHISKY OLD PARR 12A 12X1L 40GL IMP', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7971', 'AGUA MINERAL BIENESTAR 16X600ML', 'UNID', 0.00, 1, NULL);
    INSERT INTO public.productos (codigo_producto, nombre, unidad_medida, peso_unitario_kg, cant_unidad_medida, contenedor_id)
    VALUES ('7972', 'AGUA MINERAL BIENESTAR 6X1.5L', 'UNID', 0.00, 1, NULL);
END;
$$;