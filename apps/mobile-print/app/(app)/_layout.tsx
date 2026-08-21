import { Tabs } from "expo-router";

export default function AppLayout() {
  return (
    <Tabs
      screenOptions={{
        headerStyle: { backgroundColor: "#0B3A5C" },
        headerTintColor: "#fff",
        tabBarActiveTintColor: "#0B3A5C",
      }}
    >
      <Tabs.Screen
        name="orders/index"
        options={{
          title: "Órdenes",
          tabBarLabel: "Órdenes",
        }}
      />
      <Tabs.Screen
        name="orders/[id]"
        options={{
          href: null,
          title: "Ticket",
        }}
      />
      <Tabs.Screen
        name="printers"
        options={{
          title: "Impresora",
          tabBarLabel: "Impresora",
        }}
      />
    </Tabs>
  );
}
