import { Drawer } from "expo-router/drawer";
import { AppDrawerContent } from "@/components/app-drawer";
import {
  appHeaderScreenOptions,
  drawerTopOptions,
} from "@/components/nav-header";
import { useTheme } from "@/src/theme/ThemeProvider";

export default function AppLayout() {
  const { theme } = useTheme();

  return (
    <Drawer
      drawerContent={(props) => <AppDrawerContent {...props} />}
      screenOptions={{
        ...appHeaderScreenOptions,
        headerStyle: { backgroundColor: theme.colors.brand },
        drawerActiveTintColor: theme.colors.brand,
        drawerStyle: {
          width: 300,
          backgroundColor: theme.colors.surface,
          borderTopRightRadius: 20,
          borderBottomRightRadius: 20,
        },
        overlayColor: theme.colors.overlay,
      }}
    >
      <Drawer.Screen
        name="home"
        options={drawerTopOptions("Inicio", { showHome: false })}
      />
      <Drawer.Screen name="visita" options={{ headerShown: false }} />
      <Drawer.Screen name="ordenes" options={{ headerShown: false }} />
      <Drawer.Screen name="autoventas" options={{ headerShown: false }} />
      <Drawer.Screen name="radar" options={{ headerShown: false }} />
      <Drawer.Screen name="clientes" options={{ headerShown: false }} />
      <Drawer.Screen name="rutas" options={{ headerShown: false }} />
      <Drawer.Screen name="proveedores" options={{ headerShown: false }} />
      <Drawer.Screen name="camiones" options={{ headerShown: false }} />
      <Drawer.Screen name="productos" options={{ headerShown: false }} />
      <Drawer.Screen name="choferes" options={{ headerShown: false }} />
      <Drawer.Screen name="inventario-almacen" options={{ headerShown: false }} />
      <Drawer.Screen name="inventario-movil" options={{ headerShown: false }} />
      <Drawer.Screen name="inventario-movimientos" options={{ headerShown: false }} />
      <Drawer.Screen name="rendiciones" options={{ headerShown: false }} />
      <Drawer.Screen name="contenedores" options={{ headerShown: false }} />
      <Drawer.Screen name="facturas-compras" options={{ headerShown: false }} />
      <Drawer.Screen name="pagos-proveedores" options={{ headerShown: false }} />
      <Drawer.Screen name="tasas-cambio" options={{ headerShown: false }} />
      <Drawer.Screen name="cuentas-bancarias" options={{ headerShown: false }} />
      <Drawer.Screen name="usuarios" options={{ headerShown: false }} />
      <Drawer.Screen name="impresora" options={drawerTopOptions("Impresora")} />
      <Drawer.Screen name="cuenta" options={drawerTopOptions("Cuenta")} />
    </Drawer>
  );
}
