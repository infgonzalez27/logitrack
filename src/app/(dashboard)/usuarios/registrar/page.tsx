import { getRolesOptions } from "@/lib/data/roles";
import { RegisterForm } from "@/app/(auth)/register/register-form";

export default async function RegistrarUsuarioPage() {
  const options = await getRolesOptions();

  return (
    <div className="mx-auto max-w-lg space-y-6">
      <RegisterForm roles={options} />
    </div>
  );
}
