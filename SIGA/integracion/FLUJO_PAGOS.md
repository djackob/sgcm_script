# Entregables y pagos: el flujo, y qué se integra con SIGA

> Para **recorrerlo** paso a paso con las cuentas de prueba, y encadenado con
> CMN y Requerimiento, está `RECORRIDO_PRUEBAS.md` en la raíz del repositorio.
> Este documento explica el porqué; aquél es el guion.

Escrito el **2026-09-03**. Todo lo que se afirma aquí está verificado contra
`SIGA_1750` (ejercicio 2026, ejecutora 1750) o contra `DBSIGCM`. Los conteos son
consultas reales.

---

## 1. De dónde nace un expediente de pago

No se crea a mano. Al notificar la orden de servicio (paso 16 del recorrido de
requerimiento), `paMarcarOrdenNotificada` llama a
`pago.paAbrirDesdeOrdenServicioInterno`, que abre **un expediente por cada
entregable** declarado en el Anexo 5 (`CantidadEntregables` del proveedor).
También se dispara solo cuando el locador entra al portal externo, porque
`paListarPortalLocador` lo cruza por DNI, RUC o correo contra el proveedor.

Tres entregables son tres expedientes independientes, cada uno con su ciclo
completo y su propia penalidad.

## 2. El flujo, paso por paso

| # | Perfil (cuenta de prueba) | Desde | Acción | Hasta |
|---|---|---|---|---|
| 1 | `PROVEEDOR` (locador, portal externo) | `PAG_PENDIENTE` | Presentar entregable y RHE | `PAG_ENTREGABLE_PRESENTADO` |
| 2 | AU · Especialista (46183970) | `PAG_ENTREGABLE_PRESENTADO` | Aprobar conformidad técnica | `PAG_CONFORMIDAD_PEND_FIRMA` |
| 3 | AU · Jefe (44687266) | `PAG_CONFORMIDAD_PEND_FIRMA` | **Firmar** Acta de Conformidad (Anexo 11) | `PAG_CONFORMIDAD_APROBADA` |
| 4 | Abast · Especialista / Coordinador (45648851 / 42551460) | `PAG_CONFORMIDAD_APROBADA` | Completar checklist y liquidar (Anexos 9 y 10) | `PAG_EXPEDIENTE_LIQUIDADO` |
| 5 | Contabilidad (17400217) | `PAG_EXPEDIENTE_LIQUIDADO` | Registrar devengado SIAF / MADAF | `PAG_DEVENGADO_APROBADO` |
| 6 | Tesorería (10712503) | `PAG_DEVENGADO_APROBADO` | Registrar giro SIAF y abono CCI | `PAG_PAGO_EFECTUADO` |

**Rutas de observación**

| Desde | Quién | Acción | A dónde | Vuelta |
|---|---|---|---|---|
| `PAG_ENTREGABLE_PRESENTADO` | AU · Especialista | Observar entregable *(comentario obligatorio)* | `PAG_OBSERVADO_AU` | el locador subsana |
| `PAG_EXPEDIENTE_LIQUIDADO` | Contabilidad | Devolver a DEC | `PAG_OBS_UC_DEC` | 45648851 remite subsanado |
| `PAG_EXPEDIENTE_LIQUIDADO` | Contabilidad | Devolver al Área usuaria | `PAG_OBS_UC_AU` | 46183970 / 44687266 remite subsanado |

**Lo que decide cada paso**

- **1 · Presentar.** Informe PDF + RHE en PDF y XML obligatorios. SUNAT y
  rendiciones son *stub*: no hay API cableada.
- **2 · Conformidad técnica.** Aquí se calcula el atraso
  (`FechaPresentacion − FechaLimiteCronograma`). El especialista puede marcar
  `RetrasoJustificado` y entonces no habrá penalidad. Es la decisión más cara
  del flujo.
- **3 · Firma.** Única transición del módulo con `RequiereFirma = 1`.
- **4 · Liquidación.** Anexo 9: los 8 ítems obligatorios en «SÍ» o «No aplica».
  Anexo 10: penalidad diaria `= (0.10 × monto) ÷ (0.40 × plazo)`. Si la suma de
  penalidades del contrato supera el **10 %**, corta con `ALERTA_RESOLUCION`.
- **6 · Giro.** Exige CCI, Nota de Pago SIAF y constancia; papeleta si hubo
  penalidad. Neto `= monto − penalidad − 8 % si retiene 4ta`.

**Plazos** (`sigcm.PlazoRegla`): revisión AU 7 días calendario · liquidación DEC
3 hábiles · control previo UC 2 hábiles · **pago global 10 hábiles** (+5
justificados) desde la conformidad.

### Los tres anexos del módulo

Los tres son **réplicas** del formato de la Directiva N.° 002-2026-ANIN, no
formularios inspirados en ella (ESTANDARES §4.7). Se generan en el navegador, se
suben al file server y se registran en el expediente; lo que el visor muestra es
el archivo del servidor, no el que quedó en memoria.

