"use client";

import { useEffect, useState } from "react";
import { storagePublicUrl } from "@/lib/storage-url";
import { useStorageBaseUrl } from "@/components/media/storage-context";

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
  const storageBaseUrl = useStorageBaseUrl();
  const placeholder = fallbackSrc || FALLBACK[type];
  const initial = storagePublicUrl(path, storageBaseUrl) ?? placeholder;
  const [src, setSrc] = useState(initial);

  useEffect(() => {
    setSrc(initial);
  }, [initial]);

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
