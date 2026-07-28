/** Package real en Play Store RawBT. */
export const RAWBT_PACKAGE = "ru.a402d.rawbtprinter";
export const RAWBT_PLAY =
  "https://play.google.com/store/apps/details?id=ru.a402d.rawbtprinter";

export type RawBtPrintMode =
  | "intent-text"
  | "rawbt-scheme"
  | "escpos-base64";

export type RawBtPrintLog = {
  at: string;
  mode: RawBtPrintMode;
  chars: number;
  intentLength: number;
  intentPreview: string;
  ok: boolean;
  error?: string;
};

function triggerUrl(url: string) {
  // iframe evita perder la página en algunos WebViews/PWA
  const iframe = document.createElement("iframe");
  iframe.style.display = "none";
  iframe.src = url;
  document.body.appendChild(iframe);
  window.setTimeout(() => {
    iframe.remove();
  }, 2000);
  // fallback por si el iframe es bloqueado
  window.setTimeout(() => {
    window.location.href = url;
  }, 300);
}

/** ESC @ init + texto ASCII + avance de líneas (ESC d). */
function buildEscPosBytes(texto: string): Uint8Array {
  const ESC = 0x1b;
  const parts: number[] = [ESC, 0x40]; // initialize
  for (let i = 0; i < texto.length; i++) {
    const code = texto.charCodeAt(i);
    parts.push(code <= 0xff ? code : 0x3f); // ? si no es latin1
  }
  parts.push(0x0a, 0x0a, 0x0a);
  parts.push(ESC, 0x64, 0x08); // feed 8 lines
  return Uint8Array.from(parts);
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]!);
  }
  return btoa(binary);
}

/**
 * Envía a RawBT con distintos modos (para depurar SAT AF330).
 * Demo oficial RawBT usa encodeURI (no encodeURIComponent) + intent.
 */
export function printViaRawBt(
  textoRecibo: string,
  mode: RawBtPrintMode = "intent-text",
): RawBtPrintLog {
  const body = textoRecibo.trimEnd() + "\n\n\n";
  let url = "";

  if (mode === "intent-text") {
    // Demo RawBT: encodeURI + intent
    const encoded = encodeURI(body);
    url =
      "intent:" +
      encoded +
      "#Intent;scheme=rawbt;package=" +
      RAWBT_PACKAGE +
      ";end;";
  } else if (mode === "rawbt-scheme") {
    url = "rawbt:" + encodeURI(body);
  } else {
    const b64 = bytesToBase64(buildEscPosBytes(body));
    url =
      "intent:base64," +
      b64 +
      "#Intent;scheme=rawbt;package=" +
      RAWBT_PACKAGE +
      ";end;";
  }

  const log: RawBtPrintLog = {
    at: new Date().toISOString(),
    mode,
    chars: body.length,
    intentLength: url.length,
    intentPreview: url.slice(0, 200) + (url.length > 200 ? "…" : ""),
    ok: true,
  };

  try {
    console.info("[LogiTrack RawBT] print", {
      mode: log.mode,
      chars: log.chars,
      intentLength: log.intentLength,
      sample: body.slice(0, 120),
    });
    triggerUrl(url);
  } catch (err) {
    log.ok = false;
    log.error = err instanceof Error ? err.message : String(err);
    console.error("[LogiTrack RawBT] error", log.error);
  }

  return log;
}

/** Ticket mínimo para validar conexión SAT AF330 + RawBT. */
export function buildPruebaImpresionTicket(): string {
  let recibo = "   LOGITRACK - PRUEBA   \n";
  recibo += "---------------------\n";
  recibo += "Impresora SAT AF330\n";
  recibo += "Prueba RawBT OK\n";
  recibo += "---------------------\n";
  recibo += "Producto A      $10.00\n";
  recibo += "Producto B      $15.00\n";
  recibo += "---------------------\n";
  recibo += "TOTAL:          $25.00\n";
  return recibo;
}
