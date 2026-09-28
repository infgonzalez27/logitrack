import { Stack } from "expo-router";
import {
  appHeaderScreenOptions,
  stackChildOptions,
  stackIndexOptions,
} from "@/components/nav-header";

export default function FacturasComprasLayout() {
  return (
    <Stack screenOptions={appHeaderScreenOptions}>
      <Stack.Screen
        name="index"
        options={stackIndexOptions("Facturas de compra")}
      />
      <Stack.Screen
        name="nuevo"
        options={stackChildOptions("Nueva factura")}
      />
    </Stack>
  );
}
