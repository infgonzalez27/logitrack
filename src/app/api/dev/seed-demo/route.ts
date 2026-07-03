import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { seedDemoDashboard } from "@/lib/demo/seed-dashboard";

export async function POST() {
  if (process.env.NODE_ENV !== "development") {
    return NextResponse.json(
      { ok: false, error: "Solo disponible en desarrollo." },
      { status: 403 },
    );
  }

  try {
    const admin = createAdminClient();
    const result = await seedDemoDashboard(admin);

    if (!result.ok) {
      return NextResponse.json(result, { status: 500 });
    }

    return NextResponse.json({
      ok: true,
      message:
        "Datos demo cargados. Recarga el dashboard (/) para ver los gráficos.",
      summary: result.summary,
    });
  } catch (err) {
    return NextResponse.json(
      {
        ok: false,
        error: err instanceof Error ? err.message : "Error al cargar demo.",
      },
      { status: 500 },
    );
  }
}

export async function GET() {
  return POST();
}
