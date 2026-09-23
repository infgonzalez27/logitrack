import { redirect } from "next/navigation";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile } from "@/lib/auth/roles";
import { PageHeader } from "@/components/layout/page-header";
import { NuevaEmpresaForm } from "../nueva-empresa-form";

export default async function NuevaEmpresaPage() {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);
  if (rol !== "admin") {
    redirect("/");
  }

  return (
    <div className="mx-auto max-w-lg space-y-6">
      <PageHeader
        title="Nueva empresa"
        description="Registra el tenant lt_* en la BD Central y crea su gerente."
      />
      <NuevaEmpresaForm />
    </div>
  );
}
