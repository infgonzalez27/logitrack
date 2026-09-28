import { Stack } from "expo-router";
import {
  appHeaderScreenOptions,
  stackChildOptions,
  stackIndexOptions,
} from "@/components/nav-header";

export default function RadarLayout() {
  return (
    <Stack screenOptions={appHeaderScreenOptions}>
      <Stack.Screen name="index" options={stackIndexOptions("Radar")} />
      <Stack.Screen
        name="entrega/[ordenId]"
        options={stackChildOptions("Entrega")}
      />
    </Stack>
  );
}
