import { Logo } from "@/components/brand/logo";
import { Button } from "@/components/ui/button";

export default function OfflinePage() {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-lt-bg px-6 text-center">
      <Logo
        size="lg"
        layout="stacked"
        showWordmark
        className="mb-6"
        imageClassName="rounded-2xl"
      />
      <h1 className="font-display text-2xl font-bold text-lt-text">
        Sin conexión
      </h1>
      <p className="mt-3 max-w-sm text-sm text-lt-text-muted">
        No hay internet en este momento. Revisa tu red e intenta de nuevo.
      </p>
      <Button href="/ordenes" className="mt-8">
        Reintentar
      </Button>
      <p className="mt-4 text-xs text-lt-text-subtle">
        LogiTrack funciona mejor con conexión para sincronizar datos.
      </p>
    </div>
  );
}