| Anexo | Página | Quién lo emite | Cuándo | Firma |
|---|:--:|---|---|---|
| 11 · Acta de Conformidad | 51 | Jefe del Área usuaria | `PAG_CONFORMIDAD_PEND_FIRMA` | **sí**, digital |
| 9 · Check list de control de pagos | 48-49 | DEC (Abastecimiento) | `PAG_CONFORMIDAD_APROBADA` | no |
| 10 · Determinación de penalidades | 50 | DEC (Abastecimiento) | `PAG_CONFORMIDAD_APROBADA` | no |

El Anexo 9 de la Directiva tiene **trece filas** y `pago.ChecklistItem` **diez
ítems**: no son la misma lista. El PDF marca las que se corresponden con lo que
registró la DEC y deja en blanco las que la Directiva pide y el sistema no
captura —hoja de liquidación de pagos periódicos, guía de remisión, TDR, recibo
de servicios básicos—, que es lo que hoy se completa a mano sobre el papel.
Homologar las dos listas es una decisión de negocio pendiente.

El Anexo 10 no recalcula nada: toma los importes que dejó
`pago.paLiquidarExpediente`, que es quien aplica la fórmula de la Directiva.
«Otras penalidades [B]» queda en blanco porque son supuestos del TDR que el
sistema todavía no captura.

### La bandeja no pierde de vista lo que ya pasó por la unidad

`paListarPago` filtraba por `IdUnidadActual`, así que al firmar el Anexo 11 el
expediente se iba a Abastecimiento y **desaparecía** de la bandeja del área
usuaria. Eso deja ciego a quien todavía puede recibirlo de vuelta observado
(`PAG_OBS_UC_AU`). Ahora la unidad ve además lo que registra el historial como
suyo: aparece sin `MeToca` y sin acciones, como expediente ya tramitado.

---

## 3. Qué tiene SIGA, de verdad, para un servicio

Se revisó tabla por tabla antes de decidir dónde escribir. Éste es el resultado:

| Qué se buscaba | Dónde miré | Qué hay |
|---|---|---|
| Estado de la orden | `SIG_ORDEN_ADQUISICION.ESTADO` | **Se usa.** `'1'` emitida (3 745), `'4'` anulada (58). Ninguna en `'0'` |
| Compromiso SIAF | `.ESTADO_SIAF` + `SIG_ORDEN_INTERFASE` | **Se usa.** `'2'` comprometida (3 801); la interfase tiene 3 898 filas en 2026 |
| Expediente SIAF | `.EXP_SIAF`, `.NRO_CERTIFICA` | **Se usa.** Poblados en 3 801 y 3 803 de 3 803 |
| Conformidad / recepción | `.FLAG_RECEPCION`, `.FECHA_RECEPCION` | **Se usa poco pero se usa:** 82 órdenes en `'S'` con su fecha |
| Devengado | `SIG_DEVENGADO`, `_ITEM`, `_SECUENCIA` | **Vacías.** 1 sola fila en toda la base, de 2024 |
| Penalidades | `SIG_DEVENGADO_PENALIDAD_OTROS`, `SIG_CONTRATO_PENALIDAD_OTROS` | **Vacías** |
| Giro / cancelación | `.FECHA_CANCEL`, `SIG_TES_INTERFASE_CAB` | **Sin uso.** 0 y 0 |

**Conclusión:** el ANIN **devenga y gira en SIAF, no en SIGA**. De SIGA sólo se
mantiene vivo el ciclo de la orden: emisión, compromiso y —a veces— recepción.

---

## 4. El cuadro de integración, hito por hito

Los cinco hitos son los que ya definía `F012`. Lo que cambia es que ahora se
sabe cuáles tienen contraparte:

| Hito | Cuándo se dispara | Dirección | Objeto en SIGA | Estado | Dónde vive |
|:--:|---|---|---|---|---|
| **1** · Activa O/S | al abrir el expediente y al consultarlo | **SIGA → SGCM** | `SIG_ORDEN_ADQUISICION.ESTADO` + `ESTADO_SIAF` + `SIG_ORDEN_INTERFASE` | **Implementado** | `V030` + `F014.paSincronizarOrdenSiga` |
| **2** · Conformidad | al firmar el Anexo 11 (`PAG_FIRMAR_ANEXO11`) | **SGCM → SIGA** | `FLAG_RECEPCION = 'S'` + `FECHA_RECEPCION` | **Implementado** | `usp_ext_registrar_recepcion_orden` + `W004` + `F014.paEncolarRecepcionOrden` |
| **3** · Penalidades | al liquidar | — | **no existe destino** | No se implementa | queda en `pago.ExpedientePago` |
| **4** · Devengado | al consultar el expediente | **SIGA → SGCM** | `EXP_SIAF`, `NRO_CERTIFICA` | **Implementado** | `F014.paSincronizarOrdenSiga` |
| **5** · Pago cerrado | al girar | — | **no existe destino** | No se implementa | queda en `pago.ExpedientePago` |

