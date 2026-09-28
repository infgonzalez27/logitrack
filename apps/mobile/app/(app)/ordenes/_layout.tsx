import { Stack } from "expo-router";
import {
  appHeaderScreenOptions,
  stackChildOptions,
  stackIndexOptions,
} from "@/components/nav-header";

export default function OrdenesLayout() {
  return (
    <Stack screenOptions={appHeaderScreenOptions}>
      <Stack.Screen name="index" options={stackIndexOptions("Órdenes")} />
      <Stack.Screen name="[id]" options={stackChildOptions("Detalle")} />
      <Stack.Screen name="nueva" options={stackChildOptions("Nueva orden")} />
      <Stack.Screen
        name="editar/[id]"
        options={stackChildOptions("Editar orden")}
      />
    </Stack>
  );
}
