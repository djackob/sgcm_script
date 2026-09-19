# Plan de tickets / semillas — Observaciones CMN (validación 16/09/2026)

Fuente: informe técnico de cambio del módulo CMN (Anexos 3 y 4).  
Baseline código: rama `jack5` (`sgcm_front`, `sgcm_back`, `sgcm_script`).  
Fecha del plan: 2026-09-18.  
**Decisiones D1–D6: CERRADAS** (2026-09-18).

Orden de trabajo = prioridad del negocio + dependencias técnicas.  
No empezar el siguiente bloque hasta cerrar el criterio de aceptación del anterior, salvo tickets marcados como **paralelos**.

---

## Cómo leer cada ticket

| Campo | Significado |
|---|---|
| **Capas** | `script` = SQL/semillas; `front` = Angular; `back` = API bridge |
| **Semillas** | Archivos `S*` nuevos o a tocar (idempotentes) |
| **Depende de** | Tickets que deben estar listos antes |
| **Aceptación** | Qué probar en demo para darlo por cerrado |

---

## Bloque 0 — Decisiones de negocio (CERRADAS)

| # | Decisión | Impacta |
|---|---|---|
| **D1** | Mostrar mensaje de techo excedido y **no dejar continuar** el guardado hasta que el usuario ajuste el monto. Se mantiene el contrato del puente (200 + `estado:0`); el front bloquea el flujo. | T1 |
| **D2** | **Sí:** el especialista da visto bueno operativo (click, sin certificado). La firma digital queda para el cierre oficial (Anexo 4 / jefe u órgano configurado). | T2 |
| **D3** | Cambiar Ordinaria/Extraordinaria **solo antes de generar el Anexo 4**. | T3 |
| **D4** | La 2.ª firma / delegación **cambia con el tiempo**. Debe vivir en BD, leerse al **generar el Anexo 4** para armar el circuito de firmas, y administrarse desde un perfil **ADMIN_SISTEMA** (misma lógica de mantenimiento que los campos por defecto del TDR). | T5 |
| **D5** | El sistema **descarga el formato que emite el SIGA**, lo sube al servidor de archivos del SGCM y **a partir de ese PDF** arranca el flujo de firmas ya existente en el SGCM (no se firma el pdfmake como documento oficial). | T6 |
| **D6** | No es un bypass a ciegas: botón para **reintentar / actualizar el registro A4 desde el SIGA** cuando falló. Recrea el tramo SIGA→archivo, inserta el PDF en el file server y el SGCM sigue con firmas. Al guardar/completar firmas: notificar a **jefe AU**, **especialista AU**, con copia a **especialista Abast** y **jefe Abast**. | T7 |

---

## Matriz resumen

| ID | Título | Prioridad | Estado hoy | Capas |
|---|---|---|---|---|
| **T1** | Validar techo/saldo SIGA al guardar (bloqueo UX) | Crítica | **Hecho (2026-09-18)** | script + front |
| **T2** | V.B. especialista sin firma + secretaria | Alta | Hecho (local) | script (+ SSO) + front |
| **T3** | Tipo Ordinaria/Extraordinaria editable en Abast | Alta | Hecho (local) | script + front |
| **T4** | Limpiar PDF auxiliar Anexo 4 (pdfmake) | Media | Hecho (local) | front |
| **T5** | Admin firmantes A4 (BD + pantalla ADMIN) | Alta | Hecho (local) | script + front + back |
| **T6** | A4: aprobar SIGA sin firma SGCM + subir PDF firmado SIGA | Alta | Hecho (local, manual) | script + front |
| **T7** | Reintentar A4 desde SIGA si falló + notificaciones | Media | Parcial (correos al finalizar subida) | script + front + back |
| **T0** | Multi-ítem + checkboxes A3→A4 | — | Ya | — |

**T0:** consolidación multi-ítem y checkboxes para Anexo 4 ya existen (regresión al cerrar T6).

