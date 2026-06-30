"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";

type BeforeInstallPromptEvent = Event & {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed" }>;
};

export function InstallPwaPrompt() {
  const [deferredPrompt, setDeferredPrompt] =
    useState<BeforeInstallPromptEvent | null>(null);
  const [dismissed, setDismissed] = useState(false);
  const [isStandalone, setIsStandalone] = useState(false);

  useEffect(() => {
    const standalone =
      window.matchMedia("(display-mode: standalone)").matches ||
      ("standalone" in navigator &&
        (navigator as Navigator & { standalone?: boolean }).standalone ===
          true);

    setIsStandalone(standalone);

    const onBeforeInstall = (event: Event) => {
      event.preventDefault();
      setDeferredPrompt(event as BeforeInstallPromptEvent);
    };

    window.addEventListener("beforeinstallprompt", onBeforeInstall);
    return () =>
      window.removeEventListener("beforeinstallprompt", onBeforeInstall);
  }, []);

  async function handleInstall() {
    if (!deferredPrompt) return;
    await deferredPrompt.prompt();
    await deferredPrompt.userChoice;
    setDeferredPrompt(null);
    setDismissed(true);
  }

  if (isStandalone || dismissed || !deferredPrompt) {
    return null;
  }

  return (
    <div className="mb-6 flex flex-col gap-3 rounded-2xl border border-lt-primary-pastel bg-lt-primary-muted px-4 py-4 sm:flex-row sm:items-center sm:justify-between">
      <div>
        <p className="font-display text-sm font-semibold text-lt-text">
          Instalar LogiTrack
        </p>
        <p className="mt-1 text-sm text-lt-text-muted">
          Añade la app a tu pantalla de inicio para acceso rápido.
        </p>
      </div>
      <div className="flex shrink-0 gap-2">
        <Button type="button" variant="secondary" onClick={() => setDismissed(true)}>
          Ahora no
        </Button>
        <Button type="button" onClick={handleInstall}>
          Instalar
        </Button>
      </div>
    </div>
  );
}
