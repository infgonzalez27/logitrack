import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
  type TextInputProps,
  type ViewStyle,
} from "react-native";

export function Screen({
  children,
  style,
}: {
  children: React.ReactNode;
  style?: ViewStyle;
}) {
  return <View style={[styles.screen, style]}>{children}</View>;
}

export function ListRow({
  title,
  subtitle,
  onPress,
  right,
}: {
  title: string;
  subtitle?: string | null;
  onPress?: () => void;
  right?: React.ReactNode;
}) {
  const body = (
    <View style={styles.row}>
      <View style={{ flex: 1 }}>
        <Text style={styles.rowTitle}>{title}</Text>
        {subtitle ? <Text style={styles.rowSub}>{subtitle}</Text> : null}
      </View>
      {right}
    </View>
  );
  if (!onPress) return body;
  return (
    <Pressable onPress={onPress} style={styles.rowPress}>
      {body}
    </Pressable>
  );
}

export function FormField({
  label,
  ...props
}: { label: string } & TextInputProps) {
  return (
    <View style={styles.field}>
      <Text style={styles.label}>{label}</Text>
      <TextInput
        style={styles.input}
        placeholderTextColor="#9AA6B2"
        {...props}
      />
    </View>
  );
}

export function EmptyState({ message }: { message: string }) {
  return <Text style={styles.empty}>{message}</Text>;
}

export function LoadingBlock() {
  return (
    <View style={styles.center}>
      <ActivityIndicator size="large" color="#0B3A5C" />
    </View>
  );
}

export function PrimaryButton({
  label,
  onPress,
  disabled,
  loading,
}: {
  label: string;
  onPress: () => void;
  disabled?: boolean;
  loading?: boolean;
}) {
  return (
    <Pressable
      style={[styles.btn, (disabled || loading) && { opacity: 0.6 }]}
      disabled={disabled || loading}
      onPress={onPress}
    >
      {loading ? (
        <ActivityIndicator color="#fff" />
      ) : (
        <Text style={styles.btnText}>{label}</Text>
      )}
    </Pressable>
  );
}

export function SecondaryButton({
  label,
  onPress,
}: {
  label: string;
  onPress: () => void;
}) {
  return (
    <Pressable style={styles.btnGhost} onPress={onPress}>
      <Text style={styles.btnGhostText}>{label}</Text>
    </Pressable>
  );
}

export function ErrorText({ message }: { message: string | null }) {
  if (!message) return null;
  return <Text style={styles.error}>{message}</Text>;
}

export function SectionTitle({ children }: { children: string }) {
  return <Text style={styles.section}>{children}</Text>;
}

export function OptionChips({
  label,
  options,
  value,
  onChange,
  allowEmpty,
  emptyLabel = "Sin asignar",
}: {
  label: string;
  options: { value: string; label: string }[];
  value: string;
  onChange: (value: string) => void;
  allowEmpty?: boolean;
  emptyLabel?: string;
}) {
  return (
    <View style={styles.field}>
      <Text style={styles.label}>{label}</Text>
      <View style={styles.chips}>
        {allowEmpty ? (
          <Pressable
            style={[styles.chip, !value && styles.chipActive]}
            onPress={() => onChange("")}
          >
            <Text style={[styles.chipText, !value && styles.chipTextActive]}>
              {emptyLabel}
            </Text>
          </Pressable>
        ) : null}
        {options.map((opt) => {
          const active = value === opt.value;
          return (
            <Pressable
              key={opt.value}
              style={[styles.chip, active && styles.chipActive]}
              onPress={() => onChange(opt.value)}
            >
              <Text style={[styles.chipText, active && styles.chipTextActive]}>
                {opt.label}
              </Text>
            </Pressable>
          );
        })}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: "#F4F6F8", padding: 16 },
  center: { flex: 1, alignItems: "center", justifyContent: "center" },
  rowPress: { marginBottom: 8 },
  row: {
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 14,
    borderWidth: 1,
    borderColor: "#E5EAF0",
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
  },
  rowTitle: { fontSize: 16, fontWeight: "600", color: "#0B3A5C" },
  rowSub: { fontSize: 13, color: "#5B6B7C", marginTop: 3 },
  field: { marginBottom: 12 },
  label: {
    fontSize: 12,
    color: "#5B6B7C",
    textTransform: "uppercase",
    marginBottom: 6,
  },
  input: {
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 12,
    fontSize: 16,
    color: "#0B3A5C",
  },
  empty: { textAlign: "center", color: "#5B6B7C", marginTop: 32 },
  btn: {
    backgroundColor: "#0B3A5C",
    borderRadius: 12,
    paddingVertical: 14,
    alignItems: "center",
  },
  btnText: { color: "#fff", fontWeight: "600", fontSize: 16 },
  btnGhost: {
    borderWidth: 1,
    borderColor: "#0B3A5C",
    borderRadius: 12,
    paddingVertical: 12,
    alignItems: "center",
    backgroundColor: "#fff",
    marginTop: 8,
  },
  btnGhostText: { color: "#0B3A5C", fontWeight: "600" },
  error: { color: "#B42318", marginBottom: 8 },
  section: {
    fontSize: 16,
    fontWeight: "600",
    color: "#0B3A5C",
    marginTop: 8,
    marginBottom: 8,
  },
  chips: { flexDirection: "row", flexWrap: "wrap", gap: 8 },
  chip: {
    borderWidth: 1,
    borderColor: "#D0D7DE",
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 8,
    backgroundColor: "#fff",
  },
  chipActive: { backgroundColor: "#0B3A5C", borderColor: "#0B3A5C" },
  chipText: { color: "#0B3A5C", fontSize: 13, fontWeight: "500" },
  chipTextActive: { color: "#fff" },
});