**T4** baja de prioridad frente a T6: el PDF oficial es el del SIGA; pdfmake queda como apoyo visual, no como documento de firma.

---

## Tickets detallados

### T1 — Validación de techo presupuestal al guardar (Crítica) — HECHO

**D1 aplicada:** mensaje claro + **bloqueo**; no se persiste hasta corregir el monto.

**Implementado (2026-09-18)**
- **script:** `F002` — error `51129 TECHO_SALDO` si inclusiones (año base) por meta/fuente/clasificador superan el saldo de `siga.vwTechoPresupuesto` (fase 5).
- **front:** `modal-registro` muestra saldo vs solicitado y bloquea el guardado antes del viaje al servidor.

**Aceptación**
1. Saldo 20 000 y monto 100 000 → no guarda; mensaje con saldo; usuario no continúa.
2. Tras bajar el monto ≤ saldo → guarda.
3. Tras actualizar marco en SIGA, el siguiente guardado usa el saldo nuevo.

---

### T2 — Visto bueno del especialista sin firma digital (Alta)

**D2 aplicada:** sí.

**Trabajo**
- **semilla `S041`:** `CMN_ABAST_ESP_FIRMAR_A3` → `RequiereFirma = 0` (acción tipo “Validar / V.B.”); quitar especialista de firmantes digitales del A3 si aplica. Firma digital del **jefe** en A3 (si sigue escribiendo SIGA) y circuito A4 según T5/T6.
- **front:** botón sin firmador para el especialista.
- **SSO:** confirmar PE102 secretaria Abast (S021/S034 ya modelan el rol).

**Semillas:** `S041__cmn_vb_especialista_sin_firma.sql`.

**Depende de:** — (D2 cerrada).

**Aceptación**
1. Especialista valida A3 sin token.
2. Jefe firma donde el flujo lo exija.
3. Secretaria deriva sin firmar.
4. Desaparece el vaivén “enviar → devolver para firmar → reenviar” por el A3 del especialista.

---

### T3 — Tipo Ordinaria / Extraordinaria editable en Abast (Alta) — HECHO (local)

**D3 aplicada:** solo **antes de generar Anexo 4**.

**Implementado**
- **script:** `cmn.paCambiarTipoInclusion` en F002 — roles Abast (especialista/coord/jefe); estados pre-A4; rechazo si hay paquete/documento A4; historial + auditoría.
- **back:** `POST api/cmn/cambiarTipoInclusion`.
- **front:** combo + justificación en modal detalle; bandeja refresca tras guardar.
- **semilla:** `S042` documenta el ticket (sin filas de Transicion).

**Semillas:** `S042__cmn_abast_cambia_tipo_solicitud.sql`.

**Depende de:** T1 recomendado antes (misma zona CMN).

**Aceptación**
1. Abast cambia Extraordinaria → Ordinaria sin devolver a AU.
2. Con Anexo 4 ya generado → no permite el cambio.
3. El A4 posterior usa el tipo corregido (reglas de paquete / viernes).

---

### T4 — Limpieza del PDF auxiliar (pdfmake) (Media, paralelo)

**Alcance acotado por D5:** el oficial es el del SIGA. Esto solo limpia el PDF de apoyo en pantalla.

**Trabajo**
- **front:** `anexo4.pdfmake.ts` — quitar pies de borrador; bloques de firma alineados a la config de T5 (1 o 2).

**Semillas:** ninguna.

**Depende de:** puede ir en paralelo; reabrir tras T5 si cambia el número de firmantes.

**Aceptación:** PDF auxiliar sin textos provisionales; coherente con firmantes configurados.

---

### T5 — Administración de firmantes del Anexo 4 (Alta)

**D4 aplicada:** config en BD + pantalla ADMIN (patrón mantenimiento tipo campos TDR por defecto) + lectura al **generar Anexo 4**.

