# Guía Técnica y Estándar de Almacenamiento de Imágenes (Storage & Base de Datos)

**Proyecto:** LogiTrack  
**Destinatarios:** Equipo de Desarrollo Frontend & Backend  
**Propósito:** Definir el estándar de arquitectura, nombrado y consumo de imágenes para productos y perfiles de usuario utilizando Supabase Storage y PostgreSQL.

---

## 1. Regla de Oro de la Arquitectura

1. **NO almacenar cadenas Base64 ni datos binarios `BYTEA` en las tablas SQL.**
2. **Almacenar únicamente la RUTA RELATIVA (`imagen_path`)** en las columnas de las tablas PostgreSQL:
   - Tabla `public.productos`: Columna `imagen_path TEXT` (ejemplo: `/productos/harina-pan-1kg.webp`).
   - Tabla `public.perfiles_usuario`: Columna `imagen_path TEXT` (ejemplo: `/usuarios/avatar-carlos-perez.webp`).

---

## 2. Configuración de Buckets en Supabase Storage

En el panel de administración de Supabase (o mediante la API de Storage), deben configurarse los siguientes **Buckets Públicos**:

| Nombre del Bucket | Visibilidad | Propósito |
| :--- | :--- | :--- |
| `productos` | Público | Fotografías de catálogo de mercancía y productos. |
| `usuarios` | Público | Fotografías de perfil y avatares de usuarios/despachadores. |

---

## 3. Integración en Next.js (Variables de Entorno)

En el archivo `.env.local` del proyecto Next.js, se define la URL base del servicio de almacenamiento:

```env
# En Supabase Cloud / Desarrollo Local:
NEXT_PUBLIC_STORAGE_BASE_URL=https://egwryptydgxdnjvwtrfq.supabase.co/storage/v1/object/public

# Si en el futuro se migra a AWS S3 o MinIO, SOLO se cambia esta variable de entorno:
# NEXT_PUBLIC_STORAGE_BASE_URL=https://mi-bucket-logitrack.s3.amazonaws.com
```

---

## 4. Componente React Reutilizable para Frontend con Fallback Automático

Para garantizar que la aplicación **nunca muestre imágenes rotas o errores 404** si una foto es eliminada o no existe, el equipo Frontend debe utilizar este componente reusable:

```tsx
'use client';

import React, { useState } from 'react';
import Image, { ImageProps } from 'next/image';

interface LogiImageProps extends Omit<ImageProps, 'src'> {
  path?: string | null;
  type: 'producto' | 'usuario';
  fallbackSrc?: string;
}

export function LogiImage({ path, type, alt, fallbackSrc, ...props }: LogiImageProps) {
  const defaultFallback = type === 'producto' 
    ? '/images/placeholders/producto-placeholder.png'
    : '/images/placeholders/avatar-placeholder.png';

  const baseUrl = process.env.NEXT_PUBLIC_STORAGE_BASE_URL || '';
  
  // Construir la URL completa si el path existe, o usar el placeholder
  const initialSrc = path ? `${baseUrl}${path}` : (fallbackSrc || defaultFallback);

  const [imgSrc, setImgSrc] = useState<string>(initialSrc);

  return (
    <Image
      {...props}
      src={imgSrc}
      alt={alt}
      onError={() => {
        // Si el servidor de storage devuelve Error 404 o falla la carga, cambia al placeholder automáticamente
        setImgSrc(fallbackSrc || defaultFallback);
      }}
    />
  );
}
```

### Ejemplo de Uso en una Tabla o Ficha de Producto:

```tsx
import { LogiImage } from '@/components/ui/logi-image';

export function ProductoCard({ producto }: { producto: any }) {
  return (
    <div className="flex items-center gap-3">
      <LogiImage
        path={producto.imagen_path}
        type="producto"
        alt={producto.nombre}
        width={60}
        height={60}
        className="rounded-lg object-cover"
      />
      <div>
        <h4 className="font-semibold">{producto.nombre}</h4>
        <p className="text-sm text-gray-500">{producto.codigo_producto}</p>
      </div>
    </div>
  );
}
```

---

## 5. Server Action para Cargar Fotos desde el Dashboard (Next.js & Supabase Client)

A continuación se muestra la implementación recomendada en Server Actions para subir la imagen a Supabase Storage y guardar únicamente el `imagen_path` en la base de datos PostgreSQL:

```typescript
'use server';

import { createClient } from '@/lib/supabase/server';
import { revalidatePath } from 'next/cache';

export async function subirImagenProductoAction(productoId: string, formData: FormData) {
  const supabase = await createClient();
  const file = formData.get('foto') as File;

  if (!file || file.size === 0) {
    return { success: false, error: 'No se ha seleccionado ningún archivo.' };
  }

  // 1. Generar nombre único para el archivo en el bucket
  const fileExt = file.name.split('.').pop();
  const fileName = `prod_${productoId}_${Date.now()}.${fileExt}`;
  const relativePath = `/productos/${fileName}`; // Ruta que se guardará en la BD

  // 2. Subir el archivo al Bucket 'productos' en Supabase Storage
  const { data, error: uploadError } = await supabase.storage
    .from('productos')
    .upload(fileName, file, { upsert: true });

  if (uploadError) {
    return { success: false, error: uploadError.message };
  }

  // 3. Actualizar la columna imagen_path en la tabla productos de PostgreSQL
  const { error: dbError } = await supabase
    .from('productos')
    .update({ imagen_path: relativePath })
    .eq('id', productoId);

  if (dbError) {
    return { success: false, error: dbError.message };
  }

  revalidatePath('/productos');
  return { success: true, imagen_path: relativePath };
}
```

---

## 6. Ventajas Clave de este Estándar

1. **Portabilidad Absoluta:** Si el proyecto migra de Supabase a AWS S3, Azure Blob o MinIO, la base de datos no requiere modificaciones.
2. **Consultas Ultrarrápidas:** Los RPCs (`retorna_lista_productos_segun_parametros`, `retorna_radar_despachador`) siguen respondiendo en milisegundos sin sobrecargar la memoria de PostgreSQL.
3. **Cero Imágenes Rotas:** El frontend maneja con elegancia el estado fallback en caso de archivos faltantes o eliminados.
