# Procedimiento de Aprovisionamiento y Duplicación de BD Tenant (`LogiTrack` -> `lt_[empresa]`)

Este documento especifica los pasos operativos para clonar el esquema y catálogo máster de la base de datos plantilla **`LogiTrack`** hacia un nuevo proyecto de Supabase para un tenant específico **`lt_[nombre_empresa]`** (ej: `lt_ramirez`).

---

## 📋 Requisitos Previos
1. Supabase CLI instalado (`npx supabase` o `supabase` instalado globalmente).
2. Credenciales y acceso de administrador al proyecto Supabase Máster (`LogiTrack`) y al nuevo proyecto Supabase del tenant (`lt_[nombre_empresa]`).

---

## 🚀 Pasos para Aprovisionar un Nuevo Tenant

### Paso 1: Volcar el Esquema y Catálogos de la BD Plantilla (`LogiTrack`)
Ejecutar el siguiente comando desde la terminal en el directorio raíz del proyecto:

```bash
# Exportar esquema y datos semilla de LogiTrack
npx supabase db dump -f supabase/template_dump.sql --data-only --schema public
```

O si utilizas pg_dump directo desde la URI de conexión de PostgreSQL:
```bash
pg_dump "postgres://postgres:[PASSWORD]@[HOST]:5432/postgres" --schema=public --clean --if-exists > template_dump.sql
```

### Paso 2: Crear el Nuevo Proyecto Supabase para la Empresa
1. Crear una nueva organización/proyecto en Supabase Dashboard o vía CLI:
   - **Nombre de Proyecto**: `lt_[nombre_empresa]` (ejemplo: `lt_ramirez`).
2. Obtener la `SUPABASE_URL` y la `SUPABASE_ANON_KEY` del nuevo proyecto.

### Paso 3: Restaurar la Estructura en la Nueva Base de Datos (`lt_[nombre_empresa]`)
Vincular el entorno o restaurar el archivo SQL en el nuevo proyecto:

```bash
# Opción A: Mediante Supabase CLI vinculando el nuevo project ref
npx supabase link --project-ref [NUEVO_PROJECT_REF]
npx supabase db push

# Opción B: Restaurar archivo SQL directamente mediante psql
psql "postgres://postgres:[NUEVO_PASSWORD]@[NUEVO_HOST]:5432/postgres" -f supabase/template_dump.sql
```

### Paso 4: Registrar el Nuevo Tenant en la Base de Datos Central (`DB_CENTRAL`)
Conectar a la Base de Datos Central e insertar el registro en `public.empresas` y mapear a los usuarios iniciales:

```sql
-- 1. Registrar credenciales de la nueva empresa
INSERT INTO public.empresas (codigo_empresa, nombre_empresa, supabase_url, supabase_anon_key, activo)
VALUES (
    'ramirez',
    'Comercializadora Ramírez C.A.',
    'https://[NUEVO_PROJECT_REF].supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...', -- Anon Key del nuevo proyecto lt_ramirez
    true
);

-- 2. Asignar el usuario administrador al tenant
INSERT INTO public.usuarios_empresas (user_id, empresa_id, rol)
VALUES (
    '[UUID_DEL_USUARIO]', -- auth.users.id
    (SELECT id FROM public.empresas WHERE codigo_empresa = 'ramirez'),
    'administrador'
);
```

---

## 🔒 Verificación de Aislamiento
- Cada tenant `lt_[nombre_empresa]` opera en su propio proyecto Supabase independiente.
- Los usuarios de un tenant no poseen permisos ni visibilidad sobre los datos de otro tenant.
