import { Link, Stack } from "expo-router";
import { StyleSheet, Text, View } from "react-native";

export default function NotFoundScreen() {
  return (
    <>
      <Stack.Screen options={{ title: "No encontrada" }} />
      <View style={styles.root}>
        <Text style={styles.title}>Pantalla no encontrada</Text>
        <Link href="/" style={styles.link}>
          Volver al inicio
        </Link>
      </View>
    </>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    padding: 24,
    backgroundColor: "#F4F6F8",
  },
  title: { fontSize: 18, fontWeight: "600", color: "#0B3A5C" },
  link: { marginTop: 12, color: "#0B3A5C", textDecorationLine: "underline" },
});
