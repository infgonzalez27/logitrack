const tones: Record<string, string> = {
  default: "bg-zinc-100 text-zinc-700",
  success: "bg-emerald-100 text-emerald-800",
  warning: "bg-amber-100 text-amber-800",
  danger: "bg-red-100 text-red-800",
  info: "bg-blue-100 text-blue-800",
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
