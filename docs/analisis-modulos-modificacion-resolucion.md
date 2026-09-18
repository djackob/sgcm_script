# Módulos Modificación-Ampliación y Resolución — análisis y diseño

Fecha: 2026-09-17. Fuentes: Directiva N.° 002-2026-ANIN §7.3.4, §7.3.5, §7.3.7 y
§7.3.8 (pp. 15-19); Bizagi `4. MODIFICACION-AMPLIACION` y los cinco diagramas
de `5. RESOLUCION` del flujo v5.0. Se construyen juntos porque son **flujos
alternos del mismo contrato en ejecución** (módulo 3) y comparten las mismas
decisiones de diseño.

---

## 1. Qué dice la Directiva, y qué dice el Bizagi

### 1.1 Modificación al contrato (7.3.4)

| Regla | Fuente | Consecuencia |
|---|---|---|
| Las partes pueden modificar el contrato si no aumenta el monto ni desnaturaliza el requerimiento. | 7.3.4.1 | La solicitud puede nacer del **proveedor** o del **área usuaria** — los dos «Inicio» del Bizagi. |
| La modificación la **sustenta y justifica el AU ante la DEC**; si no, se rechaza. | 7.3.4.2 | El AU siempre pasa: si el proveedor pide, el AU evalúa y sustenta o rechaza; si el AU inicia, elabora el sustento directamente. |
| La DEC revisa, determina procedencia y, si es conforme, emite el **acta de modificación suscrita por ambas partes**, registrada en Pladicop. | 7.3.4.3 | Estados de la DEC: evaluar → acta → firma del jefe de Abastecimiento → **suscripción del proveedor** → notificar. La denegatoria también se notifica. |

Bizagi: «Para ampliación de plazo no se requiere acta» (nota del diagrama). El
gateway «¿Es ampliación de plazo?» separa los dos caminos desde mesa de partes.

### 1.2 Ampliación del plazo (7.3.5)

| Regla | Fuente | Consecuencia |
|---|---|---|
| El contratista la pide por carta, por mesa de partes, dentro de los **10 días hábiles** siguientes de finalizado el hecho generador; fundamentada y con la cuantificación del plazo. | 7.3.5.1 | Campos: fecha de fin del hecho generador, días solicitados, sustento. El sistema calcula si entró en plazo. |
| La DEC remite al AU en **2 días hábiles**; el AU informa en **3 días hábiles**, privilegiando el criterio técnico. | 7.3.5.2 | Dos plazos sobre el expediente. |
| Fuera de plazo o sin medios probatorios, la DEC **deniega sin pronunciamiento del AU**. | 7.3.5.3 | Salida directa desde la DEC antes de pedir opinión. |
| La DEC decide y notifica por **correo institucional** en **7 días hábiles**; sin pronunciamiento, **se entiende aceptada**. | 7.3.5.4 | Plazo global de 7 hábiles; vencido, la rutina no admite denegar. Notificación por correo con el mismo puente que el Anexo 4. |

### 1.3 Resolución (7.3.7) — cinco diagramas, una máquina

| Causal | Fuente | Diagrama | Quién inicia | Apercibimiento previo |
|---|---|---|---|---|
| a) Incumplimiento de obligaciones | 7.3.7.1.a, 7.3.7.2 | INCUMPLIMIENTO | AU informa hechos → DEC | **Sí**: carta notarial con plazo de 10 %–15 % del plazo vigente (mín. 3 días si el plazo < 30); redondeo a favor del contratista. Vencido sin cumplir → resuelve. |
| f) Penalidades > 10 % | 7.3.7.1.f, 7.3.7.2.d | ACUMULACION MAXIMA DE PENALIDAD | AU informa causal → DEC | **No** (7.3.7.2.d) |
| b) c) d) e) | 7.3.7.1, 7.3.7.3 | *(sin diagrama propio)* | AU, opinión favorable | **No**; carta simple al correo |
| Hecho sobreviniente pedido por el proveedor | 7.3.7.1.c | HECHO SOBRESALIENTE | Proveedor → AU informe técnico | No; AU puede negar → carta de respuesta negando |
| Mutuo acuerdo | 7.3.7.1 último párrafo, 7.3.7.4 | MUTUO ACUERDO | Proveedor → AU pronunciamiento | No; AU puede negar |
| Unilateral por fines institucionales | 7.3.7.4 | RESOLUCION UNILATERAL | AU, debidamente sustentado → DEC | No |

