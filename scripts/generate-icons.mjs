import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";
import toIco from "to-ico";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, "..");
const source = path.join(root, "assets", "favico.jpg");

const out = {
  favicon: path.join(root, "src", "app", "favicon.ico"),
  apple: path.join(root, "src", "app", "apple-icon.png"),
  icon192: path.join(root, "public", "icons", "icon-192.png"),
  icon512: path.join(root, "public", "icons", "icon-512.png"),
};

fs.mkdirSync(path.dirname(out.icon192), { recursive: true });

const icoSizes = [16, 32, 48, 64, 128, 256];
const icoBuffers = await Promise.all(
  icoSizes.map((size) =>
    sharp(source).resize(size, size, { fit: "cover" }).png().toBuffer(),
  ),
);

const ico = await toIco(icoBuffers);
fs.writeFileSync(out.favicon, ico);

await sharp(source).resize(180, 180, { fit: "cover" }).png().toFile(out.apple);
await sharp(source).resize(192, 192, { fit: "cover" }).png().toFile(out.icon192);
await sharp(source).resize(512, 512, { fit: "cover" }).png().toFile(out.icon512);

console.log("Generated:");
console.log(" -", path.relative(root, out.favicon));
console.log(" -", path.relative(root, out.apple));
console.log(" -", path.relative(root, out.icon192));
console.log(" -", path.relative(root, out.icon512));
