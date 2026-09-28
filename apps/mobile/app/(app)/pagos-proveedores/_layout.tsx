import { Stack } from "expo-router";
import {
  appHeaderScreenOptions,
  stackChildOptions,
  stackIndexOptions,
} from "@/components/nav-header";

export default function PagosProveedoresLayout() {
  return (
    <Stack screenOptions={appHeaderScreenOptions}>
      <Stack.Screen
        name="index"
        options={stackIndexOptions("Pagos proveedores")}
      />
      <Stack.Screen name="nuevo" options={stackChildOptions("Nuevo pago")} />
    </Stack>
  );
}
