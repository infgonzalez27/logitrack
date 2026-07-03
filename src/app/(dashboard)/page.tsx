import { redirect } from "next/navigation";
import { getCurrentProfile, getSessionUser } from "@/lib/auth";
import {
  getRoleNameFromProfile,
  labelRol,
} from "@/lib/auth/roles";
import { ventaScopeLabel } from "@/lib/dashboard/sales";
import { fetchDashboardCharts } from "@/lib/dashboard/charts";
import { fetchDashboardKpis } from "@/lib/dashboard/kpis";
import { createClient } from "@/lib/supabase/server";
import { RoleDashboard } from "@/components/dashboard/role-dashboard";

export default async function HomePage() {
  const user = await getSessionUser();
  if (!user) redirect("/login");

  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  const supabase = await createClient();
  const [kpis, charts] = await Promise.all([
    fetchDashboardKpis(supabase, rol, user.id),
    fetchDashboardCharts(supabase, rol, user.id),
  ]);

  const rolLabel = labelRol(rol);
  const nombre = profile?.nombre_completo ?? "Usuario";

  const scopeHint = ventaScopeLabel(rol);

  return (
    <RoleDashboard
      title={`Hola, ${nombre.split(" ")[0]}`}
      description={`Panel de ${rolLabel.toLowerCase()} · Ventas y cartera: ${scopeHint}.`}
      kpis={kpis}
      charts={charts}
      rol={rol}
    />
  );
}
