import { getCurrentProfile } from "@/lib/auth";
import { Sidebar } from "@/components/layout/sidebar";
import { InstallPwaPrompt } from "@/components/pwa/install-prompt";

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const profile = await getCurrentProfile();

  return (
    <div className="flex min-h-screen">
      <Sidebar userName={profile?.nombre_completo ?? "Usuario"} />
      <div className="flex flex-1 flex-col">
        <main className="flex-1 overflow-y-auto bg-lt-bg p-6 lg:p-8">
          <InstallPwaPrompt />
          {children}
        </main>
      </div>
    </div>
  );
}
