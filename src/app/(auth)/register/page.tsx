import { getRolesOptions } from "@/lib/data/roles";
import { RegisterForm } from "./register-form";

export default async function RegisterPage() {
  const options = await getRolesOptions();
  return <RegisterForm roles={options} />;
}
