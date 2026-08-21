# Checklist piloto — LogiTrack Print APK

Fecha: ________  Dispositivo: ________  Impresora: ________

## Build

- [ ] `.env` con URL y anon key de Supabase
- [ ] `npx eas build --profile preview --platform android` OK
- [ ] APK instalada en teléfono de prueba

## Auth

- [ ] Login vendedor OK
- [ ] Login gerente OK
- [ ] Rol no autorizado (p. ej. chofer) es rechazado

## Bluetooth

- [ ] Impresora emparejada en Ajustes del OS
- [ ] Aparece en pestaña Impresora
- [ ] “Probar” imprime ticket de prueba legible
- [ ] MAC queda como preferida

## Órdenes

- [ ] Lista carga órdenes
- [ ] Detalle muestra ticket
- [ ] “Imprimir ticket” sale correcto (cliente, líneas, total)
- [ ] Reimpresión OK
- [ ] Impresora apagada → mensaje de error claro

## Notas

_______________________________________________
