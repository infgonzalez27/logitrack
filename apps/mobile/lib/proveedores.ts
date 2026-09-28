import { supabase } from "./supabase";

export type Proveedor = {
  id: string;
  rif_nit: string;
  razon_social: string;
  direccion_fiscal: string | null;
  telefono: string | null;
  correo_e: string | null;
  activo: boolean;
};

export async function listProveedores(query?: string): Promise<
  { ok: true; proveedores: Proveedor[] } | { ok: false; error: string }
> {
  let q = supabase
    .from("proveedores")
    .select(
      "id, rif_nit, razon_social, direccion_fiscal, telefono, correo_e, activo",
    )
    .order("razon_social")
    .limit(200);

  const term = query?.trim();
  if (term) {
    q = q.or(
      `razon_social.ilike.%${term}%,rif_nit.ilike.%${term}%`,
    );
  }

  const { data, error } = await q;
  if (error) return { ok: false, error: error.message };
  return { ok: true, proveedores: (data ?? []) as Proveedor[] };
}

export async function getProveedor(
  id: string,
): Promise<{ ok: true; proveedor: Proveedor } | { ok: false; error: string }> {
  const { data, error } = await supabase
    .from("proveedores")
    .select(
      "id, rif_nit, razon_social, direccion_fiscal, telefono, correo_e, activo",
    )
    .eq("id", id)
    .maybeSingle();

  if (error) return { ok: false, error: error.message };
  if (!data) return { ok: false, error: "Proveedor no encontrado." };
  return { ok: true, proveedor: data as Proveedor };
}

export async function createProveedor(input: {
  rif_nit: string;
  razon_social: string;
  direccion_fiscal?: string | null;
  telefono?: string | null;
  correo_e?: string | null;
}): Promise<{ ok: true; id: string } | { ok: false; error: string }> {
  const rif = input.rif_nit.trim();
  const razon = input.razon_social.trim();
  if (!rif) return { ok: false, error: "El RIF/NIT es requerido." };
  if (!razon) return { ok: false, error: "La razón social es requerida." };

  const { data, error } = await supabase
    .from("proveedores")
    .insert({
      rif_nit: rif,
      razon_social: razon,
      direccion_fiscal: input.direccion_fiscal?.trim() || null,
      telefono: input.telefono?.trim() || null,
      correo_e: input.correo_e?.trim() || null,
      activo: true,
    })
    .select("id")
    .single();

  if (error) return { ok: false, error: error.message };
  return { ok: true, id: data.id as string };
}

export async function updateProveedor(input: {
  id: string;
  rif_nit: string;
  razon_social: string;
  direccion_fiscal?: string | null;
  telefono?: string | null;
  correo_e?: string | null;
  activo: boolean;
}): Promise<{ ok: true } | { ok: false; error: string }> {
  const rif = input.rif_nit.trim();
  const razon = input.razon_social.trim();
  if (!rif) return { ok: false, error: "El RIF/NIT es requerido." };
  if (!razon) return { ok: false, error: "La razón social es requerida." };

  const { error } = await supabase
    .from("proveedores")
    .update({
      rif_nit: rif,
      razon_social: razon,
      direccion_fiscal: input.direccion_fiscal?.trim() || null,
      telefono: input.telefono?.trim() || null,
      correo_e: input.correo_e?.trim() || null,
      activo: input.activo,
    })
    .eq("id", input.id);

  if (error) return { ok: false, error: error.message };
  return { ok: true };
}
