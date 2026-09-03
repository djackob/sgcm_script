# Del CMN al Requerimiento: qué pasa exactamente entre el Anexo 4 y el combo

Escrito el **2026-09-02** sobre la rama unida (`origin/dev_back`,
`origin/dev_front`, `origin/dev_script`, merge de Jack del 2026-09-01).

Todo lo que se afirma aquí está verificado contra el código de esa rama o contra
la base de desarrollo `192.168.40.75 / SIGA_1750` (ejecutora 1750, ejercicio
2026). Los conteos son consultas reales, no estimaciones.

---

## 0. La pregunta, respondida en una línea

> ¿Es el estado "Aprobado" lo que hace que un CMN se pueda pedir, o hace falta
> que un usuario de Logística mueva algo en el SIGA?

**Es el estado "Aprobado", y no hace falta ningún usuario de Logística.** La
firma del Anexo 4 por el Jefe de Abastecimiento en nuestro sistema ejecuta en
SIGA la misma aprobación que un logístico haría a mano desde *Consolidado del
C.M.N. → Aprobación de Solicitud de Modificación*. Lo que habilita el ítem no es
el cambio de estado de la solicitud en sí, sino el efecto colateral de esa
aprobación: `MOTIVO_SOLICITUD` vuelve a `'0'`.

La consolidación del PAAC —que sí es un proceso por lotes de Abastecimiento
dentro del SIGA— **no** hace falta para poder pedir. De las 5 837 inclusiones
aprobadas del 2026 sólo 4 406 están consolidadas, y todas son pedibles.

---

## 1. El flujo completo, tramo por tramo

```
  SIGCM (nuestro sistema)                     SIGA (SIGA_1750)
  ─────────────────────────                   ────────────────────────────────

  A. Área usuaria registra Anexo 3
     CMN_BORRADOR → … → CMN_A3_APROBADO
              │
              │  transición con OperacionIntegracion = 'ITEMS_ANEXO_3'
              ▼
     F004 encola INCLUIR_ITEM / EXCLUIR_ITEM
              │
              ▼
     W001 paEscribirCuadroModificado ──────►  usp_ext_incluir_item_cmn
                                              usp_ext_excluir_item_cmn
                                                     │
                                                     ▼
                                              SIG_CUADRO_MODIFICADO_DET
                                                ESTADO 'I' (ó 'E')
                                                MOTIVO_SOLICITUD '1' (ó '2')
                                                FLAG_MODIFICADO '1'
                                              SIG_SOLICITUD_MODIFICACION
                                                ESTADO '2'  ← "V.B. Jefe"
                                                            ← ítem NO pedible

  B. Abastecimiento arma y firma el Anexo 4
     CMN_A3_APROBADO
       → CMN_A4_FIRMA_COORD  (especialista genera)
       → CMN_A4_FIRMA_JEFE   (coordinador firma)
       → CMN_A4_ENVIADO      (JEFE firma)  ◄── AQUÍ está el cambio de estado
              │
              │  transición CMN_ABAST_JEFE_FIRMAR_A4
              │  OperacionIntegracion = 'CONSOLIDAR_CMN'
              ▼
     F004 encola CONSOLIDAR_CMN (una por expediente del paquete)
              │
              ▼
     W001 recorre integracion.MapeoCmn
          (una solicitud SIGA por centro de costo)
                        └──────────────────►  usp_ext_aprobar_solicitud_cmn
                                                     │
                                                     ▼
                                              1) SIG_SOLICITUD_MODIFICACION
                                                    ESTADO '2' → '3'  ← "Aprobado"
                                              2) SIG_DOCUMENTO_ESTADO
                                                    movimiento ESTADO='3'
                                              3) SIG_CUADRO_MODIFICADO_DET
                                                    FLAG_MODIFICADO  = '0'
                                                    FLAG_SOLICITUD   = '0'
                                                    MOTIVO_SOLICITUD = '0' ★
                                                    (ESTADO no se toca)

  C. CMN_A4_ENVIADO → CMN_FINALIZADO
     (el área usuaria recepciona el Anexo 4; es acuse, no habilita nada en SIGA)

  D. ── HUECO: paso manual, hoy fuera del SIGCM ──────────────────────────────
     El área usuaria entra al SIGA y registra su PEDIDO eligiendo ítems del
     cuadro. La ventana (sig_aba_dawi21_te.pbd) sólo ofrece ítems que cumplan:

         MOTIVO_SOLICITUD IN ('0','3')
         ESTADO NOT IN ('E','ET','IC')
         (CANT_TOTAL - CANT_TOTAL_CMN) > 0     ← saldo disponible

     Por el paso ★ el ítem recién incluido pasa el filtro. Antes no.
     Resultado: SIG_PEDIDOS + SIG_DETALLE_PEDIDOS, con SEC_CUA_MOD_SAL
     apuntando al ítem del CMN.

  E. SIGCM · Nuevo requerimiento
     modal-registro → acordeón "Datos Generales del Documento" → bloque
     "Pedidos" → combo de <app-form-pedido>, alimentado por
     listarPedidosSiga() → maestro 'PEDIDO' → sigcm.paListarMaestroSiga
     → siga.vwPedido (SIG_PEDIDOS) filtrado por AnoEje + SecEjec +
       CentroCosto del área usuaria del actor + TipoPedido.
              │
              ▼
     El usuario elige el N° de pedido y el formulario precarga meta, tarea,
     fuente de financiamiento y el resumen de ítems (maestro 'PEDIDO_DETALLE').
     Desde ahí sigue el flujo de Requerimiento a Notificación.
```

