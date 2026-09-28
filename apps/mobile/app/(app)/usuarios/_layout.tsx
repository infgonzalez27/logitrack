import { Stack } from "expo-router";
import {
  appHeaderScreenOptions,
  stackChildOptions,
  stackIndexOptions,
} from "@/components/nav-header";

export default function UsuariosLayout() {
  return (
    <Stack screenOptions={appHeaderScreenOptions}>
      <Stack.Screen name="index" options={stackIndexOptions("Usuarios")} />
      <Stack.Screen
        name="[id]"
        options={stackChildOptions("Editar usuario")}
      />
      <Stack.Screen
        name="registrar"
        options={stackChildOptions("Registrar usuario")}
      />
    </Stack>
  );
}
