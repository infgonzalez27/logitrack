import { Stack } from "expo-router";
import {
  appHeaderScreenOptions,
  stackChildOptions,
  stackIndexOptions,
} from "@/components/nav-header";

export default function ClientesLayout() {
  return (
    <Stack screenOptions={appHeaderScreenOptions}>
      <Stack.Screen name="index" options={stackIndexOptions("Clientes")} />
      <Stack.Screen name="nuevo" options={stackChildOptions("Nuevo cliente")} />
      <Stack.Screen name="[id]/index" options={stackChildOptions("Visita")} />
      <Stack.Screen
        name="[id]/editar"
        options={stackChildOptions("Editar cliente")}
      />
    </Stack>
  );
}