★ **Ése es el punto exacto que hay que explicar en la exposición.** El Anexo 4
no "manda el CMN al requerimiento": devuelve el ítem a estado estable
(`MOTIVO_SOLICITUD='0'`), y recién entonces el ítem entra en la ventana de
selección del pedido de SIGA. El combo de nuestro requerimiento **no lee el CMN
ni las solicitudes de modificación: lee pedidos ya creados en SIGA**.

---

## 2. La equivalencia de estados, en una tabla

| SIGCM (expediente CMN) | Acción | SIGA `SIG_SOLICITUD_MODIFICACION.ESTADO` | En pantalla SIGA | Ítem pedible |
|---|---|:--:|---|:--:|
| `CMN_A3_APROBADO` | Anexo 3 firmado y validado | `2` | **V.B. Jefe** | ❌ |
| `CMN_A4_FIRMA_COORD` / `CMN_A4_FIRMA_JEFE` | Anexo 4 en firmas | `2` | V.B. Jefe | ❌ |
| **`CMN_A4_ENVIADO`** | **Jefe de Abastecimiento firma el Anexo 4** | **`3`** | **Aprobado** | **✅** |
| `CMN_FINALIZADO` | Área usuaria recepciona | `3` (sin cambio) | Aprobado | ✅ |

Comprobado en `SIGA_1750`, ejercicio 2026:

```
SIG_SOLICITUD_MODIFICACION      ESTADO 2 →   1 solicitud
                                ESTADO 3 → 524 solicitudes
                                ESTADO 5 →   8 solicitudes

SIG_CUADRO_MODIFICADO_DET (ANNO_PROG = ANNO_EJEC = 2026)
  PEDIBLE      MOTIVO ESTADO  filas
     SI          0      C      4000    del cuadro, estable
     SI          0      I      3731    incluido y ya aprobado
     SI          0      IT       61    transferencia recibida
     SI          3      C         1    modificación de cantidades
     NO          0      E       196    excluido consolidado
     NO          0      ET       79    excluido por transferencia
     NO          1      I        84    incluido, solicitud AÚN ABIERTA  ← el caso
     NO          2      E       172    exclusión solicitada
```

Las 84 filas `MOTIVO='1' / ESTADO='I'` son exactamente el estado en el que queda
un ítem entre el Anexo 3 y el Anexo 4: existe en el cuadro, se ve en pantalla,
**y no se puede pedir**.

---

## 3. Dónde vive cada pieza en la rama unida

