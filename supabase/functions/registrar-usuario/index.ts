// Edge Function: registrar-usuario (RETIRADA)
// No validaba el rol de quien llamaba ni creaba el usuario en la BD de su empresa.
// La app móvil usa POST https://logitrack.informaticagonzalez.com/api/mobile/usuarios
// (ver docs/INTEGRACION-RPC.md §2.43.4).

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

Deno.serve(() =>
  new Response(
    JSON.stringify({
      ok: false,
      error:
        "Función retirada. Actualiza la app: el registro de usuarios se hace en /api/mobile/usuarios.",
    }),
    { status: 410, headers: { "Content-Type": "application/json" } },
  )
);
