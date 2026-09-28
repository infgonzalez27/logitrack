import { Stack } from "expo-router";
import {
  appHeaderScreenOptions,
  stackChildOptions,
  stackIndexOptions,
} from "@/components/nav-header";

export default function ProductosLayout() {
  return (
    <Stack screenOptions={appHeaderScreenOptions}>
      <Stack.Screen name="index" options={stackIndexOptions("Productos")} />
      <Stack.Screen
        name="nuevo"
        options={stackChildOptions("Nuevo producto")}
      />
      <Stack.Screen
        name="[id]"
        options={stackChildOptions("Editar producto")}
      />
    </Stack>
  );
}
