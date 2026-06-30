"use client";

import { useActionState } from "react";
import { useRouter } from "next/navigation";
import type { ReactNode } from "react";

type FormState = { error?: string; success?: boolean } | null;

export function ActionForm({
  action,
  redirectTo,
  children,
  className = "space-y-4",
}: {
  action: (prev: FormState, formData: FormData) => Promise<FormState>;
  redirectTo?: string;
  children: ReactNode;
  className?: string;
}) {
  const router = useRouter();

  const boundAction = async (prev: FormState, formData: FormData) => {
    const result = await action(prev, formData);
    if (result?.success && redirectTo) {
      router.push(redirectTo);
      router.refresh();
    }
    return result;
  };

  const [state, formAction, pending] = useActionState<FormState, FormData>(
    boundAction,
    null,
  );

  return (
    <form action={formAction} className={className}>
      {children}
      {state?.error && <p className="lt-alert-error">{state.error}</p>}
      {pending && (
        <p className="text-sm text-lt-text-muted">Guardando…</p>
      )}
    </form>
  );
}
