import { Alert, Pressable, StyleSheet, Switch, Text, View } from "react-native";
import { DIAS_SEMANA_OPCIONES } from "@/lib/clientes";

type Props = {
  diasVisita: string[];
  visitaCualquierDia: boolean;
  onChange: (next: {
    dias_visita: string[];
    visita_cualquier_dia: boolean;
  }) => void;
};

export function SelectorDiasVisita({
  diasVisita,
  visitaCualquierDia,
  onChange,
}: Props) {
  function toggleCualquierDia(checked: boolean) {
    onChange({
      visita_cualquier_dia: checked,
      dias_visita: checked ? [] : diasVisita,
    });
  }

  function toggleDia(dia: string) {
    if (visitaCualquierDia) return;
    const exists = diasVisita.includes(dia);
    if (exists) {
      onChange({
        visita_cualquier_dia: false,
        dias_visita: diasVisita.filter((d) => d !== dia),
      });
      return;
    }
    if (diasVisita.length >= 2) {
      Alert.alert(
        "Límite alcanzado",
        "Solo puedes asignar un máximo de 2 días de visita por cliente.",
      );
      return;
    }
    onChange({
      visita_cualquier_dia: false,
      dias_visita: [...diasVisita, dia],
    });
  }

  return (
    <View style={styles.container}>
      <View style={styles.headerRow}>
        <View style={{ flex: 1 }}>
          <Text style={styles.title}>Días de visita en ruta</Text>
          <Text style={styles.subtitle}>
            Selecciona &quot;Cualquier día&quot; o hasta 2 días específicos de la semana.
          </Text>
        </View>
        <View style={styles.switchWrap}>
          <Text style={styles.switchLabel}>Cualquier día</Text>
          <Switch
            value={visitaCualquierDia}
            onValueChange={toggleCualquierDia}
            trackColor={{ false: "#CBD5E1", true: "#0B3A5C" }}
            thumbColor="#FFFFFF"
          />
        </View>
      </View>

      {!visitaCualquierDia ? (
        <View style={styles.chipsWrap}>
          {DIAS_SEMANA_OPCIONES.map((op) => {
            const active = diasVisita.includes(op.value);
            return (
              <Pressable
                key={op.value}
                onPress={() => toggleDia(op.value)}
                style={[styles.chip, active && styles.chipActive]}
              >
                <Text style={[styles.chipText, active && styles.chipTextActive]}>
                  {op.label}
                </Text>
              </Pressable>
            );
          })}
        </View>
      ) : (
        <View style={styles.anyDayBadge}>
          <Text style={styles.anyDayText}>
            Este cliente aparecerá disponible para visita todos los días de la semana.
          </Text>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: "#FFFFFF",
    borderRadius: 12,
    borderWidth: 1,
    borderColor: "#D0D7DE",
    padding: 14,
    marginBottom: 14,
    gap: 10,
  },
  headerRow: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 12,
  },
  title: {
    fontSize: 14,
    fontWeight: "700",
    color: "#0B3A5C",
  },
  subtitle: {
    fontSize: 12,
    color: "#64748B",
    marginTop: 2,
  },
  switchWrap: {
    alignItems: "center",
    gap: 2,
  },
  switchLabel: {
    fontSize: 11,
    fontWeight: "600",
    color: "#334155",
  },
  chipsWrap: {
    flexDirection: "row",
    flexWrap: "wrap",
    gap: 8,
    marginTop: 2,
  },
  chip: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: "#CBD5E1",
    backgroundColor: "#F8FAFC",
  },
  chipActive: {
    backgroundColor: "#0B3A5C",
    borderColor: "#0B3A5C",
  },
  chipText: {
    fontSize: 13,
    fontWeight: "600",
    color: "#334155",
  },
  chipTextActive: {
    color: "#FFFFFF",
  },
  anyDayBadge: {
    backgroundColor: "#F0F9FF",
    borderRadius: 8,
    padding: 10,
    borderWidth: 1,
    borderColor: "#BAE6FD",
  },
  anyDayText: {
    fontSize: 12,
    color: "#0369A1",
    fontWeight: "500",
  },
});

