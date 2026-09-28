import type { NextConfig } from "next";
import { withSerwist } from "@serwist/turbopack";

const nextConfig: NextConfig = {
  outputFileTracingIncludes: {
    "/admin": ["./supabase/*.sql", "./supabase/tenant_patches/*.sql"],
    "/admin/**": ["./supabase/*.sql", "./supabase/tenant_patches/*.sql"],
  },
};

export default withSerwist(nextConfig);
