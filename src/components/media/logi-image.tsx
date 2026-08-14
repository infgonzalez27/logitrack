"use client";

import { useState } from "react";
import { storagePublicUrl } from "@/lib/storage-url";

const FALLBACK = {
  producto: "/images/placeholders/producto.svg",
  usuario: "/images/placeholders/avatar.svg",
} as const;

export function LogiImage({
  path,
  type,
  alt,
  fallbackSrc,
  className = "",
  width,
  height,
}: {
  path?: string | null;
  type: "producto" | "usuario";
  alt: string;
  fallbackSrc?: string | null;
  className?: string;
  width?: number;
  height?: number;
}) {
  const placeholder = fallbackSrc || FALLBACK[type];
  const initial = storagePublicUrl(path) ?? placeholder;
  const [src, setSrc] = useState(initial);

  return (
    // Storage remoto + fallback local: <img> evita config extra de next/image.
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={src}
      alt={alt}
      width={width}
      height={height}
      className={className}
      onError={() => {
        if (src !== placeholder) setSrc(placeholder);
      }}
    />
  );
}
