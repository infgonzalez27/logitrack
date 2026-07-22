import Link from "next/link";
import { Card } from "@/components/ui/card";

export function UsuarioContrasenaAviso({
  email,
}: {
  email: string | null;
}) {
  return (
    <Card title="Contraseña de acceso">
      <p className="text-sm text-lt-text-muted">
        Solo un <strong className="text-lt-text">administrador</strong> puede
        asignar una contraseña nueva a este usuario desde la app.
      </p>
      {email ? (
        <p className="mt-3 text-sm">
          <span className="text-lt-text-muted">Correo de acceso: </span>
          <span className="font-medium">{email}</span>
        </p>
      ) : null}
      <p className="mt-3 text-sm text-lt-text-muted">
        El usuario puede usar{" "}
        <Link href="/recuperar-clave" className="text-lt-primary underline">
          Recuperar contraseña
        </Link>{" "}
        en el login, o restablecerla en Supabase Auth.
      </p>
    </Card>
  );
}
