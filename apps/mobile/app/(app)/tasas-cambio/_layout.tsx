import { Stack } from "expo-router";
import {
  appHeaderScreenOptions,
  stackIndexOptions,
} from "@/components/nav-header";

export default function TasasCambioLayout() {
  return (
    <Stack screenOptions={appHeaderScreenOptions}>
      <Stack.Screen
        name="index"
        options={stackIndexOptions("Tasas de cambio")}
      />
    </Stack>
  );
}
