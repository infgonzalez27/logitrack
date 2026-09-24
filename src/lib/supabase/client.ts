import { createBrowserClient } from "@supabase/ssr";

export function getCookie(name: string) {
  if (typeof document === 'undefined') return null;
  const match = document.cookie.match(new RegExp('(^| )' + name + '=([^;]+)'));
  if (match) return decodeURIComponent(match[2]);
  return null;
}

export function createClient() {
  const cookieUrl = getCookie("lt_tenant_url");
  const cookieKey = getCookie("lt_tenant_key");

  const url = cookieUrl || process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = cookieKey || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !key) {
    throw new Error(
      "Faltan NEXT_PUBLIC_SUPABASE_URL o NEXT_PUBLIC_SUPABASE_ANON_KEY.",
    );
  }

  return createBrowserClient(url, key);
}
