import AsyncStorage from "@react-native-async-storage/async-storage";
import { PermissionsAndroid, Platform } from "react-native";
import { buildEscPosBytes, toThermalText } from "./ticket";
import { buildRasterEscPosChunks, type AnchoPapel } from "./escpos-raster";

const PRINTER_KEY = "logitrack.print.preferred_mac";
const CONFIG_KEY_PREFIX = "logitrack.print.config.";

/**
 * `texto`: ESC/POS con la fuente de la impresora.
 * `imagen`: el ticket se envía como mapa de bits (GS v 0), para impresoras
 * que avanzan papel pero no dibujan el texto.
 */
export type ModoImpresion = "texto" | "imagen";

export type PrinterConfig = { modo: ModoImpresion; ancho: AnchoPapel };

const CONFIG_DEFAULT: PrinterConfig = { modo: "texto", ancho: 58 };

export type BondedDevice = {
  address: string;
  name: string;
};

type BluetoothClassicModule = {
  isBluetoothEnabled: () => Promise<boolean>;
  requestBluetoothEnabled?: () => Promise<boolean>;
  getBondedDevices: () => Promise<Array<{ address: string; name?: string }>>;
  connectToDevice: (
    address: string,
  ) => Promise<{
    write: (data: string, encoding?: string) => Promise<boolean>;
    disconnect: () => Promise<boolean>;
  }>;
};

function getBluetoothModule(): BluetoothClassicModule | null {
  if (Platform.OS !== "android") return null;
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const mod = require("react-native-bluetooth-classic");
    return (mod.default ?? mod) as BluetoothClassicModule;
  } catch {
    return null;
  }
}

export function isBluetoothNativeAvailable(): boolean {
  return getBluetoothModule() != null;
}

/**
 * Android 12+ (API 31) exige BLUETOOTH_CONNECT / SCAN en runtime.
 * Sin esto, getBondedDevices() lanza HostFunction / SecurityException.
 */
export async function ensureBluetoothPermissions(): Promise<
  { ok: true } | { ok: false; error: string }
> {
  if (Platform.OS !== "android") return { ok: true };

  const api =
    typeof Platform.Version === "number"
      ? Platform.Version
      : Number.parseInt(String(Platform.Version), 10);

  if (!Number.isFinite(api) || api < 31) {
    return { ok: true };
  }

  try {
    const needed = [PermissionsAndroid.PERMISSIONS.BLUETOOTH_CONNECT].filter(
      Boolean,
    );

    const already = await Promise.all(
      needed.map((p) => PermissionsAndroid.check(p)),
    );
    if (already.every(Boolean)) return { ok: true };

    const result = await PermissionsAndroid.requestMultiple(needed);
    const denied = needed.filter(
      (p) => result[p] !== PermissionsAndroid.RESULTS.GRANTED,
    );
    if (denied.length) {
      return {
        ok: false,
        error:
          "Se necesita permiso de Bluetooth. Acepta BLUETOOTH_CONNECT en el diálogo o actívalo en Ajustes → Apps → LogiTrack → Permisos.",
      };
    }
    return { ok: true };
  } catch (err) {
    return {
      ok: false,
      error:
        err instanceof Error
          ? err.message
          : "No se pudo solicitar permiso de Bluetooth.",
    };
  }
}

export async function getPreferredPrinterMac(): Promise<string | null> {
  return AsyncStorage.getItem(PRINTER_KEY);
}

export async function setPreferredPrinterMac(mac: string): Promise<void> {
  await AsyncStorage.setItem(PRINTER_KEY, mac);
}

export async function clearPreferredPrinterMac(): Promise<void> {
  await AsyncStorage.removeItem(PRINTER_KEY);
}

export async function getPrinterConfig(mac: string): Promise<PrinterConfig> {
  try {
    const raw = await AsyncStorage.getItem(CONFIG_KEY_PREFIX + mac);
    if (!raw) return CONFIG_DEFAULT;
    const parsed = JSON.parse(raw) as Partial<PrinterConfig>;
    return {
      modo: parsed.modo === "imagen" ? "imagen" : "texto",
      ancho: parsed.ancho === 80 ? 80 : 58,
    };
  } catch {
    return CONFIG_DEFAULT;
  }
}

