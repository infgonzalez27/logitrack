import { Button } from "@/components/ui/button";

export default function OfflinePage() {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-lt-bg px-6 text-center">
      <div className="mb-6 flex h-16 w-16 items-center justify-center rounded-2xl bg-lt-primary shadow-[var(--lt-shadow-soft)]">
        <svg
          viewBox="0 0 24 24"
          fill="none"
          className="h-8 w-8 text-white"
          aria-hidden
        >
          <path
            d="M3 7h11v8H3V7zm11 2h4l3 3v3h-7V9z"
            stroke="currentColor"
            strokeWidth="1.75"
            strokeLinejoin="round"
          />
          <circle cx="7" cy="17" r="2" fill="currentColor" />
          <circle cx="17" cy="17" r="2" fill="currentColor" />
        </svg>
      </div>
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
