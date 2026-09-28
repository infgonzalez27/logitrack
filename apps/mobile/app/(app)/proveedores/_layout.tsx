import { Stack } from "expo-router";
import {
  appHeaderScreenOptions,
  stackChildOptions,
  stackIndexOptions,
} from "@/components/nav-header";

export default function ProveedoresLayout() {
  return (
    <Stack screenOptions={appHeaderScreenOptions}>
      <Stack.Screen name="index" options={stackIndexOptions("Proveedores")} />
      <Stack.Screen
        name="nuevo"
        options={stackChildOptions("Nuevo proveedor")}
      />
      <Stack.Screen
        name="[id]"
        options={stackChildOptions("Editar proveedor")}
      />
    </Stack>
  );
}
