<!-- BEGIN:nextjs-agent-rules -->
# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` before writing any code. Heed deprecation notices.
<!-- END:nextjs-agent-rules -->

<!-- BEGIN:logitrack-agent-rules -->
# REGLA DE ORO DE COMUNICACIÃ“N CON EL FRONTEND
Siempre que modifiques lÃ³gica, base de datos o arquitectura que afecte el desarrollo del Frontend, DEBES documentarlo inmediatamente en el archivo `docs/INTEGRACION-RPC.md` y hacer un `git push` a Github. El desarrollador Frontend leerÃ¡ este archivo para actualizar su cÃ³digo local.

# REGLA DE ENTORNO DE PRUEBAS
El usuario principal (Jorge) realiza sus pruebas desde un dispositivo mÃ³vil apuntando a la nube (entorno de producciÃ³n/staging), no en local. Esto significa que cuando el agente (tÃº) hace un `git push` a Github, esos cambios solo se reflejarÃ¡n en las pruebas del usuario UNA VEZ que el servicio de hosting en la nube (Vercel, etc.) haya detectado el commit y terminado de desplegar (build) la nueva versiÃ³n. Ten esto en cuenta si el usuario reporta que "los cambios no aparecen" a pesar de que el cÃ³digo en el repositorio ya estÃ¡ correcto.
<!-- END:logitrack-agent-rules -->
