import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { Appearance, useColorScheme } from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";
import {
  createTheme,
  type AppTheme,
  type ColorSchemeName,
} from "./tokens";

const STORAGE_KEY = "logitrack.theme.preference";

export type ThemePreference = "system" | ColorSchemeName;

interface ThemeContextValue {
  theme: AppTheme;
  preference: ThemePreference;
  setPreference: (value: ThemePreference) => void;
  toggleScheme: () => void;
}

const ThemeContext = createContext<ThemeContextValue | null>(null);

interface ThemeProviderProps {
  children: ReactNode;
}

export const ThemeProvider: React.FC<ThemeProviderProps> = ({ children }) => {
  const system = useColorScheme();
  const [preference, setPreferenceState] = useState<ThemePreference>("system");

  useEffect(() => {
    void (async () => {
      try {
        const saved = await AsyncStorage.getItem(STORAGE_KEY);
        if (saved === "light" || saved === "dark" || saved === "system") {
          setPreferenceState(saved);
        }
      } catch {
        // ignore storage errors; keep system default
      }
    })();
  }, []);

  const setPreference = useCallback((value: ThemePreference) => {
    setPreferenceState(value);
    void AsyncStorage.setItem(STORAGE_KEY, value);
  }, []);

  const resolved: ColorSchemeName =
    preference === "system"
      ? system === "dark"
        ? "dark"
        : "light"
      : preference;

  const theme = useMemo(() => createTheme(resolved), [resolved]);

  const toggleScheme = useCallback(() => {
    setPreference(resolved === "dark" ? "light" : "dark");
  }, [resolved, setPreference]);

  useEffect(() => {
    const sub = Appearance.addChangeListener(() => {
      // Re-render via useColorScheme; no-op storage.
    });
    return () => sub.remove();
  }, []);

  const value = useMemo(
    () => ({ theme, preference, setPreference, toggleScheme }),
    [theme, preference, setPreference, toggleScheme],
  );

  return (
    <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>
  );
};

export function useTheme(): ThemeContextValue {
  const ctx = useContext(ThemeContext);
  if (!ctx) {
    throw new Error("useTheme must be used within ThemeProvider");
  }
  return ctx;
}
