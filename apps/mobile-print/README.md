# LogiTrack Print (APK)

App Android para **vendedores y gerentes**: login Supabase, listar órdenes e imprimir tickets ESC/POS por Bluetooth Classic.

## Requisitos

- Node 20+
- Cuenta Expo (para EAS Build) o Android Studio (build local)
- Impresora térmica Bluetooth emparejada en el teléfono
- Variables en `.env` (copia desde `.env.example`):

```env
EXPO_PUBLIC_SUPABASE_URL=https://....supabase.co
EXPO_PUBLIC_SUPABASE_ANON_KEY=eyJ...
```

Usa las mismas credenciales públicas que la web LogiTrack (nunca `service_role`).

## Desarrollo

```bash
cd apps/mobile-print
npm install
npx expo start --dev-client
```

**Bluetooth Classic no funciona en Expo Go.** Necesitas un development build:

```bash
npx eas build --profile development --platform android
```

O prebuild local:

```bash
npx expo prebuild --platform android
npx expo run:android
```

## APK de release (piloto)

```bash
cd apps/mobile-print
npx eas build --profile preview --platform android
```

Perfil `preview` / `production` generan **APK** (`eas.json`). Distribuye con Firebase App Distribution o sideload.

## Flujo de uso en campo

1. Emparejar la térmica en **Ajustes → Bluetooth** del teléfono.
2. Abrir LogiTrack Print → login (vendedor / gerente / admin).
3. Pestaña **Impresora** → Actualizar lista → **Usar** + **Probar**.
4. Pestaña **Órdenes** → abrir orden → **Imprimir ticket**.

## Roles

| Rol | Órdenes visibles |
|---|---|
| vendedor | Las suyas (`creado_por` / `vendedor_id`) |
| gerente / admin | Listado amplio (RPC / RLS) |

## Troubleshooting

| Síntoma | Qué hacer |
|---|---|
| “Bluetooth nativo no disponible” | No uses Expo Go; instala APK dev/release |
| Lista de impresoras vacía | Emparejar en Ajustes del OS primero |
| Papel avanza en blanco | Revisar charset; el ticket ya translitera acentos |
| Fallo al conectar | Impresora encendida, cerca, no conectada a otra app |

## Checklist piloto

- [ ] Login vendedor OK
- [ ] Login gerente OK
- [ ] Prueba de impresión OK
- [ ] Imprimir orden real OK
- [ ] Reimpresión OK
- [ ] Impresora apagada → mensaje claro
