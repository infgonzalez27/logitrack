import AsyncStorage from "@react-native-async-storage/async-storage";

export type LogLevel = "log" | "info" | "warn" | "error";

export type LogEntry = {
  id: string;
  timestamp: string;
  level: LogLevel;
  message: string;
  details?: string;
};

const MAX_LOGS = 120;
const STORAGE_KEY_LAST_CRASH = "@logitrack:last_crash";
const inMemoryLogs: LogEntry[] = [];
let listeners: Array<() => void> = [];

export function addLog(level: LogLevel, message: string, details?: unknown) {
  const entry: LogEntry = {
    id: `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
    timestamp: new Date().toLocaleTimeString("es-VE", { hour12: false }),
    level,
    message: typeof message === "string" ? message : JSON.stringify(message),
    details: details
      ? typeof details === "string"
        ? details
        : JSON.stringify(details, null, 2)
      : undefined,
  };
  inMemoryLogs.unshift(entry);
  if (inMemoryLogs.length > MAX_LOGS) {
    inMemoryLogs.pop();
  }
  listeners.forEach((l) => {
    try {
      l();
    } catch {}
  });
}

export function subscribeLogs(fn: () => void): () => void {
  listeners.push(fn);
  return () => {
    listeners = listeners.filter((l) => l !== fn);
  };
}

export function getLogs(): LogEntry[] {
  return [...inMemoryLogs];
}

export function clearLogs() {
  inMemoryLogs.length = 0;
  listeners.forEach((l) => {
    try {
      l();
    } catch {}
  });
}

export async function recordCrash(error: unknown, isFatal = false) {
  const errObj = error instanceof Error ? error : new Error(String(error));
  const crashData = {
    timestamp: new Date().toISOString(),
    isFatal,
    message: errObj.message,
    stack: errObj.stack,
  };
  addLog(
    "error",
    `CRASH [${isFatal ? "FATAL" : "ERROR"}]: ${errObj.message}`,
    errObj.stack,
  );
  try {
    await AsyncStorage.setItem(
      STORAGE_KEY_LAST_CRASH,
      JSON.stringify(crashData),
    );
  } catch {}
}

export async function getLastCrash(): Promise<{
  timestamp: string;
  isFatal: boolean;
  message: string;
  stack?: string;
} | null> {
  try {
    const raw = await AsyncStorage.getItem(STORAGE_KEY_LAST_CRASH);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

let initialized = false;
export function initCrashLogger() {
  if (initialized) return;
  initialized = true;

  const originalLog = console.log.bind(console);
  const originalWarn = console.warn.bind(console);
  const originalError = console.error.bind(console);

  console.log = (...args: unknown[]) => {
    originalLog(...args);
    addLog(
      "log",
      args
        .map((a) => (typeof a === "object" ? JSON.stringify(a) : String(a)))
        .join(" "),
    );
  };

  console.warn = (...args: unknown[]) => {
    originalWarn(...args);
    addLog(
      "warn",
      args
        .map((a) => (typeof a === "object" ? JSON.stringify(a) : String(a)))
        .join(" "),
    );
  };

  console.error = (...args: unknown[]) => {
    originalError(...args);
    addLog(
      "error",
      args
        .map((a) => (typeof a === "object" ? JSON.stringify(a) : String(a)))
        .join(" "),
    );
  };

  // Interceptar errores globales JS no capturados en React Native
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const globalObj = global as any;
  if (globalObj.ErrorUtils?.setGlobalHandler) {
    const defaultHandler = globalObj.ErrorUtils.getGlobalHandler?.();
    globalObj.ErrorUtils.setGlobalHandler(
      async (error: unknown, isFatal?: boolean) => {
        await recordCrash(error, isFatal);
        if (__DEV__ && defaultHandler) {
          defaultHandler(error, isFatal);
        }
      },
    );
  }
}