Los hitos 3 y 5 **no se implementan a propósito**: escribir en columnas que
nadie lee sería inventar una integración. Cuando el ANIN empiece a devengar en
SIGA, el sitio es `SIG_DEVENGADO` y este documento hay que corregirlo.

### El cambio de fondo en el hito 4

Hoy Contabilidad **teclea** el N.º de expediente SIAF en nuestra pantalla. SIGA
ya lo tiene en `EXP_SIAF` para 3 801 de 3 803 órdenes. La sincronización lo lee
y lo deja disponible: el dato deja de depender de que alguien lo copie bien.

### Por qué el hito 2 escribe y los demás no

Porque la recepción es un hecho del expediente logístico y tiene columna propia
que el ANIN usa. En cambio **aprobar la orden y comprometerla en SIAF no lo
hacemos nosotros**: eso es de Logística dentro de SIGA, tiene permiso por
usuario (`USERS_OPCION`, 93 personas con la opción de autorización) y el
compromiso llega al MEF por `SIG_ORDEN_INTERFASE`. El SGCM **espera y verifica**
ese estado; no lo fuerza. Es la misma línea que la sección 6 de
`FLUJO_CMN_A_REQUERIMIENTO.md`.

---

## 5. Cómo viaja la recepción (hito 2)

```
  Jefe AU firma el Anexo 11
        │
        ▼
  pago.paMarcarConformidadFirmada
        │  EXEC pago.paEncolarRecepcionOrden
        ▼
  integracion.Operacion  Operacion = 'REGISTRAR_RECEPCION_OS'
        │                IdempotenciaKey = pago:{IdExpedientePago}:RECEPCION_OS
        ▼
  integracion.paEscribirRecepcionOrden   (W004, Modo = real | simulacion)
        │
        ▼
  siga.usp_ext_registrar_recepcion_orden
        │
        ▼
  SIG_ORDEN_ADQUISICION   FLAG_RECEPCION = 'S', FECHA_RECEPCION
```

Tres decisiones que conviene no deshacer:

- **Se encola, no se escribe en línea.** Si SIGA no responde, la conformidad no
  puede quedarse esperando. La cola reintenta; el hito queda en `PENDIENTE`.
- **Es idempotente en los dos extremos.** Varios entregables de la misma orden
  encolan su propia operación: el primero marca la recepción y los demás la
  encuentran hecha. `@Aplicados = 0` no es un fallo, y el hito de cada
  expediente igual queda anotado.
- **Un expediente sin orden en SIGA no encola nada.** Es el caso de los datos
  sembrados por `S909`: el hito 2 queda en `SIMULADO` diciendo que la
  conformidad vive sólo en el SGCM.

## 6. Estado de la integración

**Probada contra SIGA el 2026-09-03.** Se encoló la recepción de la orden 3809
(que estaba en `FLAG_RECEPCION = 'N'`) y se drenó en `Modo = real`:

```
ANTES     3809 | ESTADO 1 | ESTADO_SIAF 2 | FLAG_RECEPCION N | FECHA NULL
drenaje   {"Escritas":1,"Mensaje":"Recepcion conforme registrada en SIGA (FLAG_RECEPCION = S)."}
DESPUES   3809 | ESTADO 1 | ESTADO_SIAF 2 | FLAG_RECEPCION S | 2026-09-03
2do pase  {"Aplicados":0,"Mensaje":"La orden ya figuraba recibida en SIGA."}
```

El hito 2 quedó en `REGISTRADO` y la operación en `COMPLETADO / real`. La
idempotencia está comprobada en los dos extremos.

### El worker

Vive en `anin.scm/Services/IntegracionSigaWorker.cs` y se configura en la
sección `IntegracionSiga` de `appsettings.json`. **Esa sección no existía**: sin
ella `Habilitado` cae en `false`, que es la razón por la que la cola no se
drenaba sola. Ahora está declarada.

Dos cosas que hay que saber:

- **`appsettings.json` está versionado.** Con `Modo: "real"` el worker escribe en
  `SIGA_1750` cada 30 segundos sin que nadie apriete nada. Antes de llevar el
  archivo a otra copia, decidir si va encendido.
- El worker drena los cuatro escritores en orden: cuadro modificado, cuadro de
  adquisición, orden de servicio y **recepción**. Este último faltaba en la
  lista, así que aunque se encendiera el worker la recepción nunca salía.

Para drenar a mano, con el worker apagado:

```sql
EXEC integracion.paEscribirRecepcionOrden N'{"Modo":"real","Actor":{"Usuario":"44687266"}}';
```

## 7. Qué queda por decidir

1. **La pantalla muestra el estado de SIGA pero no bloquea.** Un expediente cuya
   orden sigue pendiente en SIGA se ve con la píldora en ámbar; si además debe
   impedirse liquidar es una regla de negocio que nadie ha tomado.
2. **La orden 3809 quedó marcada como recibida** por la prueba. Es una orden
   real de la copia de desarrollo y hay que devolverla a `'N'`.
