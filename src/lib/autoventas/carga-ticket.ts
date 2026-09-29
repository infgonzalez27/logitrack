export type CargaTicketLinea = {
  codigo: string;
  producto: string;
  cantidad: number;
};

export type CargaTicketData = {
  camion: string;
  fecha: string;
  lineas: CargaTicketLinea[];
};

/** Codifica el comprobante para pasarlo en la URL de impresión (base64url). */
export function encodeCargaTicket(data: CargaTicketData): string {
  const bytes = new TextEncoder().encode(JSON.stringify(data));
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function decodeCargaTicket(raw: string | undefined): CargaTicketData | null {
  if (!raw?.trim()) return null;
  try {
    const parsed = JSON.parse(
      Buffer.from(raw, "base64url").toString("utf8"),
    ) as Partial<CargaTicketData>;
    if (!Array.isArray(parsed.lineas)) return null;
    return {
      camion: String(parsed.camion ?? "—"),
      fecha: String(parsed.fecha ?? ""),
      lineas: parsed.lineas.map((l) => ({
        codigo: String(l?.codigo ?? ""),
        producto: String(l?.producto ?? ""),
        cantidad: Number(l?.cantidad) || 0,
      })),
    };
  } catch {
    return null;
  }
}
