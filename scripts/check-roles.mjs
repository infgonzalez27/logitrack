import { createClient } from "@supabase/supabase-js";
import { readFileSync, existsSync } from "fs";
import { resolve } from "path";

function loadEnv() {
  const path = existsSync(resolve(".env.local"))
    ? ".env.local"
    : existsSync(resolve(".env"))
      ? ".env"
      : null;
  if (!path) return {};
  const env = {};
  for (const line of readFileSync(path, "utf8").split(/\r?\n/)) {
    if (!line || line.startsWith("#")) continue;
    const i = line.indexOf("=");
    if (i === -1) continue;
    const key = line.slice(0, i).trim();
    let val = line.slice(i + 1).trim();
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1);
    }
    env[key] = val;
  }
  return env;
}

const env = loadEnv();
const url = env.NEXT_PUBLIC_SUPABASE_URL;
const key = env.SUPABASE_SERVICE_ROLE_KEY;

if (!url || !key) {
  console.error("Faltan variables Supabase en .env.local o .env");
  process.exit(1);
}

const supabase = createClient(url, key);
const { data, error } = await supabase
  .from("roles")
  .select("id, nombre, descripcion, created_at")
  .order("nombre");

if (error) {
  console.error("Error:", error.message);
  process.exit(1);
}

const tieneVendedor = (data ?? []).some((r) => r.nombre === "vendedor");

console.log(JSON.stringify({ tieneVendedor, roles: data }, null, 2));
