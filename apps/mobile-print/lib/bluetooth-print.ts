import AsyncStorage from "@react-native-async-storage/async-storage";
import { Platform } from "react-native";
import { buildEscPosBytes, bytesToBase64 } from "./ticket";

const PRINTER_KEY = "logitrack.print.preferred_mac";

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
    write: (data: string) => Promise<boolean>;
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

export async function getPreferredPrinterMac(): Promise<string | null> {
  return AsyncStorage.getItem(PRINTER_KEY);
}

export async function setPreferredPrinterMac(mac: string): Promise<void> {
  await AsyncStorage.setItem(PRINTER_KEY, mac);
}

export async function clearPreferredPrinterMac(): Promise<void> {
  await AsyncStorage.removeItem(PRINTER_KEY);
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
    const message =
      err instanceof Error ? err.message : "No se pudieron listar impresoras.";
    return { ok: false, error: message };
  }
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

  try {
    const enabled = await bt.isBluetoothEnabled();
    if (!enabled && bt.requestBluetoothEnabled) {
      await bt.requestBluetoothEnabled();
    }

    const connection = await bt.connectToDevice(address);
    const bytes = buildEscPosBytes(texto, opts);
    // Muchas libs aceptan base64 con prefijo; otras texto plano.
    // Enviamos latin1 como string de chars 0-255 vía base64 decode en write si hace falta.
    const asLatin1 = Array.from(bytes, (b) => String.fromCharCode(b)).join("");
    try {
      await connection.write(asLatin1);
    } catch {
      await connection.write(bytesToBase64(bytes));
    }
    try {
      await connection.disconnect();
    } catch {
      /* ignore */
    }
    await setPreferredPrinterMac(address);
    return { ok: true };
  } catch (err) {
    const message =
      err instanceof Error
        ? err.message
        : "Fallo al imprimir. Revisa que la impresora esté encendida y emparejada.";
    return { ok: false, error: message };
  }
}
