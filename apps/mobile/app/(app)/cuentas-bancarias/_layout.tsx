import { Stack } from "expo-router";
import {
  appHeaderScreenOptions,
  stackIndexOptions,
} from "@/components/nav-header";

export default function CuentasBancariasLayout() {
  return (
    <Stack screenOptions={appHeaderScreenOptions}>
      <Stack.Screen
        name="index"
        options={stackIndexOptions("Cuentas bancarias")}
      />
    </Stack>
  );
}
