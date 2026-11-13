"use client";

import { createContext, useContext } from "react";

const StorageBaseContext = createContext<string | undefined>(undefined);

/**
 * Provee la URL base de Storage del proyecto Supabase del tenant activo
 * (`https://<tenant>.supabase.co/storage/v1/object/public`) a los componentes cliente.
 */
export function StorageBaseProvider({
  baseUrl,
  children,
}: {
  baseUrl: string;
  children: React.ReactNode;
}) {
  return (
    <StorageBaseContext.Provider value={baseUrl}>
      {children}
    </StorageBaseContext.Provider>
  );
}

export function useStorageBaseUrl(): string | undefined {
  return useContext(StorageBaseContext);
}
