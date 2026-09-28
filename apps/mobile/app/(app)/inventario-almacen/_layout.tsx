import { Stack } from "expo-router";
import {
  appHeaderScreenOptions,
  stackChildOptions,
  stackIndexOptions,
} from "@/components/nav-header";

export default function InventarioAlmacenLayout() {
  return (
    <Stack screenOptions={appHeaderScreenOptions}>
      <Stack.Screen
        name="index"
        options={stackIndexOptions("Inventario almacén")}
      />
      <Stack.Screen
        name="nuevo"
        options={stackChildOptions("Registrar stock")}
      />
    </Stack>
  );
}