| Paso | Archivo | Ref |
|---|---|---|
| Transición que dispara la aprobación | `db/20_seed/S001__roles_estados_transiciones.sql` | `CMN_ABAST_JEFE_FIRMAR_A4`, `OperacionIntegracion = 'CONSOLIDAR_CMN'` |
| Encolado | `db/10_api/F004__transicion_encolado.sql` | rama `ELSE IF @OperacionIntegracion = 'CONSOLIDAR_CMN'` |
| Drenaje / escritor | `db/15_siga/W001__escritor_cuadro_modificado.sql` | `IF @op = 'CONSOLIDAR_CMN'`, cursor sobre `integracion.MapeoCmn` |
| Efecto en SIGA | `SIGA/integracion/usp_ext_aprobar_solicitud_cmn.sql` | idempotente; no toca `SIG_CUADRO_MODIFICADO_CMN` (FK de 10 columnas contra `SIG_PAAC_CENTRO_COSTO`) |
| Vista de pedidos | `db/00_ddl/V012__siga_vw_pedido.sql` | `siga.vwPedido` sobre `SIG_PEDIDOS` |
| Combo del requerimiento | `db/10_api/F001__utilitarios_contrato.sql` | maestros `PEDIDO` y `PEDIDO_DETALLE` |
| Front · servicio | `.../gestion-requerimiento/services/requerimiento.service.ts` | `listarPedidosSiga()`, `listarPedidoDetalleSiga()` |
| Front · pantalla | `.../modals/modal-registro/modal-registro.component.{ts,html}` | `cargarPedidosSiga()`, `<app-form-pedido [opcionesPedido]="pedidosSiga">` |

Análisis de respaldo: `SIGA/integracion/ANALISIS_CMN.md` (los dos cuadros, el
ciclo de vida del ítem, el saldo) y la cabecera de
`SIGA/integracion/usp_ext_registrar_requerimiento.sql`.

---

## 4. Lo que nuestro sistema NO contempla

### 4.1 El pedido de SIGA se crea a mano — no hay pantalla en el SIGCM

Entre el Anexo 4 aprobado (paso C) y el combo del requerimiento (paso E) hay un
paso que hoy ocurre **fuera** del SIGCM: el área usuaria entra al SIGA y crea el
pedido. Nada en la rama unida lo automatiza.

Existe `SIGA/integracion/usp_ext_registrar_requerimiento.sql`, que sí sabe crear
la cabecera y el detalle validando las tres reglas del cliente SIGA, pero:

- su propia cabecera dice *"se entrega para homologación; no se instala
  automáticamente"*;
- `W001` lo declara como sinónimo esperado, **pero ningún `EXEC` lo invoca** en
  toda la rama (`F004` sólo expande `ITEMS_ANEXO_3`, `CONSOLIDAR_CMN`,
  `CREAR_CUADRO_ADQUISICION` y `CREAR_ORDEN_SERVICIO`).

Para la exposición conviene decirlo así: *el SIGCM aprueba el CMN en SIGA y
luego lee de SIGA el pedido que el área usuaria registró ahí*. Cerrar el hueco
es cablear una operación `REGISTRAR_PEDIDO` en F004 + W001 apuntando a ese
procedimiento.

### 4.2 Defecto: el combo filtra el tipo de pedido equivocado

`F001__utilitarios_contrato.sql` filtra `TipoPedido = '1'` y comenta *"TipoPedido
1 es el pedido de área usuaria; el 2 es de almacén"*. `V012__siga_vw_pedido.sql`
repite lo mismo. **Los datos dicen lo contrario.**

Consultado en `SIGA_1750`, ejercicio 2026, ejecutora 1750:

```
SIG_PEDIDOS            TIPO_PEDIDO 1 → 1 193 pedidos
                       TIPO_PEDIDO 2 → 7 131 pedidos

SIG_DETALLE_PEDIDOS    TIPO_PEDIDO  líneas  con enlace al CMN (SEC_CUA_MOD_SAL)
                            1        3 261            0
                            2        7 523        7 523   ← 100 %
```

El pedido que nace del CMN es el **tipo 2**. El tipo 1 no tiene ni una sola línea
enlazada al cuadro. Coincide con la cabecera de
`usp_ext_registrar_requerimiento.sql`, que escribe `TIPO_PEDIDO='2'` y documenta
esos mismos conteos.

**Consecuencia:** tal como está, el combo del requerimiento lista pedidos de
almacén y **nunca mostrará el pedido que el usuario acaba de crear a partir de su
CMN aprobado**. Es justamente el síntoma que motivó esta revisión.

