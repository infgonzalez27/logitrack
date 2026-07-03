import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { canCreateOrden } from "@/lib/auth/orden-permissions";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { createClient } from "@/lib/supabase/server";
import { joinOne } from "@/lib/supabase/join";
import { NuevaOrdenForm } from "./nueva-orden-form";

export default async function NuevaOrdenPage() {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (!canCreateOrden(rol)) redirect("/ordenes");

  const supabase = await createClient();

  const [{ data: choferes }, { data: productos }] = await Promise.all([
    supabase
      .from("choferes")
      .select("perfil_id, perfiles_usuario(nombre_completo)")
      .neq("estado", "suspendido"),
    supabase.from("productos").select("id, nombre, peso_unitario_kg").order("nombre"),
  ]);

  return (
    <NuevaOrdenForm
      choferes={(choferes ?? []).map((c) => {
        const perfil = joinOne(c.perfiles_usuario);
        return {
          value: c.perfil_id,
          label: perfil?.nombre_completo ?? c.perfil_id,
        };
      })}
      productos={(productos ?? []).map((p) => ({
        value: p.id,
        label: p.nombre,
        peso: p.peso_unitario_kg,
      }))}
    />
  );
}