Común a todas: la resolución puede ser **total o parcial** y la parcial debe
precisar qué parte queda resuelta; si no lo precisa, es total (7.3.7.5). Las
cartas se notifican de forma **notarial o por PLADICOP** (7.3.7.2.e); en los
casos del 7.3.7.3, por **correo**.

**7.3.8 Nulidad**: la declara la AGA con carta notarial. No es un flujo del
sistema —no hay bandeja ni evaluación—; se deja fuera y se anota.

## 2. Decisiones de diseño

### 2.1 Cuelgan del contrato de Ejecución

Las dos solicitudes existen **sobre un `ejecucion.Contrato` vigente**. Ese es
el enlace con lo ya construido y lo que evita repetir proveedor, plazo y monto:
todo se lee del contrato. Cada solicitud es un `sigcm.Expediente` propio con
`IdExpedientePadre` = contrato, igual que las entregas.

- La **ampliación aprobada** actualiza `Contrato.FechaFinPrevista` y amplía el
  plazo `EJE_EJECUCION_CONTRATO` (`AmpliadoHasta`), que es exactamente lo que
  `sigcm.Plazo` ya sabe hacer.
- La **resolución consumada** cierra el contrato: nuevo estado `EJE_RESUELTO`
  (final) y transición `EJE_RESOLVER`, que ejecuta la rutina de resolución y no
  una persona desde la pantalla de Ejecución.

### 2.2 Un módulo para modificación y ampliación

El Bizagi los dibuja en el mismo diagrama y el esquema reservado se llama
`ampliacion`; el módulo `MODIFICACION` de `sigcm.Modulo` los cubre a los dos.
Una sola tabla `ampliacion.Solicitud` con `Tipo` = `MODIFICACION` |
`AMPLIACION_PLAZO` y dos cadenas de estados (`MOD_*`, `AMP_*`), porque sus
reglas y plazos no coinciden en nada salvo el origen.

### 2.3 Mesa de partes = portal

Misma decisión que en Ejecución: la carta del proveedor entra por el portal
(mesa de partes virtual, 7.3.5.1) y llega directo a quien evalúa. El rol
`MESA_PARTES` no interviene.

### 2.4 El acta la firma la DEC en el sistema y el proveedor la suscribe

«Suscrita por ambas partes» (7.3.4.3): el jefe de Abastecimiento firma
digitalmente el acta (firmador, `RequiereFirma`), y el proveedor la **acepta
desde el portal** —transición propia, sin dispositivo—. La aceptación queda en
el historial con quién y cuándo, que es lo que el acta necesita. El PDF es un
formato propio: la Directiva no trae anexo para el acta ni para las cartas.

### 2.5 El apercibimiento se calcula, no se teclea

`PlazoApercibimientoDias` sale de la Directiva 7.3.7.2.b: entre el 10 % y el
15 % del plazo vigente (o del entregable), redondeado **hacia arriba**, y tres
días si el plazo es menor a 30. La DEC elige dentro de ese rango; fuera de él
la rutina no lo acepta. Si el plazo vence sin respuesta, la DEC lo declara
vencido y pasa a resolver; si el proveedor responde, el AU evalúa si subsanó.

### 2.6 Notificaciones por correo

Las decisiones de ampliación (7.3.5.4) y las cartas simples del 7.3.7.3 se
notifican por correo con el **mismo puente** que el Anexo 4 y la orden:
la rutina arma el sobre, el controlador lo envía y vuelve a marcar el
resultado. El puente se generaliza en `ControladorPuente.NotificarPorCorreo`
para no copiar 120 líneas por cada aviso. La notificación **notarial** o por
PLADICOP se registra —número de carta, fecha, medio— pero la hace una persona.

## 3. Máquinas de estados

### Modificación (`MOD_*`)

