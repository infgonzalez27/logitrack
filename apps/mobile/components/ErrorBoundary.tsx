import React, { Component, type ReactNode } from "react";
import {
  Alert,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { recordCrash } from "@/lib/logger";

interface Props {
  children: ReactNode;
}

interface State {
  hasError: boolean;
  error: Error | null;
  errorInfo: React.ErrorInfo | null;
}

export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = {
      hasError: false,
      error: null,
      errorInfo: null,
    };
  }

  static getDerivedStateFromError(error: Error): Partial<State> {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    this.setState({ errorInfo });
    void recordCrash(error, false);
  }

  resetError = () => {
    this.setState({ hasError: false, error: null, errorInfo: null });
  };

  copyDetails = () => {
    const { error, errorInfo } = this.state;
    const text = `Error: ${error?.message}\n\nStack:\n${error?.stack}\n\nComponentStack:\n${errorInfo?.componentStack}`;
    Alert.alert("Detalle del Error", text, [{ text: "Cerrar" }]);
  };

  render() {
    if (this.state.hasError) {
      const { error } = this.state;
      return (
        <View style={styles.container}>
          <View style={styles.card}>
            <Text style={styles.title}>Ocurrió un problema</Text>
            <Text style={styles.subtitle}>
              No se pudo cargar esta sección correctamente. Por favor, intenta de nuevo.
            </Text>

            {__DEV__ && error ? (
              <ScrollView style={styles.logBox}>
                <Text style={styles.errorMessage}>
                  {error.name}: {error.message}
                </Text>
                {error.stack ? (
                  <Text style={styles.stack}>{error.stack}</Text>
                ) : null}
              </ScrollView>
            ) : null}

            <View style={styles.actions}>
              <Pressable style={styles.btnPrimary} onPress={this.resetError}>
                <Text style={styles.btnPrimaryText}>Reintentar</Text>
              </Pressable>
            </View>
          </View>
        </View>
      );
    }

    return this.props.children;
  }
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#F4F6F8",
    padding: 16,
    justifyContent: "center",
  },
  card: {
    backgroundColor: "#FFFFFF",
    borderRadius: 16,
    padding: 20,
    borderWidth: 1,
    borderColor: "#E5EAF0",
    maxHeight: "90%",
  },
  title: {
    fontSize: 18,
    fontWeight: "700",
    color: "#B42318",
    marginBottom: 4,
  },
  subtitle: {
    fontSize: 14,
    color: "#5B6B7C",
    marginBottom: 14,
  },
  logBox: {
    backgroundColor: "#1E293B",
    borderRadius: 10,
    padding: 12,
    maxHeight: 280,
    marginBottom: 16,
  },
  errorMessage: {
    color: "#F87171",
    fontWeight: "700",
    fontSize: 13,
    marginBottom: 8,
    fontFamily: "monospace",
  },
  stack: {
    color: "#94A3B8",
    fontSize: 11,
    fontFamily: "monospace",
  },
  componentStack: {
    color: "#CBD5E1",
    fontSize: 10,
    fontFamily: "monospace",
    marginTop: 6,
  },
  actions: {
    flexDirection: "row",
    gap: 10,
  },
  btnPrimary: {
    flex: 1,
    backgroundColor: "#0B3A5C",
    borderRadius: 10,
    paddingVertical: 12,
    alignItems: "center",
  },
  btnPrimaryText: {
    color: "#FFFFFF",
    fontWeight: "600",
    fontSize: 14,
  },
  btnSecondary: {
    flex: 1,
    backgroundColor: "#F1F5F9",
    borderRadius: 10,
    paddingVertical: 12,
    alignItems: "center",
    borderWidth: 1,
    borderColor: "#CBD5E1",
  },
  btnSecondaryText: {
    color: "#0B3A5C",
    fontWeight: "600",
    fontSize: 14,
  },
});
