// Supabase Edge Function: upload_product_image
// Permite subir fotos de productos (WebP, JPG, PNG <= 5MB) al bucket "productos"
// y actualizar inmediatamente la columna imagen_path en la tabla public.productos.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const MAX_FILE_SIZE_BYTES = 5 * 1024 * 1024; // 5 MB
const ALLOWED_MIME_TYPES = new Set([
  "image/webp",
  "image/jpeg",
  "image/jpg",
  "image/png",
]);

Deno.serve(async (req: Request) => {
  // Manejo de preflight CORS
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ ok: false, error: "Método no permitido. Usa POST." }),
      { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !supabaseServiceKey) {
      return new Response(
        JSON.stringify({ ok: false, error: "Variables de entorno de Supabase no configuradas." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Cliente con Service Role para acceso seguro a Storage y PostgreSQL
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const contentType = req.headers.get("content-type") || "";
    if (!contentType.includes("multipart/form-data")) {
      return new Response(
        JSON.stringify({ ok: false, error: "Content-Type debe ser multipart/form-data." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const formData = await req.formData();
    const file = formData.get("file");
    const productId = formData.get("product_id");

    if (!productId || typeof productId !== "string") {
      return new Response(
        JSON.stringify({ ok: false, error: "El parámetro 'product_id' (UUID) es obligatorio." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!file || !(file instanceof File)) {
      return new Response(
        JSON.stringify({ ok: false, error: "El archivo 'file' es obligatorio." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (file.size > MAX_FILE_SIZE_BYTES) {
      return new Response(
        JSON.stringify({ ok: false, error: "El archivo supera el tamaño máximo permitido de 5 MB." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const mime = file.type || "application/octet-stream";
    if (!ALLOWED_MIME_TYPES.has(mime)) {
      return new Response(
        JSON.stringify({
          ok: false,
          error: "Tipo de archivo no permitido. Solo se aceptan WebP, JPG y PNG.",
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Determinar extensión adecuada
    let ext = "webp";
    if (mime === "image/jpeg" || mime === "image/jpg") ext = "jpg";
    else if (mime === "image/png") ext = "png";
    else if (file.name.includes(".")) {
      ext = file.name.split(".").pop()?.toLowerCase() || "webp";
    }

    const fileName = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`;
    const storagePath = `${fileName}`;
    const relativeImagePath = `/productos/${fileName}`;

    // 1. Subir archivo a Supabase Storage (bucket "productos")
    const arrayBuffer = await file.arrayBuffer();
    const { error: uploadError } = await supabase.storage
      .from("productos")
      .upload(storagePath, arrayBuffer, {
        contentType: mime,
        upsert: true,
      });

    if (uploadError) {
      return new Response(
        JSON.stringify({
          ok: false,
          error: `Error al subir al bucket 'productos': ${uploadError.message}`,
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 2. Actualizar campo imagen_path en la tabla productos
    const { error: updateError } = await supabase
      .from("productos")
      .update({ imagen_path: relativeImagePath })
      .eq("id", productId);

    if (updateError) {
      return new Response(
        JSON.stringify({
          ok: false,
          error: `Imagen subida pero falló la actualización del producto: ${updateError.message}`,
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({
        ok: true,
        imagen_path: relativeImagePath,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : "Error interno del servidor.";
    return new Response(
      JSON.stringify({ ok: false, error: message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

