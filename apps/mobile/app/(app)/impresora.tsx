import { useCallback, useState } from "react";
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { useFocusEffect } from "expo-router";
import {
  clearPreferredPrinterMac,
  getPreferredPrinterMac,
  getPrinterConfig,
  listBondedPrinters,
  printTextToBluetooth,
  setPreferredPrinterMac,
  setPrinterConfig,
  type BondedDevice,
  type PrinterConfig,
} from "@/lib/bluetooth-print";
import { toThermalText } from "@/lib/ticket";

const TEST_TICKET = toThermalText(
  [
    "LogiTrack",
    "PRUEBA DE IMPRESORA",
    "--------------------------------",
    "Si lees esto, la impresora",
    "funciona con LogiTrack.",
    "CODIGO  PRODUCTO        CARGADO",
    "0001    Producto demo         12",
    "--------------------------------",
    "*** Fin ***",
  ].join("\n") + "\n\n\n",
);

function Opcion({
  label,
  activo,
  onPress,
}: {
  label: string;
  activo: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      onPress={onPress}
      style={[styles.chip, activo && styles.chipActivo]}
    >
      <Text style={[styles.chipText, activo && styles.chipTextActivo]}>
        {label}
      </Text>
    </Pressable>
  );
}

export default function ImpresoraScreen() {
  const [devices, setDevices] = useState<BondedDevice[]>([]);
  const [preferred, setPreferred] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [configs, setConfigs] = useState<Record<string, PrinterConfig>>({});

  async function cambiarConfig(address: string, cambio: Partial<PrinterConfig>) {
    const actual = configs[address] ?? (await getPrinterConfig(address));
    const nueva = { ...actual, ...cambio };
    setConfigs((prev) => ({ ...prev, [address]: nueva }));
    await setPrinterConfig(address, nueva);
  }

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    setMessage(null);
    const mac = await getPreferredPrinterMac();
    setPreferred(mac);
    const result = await listBondedPrinters();
    setLoading(false);
    if (!result.ok) {
      setError(result.error);
      setDevices([]);
      return;
    }
    setDevices(result.devices);
    const entradas = await Promise.all(
      result.devices.map(
        async (d) => [d.address, await getPrinterConfig(d.address)] as const,
      ),
    );
    setConfigs(Object.fromEntries(entradas));
  }, []);

  useFocusEffect(
    useCallback(() => {
      void load();
    }, [load]),
  );

  async function selectDevice(address: string) {
    await setPreferredPrinterMac(address);
    setPreferred(address);
    setMessage(`Impresora guardada: ${address}`);
  }

  async function testPrint(address: string) {
    setBusy(true);
    setError(null);
    setMessage(null);
    const result = await printTextToBluetooth(address, TEST_TICKET);
    setBusy(false);
    if (!result.ok) {
      setError(result.error);
      return;
    }
    setMessage("Prueba enviada. Revisa el papel de la térmica.");
  }

  return (
    <ScrollView style={styles.root} contentContainerStyle={{ padding: 16 }}>
      <Text style={styles.title}>Impresora Bluetooth</Text>
      <Text style={styles.help}>
        Empareja la térmica en Ajustes del teléfono, luego elígela aquí. Se
        requiere APK nativa (no Expo Go) para Bluetooth Classic.
      </Text>

      <Pressable style={styles.btn} onPress={() => void load()}>
        <Text style={styles.btnText}>Actualizar lista</Text>
      </Pressable>

      {preferred ? (
        <View style={styles.pref}>
          <Text style={styles.prefLabel}>Preferida</Text>
          <Text style={styles.prefValue}>{preferred}</Text>
          <Pressable
            onPress={() =>
              void clearPreferredPrinterMac().then(() => setPreferred(null))
            }
          >
            <Text style={styles.clear}>Quitar preferida</Text>
          </Pressable>
        </View>
      ) : null}

      {loading ? (
        <ActivityIndicator color="#0B3A5C" style={{ marginTop: 20 }} />
      ) : null}
      {error ? <Text style={styles.error}>{error}</Text> : null}
      {message ? <Text style={styles.ok}>{message}</Text> : null}

      {devices.map((d) => {
        const cfg = configs[d.address] ?? { modo: "texto", ancho: 58 };
        return (
        <View key={d.address} style={styles.card}>
          <Text style={styles.name}>{d.name}</Text>
          <Text style={styles.mac}>{d.address}</Text>
          <Text style={styles.optLabel}>Modo de impresión</Text>
          <View style={styles.chips}>
            <Opcion
              label="Texto"
              activo={cfg.modo === "texto"}
              onPress={() => void cambiarConfig(d.address, { modo: "texto" })}
            />
            <Opcion
              label="Imagen"
              activo={cfg.modo === "imagen"}
              onPress={() => void cambiarConfig(d.address, { modo: "imagen" })}
            />
          </View>
          {cfg.modo === "imagen" ? (
            <>
              <Text style={styles.optLabel}>Ancho del papel</Text>
              <View style={styles.chips}>
                <Opcion
                  label="58 mm"
                  activo={cfg.ancho === 58}
                  onPress={() => void cambiarConfig(d.address, { ancho: 58 })}
                />
                <Opcion
                  label="80 mm"
                  activo={cfg.ancho === 80}
                  onPress={() => void cambiarConfig(d.address, { ancho: 80 })}
                />
              </View>
            </>
          ) : null}
          <Text style={styles.optHint}>
            Si el papel avanza pero sale en blanco, usa «Imagen».
          </Text>
          <View style={styles.row}>
            <Pressable
              style={styles.smallBtn}
              onPress={() => void selectDevice(d.address)}
            >
              <Text style={styles.smallBtnText}>Usar</Text>
            </Pressable>
            <Pressable
              style={[styles.smallBtn, styles.smallBtnAlt]}
              disabled={busy}
              onPress={() => void testPrint(d.address)}
            >
              <Text style={styles.smallBtnText}>{busy ? "…" : "Probar"}</Text>
            </Pressable>
          </View>
        </View>
        );
      })}

      {!loading && !devices.length && !error ? (
        <Text style={styles.empty}>
          No hay dispositivos emparejados. Ve a Ajustes → Bluetooth y empareja
          la impresora.
        </Text>
      ) : null}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#F4F6F8" },
  title: { fontSize: 22, fontWeight: "700", color: "#0B3A5C" },
  help: { color: "#5B6B7C", marginTop: 8, marginBottom: 16, lineHeight: 20 },
  btn: {
    backgroundColor: "#0B3A5C",
    borderRadius: 12,
    paddingVertical: 12,
    alignItems: "center",
  },
  btnText: { color: "#fff", fontWeight: "600" },
  pref: {
    marginTop: 16,
    backgroundColor: "#E8F1F8",
    borderRadius: 12,
    padding: 12,
  },
  prefLabel: { fontSize: 12, color: "#5B6B7C" },
  prefValue: { fontWeight: "700", marginTop: 4, color: "#0B3A5C" },
  clear: { color: "#B42318", marginTop: 8, fontWeight: "600" },
  error: { color: "#B42318", marginTop: 12 },
  ok: { color: "#027A48", marginTop: 12 },
  card: {
    marginTop: 12,
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    borderWidth: 1,
    borderColor: "#E5EAF0",
  },
  name: { fontWeight: "700", fontSize: 16, color: "#0B3A5C" },
  mac: { color: "#5B6B7C", marginTop: 4 },
  row: { flexDirection: "row", gap: 8, marginTop: 12 },
  optLabel: { fontSize: 12, color: "#5B6B7C", marginTop: 12 },
  optHint: { fontSize: 12, color: "#5B6B7C", marginTop: 8 },
  chips: { flexDirection: "row", gap: 8, marginTop: 6 },
  chip: {
    borderWidth: 1,
    borderColor: "#C8D3DE",
    borderRadius: 999,
    paddingVertical: 6,
    paddingHorizontal: 14,
    backgroundColor: "#fff",
  },
  chipActivo: { backgroundColor: "#0B3A5C", borderColor: "#0B3A5C" },
  chipText: { color: "#0B3A5C", fontWeight: "600" },
  chipTextActivo: { color: "#fff" },
  smallBtn: {
    backgroundColor: "#0B3A5C",
    borderRadius: 10,
    paddingVertical: 10,
    paddingHorizontal: 16,
  },
  smallBtnAlt: { backgroundColor: "#1F6B4A" },
  smallBtnText: { color: "#fff", fontWeight: "600" },
  empty: { marginTop: 24, color: "#5B6B7C", textAlign: "center" },
});
