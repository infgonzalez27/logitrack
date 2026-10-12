import sharp from "sharp";
import fs from "fs";

async function generateRaster(imagePath, targetWidth, targetHeight, canvasWidth) {
  const { data, info } = await sharp(imagePath)
    .resize(targetWidth, targetHeight, {
      fit: "contain",
      background: { r: 255, g: 255, b: 255, alpha: 1 },
    })
    .toColorspace("b-w")
    .threshold(140)
    .raw()
    .toBuffer({ resolveWithObject: true });

  const w = info.width;
  const h = info.height;
  const bytesPerRow = canvasWidth / 8;
  const xOffset = Math.floor((canvasWidth - w) / 2);

  const fullCanvas = new Uint8Array(bytesPerRow * h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const pixel = data[y * w + x];
      if (pixel < 128) {
        const cx = xOffset + x;
        const byteIdx = y * bytesPerRow + (cx >> 3);
        const bitIdx = 7 - (cx & 7);
        fullCanvas[byteIdx] |= (1 << bitIdx);
      }
    }
  }

  const chunkHeight = 32;
  const chunks = [];
  for (let y = 0; y < h; y += chunkHeight) {
    const currentH = Math.min(chunkHeight, h - y);
    const stripeData = fullCanvas.slice(y * bytesPerRow, (y + currentH) * bytesPerRow);
    const cmd = new Uint8Array(8 + stripeData.length);
    cmd.set([
      0x1d,
      0x76,
      0x30,
      0x00,
      bytesPerRow & 0xff,
      bytesPerRow >> 8,
      currentH & 0xff,
      currentH >> 8,
    ]);
    cmd.set(stripeData, 8);
    chunks.push(Buffer.from(cmd).toString("base64"));
  }
  return chunks;
}

async function main() {
  const ramirez58 = await generateRaster("apps/mobile/assets/logos/ramirez.png", 240, 160, 384);
  const ramirez80 = await generateRaster("apps/mobile/assets/logos/ramirez.png", 320, 210, 576);

  const berraco58 = await generateRaster("apps/mobile/assets/logos/berraco.png", 240, 160, 384);
  const berraco80 = await generateRaster("apps/mobile/assets/logos/berraco.png", 320, 210, 576);

  const code = `import type { AnchoPapel } from "./escpos-raster";

/** Logos pre-renderizados a mapas de bits ESC/POS (GS v 0) para Bluetooth térmico */
const RASTER_DATA: Record<string, Record<AnchoPapel, string[]>> = {
  ramirez: {
    58: ${JSON.stringify(ramirez58, null, 2)},
    80: ${JSON.stringify(ramirez80, null, 2)},
  },
  berraco: {
    58: ${JSON.stringify(berraco58, null, 2)},
    80: ${JSON.stringify(berraco80, null, 2)},
  },
};

function base64ToUint8Array(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

/** Devuelve los bloques ESC/POS raster listos para enviar por Bluetooth */
export function getEmpresaLogoRasterChunks(
  codigoEmpresa: string | null | undefined,
  ancho: AnchoPapel,
): Uint8Array[] {
  if (!codigoEmpresa) return [];
  const code = codigoEmpresa.trim().toLowerCase().replace(/^lt_/, "");
  const data = RASTER_DATA[code]?.[ancho];
  if (!data || !data.length) return [];
  return data.map(base64ToUint8Array);
}

/** Imágenes requeridas para la vista previa en pantalla de la app móvil */
export const EMPRESAS_LOGOS_MOBILE: Record<string, any> = {
  ramirez: require("@/assets/logos/ramirez.png"),
  berraco: require("@/assets/logos/berraco.png"),
};

export function getEmpresaLogoSource(codigoEmpresa?: string | null): any | null {
  if (!codigoEmpresa) return null;
  const code = codigoEmpresa.trim().toLowerCase().replace(/^lt_/, "");
  return EMPRESAS_LOGOS_MOBILE[code] ?? null;
}
`;

  fs.writeFileSync("apps/mobile/lib/logos-raster.ts", code, "utf8");
  console.log("logos-raster.ts generated successfully");
}

main().catch(console.error);
