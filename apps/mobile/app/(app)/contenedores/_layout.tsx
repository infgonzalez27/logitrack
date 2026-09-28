import { Stack } from "expo-router";
import {
  appHeaderScreenOptions,
  stackChildOptions,
  stackIndexOptions,
} from "@/components/nav-header";

export default function ContenedoresLayout() {
  return (
    <Stack screenOptions={appHeaderScreenOptions}>
      <Stack.Screen name="index" options={stackIndexOptions("Contenedores")} />
      <Stack.Screen name="[clienteId]" options={stackChildOptions("Detalle")} />
    </Stack>
  );
}
