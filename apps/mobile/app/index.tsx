import { Redirect } from "expo-router";
import { useAuth } from "@/lib/auth-context";
import { homeHrefForRole } from "@/lib/auth";

export default function Index() {
  const { profile } = useAuth();
  if (profile) {
    return <Redirect href={homeHrefForRole(profile.rol) as never} />;
  }
  return <Redirect href="/login" />;
}