export async function setPrinterConfig(
  mac: string,
  config: PrinterConfig,
): Promise<void> {
  await AsyncStorage.setItem(CONFIG_KEY_PREFIX + mac, JSON.stringify(config));
}

function toLatin1(bytes: Uint8Array): string {
  let out = "";
  for (let i = 0; i < bytes.length; i++) out += String.fromCharCode(bytes[i]!);
  return out;
}

function esperar(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function listBondedPrinters(): Promise<
  { ok: true; devices: BondedDevice[] } | { ok: false; error: string }
> {
  const bt = getBluetoothModule();
  if (!bt) {
    return {
      ok: false,
      error:
        "Bluetooth nativo no disponible. Compila un development build / APK (no Expo Go).",
    };
  }

  const perms = await ensureBluetoothPermissions();
  if (!perms.ok) return perms;

  try {
    const enabled = await bt.isBluetoothEnabled();
    if (!enabled && bt.requestBluetoothEnabled) {
      await bt.requestBluetoothEnabled();
    }
    const devices = await bt.getBondedDevices();
    return {
      ok: true,
      devices: devices.map((d) => ({
        address: d.address,
        name: d.name?.trim() || d.address,
      })),
    };
  } catch (err) {
    const raw =
      err instanceof Error ? err.message : "No se pudieron listar impresoras.";
    if (/BLUETOOTH_CONNECT|permission/i.test(raw)) {
      return {
        ok: false,
        error:
          "Falta permiso BLUETOOTH_CONNECT. Ve a Ajustes → Apps → LogiTrack → Permisos y activa Bluetooth / Dispositivos cercanos.",
      };
    }
    return { ok: false, error: raw };
  }
}

/** Imprime en la impresora guardada; `sinImpresora` si aún no se configuró. */
export async function printToPreferredPrinter(
  texto: string,
): Promise<
  { ok: true } | { ok: false; error: string; sinImpresora?: boolean }
> {
  const mac = await getPreferredPrinterMac();
  if (!mac) {
    return {
      ok: false,
      sinImpresora: true,
      error: "No hay impresora guardada. Configúrala en Impresora.",
    };
  }
  return printTextToBluetooth(mac, texto);
}

export async function printTextToBluetooth(
  address: string,
  texto: string,
  opts?: { cut?: boolean },
): Promise<{ ok: true } | { ok: false; error: string }> {
  const bt = getBluetoothModule();
  if (!bt) {
    return {
      ok: false,
      error:
        "Bluetooth nativo no disponible. Usa la APK de desarrollo o release.",
    };
  }

  const perms = await ensureBluetoothPermissions();
  if (!perms.ok) return perms;

  try {
    const enabled = await bt.isBluetoothEnabled();
    if (!enabled && bt.requestBluetoothEnabled) {
      await bt.requestBluetoothEnabled();
    }

    const config = await getPrinterConfig(address);
    const connection = await bt.connectToDevice(address);
    // Sin encoding la librería convierte el string a UTF-8 y altera bytes ≥ 0x80.
    if (config.modo === "imagen") {
      const chunks = buildRasterEscPosChunks(toThermalText(texto), {
        ancho: config.ancho,
        cut: opts?.cut,
      });
      for (const chunk of chunks) {
        await connection.write(toLatin1(chunk), "latin1");
        await esperar(25);
      }
    } else {
      await connection.write(toLatin1(buildEscPosBytes(texto, opts)), "latin1");
    }
    // Cerrar el socket enseguida puede descartar lo que aún no salió por RFCOMM.
    await esperar(config.modo === "imagen" ? 1500 : 800);
    try {
      await connection.disconnect();
    } catch {
      /* ignore */
    }
    await setPreferredPrinterMac(address);
    return { ok: true };
  } catch (err) {
    const raw =
      err instanceof Error
        ? err.message
        : "Fallo al imprimir. Revisa que la impresora esté encendida y emparejada.";
    if (/BLUETOOTH_CONNECT|permission/i.test(raw)) {
      return {
        ok: false,
        error:
          "Falta permiso BLUETOOTH_CONNECT. Actívalo en Ajustes → Apps → LogiTrack → Permisos.",
      };
    }
    return { ok: false, error: raw };
  }
}
