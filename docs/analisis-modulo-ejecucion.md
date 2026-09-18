# Módulo Ejecución contractual — análisis y diseño

Fecha: 2026-09-17. Fuentes: Directiva N.° 002-2026-ANIN §7.3 (ejecución
contractual, pp. 14-17) y el diagrama Bizagi `3. EJECUCION` del flujo v5.0.
Estado de partida: `dev_work_mrz` en la punta de `jack5`, base local al día.

---

## 1. Qué dice la Directiva

| Numeral | Regla | Consecuencia en el sistema |
|---|---|---|
| 7.3.1 | La ejecución empieza el día calendario **siguiente a la notificación** de la orden. Nunca antes. | `FechaInicio = NotificadoEn + 1`. El contrato nace cuando `REQ_NOTIFICAR_OS` se ejecuta, no antes. |
| 7.3.2 | El AU supervisa el cumplimiento conforme a EETT/TDR. | El expediente de ejecución vive en el área usuaria; su responsable es el especialista del AU. |
| 7.3.3 | El AU comunica a la DEC con documento (SGD) **toda incidencia, incumplimiento o riesgo**. | Registro de incidencias del contrato: AU registra, DEC atiende. |
| 7.3.6.1 | Conformidad en **7 días calendario** desde recibido el bien/entregable (20 en consultorías). | Plazo `EJE_CONFORMIDAD_BIEN` sobre la entrega recepcionada; el de servicios ya lo lleva Pagos (`PAG_REVISION_AU`). |
| 7.3.6.2 | Servicios: el contratista presenta el entregable por **mesa de partes física o virtual** dirigido al AU; el AU otorga conformidad con el Anexo 11. | **Ya implementado en Pagos**: el portal del locador es la mesa de partes virtual y `PAG_PRESENTAR → PAG_APROBAR_TECNICO → PAG_FIRMAR_ANEXO11` es este numeral. No se duplica. |
| 7.3.6.3.a | Bienes en **Sede Central**: el contratista ingresa el bien por el encargado de **Almacén** con Guía de Remisión; Almacén verifica EETT con apoyo del AU, que pone su **visto bueno en la guía**. | Ruta «almacén»: autorizar ingreso → acompañamiento del AU → verificar → recepcionar. |
| 7.3.6.3.b | Bienes en **otra ubicación**: recibe y suscribe la guía el **responsable designado por el AU**; después la guía suscrita se remite a Almacén para su firma. | Ruta «sede desconcentrada»: el AU autoriza, verifica y recepciona; Almacén cierra registrando la guía. |
| 7.3.6.3.c | Bienes observados al momento de la entrega: **retiro por el proveedor** previa suscripción de un **acta** por el proveedor, el AU y Almacén. | Estado `OBSERVADA` con documento `EJE_ACTA_INCUMPLIMIENTO` y cierre `RETIRADA`. |
| 7.3.6.3.d | Conformidad de bienes con el Anexo 11. | Tras la recepción, el proveedor presenta el entregable en Pagos, donde ya existe el Anexo 11. |
| 7.3.6.4 / .5 | Observaciones: plazo de subsanación ≤ 30 % del plazo del entregable; penalidad por mora si se agota. | Ya implementado en Pagos (`paObservarEntregable`, `FechaLimiteSubsanacion`). |

## 2. Qué dice el Bizagi (3. EJECUCIÓN)

Cuatro carriles: PROVEEDOR, MESA DE PARTES, ÁREA USUARIA, UNIDAD DE
ABASTECIMIENTO. Tres ramas a partir de «Ejecutar la OS u OC»:

```
¿Es servicio?
 ├─ Sí ─ Presentar entregable → Mesa de partes recepciona y deriva → AU evalúa
 │        ├─ sin observaciones → Informe de conformidad (Anexo 11) → [Iniciar pago del entregable] → Fin
 │        └─ con observaciones → Informe → DEC notifica al proveedor → proveedor responde → vuelve a ejecutar
 └─ No ─ Entregar bienes → ¿Sede Central?
          ├─ Sí ─ Transportar a Almacén → DEC autoriza ingreso → solicita acompañamiento → AU designa responsable
          │        → DEC verifica → ¿observaciones?
          │              ├─ Sí → Acta de incumplimiento → proveedor retira → Fin
          │              └─ No → DEC recepciona → Pecosa → entrega al AU → AU recepciona → Fin
          │                                     └→ Guía de Remisión suscrita → proveedor presenta entregable (rama servicio)
          └─ No ─ Transportar a Sede Desconcentrada → AU autoriza ingreso → AU verifica → ¿observaciones?
                       ├─ Sí → Acta de incumplimiento → proveedor retira → Fin
                       └─ No → AU recepciona → Guía suscrita → proveedor presenta entregable (rama servicio)
```

