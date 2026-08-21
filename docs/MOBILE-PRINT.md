# Impresión térmica LogiTrack

## Resumen

- **Web (Vercel):** gestión (órdenes, clientes, radar, tasas). La impresión por navegador / RawBT es frágil con Bluetooth Classic.
- **APK Android (`apps/mobile-print`):** canal oficial de impresión ESC/POS Bluetooth para **vendedores y gerentes**.

## Repo / Git

- Código permanente: carpeta [`apps/mobile-print`](../apps/mobile-print).
- Desarrollo en rama `feature/mobile-print-apk` hasta el piloto; luego merge a `main`.
- Releases APK: tags `mobile-print-vX.Y.Z` (independientes del deploy web).

## Distribución (Firebase App Distribution)

1. Crear app Android en Firebase (`com.informaticagonzalez.logitrackprint`).
2. Generar APK con EAS: `cd apps/mobile-print && npx eas build --profile preview --platform android`.
3. Subir el artefacto a App Distribution e invitar correos de vendedores/gerentes.
4. En el teléfono: aceptar invitación → instalar → permitir orígenes desconocidos si pide.

Guía de uso en campo: [`apps/mobile-print/README.md`](../apps/mobile-print/README.md).

## Ticket ESC/POS

El builder vive en `apps/mobile-print/lib/ticket.ts` (texto plano + bytes). Misma idea que el ticket web en `src/components/print/orden-ticket.tsx`. En una fase posterior se puede extraer a `packages/ticket-escpos`.
