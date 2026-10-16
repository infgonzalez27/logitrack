import React, { useMemo, useState } from "react";
import {
  Modal,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { Ionicons } from "@expo/vector-icons";

const MESES = [
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

const DIAS_SEMANA = ["Do", "Lu", "Ma", "Mi", "Ju", "Vi", "Sá"];

const HORAS_RAPIDAS = ["07:00", "08:00", "09:00", "11:00", "14:00", "16:00"];

function pad(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

function parseFecha(iso: string | null | undefined) {
  if (!iso) {
    const now = new Date();
    return {
      year: now.getFullYear(),
      month: now.getMonth(),
      day: now.getDate(),
      time: "08:00",
    };
  }

  // Si tiene formato YYYY-MM-DD o YYYY-MM-DDTHH:mm
  const parts = iso.split("T");
  const dParts = parts[0].split("-");
  const y = parseInt(dParts[0], 10);
  const m = parseInt(dParts[1], 10) - 1;
  const d = parseInt(dParts[2], 10);
  const time = parts[1] ? parts[1].slice(0, 5) : "08:00";

  if (!isNaN(y) && !isNaN(m) && !isNaN(d)) {
    return { year: y, month: m, day: d, time };
  }

  const date = new Date(iso);
  if (!isNaN(date.getTime())) {
    return {
      year: date.getFullYear(),
      month: date.getMonth(),
      day: date.getDate(),
      time: `${pad(date.getHours())}:${pad(date.getMinutes())}`,
    };
  }

  const now = new Date();
  return {
    year: now.getFullYear(),
    month: now.getMonth(),
    day: now.getDate(),
    time: "08:00",
  };
}

export function formatFechaDespachoLegible(iso: string | null | undefined): string {
  if (!iso) return "Sin fecha asignada";
  const { year, month, day, time } = parseFecha(iso);
  const d = new Date(year, month, day);
  const nombresDias = [
    "Domingo",
    "Lunes",
    "Martes",
    "Miércoles",
    "Jueves",
    "Viernes",
    "Sábado",
  ];
  const diaSemana = nombresDias[d.getDay()] ?? "";
  const mesNombre = MESES[month] ?? "";

  // Convertir 24h a 12h con AM/PM para claridad
  const [hhStr, mmStr] = time.split(":");
  let hh = parseInt(hhStr, 10);
  const ampm = hh >= 12 ? "PM" : "AM";
  if (hh === 0) hh = 12;
  else if (hh > 12) hh -= 12;
  const hora12 = `${pad(hh)}:${mmStr ?? "00"} ${ampm}`;

  return `${diaSemana}, ${day} de ${mesNombre} ${year} · ${hora12}`;
}

export type FechaDespachoPickerProps = {
  label?: string;
  value: string;
  onChange: (value: string) => void;
  required?: boolean;
};

export function FechaDespachoPicker({
  label = "Fecha de despacho (Radar)",
  value,
  onChange,
  required = false,
}: FechaDespachoPickerProps) {
  const [modalVisible, setModalVisible] = useState(false);

  // Parsear fecha actual
  const inicial = useMemo(() => parseFecha(value), [value]);

  const [selYear, setSelYear] = useState(inicial.year);
  const [selMonth, setSelMonth] = useState(inicial.month);
  const [selDay, setSelDay] = useState(inicial.day);
  const [selTime, setSelTime] = useState(inicial.time);

  // Navegación de meses
  const [viewYear, setViewYear] = useState(inicial.year);
  const [viewMonth, setViewMonth] = useState(inicial.month);

  function abrirModal() {
    const act = parseFecha(value);
    setSelYear(act.year);
    setSelMonth(act.month);
    setSelDay(act.day);
    setSelTime(act.time);
    setViewYear(act.year);
    setViewMonth(act.month);
    setModalVisible(true);
  }

  function mesAnterior() {
    if (viewMonth === 0) {
      setViewMonth(11);
      setViewYear((y) => y - 1);
    } else {
      setViewMonth((m) => m - 1);
    }
  }

  function mesSiguiente() {
    if (viewMonth === 11) {
      setViewMonth(0);
      setViewYear((y) => y + 1);
    } else {
      setViewMonth((m) => m + 1);
    }
  }

  function seleccionarDia(dia: number) {
    setSelYear(viewYear);
    setSelMonth(viewMonth);
    setSelDay(dia);
  }

  function setPreset(diasOffset: number) {
    const target = new Date();
    target.setDate(target.getDate() + diasOffset);
    const y = target.getFullYear();
    const m = target.getMonth();
    const d = target.getDate();
    setSelYear(y);
    setSelMonth(m);
    setSelDay(d);
    setViewYear(y);
    setViewMonth(m);
  }

  function confirmar() {
    const isoResultado = `${selYear}-${pad(selMonth + 1)}-${pad(selDay)}T${selTime}`;
    onChange(isoResultado);
    setModalVisible(false);
  }

  // Generar cuadrícula del mes
  const primerDiaSemana = new Date(viewYear, viewMonth, 1).getDay();
  const totalDiasMes = new Date(viewYear, viewMonth + 1, 0).getDate();

  const hoy = new Date();
  const esHoy = (dia: number) =>
    hoy.getFullYear() === viewYear &&
    hoy.getMonth() === viewMonth &&
    hoy.getDate() === dia;

  const esSeleccionado = (dia: number) =>
    selYear === viewYear && selMonth === viewMonth && selDay === dia;

  return (
    <View style={styles.container}>
      {label ? (
        <Text style={styles.label}>
          {label} {required ? <Text style={styles.req}>*</Text> : null}
        </Text>
      ) : null}

      <Pressable style={styles.cardTrigger} onPress={abrirModal}>
        <View style={styles.iconCircle}>
          <Ionicons name="calendar" size={20} color="#0B3A5C" />
        </View>
        <View style={{ flex: 1 }}>
          <Text style={styles.triggerDate}>
            {formatFechaDespachoLegible(value)}
          </Text>
          <Text style={styles.triggerHint}>
            Toca para cambiar día u hora
          </Text>
        </View>
        <Ionicons name="chevron-forward" size={18} color="#9AA6B2" />
      </Pressable>

      <Modal
        visible={modalVisible}
        transparent
        animationType="fade"
        onRequestClose={() => setModalVisible(false)}
      >
        <View style={styles.modalOverlay}>
          <View style={styles.modalContent}>
            {/* Cabecera */}
            <View style={styles.modalHeader}>
              <View>
                <Text style={styles.modalTitle}>Fecha de despacho</Text>
                <Text style={styles.modalSub}>
                  Asigna el día y hora para organizar en Radar
                </Text>
              </View>
              <Pressable
                style={styles.closeBtn}
                onPress={() => setModalVisible(false)}
                hitSlop={8}
              >
                <Ionicons name="close" size={22} color="#5B6B7C" />
              </Pressable>
            </View>

            <ScrollView contentContainerStyle={{ padding: 16, gap: 16 }}>
              {/* Accesos rápidos */}
              <View style={styles.presetsRow}>
                <Pressable
                  style={styles.presetChip}
                  onPress={() => setPreset(0)}
                >
                  <Text style={styles.presetChipText}>Hoy</Text>
                </Pressable>
                <Pressable
                  style={styles.presetChip}
                  onPress={() => setPreset(1)}
                >
                  <Text style={styles.presetChipText}>Mañana</Text>
                </Pressable>
                <Pressable
                  style={styles.presetChip}
                  onPress={() => setPreset(2)}
                >
                  <Text style={styles.presetChipText}>En 2 días</Text>
                </Pressable>
              </View>

              {/* Selector de Mes / Año */}
              <View style={styles.monthSelector}>
                <Pressable
                  style={styles.navBtn}
                  onPress={mesAnterior}
                  hitSlop={8}
                >
                  <Ionicons name="chevron-back" size={20} color="#0B3A5C" />
                </Pressable>
                <Text style={styles.monthTitle}>
                  {MESES[viewMonth]} {viewYear}
                </Text>
                <Pressable
                  style={styles.navBtn}
                  onPress={mesSiguiente}
                  hitSlop={8}
                >
                  <Ionicons name="chevron-forward" size={20} color="#0B3A5C" />
                </Pressable>
              </View>

              {/* Días de la semana */}
              <View style={styles.diasSemanaRow}>
                {DIAS_SEMANA.map((d, i) => (
                  <Text key={i} style={styles.diaSemanaText}>
                    {d}
                  </Text>
                ))}
              </View>

              {/* Cuadrícula de días */}
              <View style={styles.gridDias}>
                {/* Días vacíos al inicio */}
                {Array.from({ length: primerDiaSemana }).map((_, i) => (
                  <View key={`empty-${i}`} style={styles.diaCelda} />
                ))}

                {/* Días del mes */}
                {Array.from({ length: totalDiasMes }).map((_, i) => {
                  const dia = i + 1;
                  const selected = esSeleccionado(dia);
                  const today = esHoy(dia);

                  return (
                    <Pressable
                      key={`day-${dia}`}
                      style={[
                        styles.diaCelda,
                        today && styles.diaHoy,
                        selected && styles.diaSeleccionado,
                      ]}
                      onPress={() => seleccionarDia(dia)}
                    >
                      <Text
                        style={[
                          styles.diaNumero,
                          today && styles.diaNumeroHoy,
                          selected && styles.diaNumeroSeleccionado,
                        ]}
                      >
                        {dia}
                      </Text>
                    </Pressable>
                  );
                })}
              </View>

              {/* Selector de Hora */}
              <View style={{ gap: 8, marginTop: 4 }}>
                <Text style={styles.sectionLabel}>Hora aproximada de despacho</Text>
                <View style={styles.horasRow}>
                  {HORAS_RAPIDAS.map((h) => {
                    const sel = selTime === h;
                    return (
                      <Pressable
                        key={h}
                        style={[styles.horaChip, sel && styles.horaChipSel]}
                        onPress={() => setSelTime(h)}
                      >
                        <Text
                          style={[
                            styles.horaChipText,
                            sel && styles.horaChipTextSel,
                          ]}
                        >
                          {h}
                        </Text>
                      </Pressable>
                    );
                  })}
                </View>
              </View>
            </ScrollView>

            {/* Botones de acción */}
            <View style={styles.modalFooter}>
              <Pressable
                style={styles.cancelBtn}
                onPress={() => setModalVisible(false)}
              >
                <Text style={styles.cancelBtnText}>Cancelar</Text>
              </Pressable>
              <Pressable style={styles.confirmBtn} onPress={confirmar}>
                <Text style={styles.confirmBtnText}>Confirmar fecha</Text>
              </Pressable>
            </View>
          </View>
        </View>
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 6,
  },
  label: {
    fontSize: 12,
    fontWeight: "600",
    color: "#5B6B7C",
    textTransform: "uppercase",
  },
  req: {
    color: "#D92D20",
  },
  cardTrigger: {
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 12,
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
  },
  iconCircle: {
    width: 38,
    height: 38,
    borderRadius: 10,
    backgroundColor: "#EEF4F9",
    alignItems: "center",
    justifyContent: "center",
  },
  triggerDate: {
    fontSize: 15,
    fontWeight: "700",
    color: "#0B3A5C",
  },
  triggerHint: {
    fontSize: 12,
    color: "#7E8B9B",
    marginTop: 2,
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: "rgba(0, 0, 0, 0.45)",
    justifyContent: "center",
    alignItems: "center",
    padding: 16,
  },
  modalContent: {
    backgroundColor: "#fff",
    width: "100%",
    maxWidth: 380,
    borderRadius: 20,
    maxHeight: "90%",
    overflow: "hidden",
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.15,
    shadowRadius: 12,
    elevation: 8,
  },
  modalHeader: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    paddingHorizontal: 18,
    paddingTop: 16,
    paddingBottom: 12,
    borderBottomWidth: 1,
    borderBottomColor: "#E5EAF0",
  },
  modalTitle: {
    fontSize: 17,
    fontWeight: "700",
    color: "#0B3A5C",
  },
  modalSub: {
    fontSize: 12,
    color: "#7E8B9B",
    marginTop: 2,
  },
  closeBtn: {
    padding: 4,
  },
  presetsRow: {
    flexDirection: "row",
    gap: 8,
  },
  presetChip: {
    flex: 1,
    backgroundColor: "#F4F6F8",
    paddingVertical: 8,
    borderRadius: 8,
    alignItems: "center",
    borderWidth: 1,
    borderColor: "#E5EAF0",
  },
  presetChipText: {
    fontSize: 13,
    fontWeight: "600",
    color: "#0B3A5C",
  },
  monthSelector: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    paddingVertical: 6,
  },
  navBtn: {
    width: 32,
    height: 32,
    borderRadius: 8,
    backgroundColor: "#F4F6F8",
    alignItems: "center",
    justifyContent: "center",
  },
  monthTitle: {
    fontSize: 16,
    fontWeight: "700",
    color: "#0B3A5C",
  },
  diasSemanaRow: {
    flexDirection: "row",
    justifyContent: "space-between",
    paddingBottom: 6,
    borderBottomWidth: 1,
    borderBottomColor: "#F0F2F5",
  },
  diaSemanaText: {
    width: 40,
    textAlign: "center",
    fontSize: 12,
    fontWeight: "700",
    color: "#8B98A5",
  },
  gridDias: {
    flexDirection: "row",
    flexWrap: "wrap",
    justifyContent: "space-between",
    rowGap: 6,
  },
  diaCelda: {
    width: 40,
    height: 40,
    borderRadius: 20,
    alignItems: "center",
    justifyContent: "center",
  },
  diaHoy: {
    borderWidth: 1,
    borderColor: "#0B3A5C",
  },
  diaSeleccionado: {
    backgroundColor: "#0B3A5C",
  },
  diaNumero: {
    fontSize: 14,
    fontWeight: "500",
    color: "#1C252E",
  },
  diaNumeroHoy: {
    fontWeight: "700",
    color: "#0B3A5C",
  },
  diaNumeroSeleccionado: {
    color: "#fff",
    fontWeight: "700",
  },
  sectionLabel: {
    fontSize: 12,
    fontWeight: "600",
    color: "#5B6B7C",
    textTransform: "uppercase",
  },
  horasRow: {
    flexDirection: "row",
    flexWrap: "wrap",
    gap: 8,
  },
  horaChip: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 8,
    backgroundColor: "#F4F6F8",
    borderWidth: 1,
    borderColor: "#E5EAF0",
  },
  horaChipSel: {
    backgroundColor: "#0B3A5C",
    borderColor: "#0B3A5C",
  },
  horaChipText: {
    fontSize: 13,
    fontWeight: "600",
    color: "#0B3A5C",
  },
  horaChipTextSel: {
    color: "#fff",
  },
  modalFooter: {
    flexDirection: "row",
    justifyContent: "flex-end",
    gap: 10,
    padding: 16,
    borderTopWidth: 1,
    borderTopColor: "#E5EAF0",
    backgroundColor: "#FAFBFD",
  },
  cancelBtn: {
    paddingVertical: 10,
    paddingHorizontal: 16,
    borderRadius: 10,
  },
  cancelBtnText: {
    fontSize: 14,
    fontWeight: "600",
    color: "#5B6B7C",
  },
  confirmBtn: {
    backgroundColor: "#0B3A5C",
    paddingVertical: 10,
    paddingHorizontal: 18,
    borderRadius: 10,
  },
  confirmBtnText: {
    fontSize: 14,
    fontWeight: "700",
    color: "#fff",
  },
});
