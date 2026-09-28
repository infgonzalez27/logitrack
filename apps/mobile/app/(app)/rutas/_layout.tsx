import { Stack } from "expo-router";
import {
  appHeaderScreenOptions,
  stackChildOptions,
  stackIndexOptions,
} from "@/components/nav-header";

export default function RutasLayout() {
  return (
    <Stack screenOptions={appHeaderScreenOptions}>
      <Stack.Screen name="index" options={stackIndexOptions("Rutas")} />
      <Stack.Screen name="nuevo" options={stackChildOptions("Nueva ruta")} />
      <Stack.Screen name="[id]" options={stackChildOptions("Editar ruta")} />
    </Stack>
  );
}