Corrección: cambiar el filtro a `TipoPedido = '2'` en las dos ramas del maestro
(`PEDIDO` y `PEDIDO_DETALLE`) de `F001`, y corregir los comentarios de `F001` y
`V012`.

### 4.3 El combo de solicitudes CMN existe en TypeScript pero no en la pantalla

`modal-registro.component.ts` tiene `condicionCmn` (`INCLUIDO` / `NO_INCLUIDO`),
`cambiarCondicionCmn()` y `cargarSolicitudesCmn()`, que llama a
`listarSolicitudCmnFinalizada()` — el combo de REQ-04, el del requerimiento que
**no** estaba en el CMN y se apoya en una modificación ya tramitada. Ese combo
pide solicitudes en `CMN_A4_ENVIADO` y `CMN_FINALIZADO` (los dos estados
posteriores a la firma del Anexo 4, coherente con la tabla de la sección 2).

Pero `modal-registro.component.html` **no lo renderiza**: cero ocurrencias de
`condicionCmn` y de `solicitudesCmn`. El valor viaja al backend siempre como
`INCLUIDO`. Falta el bloque de pantalla.

---

## 5. Guion corto para la exposición

1. El área usuaria pide una inclusión con el **Anexo 3**. En SIGA eso abre una
   *solicitud de modificación* en estado **V.B. Jefe** y deja el ítem marcado
   como "tiene una solicitud abierta". En ese estado el ítem existe pero **SIGA
   no lo deja pedir**.
2. Abastecimiento consolida uno o varios Anexos 3 en un **Anexo 4**. Cuando el
   **Jefe de Abastecimiento lo firma**, nuestro sistema ejecuta en SIGA la
   aprobación de cada solicitud: pasa a **Aprobado** y, sobre todo, devuelve el
   ítem a estado estable.
3. Eso es lo que un logístico haría a mano en *Consolidado del C.M.N. →
   Aprobación de Solicitud de Modificación*. **Nuestro sistema lo hace por él**;
   no hay un paso manual escondido.
4. Con el ítem ya estable, el área usuaria registra su **pedido en SIGA**
   eligiéndolo del cuadro. Ese pedido es el que aparece en el **combo del
   requerimiento** del SIGCM y es el que arrastra meta, tarea, fuente de
   financiamiento e ítems al formulario.
5. La **consolidación del PAAC** es otro proceso, por lotes, y no bloquea nada:
   hay 5 837 inclusiones aprobadas contra 4 406 consolidadas, y todas se pueden
   pedir.

---

## 6. Del pedido a la orden: los dos pasos que siguen siendo de una persona en SIGA

Añadido el **2026-09-03**. Verificado contra `SIGA_1750`, ejercicio 2026,
ejecutora 1750, y contra el código de los `usp_ext_*` que instalamos.

La sección 0 responde que para **aprobar el CMN** no hace falta ningún
logístico: eso lo hace el Anexo 4. Pero de ahí a la orden de servicio hay
**otros dos actos que en SIGA los ejecuta una persona**, y que el SIGCM hoy ni
espera ni comprueba.

```
  1. PEDIDO                SIG_PEDIDOS (TIPO_PEDIDO='2')    ESTADO '0'
  2. AUTORIZACION          Pedidos → opcion 04              ESTADO '0' → '1'   ← PERSONA
     DEL PEDIDO            (pagina 03020000)                graba cuser_id_vb
  3. CUADRO DE ADQUISICION SIG_CUADRO_ADQUISICION           ESTADO '1' → '2'
  4. ORDEN DE SERVICIO     SIG_ORDEN_ADQUISICION            ESTADO '0', SIAF '0'
  5. APROBACION Y                                           ESTADO '0' → '1'   ← PERSONA
     COMPROMISO SIAF                                        SIAF   '0' → '2'
  6. Recien aqui la orden es notificable al locador
```

| Comprobación | Resultado |
|---|---|
| Pedidos de servicio (tipo 2 / S) 2026 | 7 024: **6 991 en `ESTADO='1'`**, 33 en `'0'` |
| Los 6 991 autorizados | todos con `cuser_id_vb`; los 33 pendientes, ninguno |
| Órdenes de servicio 2026 | 3 743 en `ESTADO='1'` + `ESTADO_SIAF='2'`, 58 anuladas, **ninguna en `ESTADO='0'`** |
| Usuarios con la opción 04 (nivel 2 ó 3) | **93**, cada uno sobre su centro de costo |

