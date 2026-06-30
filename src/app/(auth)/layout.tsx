export default function AuthLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="relative flex min-h-screen items-center justify-center overflow-hidden px-4 py-10 lt-auth-bg">
      <div className="pointer-events-none absolute inset-0" aria-hidden />
      <div className="relative w-full max-w-md">
        <div className="mb-8 text-center">
          <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-2xl bg-lt-primary shadow-[var(--lt-shadow-soft)]">
            <svg
              viewBox="0 0 24 24"
              fill="none"
              className="h-6 w-6 text-white"
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
            LogiTrack
          </h1>
          <p className="mt-1 text-sm text-lt-text-muted">
            Gestión logística y distribución
          </p>
        </div>
        {children}
      </div>
    </div>
  );
}
