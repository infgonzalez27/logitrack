import { useEffect, useMemo, useState } from "react";
import { Modal, Pressable, StyleSheet, Text, View } from "react-native";
import { Ionicons } from "@expo/vector-icons";

const MESES_ES = [
  "Enero",
  "Febrero",
  "Marzo",
  "Abril",
  "Mayo",
  "Junio",
  "Julio",
  "Agosto",
  "Septiembre",
  "Octubre",
  "Noviembre",
  "Diciembre",
];

const DIAS_SEMANA = ["Lu", "Ma", "Mi", "Ju", "Vi", "Sa", "Do"];

function parseIso(iso: string): { year: number; month: number; day: number } {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso.trim());
  if (m) {
    return {
      year: Number(m[1]),
      month: Number(m[2]) - 1,
      day: Number(m[3]),
    };
  }
  const now = new Date();
  return {
    year: now.getFullYear(),
    month: now.getMonth(),
    day: now.getDate(),
  };
}

function toIso(year: number, month: number, day: number): string {
  const y = String(year);
  const m = String(month + 1).padStart(2, "0");
  const d = String(day).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

export function CalendarPickerModal({
  visible,
  value,
  onSelect,
  onClose,
}: {
  visible: boolean;
  value: string;
  onSelect: (isoDate: string) => void;
  onClose: () => void;
}) {
  const parsed = useMemo(() => parseIso(value), [value]);
  const [viewYear, setViewYear] = useState(parsed.year);
  const [viewMonth, setViewMonth] = useState(parsed.month);

  useEffect(() => {
    if (visible) {
      setViewYear(parsed.year);
      setViewMonth(parsed.month);
    }
  }, [visible, parsed.year, parsed.month]);

  const hoyIso = useMemo(() => {
    const now = new Date();
    return toIso(now.getFullYear(), now.getMonth(), now.getDate());
  }, []);

  const cells = useMemo(() => {
    const firstDay = new Date(viewYear, viewMonth, 1).getDay(); // 0=Dom .. 6=Sab
    const offset = (firstDay + 6) % 7; // Lunes = 0 .. Domingo = 6
    const daysInMonth = new Date(viewYear, viewMonth + 1, 0).getDate();

    const list: Array<{ day: number | null; iso?: string }> = [];
    for (let i = 0; i < offset; i++) list.push({ day: null });
    for (let d = 1; d <= daysInMonth; d++) {
      list.push({ day: d, iso: toIso(viewYear, viewMonth, d) });
    }
    while (list.length % 7 !== 0) list.push({ day: null });
    return list;
  }, [viewYear, viewMonth]);

  const prevMonth = () => {
    if (viewMonth === 0) {
      setViewMonth(11);
      setViewYear((y) => y - 1);
    } else {
      setViewMonth((m) => m - 1);
    }
  };

  const nextMonth = () => {
    if (viewMonth === 11) {
      setViewMonth(0);
      setViewYear((y) => y + 1);
    } else {
      setViewMonth((m) => m + 1);
    }
  };

  return (
    <Modal
      visible={visible}
      transparent
      animationType="fade"
      onRequestClose={onClose}
    >
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable style={styles.card} onPress={() => {}}>
          <View style={styles.header}>
            <Pressable onPress={prevMonth} style={styles.navBtn}>
              <Ionicons name="chevron-back" size={20} color="#0B3A5C" />
            </Pressable>
            <Text style={styles.monthTitle}>
              {MESES_ES[viewMonth]} {viewYear}
            </Text>
            <Pressable onPress={nextMonth} style={styles.navBtn}>
              <Ionicons name="chevron-forward" size={20} color="#0B3A5C" />
            </Pressable>
          </View>

          <View style={styles.weekRow}>
            {DIAS_SEMANA.map((d) => (
              <Text key={d} style={styles.weekDay}>
                {d}
              </Text>
            ))}
          </View>

          <View style={styles.grid}>
            {cells.map((c, idx) => {
              if (!c.day || !c.iso) {
                return <View key={`empty-${idx}`} style={styles.cell} />;
              }
              const isSelected = c.iso === value.trim();
              const isToday = c.iso === hoyIso;
              return (
                <Pressable
                  key={c.iso}
                  onPress={() => {
                    onSelect(c.iso!);
                    onClose();
                  }}
                  style={[
                    styles.cell,
                    isToday && !isSelected && styles.cellToday,
                    isSelected && styles.cellSelected,
                  ]}
                >
                  <Text
                    style={[
                      styles.cellText,
                      isToday && !isSelected && styles.cellTextToday,
                      isSelected && styles.cellTextSelected,
                    ]}
                  >
                    {c.day}
                  </Text>
                </Pressable>
              );
            })}
          </View>

          <View style={styles.footer}>
            <Pressable
              onPress={() => {
                onSelect(hoyIso);
                onClose();
              }}
              style={styles.todayBtn}
            >
              <Text style={styles.todayBtnText}>Hoy</Text>
            </Pressable>
            <Pressable onPress={onClose} style={styles.cancelBtn}>
              <Text style={styles.cancelBtnText}>Cerrar</Text>
            </Pressable>
          </View>
        </Pressable>
      </Pressable>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: {
    flex: 1,
    backgroundColor: "rgba(15, 23, 42, 0.5)",
    justifyContent: "center",
    alignItems: "center",
    padding: 20,
  },
  card: {
    width: "100%",
    maxWidth: 340,
    backgroundColor: "#FFFFFF",
    borderRadius: 16,
    padding: 16,
    shadowColor: "#000",
    shadowOpacity: 0.2,
    shadowRadius: 12,
    elevation: 6,
  },
  header: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    marginBottom: 12,
  },
  navBtn: {
    padding: 6,
    borderRadius: 8,
    backgroundColor: "#F1F5F9",
  },
  monthTitle: {
    fontSize: 16,
    fontWeight: "700",
    color: "#0F172A",
  },
  weekRow: {
    flexDirection: "row",
    marginBottom: 6,
  },
  weekDay: {
    width: "14.285%",
    textAlign: "center",
    fontSize: 12,
    fontWeight: "600",
    color: "#64748B",
  },
  grid: {
    flexDirection: "row",
    flexWrap: "wrap",
  },
  cell: {
    width: "14.285%",
    aspectRatio: 1,
    justifyContent: "center",
    alignItems: "center",
    borderRadius: 8,
  },
  cellToday: {
    backgroundColor: "#E0F2FE",
  },
  cellSelected: {
    backgroundColor: "#0B3A5C",
  },
  cellText: {
    fontSize: 14,
    fontWeight: "500",
    color: "#0F172A",
  },
  cellTextToday: {
    color: "#0369A1",
    fontWeight: "700",
  },
  cellTextSelected: {
    color: "#FFFFFF",
    fontWeight: "700",
  },
  footer: {
    flexDirection: "row",
    justifyContent: "space-between",
    marginTop: 14,
    paddingTop: 10,
    borderTopWidth: 1,
    borderTopColor: "#E2E8F0",
  },
  todayBtn: {
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 8,
    backgroundColor: "#E0F2FE",
  },
  todayBtnText: {
    fontSize: 13,
    fontWeight: "700",
    color: "#0369A1",
  },
  cancelBtn: {
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 8,
    backgroundColor: "#F1F5F9",
  },
  cancelBtnText: {
    fontSize: 13,
    fontWeight: "600",
    color: "#475569",
  },
});
