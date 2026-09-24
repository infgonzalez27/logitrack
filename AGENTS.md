<!-- BEGIN:nextjs-agent-rules -->
# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` before writing any code. Heed deprecation notices.
<!-- END:nextjs-agent-rules -->

<!-- BEGIN:logitrack-agent-rules -->
# REGLA DE ORO DE COMUNICACIÓN CON EL FRONTEND
Siempre que modifiques lógica, base de datos o arquitectura que afecte el desarrollo del Frontend, DEBES documentarlo inmediatamente en el archivo `docs/INTEGRACION-RPC.md` y hacer un `git push` a Github. El desarrollador Frontend leerá este archivo para actualizar su código local.

# REGLA DE ENTORNO DE PRUEBAS
El usuario principal (Jorge) realiza sus pruebas desde un dispositivo móvil apuntando a la nube (entorno de producción/staging), no en local. Esto significa que cuando el agente (tú) hace un `git push` a Github, esos cambios solo se reflejarán en las pruebas del usuario UNA VEZ que el servicio de hosting en la nube (Vercel, etc.) haya terminado de desplegar (build) la nueva versión. Ten esto en cuenta si el usuario reporta que "los cambios no aparecen" a pesar de que el código en el repositorio ya está correcto.

Vercel NO está conectado a GitHub: cada cambio del frontend se publica a mano con `npx vercel --prod --yes` (https://logitrack.informaticagonzalez.com).
<!-- END:logitrack-agent-rules -->