Una orden en `ESTADO='0'` **no existe en la operación real**. Es exactamente el
estado en el que la deja `usp_ext_crear_orden_servicio_desde_cuadro`, cuya
cabecera lo dice: *"Deja la orden pendiente… NO certifica, NO compromete y NO
inserta `SIG_ORDEN_INTERFASE`"*.

### Qué hace y qué no hace el SIGCM en esos dos puntos

- `usp_ext_crear_cuadro_adquisicion_desde_pedido` lee `SIG_PEDIDOS` **sin mirar
  `ESTADO`**: arma el cuadro aunque el pedido no esté autorizado. Escribe
  `FECHA_APROB` pero no `ESTADO` ni `cuser_id_vb`.
- El combo del requerimiento tampoco filtra: `siga.vwPedido` **ya expone
  `Estado`** y el maestro `PEDIDO` de `F001` no lo usa. El `TODO` que espera
  esta validación está desde el principio en `F005` («los pedidos se guardan con
  `Verificado = 0`»), y `RequerimientoPedido.Verificado` nace en `0` y **nadie lo
  pone en `1`**.
- No existe ninguna vista sobre `SIG_ORDEN_ADQUISICION`: `REQ_NOTIFICAR_OS`
  notifica al locador sin leer el estado de la orden en SIGA.

### Por qué no lo resolvemos escribiendo nosotros ese estado

El paso 5 es el **compromiso presupuestal SIAF**, que se materializa en
`SIG_ORDEN_INTERFASE` hacia el MEF. Y traer al logístico a nuestro sistema
tropieza con que **SIGA autoriza por usuario, no por sistema**: el permiso vive
en `USERS_OPCION` y `SEG_ROL_PAGINA_PRIVILEGIO` cuenta por cuenta, mientras el
SIGCM escribe con una sola conexión de servicio y pasa como usuario de auditoría
el **DNI del actor del SIGCM**. Se ve en los datos: en `SIG_CUADRO_MODIFICADO_DET`
conviven `IRIVERA`, `MPINO`, `NDIBURGA`… y una fila `S901`, que es la nuestra.
Hacerlo desde aquí puentearía el control de acceso de SIGA y dejaría su auditoría
apuntando a un usuario que en SIGA no existe.

**Camino recomendado (pendiente):** que el SIGCM **espere y verifique**, no que
apruebe. Vista `siga.vwOrdenServicio` sobre `SIG_ORDEN_ADQUISICION`, candado en
`paPrepararNotificacionOrden` mientras `ESTADO <> '1'` o `ESTADO_SIAF <> '2'`,
y en el combo del pedido exigir `Estado = '1'` marcando `Verificado = 1`.

### Corrección a la sección 4.2: el tipo de pedido no separa área usuaria de almacén

`TIPO_PEDIDO` separa **con cargo al CMN** de **contra stock**, y se combina con
`TIPO_BIEN`:

```
SIG_DETALLE_PEDIDOS (2026, ejecutora 1750)
  TIPO_PEDIDO  TIPO_BIEN  lineas   con enlace al CMN (SEC_CUA_MOD_SAL)
       1           B       3 261                0
       2           B         453              453   (100 %)
       2           S       7 070            7 070   (100 %)
```

El pedido que nace del CMN es el **tipo 2, sea bien o servicio**; el `TIPO_BIEN`
es el que separa bienes de servicios. `F001` hoy calcula
`CASE WHEN TipoBien='S' THEN '2' ELSE '1'`: acierta para servicios y **para
bienes manda al tipo 1**, que son los pedidos de almacén sin un solo enlace al
cuadro. Debe ser `'2'` en los dos casos. **Pendiente, no corregido.**

### Estado de la integración en desarrollo

`integracion.Operacion` sólo tiene `INCLUIR_ITEM` y `CONSOLIDAR_CMN` completadas:
**`CREAR_CUADRO_ADQUISICION` y `CREAR_ORDEN_SERVICIO` no se han ejecutado nunca
contra SIGA**. El requerimiento de prueba con orden emitida lo siembra `S909` en
nuestras tablas. Ese tramo está escrito y **no probado contra SIGA**.