**Lectura clave:** la rama «servicio» del Bizagi *es* el módulo de Pagos ya
construido (`PAG_PENDIENTE → … → PAG_CONFORMIDAD_APROBADA`), y las dos ramas de
«bienes» desembocan en ella al «Presentar entregable». Lo que **falta** en el
sistema es exactamente lo que está a la izquierda de ese punto:

1. El **contrato en ejecución** como cosa propia: fecha de inicio, plazo, fin
   previsto, lugar de entrega, quién supervisa, cuánto se ha entregado.
2. La **entrega física de bienes** con sus dos rutas, sus actas y sus
   documentos (guía de remisión, guía suscrita, acta de incumplimiento,
   Pecosa).
3. Las **incidencias** del 7.3.3.

Y lo que **no hay que construir**: una segunda máquina de «presentar →
evaluar → conformidad», ni una mesa de partes separada del portal.

## 3. Decisiones de diseño

### 3.1 Dos unidades de trabajo, un esquema

| Entidad | Un expediente por… | Nace | Muere |
|---|---|---|---|
| `ejecucion.Contrato` | orden notificada (requerimiento) | `REQ_NOTIFICAR_OS`, automáticamente, igual que Pagos abre sus expedientes | `EJE_CULMINAR` (AU jefe) cuando todos los entregables tienen conformidad |
| `ejecucion.Entrega` | entrega física de bienes (una O/C puede tener varias) | el proveedor la anuncia con su guía de remisión | `RETIRADA`, `ENTREGADA_AU` o `GUIA_REGISTRADA` |

Cada uno es un `sigcm.Expediente` (módulo `EJECUCION`) con la entrega colgando
del contrato por `IdExpedientePadre`. Así el motor de transiciones, la
trazabilidad, los documentos y las firmas se reutilizan sin tocarlos: es la
misma decisión que tomó Pagos con un expediente por entregable.

### 3.2 Máquina de estados

**Contrato** — `EJE_VIGENTE` (inicial, AU especialista) → `EJE_CULMINADO`
(final). La resolución del contrato la registrará el módulo 5; aquí no se
inventa un estado que ninguna transición alcance.

**Entrega** — dos rutas que se eligen por `Contrato.LugarEntrega`:

```
Ruta ALMACÉN (Sede Central)                       Ruta SEDE (desconcentrada)
POR_AUTORIZAR_ALMACEN (DEC)                       POR_AUTORIZAR_SEDE (AU esp)
  └ AUTORIZAR_INGRESO_ALMACEN                       └ AUTORIZAR_INGRESO_SEDE
POR_DESIGNAR_VERIFICADOR (AU jefe)                EN_VERIFICACION_SEDE (AU esp)
  └ DESIGNAR_VERIFICADOR                            ├ OBSERVAR_SEDE → OBSERVADA
EN_VERIFICACION_ALMACEN (DEC)                       └ RECEPCIONAR_SEDE
  ├ OBSERVAR_ALMACEN → OBSERVADA (proveedor)      RECEPCIONADA_SEDE (DEC)
  └ RECEPCIONAR_ALMACEN                             └ REGISTRAR_GUIA_ALMACEN
RECEPCIONADA_ALMACEN (DEC)                        GUIA_REGISTRADA (final)
  └ ENTREGAR_AU (Pecosa)
ENTREGADA_AU (final)                              OBSERVADA (proveedor)
                                                    └ RETIRAR → RETIRADA (final)
```

El **enrutamiento de unidad** lo resuelve el módulo y no el motor: los estados
del AU vuelven a la unidad de origen del contrato, los de la DEC van a la
unidad que ejerce `ABAST_ESPECIALISTA`, los del proveedor a la unidad donde
ese proveedor tiene su rol. Se manda `IdUnidadDestino` explícito porque la
regla 3 del motor (unidad única *con centro de costo SIGA*) no dispara en un
ambiente donde Abastecimiento no tiene centro de costo cargado.

