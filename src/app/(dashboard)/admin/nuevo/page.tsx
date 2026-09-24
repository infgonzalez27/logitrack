import Link from "next/link";
import { getCurrentProfile } from "@/lib/auth";
import { getRoleNameFromProfile, labelRol } from "@/lib/auth/roles";
import { PageHeader } from "@/components/layout/page-header";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { NuevaEmpresaForm } from "../nueva-empresa-form";

export default async function NuevaEmpresaPage() {
  const profile = await getCurrentProfile();
  const rol = getRoleNameFromProfile(profile);

  if (rol !== "admin") {
    return (
      <div className="mx-auto max-w-lg space-y-4">
        <PageHeader title="Nueva empresa" />
        <Card>
          <p className="text-sm text-lt-text">
            Solo <strong>admin</strong> puede crear empresas. Sesión actual:{" "}
            <strong>{labelRol(rol)}</strong>.
          </p>
          <div className="mt-4 flex gap-3">
            <Button href="/login" variant="primary">
              Ir a login
            </Button>
            <Button href="/admin" variant="secondary">
              Volver
            </Button>
          </div>
        </Card>
        <p className="text-xs text-lt-text-muted">
          <Link href="/admin" className="text-lt-primary hover:underline">
            /admin
          </Link>
        </p>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-lg space-y-6">
      <PageHeader
        title="Nueva empresa"
        description="Registra empresa y gerente. El backend crea el proyecto lt_* y llama a los RPCs de Central."
      />
      <NuevaEmpresaForm />
    </div>
  );
}
