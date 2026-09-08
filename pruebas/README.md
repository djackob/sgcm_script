# `pruebas/` — cómo se prueba el SIGCM

Todo lo que sirve para **recorrer el sistema** vive aquí. Si vas a probar, a
preparar una demostración o a comprobar que un cambio no rompió el flujo,
empieza por esta carpeta y no busques en otro sitio.

| Archivo | Para qué |
|---|---|
| **`PRUEBAS_FLUJO_COMPLETO.md`** | **El guion.** CMN → Requerimiento → Pagos paso a paso, con el DNI que da cada paso, los casos de observación y qué se escribe en SIGA. |
| `humo_maestros_siga.sql` | Prueba de humo de los maestros SIGA y de los días hábiles. Se corre suelta, contra `DBSIGCM`. |

## Dónde está cada cosa

Los **datos sembrados** no viven aquí sino en `db/90_pruebas/`, porque comparten
convención con el resto de las migraciones —prefijo `S9xx`, idempotentes, se
limpian solos— y el instalador los ignora a propósito:

| Semilla | Qué deja |
|---|---|
| `S909__datos_prueba_pago.sql` | Requerimiento con orden emitida y 3 entregables, locador persona jurídica, sin mora |
| `S910__datos_prueba_pago_penalidad.sql` | Lo mismo con locador persona natural y un entregable con penalidad |
| `S911__cmn_devolucion_au.sql` | Dos CMN parados antes de observarse: uno en Administración, otro en Abastecimiento |
| `S900`, `S901`–`S908` | Datos de acceso local y pruebas de CMN contra SIGA, de iteraciones anteriores |

Y el **porqué** de cada tramo está en los documentos de análisis, que no son
guiones de prueba:

- `SIGA/integracion/FLUJO_CMN_A_REQUERIMIENTO.md` — cómo el Anexo 4 habilita el
  ítem y qué actos siguen siendo de una persona dentro de SIGA.
- `SIGA/integracion/FLUJO_PAGOS.md` — el módulo de pagos y los cinco hitos de
  integración.

## La regla

**Toda prueba se documenta aquí.** Si al probar descubres algo que el guion no
dice —un paso que falta, una cuenta que no sirve, un estado que no existe—,
corrígelo en `PRUEBAS_FLUJO_COMPLETO.md` en la misma sesión. Un guion que miente
cuesta más que no tenerlo: se sigue al pie de la letra hasta que falla, y ahí se
pierde la mañana averiguando si el error es del sistema o del papel.

Los cambios de flujo, además, terminan con **su** script de prueba en
`db/90_pruebas/` (`ESTANDARES.md` §3.5).
