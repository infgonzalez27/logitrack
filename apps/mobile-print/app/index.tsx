import { Redirect } from "expo-router";
import { useAuth } from "@/lib/auth-context";

export default function Index() {
  const { profile } = useAuth();
  if (profile) return <Redirect href="/(app)/orders" />;
  return <Redirect href="/login" />;
}