**Trabajo**
- **script / DDL:** tabla de configuración vigente para firmantes del Anexo 4 (orden, rol/perfil, activo, vigencia o “configuración actual”). Al generar A4, `F007` (o equivalente) **materializa** `TipoDocumentoFirma` / `RolFirmaRequerida` del paquete según esa config (snapshot del momento de generación).
- **front (ADMIN_SISTEMA):** pantalla de mantenimiento para alta/baja/orden de firmantes (misma idea que administrar defaults del TDR: listar, editar, guardar).
- **API:** rutinas listar/guardar config (F00x nuevo o extensión panel admin).
- **back:** si tras la 1.ª firma queda pendiente la 2.ª → correo al rol/bandeja correspondiente.

**Semillas:** `S043__cmn_firmantes_anexo4.sql` — config inicial (p.ej. solo `ABAST_JEFE`); módulo/permiso admin si hace falta.

**Depende de:** T2 (flujo Abast estable). Antes o junto a T6 (T6 necesita saber cuántas firmas aplicar al PDF traído del SIGA).

**Aceptación**
1. Admin cambia de 1 a 2 firmantes (o cambia el 2.º rol) sin redeploy.
2. Un Anexo 4 **generado después** del cambio usa la nueva config.
3. Un Anexo 4 ya generado conserva su snapshot de firmantes.
4. Caso 2 firmas: no finaliza hasta completar ambas.

---

### T6 — Descargar Anexo 4 desde SIGA → archivo → firmar en SGCM (Alta)

**D5 aplicada:** el SGCM **no** usa el pdfmake como documento a firmar. Flujo objetivo:

```
Consolidar / obtener A4 en SIGA
        ↓
SGCM descarga el formato emitido por SIGA
        ↓
Sube el PDF al file server (documento del expediente/paquete)
        ↓
Motor de firmas SGCM (F003 + config T5) sobre ESE archivo
        ↓
Cierre + notificaciones
```

**Trabajo**
- **Investigación / SIGA:** cómo obtener el PDF oficial (ruta de archivo en BD SIGA, USP, share, o exportación). Pico técnico obligatorio antes de cerrar el diseño de `usp_ext_*` / bridge.
- **script:** tras `CONSOLIDAR_CMN` (o paso dedicado): operación para “traer PDF A4 SIGA” → registrar documento `ANEXO4_OFICIAL_SIGA` (o reemplazar versión); estado intermedio tipo “A4 listo para firma” vs `CMN_FINALIZADO`.
- **back:** servicio que descarga desde SIGA y graba en el file server (patrón `UT_File` / documentos actuales).
- **front:** la acción “Generar / preparar Anexo 4” dispara ese tramo; la UI de firma trabaja sobre el PDF ya almacenado (flujo de firma existente).
- **Notificaciones al completar firmas:** ver T7 (destinatarios unificados).

**Semillas:** `S044__cmn_a4_desde_siga_y_firmas.sql` (estados, tipo documento, transiciones; alinear con S020).

**Depende de:** T5 (quién firma); T2. **Bloqueante externo:** mecanismo real de descarga desde SIGA.

**Aceptación**
1. Tras preparar A4, el archivo en servidor es el emitido por SIGA (no solo pdfmake).
2. Las firmas digitales se aplican a ese archivo con el motor actual del SGCM.
3. Sin PDF SIGA no se inicia el circuito de firmas oficiales.
4. Al completar firmas, el expediente cierra y queda el documento para Transparencia.

**Riesgo:** si SIGA no expone el PDF de forma automatizable, T6 se bloquea hasta que ANIN/MEF indique ruta o API.

---

### T7 — Reintentar A4 desde SIGA cuando falló (Media)

**D6 aplicada:** botón de **recuperación**, no cierre inventado.

**Trabajo**
- **front:** acción “Actualizar / reintentar Anexo 4 desde SIGA” visible para Abast cuando la integración o la descarga falló (outbox en error, sin archivo, etc.).
- **script + back:** reejecuta el tramo de T6 (recrear registro A4 en SIGA si aplica + descargar PDF + insertar en file server). Auditoría del reintento.
- **Firmas:** una vez el PDF está en el servidor, el flujo de firmas (T5) continúa igual.
- **Notificaciones al guardar / completar:**  
  - **Para:** jefe de Área Usuaria, especialista de Área Usuaria  
  - **Copia (CC):** especialista de Abastecimiento, jefe de Abastecimiento  
  Ampliar/ajustar `F013` (hoy más acotado a AU / punto focal).

