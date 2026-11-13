"use client";

import { useEffect, useRef, useState } from "react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";

/**
 * Campo para subir una foto desde el dispositivo/PC al crear un producto,
 * con vista previa local y respaldo opcional de ruta manual.
 */
export function NuevoProductoImagenField() {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [fileName, setFileName] = useState<string | null>(null);
  const [manualPath, setManualPath] = useState("");

  useEffect(() => {
    return () => {
      if (previewUrl) URL.revokeObjectURL(previewUrl);
    };
  }, [previewUrl]);

  function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (previewUrl) URL.revokeObjectURL(previewUrl);
    if (!file) {
      setPreviewUrl(null);
      setFileName(null);
      return;
    }
    setPreviewUrl(URL.createObjectURL(file));
    setFileName(file.name);
  }

  function clearFile() {
    if (previewUrl) URL.revokeObjectURL(previewUrl);
    setPreviewUrl(null);
    setFileName(null);
    if (fileInputRef.current) fileInputRef.current.value = "";
  }

  return (
    <div className="space-y-3 rounded-xl border border-lt-border-light bg-lt-surface-muted/40 p-3">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
        <div className="flex h-24 w-24 shrink-0 items-center justify-center overflow-hidden rounded-xl border border-lt-border-light bg-white p-2">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={previewUrl ?? "/images/placeholders/producto.svg"}
            alt="Vista previa del producto"
            className="max-h-full max-w-full object-contain"
          />
        </div>
        <div className="min-w-0 flex-1 space-y-2">
          <input
            ref={fileInputRef}
            type="file"
            name="imagen_file"
            accept="image/webp,image/jpeg,image/png"
            className="hidden"
            onChange={handleFileChange}
          />
          <div className="flex flex-wrap items-center gap-2">
            <Button
              type="button"
              variant="secondary"
              onClick={() => fileInputRef.current?.click()}
            >
              {fileName ? "📷 Cambiar foto" : "📷 Subir foto desde dispositivo"}
            </Button>
            {fileName ? (
              <button
                type="button"
                onClick={clearFile}
                className="text-xs text-lt-red hover:underline"
              >
                Quitar ({fileName})
              </button>
            ) : null}
          </div>
          <p className="text-xs text-lt-text-muted">
            WebP, JPG o PNG (máx. 5 MB). Se subirá automáticamente al Storage de tu empresa al guardar.
          </p>
        </div>
      </div>

      {!fileName ? (
        <Input
          label="O especificar ruta / URL manual (opcional)"
          name="imagen_path"
          placeholder="/productos/zulia.webp"
          value={manualPath}
          onChange={(e) => setManualPath(e.target.value)}
        />
      ) : (
        <input type="hidden" name="imagen_path" value="" />
      )}
    </div>
  );
}
