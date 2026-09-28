// Edge Function: reset-password (RETIRADA)
// Permitía a cualquier usuario con sesión cambiar la contraseña de otro.
// La app móvil usa POST https://logitrack.informaticagonzalez.com/api/mobile/usuarios/contrasena
// (ver docs/INTEGRACION-RPC.md §2.43.4).

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

Deno.serve(() =>
  new Response(
    JSON.stringify({
      ok: false,
      error:
        "Función retirada. Actualiza la app: el cambio de contraseña se hace en /api/mobile/usuarios/contrasena.",
    }),
    { status: 410, headers: { "Content-Type": "application/json" } },
  )
);
