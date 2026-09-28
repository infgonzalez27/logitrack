import { Stack } from "expo-router";
import {
  appHeaderScreenOptions,
  stackChildOptions,
  stackIndexOptions,
} from "@/components/nav-header";

export default function RendicionesLayout() {
  return (
    <Stack screenOptions={appHeaderScreenOptions}>
      <Stack.Screen name="index" options={stackIndexOptions("Cobranzas")} />
      <Stack.Screen
        name="nueva"
        options={stackChildOptions("Nueva cobranza")}
      />
      <Stack.Screen name="[id]" options={stackChildOptions("Detalle")} />
      <Stack.Screen
        name="por-liquidar"
        options={stackChildOptions("Órdenes por liquidar")}
      />
      <Stack.Screen
        name="formas-pago"
        options={stackChildOptions("Formas de pago")}
      />
    </Stack>
  );
}
