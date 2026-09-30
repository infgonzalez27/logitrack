<!-- BEGIN:nextjs-agent-rules -->
# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` before writing any code. Heed deprecation notices.
<!-- END:nextjs-agent-rules -->

<!-- BEGIN:logitrack-agent-rules -->
# REGLA DE ORO DE COMUNICACIÓN CON EL FRONTEND
Siempre que modifiques lógica, base de datos o arquitectura que afecte el desarrollo del Frontend, DEBES documentarlo inmediatamente en el archivo `docs/INTEGRACION-RPC.md` y hacer un `git push` a Github. El desarrollador Frontend leerá este archivo para actualizar su código local.

# REGLA DE ENTORNO DE PRUEBAS
El usuario principal (Jorge) realiza sus pruebas desde un dispositivo móvil apuntando a la nube (entorno de producción/staging), no en local. Esto significa que cuando el agente (tú) hace un `git push` a Github, esos cambios se reflejarán cuando el frontend se despliegue.
NO ACTUALIZAMOS tareas del Frontend y Backend en Vercel.

# REGLA DE BUILDS DE LA APP MÓVIL (APK)
Los builds de EAS cuestan dinero. NUNCA lances `eas build` sin autorización explícita del usuario en ese momento. Los cambios en `apps/mobile` se hacen, se prueban con typecheck y se suben a GitHub, pero el APK se compila solo cuando el usuario lo pida, agrupando varios cambios en un mismo build.

# REGLA DE CAMBIOS DE BD PARA EMPRESAS (TENANTS lt_*)
Cada empresa tiene su propio proyecto Supabase. Todo cambio de esquema, RPC, trigger o política RLS que deba existir en las empresas va como archivo **idempotente** en `supabase/tenant_patches/AAAAMMDDHHMMSS_descripcion.sql` (`CREATE OR REPLACE`, `DROP ... IF EXISTS` antes de `CREATE`, `IF NOT EXISTS`).

# REGLA DE SQL: EL AGENTE EJECUTA
El agente (tú) es el encargado con permiso para ejecutar sentencias SQL en la base de datos en Supabase. Si hay un cambio pendiente, puedes ejecutarlo utilizando las credenciales CLI activas o los comandos correspondientes.
<!-- END:logitrack-agent-rules -->