**Semillas:** `S045__cmn_reintento_a4_siga.sql` + ajustes de notificación en F013 o `S046` si hace falta.

**Depende de:** T6 (misma tubería de descarga). Destinatarios de correo pueden implementarse junto con T6.

**Aceptación**
1. Con fallo simulado de A4/SIGA, el botón recrea el PDF en el file server.
2. Después se puede firmar con las firmas configuradas.
3. Al completar: correos a jefe AU + especialista AU, CC especialista Abast + jefe Abast.
4. Queda traza de reintento en auditoría.

---

## Orden de ejecución recomendado (con D1–D6 cerradas)

```
T1 techo (bloqueo UX)
    │
    ▼
T2 V.B. especialista sin firma
    │
    ├─► T3 tipo solicitud (solo pre-A4)
    │
    ├─► T4 PDF auxiliar (paralelo, menor)
    │
    ▼
T5 admin firmantes A4 (BD + pantalla ADMIN)
    │
    ▼
T6 descargar A4 SIGA → file server → firmas SGCM
    │     (pico: ¿cómo se obtiene el PDF del SIGA?)
    ▼
T7 reintento A4 desde SIGA + notificaciones finales
```

**Release mínimo (demo fallas del 16/09):** T1 + T2 + T3.  
**Release firmas configurables:** + T5.  
**Release documento oficial SIGA:** + T6 + T7 (+ T4 opcional).

---

## Semillas propuestas (nombres tentativos)

| Archivo | Ticket |
|---|---|
| `S041__cmn_vb_especialista_sin_firma.sql` | T2 |
| `S042__cmn_abast_cambia_tipo_solicitud.sql` | T3 |
| `S043__cmn_firmantes_anexo4.sql` | T5 |
| `S044__cmn_a4_desde_siga_y_firmas.sql` | T6 |
| `S045__cmn_reintento_a4_siga.sql` | T7 |

API / piezas clave: `F002` (T1, T3), `F007` (T3, T5, T6), `F003` (T5/T6 firmas), `F013` (T6/T7 correos), `W001` + `usp_ext_aprobar_solicitud_cmn` (T6/T7), panel admin + file server (T5/T6).

---

## Fuera de alcance / riesgos abiertos

- Reescribir el CMN desde cero.
- Cambiar el protocolo HTTP global del puente (D1 no lo pide).
- **T6 bloqueante:** aún no hay en el repo un USP/endpoint que **devuelva el PDF** del Anexo 4 tal como lo emite el cliente SIGA. Hay que descubrirlo con ANIN/SIGA antes de comprometer fecha de T6.
- No mezclar con `ejecucion.Incidencia` (módulo ejecución contractual).

---

## Próximo paso

1. ~~Arrancar **T1**~~ → hecho.  
2. ~~Arrancar **T2**~~ → hecho en local (`S041` + icono V.B. en bandeja).  
3. ~~Arrancar **T3**~~ → hecho en local (`paCambiarTipoInclusion` + combo en detalle).  
4. ~~**T4**~~ → hecho (PDF auxiliar sin pie «generado por»; firmas según snapshot).  
5. ~~**T5**~~ → hecho en local (`V035`/`F019`/`S043` + pantalla `mantenimiento-firmantes-a4`).  
6. ~~**T6**~~ → flujo manual local (`S044`): sin firma digital del PDF SGCM → `CONSOLIDAR_CMN` → estado `CMN_A4_PEND_DOC_SIGA` → subir PDF firmado del SIGA → correo + `CMN_FINALIZADO`.  
7. **T7** reintento automático de descarga: no aplica (no hay API PDF); el correo al cerrar ya corre en la subida (F013).