```
Proveedor pide                 AU inicia
MOD_PRESENTADA (AU esp) ──►    MOD_EN_SUSTENTO_AU (AU esp)
  │ rechaza (informe) ──► MOD_RECHAZADA_AU (AU jefe firma) ──► MOD_EN_EVALUACION_DEC
  └ acepta ──► MOD_EN_SUSTENTO_AU ──► MOD_POR_REMITIR_AU (AU jefe) ──► MOD_EN_EVALUACION_DEC (DEC esp)
MOD_EN_EVALUACION_DEC ─ conforme ──► MOD_POR_FIRMA_ACTA (Abast jefe, firma acta)
                                        └──► MOD_POR_SUSCRIPCION (proveedor acepta) ──► MOD_APROBADA (fin, notifica)
                      ─ no conforme ──► MOD_DENEGADA (fin, carta, notifica)
```

### Ampliación (`AMP_*`)

```
AMP_PRESENTADA (DEC esp, 2 hábiles)
  ├ fuera de plazo / sin sustento ──► AMP_DENEGADA (fin, carta por correo)
  └ remite ──► AMP_EN_OPINION_AU (AU esp, 3 hábiles) ──► AMP_EN_DECISION_DEC (DEC esp, 7 hábiles desde la solicitud)
                                                            ├ aprueba ──► AMP_APROBADA (fin; nueva fecha fin; correo)
                                                            └ deniega ──► AMP_DENEGADA (fin; correo) — no admitido si venció el plazo (aceptación tácita)
```

### Resolución (`RES_*`)

```
AU informa (a, b, c, d, e, f, unilateral)        Proveedor pide (mutuo acuerdo, hecho sobreviniente)
RES_INFORMADA (AU jefe remite)                    RES_SOLICITADA (AU esp opina)
  └──► RES_EN_EVALUACION_DEC (DEC esp)              ├ desfavorable ──► RES_DENEGADA (fin, carta negando)
                                                    └ favorable ──► RES_EN_EVALUACION_DEC
RES_EN_EVALUACION_DEC
  ├ desestima ──► RES_DESESTIMADA (fin)
  ├ apercibe (solo causal a, reversible) ──► RES_POR_FIRMA_APERCIBIMIENTO (Abast jefe firma carta)
  │      └──► RES_APERCIBIDO (proveedor, plazo 10–15 %)
  │             ├ responde ──► RES_RESPUESTA_EN_EVALUACION (AU esp)
  │             │                 ├ subsanó ──► RES_SUBSANADO (fin)
  │             │                 └ no subsanó ──► RES_POR_RESOLVER
  │             └ vence sin respuesta (DEC) ──► RES_POR_RESOLVER
  └ resuelve directo (7.3.7.2.d, 7.3.7.3, mutuo, unilateral) ──► RES_POR_RESOLVER (Abast jefe firma carta)
RES_POR_RESOLVER ──► RES_RESUELTO (fin; contrato → EJE_RESUELTO)
```

## 4. Pantallas

Dos rutas, `gestion-modificacion` y `gestion-resolucion`, con el mismo
criterio que las otras cuatro: bandeja con `MeToca`, detalle en modal, acciones
desde `Transiciones`, textos sólo de campos y errores. Las solicitudes se
**inician desde el detalle del contrato** en Ejecución («Solicitar
modificación», «Solicitar ampliación», «Informar causal de resolución»,
«Solicitar resolución») para que nazcan siempre atadas a un contrato vigente,
y se trabajan en su propia bandeja.

Documentos generados en el navegador con pdfmake, como los Anexos: **Acta de
modificación**, **Carta de respuesta** (ampliación aprobada/denegada,
modificación denegada, resolución negada), **Carta de apercibimiento** y
**Carta de resolución**. Firma digital del jefe de Abastecimiento en el acta y
en las dos cartas de resolución; con `firma.omitir_dispositivo` en `true`
(local) el paso avanza con el PDF sin firmar y la firma queda registrada, como
en los otros módulos.

## 5. Fuera de alcance

- Nulidad del contrato (7.3.8): acto de la AGA con carta notarial, sin flujo.
- Registro en Pladicop del acta y de las resoluciones (Directiva §9): no hay
  interfaz; se anota el número de registro si lo hubiera.
- Efecto de la resolución sobre los expedientes de pago abiertos: se anota en el
  contrato; Pagos decide qué hacer con los entregables pendientes.
