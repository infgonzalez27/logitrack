import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

const PUBLIC_ROUTES = [
  "/login",
  "/register",
  "/recuperar-clave",
  "/actualizar-clave",
  "/~offline",
];

const GUEST_ONLY_ROUTES = ["/login", "/register"];

function isPublicAssetPath(pathname: string) {
  return (
    pathname.startsWith("/serwist/") ||
    pathname.startsWith("/icons/") ||
    pathname === "/manifest.webmanifest" ||
    pathname === "/apple-icon.png"
  );
}

export async function updateSession(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value),
          );
          supabaseResponse = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options),
          );
        },
      },
    },
  );

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { pathname } = request.nextUrl;
  const isPublic =
    PUBLIC_ROUTES.some((route) => pathname.startsWith(route)) ||
    pathname.startsWith("/api/") ||
    isPublicAssetPath(pathname);

  if (!user && !isPublic) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("redirect", pathname);
    return NextResponse.redirect(url);
  }

  if (user) {
    // Inject Tenant routing cookies if missing
    let tenantUrl = request.cookies.get("lt_tenant_url")?.value;
    let tenantKey = request.cookies.get("lt_tenant_key")?.value;
    
    if (!tenantUrl || !tenantKey) {
      const { data } = await supabase
        .from("usuarios_empresas")
        .select("empresas(supabase_url, supabase_anon_key)")
        .eq("user_id", user.id)
        .single();
        
      if (data && data.empresas) {
        // @ts-ignore
        tenantUrl = data.empresas.supabase_url;
        // @ts-ignore
        tenantKey = data.empresas.supabase_anon_key;
        
        if (tenantUrl && tenantKey) {
          supabaseResponse.cookies.set("lt_tenant_url", tenantUrl, { path: "/" });
          supabaseResponse.cookies.set("lt_tenant_key", tenantKey, { path: "/" });
        }
      }
    }
  }

  if (user && GUEST_ONLY_ROUTES.some((route) => pathname.startsWith(route))) {
    const url = request.nextUrl.clone();
    url.pathname = "/ordenes";
    return NextResponse.redirect(url);
  }

  return supabaseResponse;
}
