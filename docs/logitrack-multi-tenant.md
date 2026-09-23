# Specification: Multi-Tenant Architecture & Routing (LogiTrack Template)

## Context & Purpose
The core database structure is fully built under the template database **`LogiTrack`**. 
New tenant databases are provisioned by duplicating the `LogiTrack` schema into new Supabase projects using the prefix naming standard **`lt_[nombre_empresa]`** (e.g., `lt_ramirez`).

This spec instructs Google Antigravity to:
1. Create the **Central Routing Database** (Main catalog linking users to their specific `lt_*` database).
2. Execute the database duplication procedure from `LogiTrack` to `lt_[nombre_empresa]`.
3. Implement the dynamic tenant client switcher for application code.

---

## Architectural Layout
+---------------------------------------+
                              | Central Supabase Project              |
                              |  - auth.users                         |
                              |  - public.empresas                    |
                              |  - public.usuarios_empresas           |
                              +-------------------+-------------------+
                                                  |
                                                  | (Resolves tenant URL & Key)
                                                  v
                 +--------------------------------+-------------------------------+
                 |                                                                |
                 v                                                                v
 +---------------+-------------------------------+        +-----------------------+-----------------------+
 | Base Master Database: `LogiTrack`              |        | Duplicated Tenant Database: `lt_ramirez`       |
 | (Template for all company clones)             |        | (Cloned from LogiTrack)               |
 +-----------------------------------------------+        +-----------------------------------------------+

---

## Phase 1: Central Database Schema Setup
**Target Database:** Central Supabase Project (`DB_CENTRAL`)

### Tasks

- [ ] **Task 1.1: Create Companies Catalog (`public.empresas`)**
  Create the table storing connection references for each company database (`lt_*`).
  
- [ ] Task 1.2: Create User-Tenant Link (public.usuarios_empresas)
Link central auth.users to their assigned company database.  

CREATE TABLE IF NOT EXISTS public.usuarios_empresas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    empresa_id UUID NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
    rol VARCHAR(50) DEFAULT 'operador',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_user_empresa UNIQUE (user_id, empresa_id)
);

-- RLS Isolation
ALTER TABLE public.empresas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.usuarios_empresas ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow users to read their own mapping" 
ON public.usuarios_empresas FOR SELECT TO authenticated 
USING (auth.uid() = user_id);

CREATE POLICY "Allow users to read assigned empresa details" 
ON public.empresas FOR SELECT TO authenticated 
USING (id IN (SELECT empresa_id FROM public.usuarios_empresas WHERE user_id = auth.uid()));

[ ] Task 2.1: Dump Master Schema & Seed Data from LogiTrack
Run via terminal / CLI to extract the template

[ ] Task 2.2: Restore Dump into New Tenant (lt_ramirez)
Restore the exact LogiTrack structure into the new Supabase project

[ ] Task 3.1: Implement LogiTrack Tenant Router
Create the utility class that handles central login and switches the Supabase client connection to the assigned lt_* project.

*"Lee la especificación `logitrack-multi-tenant.md` y ejecuta la Fase 1 para crear las tablas centrales de enrutamiento y la Fase 3 para crear el módulo TypeScript de conexion a las bases `lt_*`."*