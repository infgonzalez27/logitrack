import { Logo } from "@/components/brand/logo";

export default function AuthLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="relative flex min-h-screen items-center justify-center overflow-hidden px-4 py-10 lt-auth-bg">
      <div className="pointer-events-none absolute inset-0" aria-hidden />
      <div className="relative w-full max-w-md">
        <div className="mb-8 flex justify-center">
          <Logo
            size="xl"
            layout="stacked"
            subtitle="Gestión logística y distribución"
          />
        </div>
        {children}
      </div>
    </div>
  );
}
