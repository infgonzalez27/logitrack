import { Stack } from "expo-router";
import {
  appHeaderScreenOptions,
  stackChildOptions,
  stackIndexOptions,
} from "@/components/nav-header";

export default function CamionesLayout() {
  return (
    <Stack screenOptions={appHeaderScreenOptions}>
      <Stack.Screen name="index" options={stackIndexOptions("Camiones")} />
      <Stack.Screen name="nuevo" options={stackChildOptions("Nuevo camión")} />
      <Stack.Screen name="[id]" options={stackChildOptions("Editar camión")} />
    </Stack>
  );
}
