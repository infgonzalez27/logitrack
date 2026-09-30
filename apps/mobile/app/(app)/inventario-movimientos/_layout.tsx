import { Stack } from "expo-router";
import {
  appHeaderScreenOptions,
  stackChildOptions,
  stackIndexOptions,
} from "@/components/nav-header";

export default function MovimientosInventarioLayout() {
  return (
    <Stack screenOptions={appHeaderScreenOptions}>
      <Stack.Screen
        name="index"
        options={stackIndexOptions("Movimientos especiales")}
      />
      <Stack.Screen
        name="nuevo"
        options={stackChildOptions("Nuevo movimiento")}
      />
    </Stack>
  );
}
