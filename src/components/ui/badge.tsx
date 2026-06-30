const tones: Record<string, string> = {
  default: "bg-lt-surface-muted text-lt-text-muted",
  success: "bg-lt-success-bg text-lt-success-text",
  warning: "bg-lt-warning-bg text-lt-warning-text",
  danger: "bg-lt-danger-bg text-lt-danger-text",
  info: "bg-lt-info-bg text-lt-info-text",
};

export function Badge({
  children,
  tone = "default",
}: {
  children: React.ReactNode;
  tone?: keyof typeof tones;
}) {
  return (
    <span
      className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ${tones[tone]}`}
    >
      {children}
    </span>
  );
}

export function ordenEstadoTone(estado: string): keyof typeof tones {
  switch (estado) {
    case "borrador":
      return "default";
    case "lista_para_carga":
      return "info";
    case "en_transito":
      return "warning";
    case "liquidada":
      return "success";
    case "anulada":
      return "danger";
    default:
      return "default";
  }
}