El **verificador designado** por el jefe del AU se guarda en la entrega
(`IdVerificador`), no como `IdResponsableDestino` del motor: el estado
siguiente es de Almacén, y el motor exige que la persona derivada ejerza el rol
del estado destino. Son dos cosas distintas —quién acompaña y de quién es el
turno— y se registran por separado.

### 3.3 Enlace con Pagos

Al anunciar una entrega el proveedor indica a qué **entregable del cronograma**
corresponde (`NumeroEntregable`), y la entrega guarda `IdExpedientePago`. Al
recepcionarla, ese expediente de pago sigue en `PAG_PENDIENTE` esperando que el
proveedor presente su comprobante: la ejecución no lo mueve, sólo lo apunta. El
detalle del contrato muestra los entregables con su estado de pago para que la
pregunta «¿ya se pagó lo que se entregó?» se conteste sin cambiar de pantalla.

### 3.4 Incidencias (7.3.3)

Tabla plana `ejecucion.Incidencia` con tres tipos —`INCIDENCIA`,
`INCUMPLIMIENTO`, `RIESGO`— y dos estados, `COMUNICADA` → `ATENDIDA`. No es
una máquina de estados del motor porque no mueve el expediente: es un registro
del contrato. El AU la registra citando el documento SGD; la DEC la atiende.

### 3.5 Roles

No se crea rol «Almacén»: la Directiva lo sitúa dentro de la DEC y el padrón
del SSO no lo distingue. Las acciones de almacén las ejercen
`ABAST_ESPECIALISTA` y `ABAST_COORDINADOR`. `MESA_PARTES` existe como rol pero
no interviene: la mesa de partes virtual es el portal.

### 3.6 Documentos y plazos

| Documento | Cuándo |
|---|---|
| `EJE_GUIA_REMISION` | el proveedor la sube al anunciar |
| `EJE_GUIA_REMISION_SUSCRITA` | al recepcionar (7.3.6.3.a/b) |
| `EJE_ACTA_INCUMPLIMIENTO` | al observar (7.3.6.3.c), requisito de la transición |
| `EJE_PECOSA` | al entregar el bien al AU |
| `EJE_INFORME_INCIDENCIA` | opcional en la incidencia |

Plazos: `EJE_EJECUCION_CONTRATO` (vencimiento = fin previsto del contrato; se
calcula en F016 porque el número de días es del contrato, no fijo) y
`EJE_CONFORMIDAD_BIEN` (7 días calendario desde la recepción).

## 4. Pantalla

Una sola ruta, `gestion-ejecucion`, con el criterio de las otras tres bandejas:

- **Bandeja de contratos**: código, requerimiento y O/S, proveedor, prestación,
  plazo (inicio → fin, días restantes o vencido), avance de entregables
  (conformes / total), estado con píldora, `MeToca`. Buscar por texto.
- **Detalle en modal** con pestañas: *Contrato* (ficha + lugar de entrega
  editable por el AU/DEC + acciones), *Entregas* (bienes: tabla de entregas con
  su estado y las acciones de cada una como iconos; formulario de anuncio para
  el proveedor), *Entregables* (los expedientes de Pagos, sólo lectura),
  *Incidencias*, *Trazabilidad*.
- Las acciones salen de `Transiciones` de la base, expediente por expediente
  (contrato y cada entrega). La pantalla no deduce nada del estado.
- Sin textos explicativos (§4.7). Lo que hay que saber va en comentarios del
  código.

## 5. Lo que queda fuera y por qué

- **Notificar observaciones del entregable al proveedor por la DEC** (rama
  servicio del Bizagi): en Pagos hoy el AU observa y el locador lo ve en su
  portal. Que la DEC intermedie es un ajuste de Pagos, no de este módulo.
- **Resolución** y **ampliación de plazo**: módulos 4 y 5.
- **Escritura en SIGA de la recepción de bienes**: `W004` ya escribe la
  recepción de la orden al firmar el Anexo 11; una entrega física recepcionada
  no tiene contraparte propia en SIGA distinta de esa.
