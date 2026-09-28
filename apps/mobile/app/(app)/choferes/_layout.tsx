import { Stack } from "expo-router";
import {
  appHeaderScreenOptions,
  stackChildOptions,
  stackIndexOptions,
} from "@/components/nav-header";

export default function ChoferesLayout() {
  return (
    <Stack screenOptions={appHeaderScreenOptions}>
      <Stack.Screen name="index" options={stackIndexOptions("Choferes")} />
      <Stack.Screen name="nuevo" options={stackChildOptions("Nuevo chofer")} />
      <Stack.Screen name="[id]" options={stackChildOptions("Editar chofer")} />
    </Stack>
  );
}
