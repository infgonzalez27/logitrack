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

Las fotos de producto deben ser **cajas / empaque**, no botellas individuales.

---

## 2. Configuración de Buckets en Supabase Storage

En el panel de administración de Supabase deben configurarse los siguientes **Buckets Públicos**:

| Nombre del Bucket | Visibilidad | Propósito |
| :--- | :--- | :--- |
| `productos` | Público | Fotografías de catálogo (cajas). |
| `usuarios` | Público | Fotografías de perfil y avatares. |

---

## 3. Integración en Next.js (Variables de Entorno)

```env
NEXT_PUBLIC_STORAGE_BASE_URL=https://egwryptydgxdnjvwtrfq.supabase.co/storage/v1/object/public
```

Si en el futuro se migra a AWS S3 o MinIO, solo se cambia esta variable.

---

## 4. Consumo en Frontend

Usar `LogiImage` (`src/components/media/logi-image.tsx`): construye la URL con `NEXT_PUBLIC_STORAGE_BASE_URL` + `imagen_path` y cae a placeholder si falla.

Prioridad de foto de producto:

1. `productos.imagen_path` (Storage)
2. Fallback local de caja/lata en `public/productos`
3. Placeholder SVG

---

## 5. Server Action de subida

Subir el archivo al bucket (`productos` o `usuarios`) y guardar **solo** la ruta relativa en `imagen_path`. No persistir bytes en PostgreSQL.

---

## 6. Catálogo canónico de cajas (listo para upload)

Fuente de verdad local:

| Carpeta | Uso |
| :--- | :--- |
| `assets/storage/productos/*.webp` | Archivos listos para el bucket público `productos` |
| `assets/storage/productos/manifest.json` | Mapa etiqueta → `imagen_path` |
| `assets/storage/_source/*.png` | Originales (no subir) |
| `public/productos/*.webp` | Fallback local si `imagen_path` aún es null |

Especificación de cada asset:

- Formato: **WebP**
- Lienzo: **1024×1024** (producto centrado, fondo blanco)
- `imagen_path`: `/productos/<slug>.webp`

| Etiqueta | Archivo | `imagen_path` |
| :--- | :--- | :--- |
| Cardenal Estilo Munich | `cardenal-estilo-munich.webp` | `/productos/cardenal-estilo-munich.webp` |
| Cardenal Ultra | `cardenal-ultra.webp` | `/productos/cardenal-ultra.webp` |
| Malta Morena | `malta-morena.webp` | `/productos/malta-morena.webp` |
| Malta Regional | `malta-regional.webp` | `/productos/malta-regional.webp` |
| Morena Tipo Lager | `morena-tipo-lager.webp` | `/productos/morena-tipo-lager.webp` |
| Morena Tipo Pilsen | `morena-tipo-pilsen.webp` | `/productos/morena-tipo-pilsen.webp` |
| Regional clásica | `regional-clasica.webp` | `/productos/regional-clasica.webp` |
| Regional Light | `regional-light.webp` | `/productos/regional-light.webp` |
| Zulia | `zulia.webp` | `/productos/zulia.webp` |

Tras subir al bucket, actualizar `productos.imagen_path` con la ruta relativa (varios SKU pueden compartir la misma caja).
