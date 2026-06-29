import { createClient } from "@/lib/supabase/server";
import { joinOne } from "@/lib/supabase/join";
import { NuevaOrdenForm } from "./nueva-orden-form";

export default async function NuevaOrdenPage() {
  const supabase = await createClient();

  const [
    { data: clientes },
    { data: camiones },
    { data: choferes },
    { data: productos },
  ] = await Promise.all([
    supabase.from("clientes").select("id, razon_social").eq("activo", true).order("razon_social"),
    supabase.from("camiones").select("id, placa").neq("estado", "inactivo").order("placa"),
    supabase
      .from("choferes")
      .select("perfil_id, perfiles_usuario(nombre_completo)")
      .neq("estado", "suspendido"),
    supabase.from("productos").select("id, nombre, peso_unitario_kg").order("nombre"),
  ]);

  return (
    <NuevaOrdenForm
      clientes={(clientes ?? []).map((c) => ({
        value: c.id,
        label: c.razon_social,
      }))}
      camiones={(camiones ?? []).map((c) => ({
        value: c.id,
        label: c.placa,
      }))}
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
