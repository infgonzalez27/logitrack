import https from "node:https";

export type BcvTasaResult = {
  tasa: number;
  fecha_tasa: string;
  fuente: "bcv.org.ve";
  raw?: string;
};

function todayIsoDate(): string {
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

function parseEsNumber(value: string): number | null {
  const cleaned = value
    .replace(/\s/g, "")
    .replace(/\./g, "")
    .replace(",", ".");
  const n = Number(cleaned);
  return Number.isFinite(n) && n > 0 ? n : null;
}

function fetchBcvHtml(url: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const req = https.get(
      url,
      {
        rejectUnauthorized: false,
        headers: {
          "User-Agent":
            "Mozilla/5.0 (compatible; LogiTrack/1.0; +https://logitrack.informaticagonzalez.com)",
          Accept: "text/html,application/xhtml+xml",
        },
        timeout: 20000,
      },
      (res) => {
        if (
          res.statusCode &&
          res.statusCode >= 300 &&
          res.statusCode < 400 &&
          res.headers.location
        ) {
          res.resume();
          fetchBcvHtml(res.headers.location).then(resolve, reject);
          return;
        }
        if (!res.statusCode || res.statusCode >= 400) {
          res.resume();
          reject(new Error(`BCV respondió HTTP ${res.statusCode ?? "?"}`));
          return;
        }
        const chunks: Buffer[] = [];
        res.on("data", (chunk: Buffer) => chunks.push(chunk));
        res.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
      },
    );
    req.on("error", reject);
    req.on("timeout", () => {
      req.destroy();
      reject(new Error("Timeout al consultar BCV"));
    });
  });
}

/**
 * Obtiene la tasa USD de referencia desde https://www.bcv.org.ve/
 * (contingencia si no hay tasa del día; el usuario puede registrar a mano).
 */
export async function scrapeTasaUsdBcv(): Promise<
  | { ok: true; data: BcvTasaResult }
  | { ok: false; error: string }
> {
  try {
    const html = await fetchBcvHtml("https://www.bcv.org.ve/");

    const dolarBlock =
      html.match(
        /id=["']dolar["'][^>]*>[\s\S]*?<strong[^>]*>\s*([\d.,]+)\s*<\/strong>/i,
      ) ??
      html.match(
        /USD[\s\S]{0,200}?<strong[^>]*>\s*([\d.,]+)\s*<\/strong>/i,
      );

    if (!dolarBlock?.[1]) {
      return {
        ok: false,
        error:
          "No se pudo leer la tasa USD en BCV (cambió el HTML). Regístrala manualmente.",
      };
    }

    const tasa = parseEsNumber(dolarBlock[1]);
    if (tasa == null) {
      return {
        ok: false,
        error: `Valor de tasa inválido en BCV: "${dolarBlock[1]}".`,
      };
    }

    return {
      ok: true,
      data: {
        tasa,
        fecha_tasa: todayIsoDate(),
        fuente: "bcv.org.ve",
        raw: dolarBlock[1],
      },
    };
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Error de red al consultar BCV.";
    return {
      ok: false,
      error: `${message}. Registra la tasa manualmente.`,
    };
  }
}
