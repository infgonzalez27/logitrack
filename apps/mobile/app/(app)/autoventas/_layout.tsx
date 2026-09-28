import { Stack } from "expo-router";
import {
  appHeaderScreenOptions,
  stackChildOptions,
  stackIndexOptions,
} from "@/components/nav-header";

export default function AutoventasLayout() {
  return (
    <Stack screenOptions={appHeaderScreenOptions}>
      <Stack.Screen name="index" options={stackIndexOptions("AutoVentas")} />
      <Stack.Screen name="nueva" options={stackChildOptions("Venta en ruta")} />
    </Stack>
  );
}
