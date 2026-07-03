import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function GET() {
  if (process.env.NODE_ENV !== "development") {
    return NextResponse.json(
      { ok: false, error: "Solo disponible en desarrollo." },
      { status: 403 },
    );
  }

  try {
    const admin = createAdminClient();
    const { data, error } = await admin
      .from("roles")
      .select("id, nombre, descripcion, created_at")
      .order("nombre");

    if (error) {
      return NextResponse.json({ ok: false, error: error.message }, { status: 500 });
    }

    const roles = data ?? [];
    const tieneVendedor = roles.some((r) => r.nombre === "vendedor");

    return NextResponse.json({
      ok: true,
      total: roles.length,
      tieneVendedor,
      roles,
    });
  } catch (err) {
    return NextResponse.json(
      {
        ok: false,
        error: err instanceof Error ? err.message : "Error al consultar roles.",
      },
      { status: 500 },
    );
  }
}
