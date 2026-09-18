# Pruebas del flujo completo: CMN → Requerimiento → Pagos

Cómo recorrer el sistema entero, de punta a punta, con las cuentas del ambiente
de desarrollo. **Éste es el guion para probar y para exponer.** Última
verificación contra la base: **2026-09-08**.

> Este documento dice **qué hacer y con qué cuenta**. Lo que explica **por qué**
> cada paso hace lo que hace está en `SIGA/integracion/FLUJO_CMN_A_REQUERIMIENTO.md`
> (el tramo CMN → pedido) y en `SIGA/integracion/FLUJO_PAGOS.md` (pagos y la
> integración con SIGA). El estado de cada módulo, en `INIT.md` §4.

**Índice de lo que se puede probar**

| Tramo | Camino feliz | Observaciones |
|---|---|---|
| A · Gestión CMN | §2 | §2 bis |
| B · Requerimiento | §4 | §4 bis |
| C · Entregables y pagos | §5 | §5 bis |

---

## 0. Antes de empezar

- **Clave `123456`** para todas las cuentas. La puerta es el SSO institucional.
- **Hay que cambiar de usuario en cada transferencia.** Un expediente que le toca
  a otro perfil no muestra sus acciones: eso no es un error, es la máquina de
  estados.
- **`44687266` tiene dos perfiles** (Área usuaria - Jefe y Administrador). Al
  entrar elige **«Área usuaria - Jefe»** o no verá las bandejas del flujo.
- **Sin dispositivo de firma:** `firma.omitir_dispositivo` en `true` dentro de
  `src/assets/config/config.json` (o el de `dist/`, sin recompilar). En el equipo
  donde se firma de verdad va en `false`. Tras cambiarlo, **Ctrl+F5**.

### Las cuentas

| DNI | Persona | Perfil | Unidad |
|---|---|---|---|
| 46183970 | CESAR ORTIZ DURAN | `AREA_ESPECIALISTA` | OTI |
| 44687266 | GUSTAVO CRUZ ÑAÑEZ | `AREA_JEFE` | OTI |
| 46025999 | ALEXANDER TICONA | `OA` | Of. Administración |
| 09086695 | CESAR CALVO RAMIREZ | `ABAST_JEFE` | UA |
| 42551460 | MAIRA CABRERA OSORIO | `ABAST_COORDINADOR` | UA |
| 45648851 | MAGALY VARGAS CASTILLA | `ABAST_ESPECIALISTA` | UA |
| 17400217 | VICTOR PISCOYA | `CONTABILIDAD` | UC |
| 41159236 | EVELYN POBLETE CACERES | `AREA_COORDINADOR` | OTI |
| 10712503 | MANUEL CORONADO VELEZ | `TESORERIA` | UT |
| — | locador de prueba | `PROVEEDOR` | portal externo |

**`AREA_COORDINADOR` ya tiene cuenta.** `sso/S02` le dio `PE099 COORDINADOR
OFICINA` a Evelyn Poblete el 2026-09-02. Los recorridos del tramo B siguen
esquivando su visto bueno porque es el camino más corto, no porque falte la
cuenta. `OPP` ya no interviene: la CCP la carga la DEC.

**Las dos secretarías**, creadas el 2026-09-07. Cada una ve la misma bandeja que
su jefe y hace lo mismo **salvo firmar**; deriva al coordinador y al especialista
de su unidad, y **no aparece** en el combo «Derivar a» de nadie.

| DNI | Persona | Rol | Unidad | Perfil SSO |
|---|---|---|---|---|
| 40597381 | GRACIELA NAJARRO BELLIDO | `AREA_SECRETARIA` | OTI | `PE100` |
| 46970816 | WENDY MENDOZA CORREA | `ABAST_SECRETARIA` | UA | `PE102` |

Para dárselo a otra persona:

```bash
psql -h 192.168.20.111 -p 5434 -U postgres -d saa_ -v dni=<DNI> -v cod_dependencia=D0001 -v cod_perfil=PE100 -f sso/S03__perfil_secretaria_area_usuaria.sql
```

`PE100` si el área usuaria es una oficina, `PE101` si es una unidad, y
`sso/S04` con `PE102` para la secretaría de Abastecimiento.

---

## 1. Cómo se encadenan los tres módulos

No son tres sistemas: es uno solo, y cada tramo depende del anterior.

```
  A. GESTIÓN CMN                          Anexo 3 → Anexo 4
        │  la firma del Anexo 4 aprueba la solicitud EN SIGA
        │  y devuelve el ítem a estado estable (MOTIVO_SOLICITUD = '0')
        ▼
  ── el área usuaria registra su PEDIDO en SIGA ──  (paso manual, fuera del SGCM)
        │
        ▼
  B. REQUERIMIENTO                        registro → conformidad → indagación →
        │                                 filtros → CCP → cuadro → orden
        │  al NOTIFICAR la orden se abren los expedientes de pago
        │  y se da de alta al locador en el SSO externo
        ▼
  C. ENTREGABLES Y PAGOS                  uno por entregable del Anexo 5
                                          presentación → conformidad →
                                          liquidación → devengado → giro
```

Los dos enlaces que más confusión generan:

- **El requerimiento sólo puede pedir ítems que el CMN dejó disponibles**, y los
  lee de un **pedido de SIGA** (`TIPO_PEDIDO = 2`), no del CMN.
- **El expediente de pago nace de la orden de servicio**: sin llegar a
  `REQ_OS_EMITIDA` no hay nada que pagar.

---

## 2. Tramo A · Gestión CMN

| # | DNI | Perfil | Acción | Estado resultante |
|---|---|---|---|---|
| 1 | 46183970 | AU · Especialista | Registrar la solicitud y **Generar Anexo 3** | `CMN_PEND_FIRMA_A3` |
| 2 | 44687266 | AU · Jefe | **Firmar** Anexo 3 y remitir a la OA 🖊 | `CMN_EN_EVAL_OA` |
| 3 | 46025999 | Of. Administración | Derivar al Jefe de Abastecimiento | `CMN_EN_ABAST_JEFE` |
| 4 | 09086695 | Abast · Jefe | Derivar al Coordinador *(o directo al Especialista)* | `CMN_EN_ABAST_COORD` |
| 5 | 42551460 | Abast · Coordinador | Derivar al Especialista | `CMN_EN_ABAST_ESP` |
| 6 | 45648851 | Abast · Especialista | **Firmar** el Anexo 3 y elevar al Jefe 🖊 | `CMN_A3_FIRMA_JEFE` |
| 7 | 09086695 | Abast · Jefe | **Firmar** el Anexo 3 y **registrarlo en SIGA** 🖊 📤 | `CMN_A3_APROBADO` |
| 8 | 45648851 | Abast · Especialista | Generar Anexo 4 y remitir al Jefe | `CMN_A4_FIRMA_JEFE` |
| 9 | 09086695 | Abast · Jefe | **Firmar** el Anexo 4, **aprobar en SIGA** y remitir al AU 🖊 📤 | `CMN_A4_ENVIADO` |
| 10 | 44687266 | AU · Jefe | Recepcionar Anexo 4 | `CMN_FINALIZADO` |

🖊 exige firma · 📤 escribe en SIGA

**Ruta de observación:** desarrollada entera en la sección 2 bis.

**El paso 9 es el importante:** ahí el ítem queda pedible en SIGA. No hace falta
que ningún logístico mueva nada a mano.

---

## 2 bis. Tramo A · el ciclo de observación del CMN

Un CMN se puede observar desde **tres sitios**, y los tres terminan devolviéndolo
al **Jefe del área usuaria**. Desde ahí baja al especialista, que subsana, y todo
vuelve a subir.

### Las tres entradas

| Desde | Estado | Quién | DNI | Acción | Termina en |
|:--:|---|---|---|---|---|
| **1** | `CMN_EN_EVAL_OA` | Of. Administración | 46025999 | Observar desde la Oficina de Administración | `CMN_OBS_AU_JEFE` |
| **2** | `CMN_EN_ABAST_JEFE` | Abast · Jefe **o Secretaria** | 09086695 · **46970816** | Observar y devolver al Jefe del Área usuaria | `CMN_OBS_AU_JEFE` |
| **3** | `CMN_EN_ABAST_ESP` | Abast · Especialista | 45648851 | Observar el Anexo 3 | `CMN_OBS_ABAST_COORD` |

Las tres exigen comentario: es lo que el área usuaria tiene que subsanar.

**1 y 2 son atajos: van directo al Jefe del área usuaria.** El 2 lo sembró `S030`
y es el que puede ejecutar también la secretaria de Abastecimiento.

### La entrada 3 sube dos escalones antes de devolver

| # | Estado | Quién | DNI | Acción | Pasa a |
|---|---|---|---|---|---|
| 3.1 | `CMN_OBS_ABAST_COORD` | Abast · Coordinador **o Secretaria** | 42551460 · **46970816** | Elevar la observación al Jefe de Abastecimiento | `CMN_OBS_ABAST_JEFE` |
| 3.2 | `CMN_OBS_ABAST_JEFE` | Abast · Jefe **o Secretaria** | 09086695 · **46970816** | Devolver observado al Jefe del área usuaria | `CMN_OBS_AU_JEFE` |

### La bajada dentro del área usuaria, y la vuelta

**En CMN no hay coordinador.** El jefe baja la observación directo a cualquiera
de sus especialistas, ése la resuelve y se la devuelve a él. Coordinado con el
área el 2026-09-08 y sembrado en `S035`; vale igual para **todas** las áreas
usuarias.

| # | Estado | Quién | DNI | Acción | Pasa a |
|---|---|---|---|---|---|
| 4 | `CMN_OBS_AU_JEFE` | AU · Jefe **o Secretaria** | 44687266 · **40597381** | Derivar al Especialista para subsanar | `CMN_OBSERVADO` |
| 5 | `CMN_OBSERVADO` | AU · Especialista | 46183970 · 43552822 | Registrar la subsanación y devolver al Jefe *(comentario)* | `CMN_SUBS_AU_JEFE` |
| 6 | `CMN_SUBS_AU_JEFE` | AU · Jefe | 44687266 | **Firmar** y remitir el subsanado 🖊 | *vuelve a quien observó* |

En el paso 4 el combo «Derivar a» ofrece a **todos los especialistas de la
unidad** —la arista `CMN · AREA_JEFE → AREA_ESPECIALISTA` tiene alcance
`MISMA_UNIDAD`—, así que el jefe elige a quién se lo encarga. En OTI hoy salen
tres.

El paso 6 **no lo puede dar la secretaria**: exige firma. Es el único de todo el
ciclo que le queda fuera.

### El subsanado vuelve a quien observó, no siempre a Abastecimiento

La transición declara `CMN_EN_ABAST_JEFE` como destino, pero la observación
guarda su `CodigoEstadoRetorno` y `sigcm.fnEstadoDestinoTransicion` (V029) manda
el expediente de vuelta al escalón que lo observó:

| Observó | El subsanado vuelve a |
|---|---|
| Oficina de Administración | `CMN_EN_EVAL_OA` |
| Abastecimiento | `CMN_EN_ABAST_JEFE` |

Comprobado con los dos casos de `S911`. La observación queda `CERRADA` al firmar
el jefe.

### Dónde entran las dos secretarías

| Rol | Persona | DNI | Pasos que puede dar |
|---|---|---|---|
| `AREA_SECRETARIA` | GRACIELA NAJARRO BELLIDO (OTI) | **40597381** | 4 |
| `ABAST_SECRETARIA` | WENDY MENDOZA CORREA (UA) | **46970816** | 2 · 3.1 · 3.2 |

Cada una ve la bandeja de su unidad igual que su jefe, y **ninguna aparece en el
combo «Derivar a»** de nadie.

### El coordinador del área usuaria no interviene en CMN

`AREA_COORDINADOR` existe —EVELYN POBLETE CACERES, DNI 41159236, con `PE099`
desde el 2026-09-02— y **sí trabaja en Requerimiento**, pero **no en CMN**: ahí
el circuito va del jefe al especialista y de vuelta. `S035` retiró sus dos pasos
y dejó `CMN_OBS_AU_COORD` y `CMN_SUBS_AU_COORD` marcados como «circuito
retirado», sin transiciones activas.

### Datos sembrados para probarlo

`db/90_pruebas/S911__cmn_devolucion_au.sql` deja dos expedientes que ya
recorrieron el flujo de verdad —registro, Anexo 3, PDF, firma del jefe— parados
justo antes de la observación:

| Expediente | Estado | Bandeja | Para probar la entrada |
|---|---|---|---|
| el primero | `CMN_EN_EVAL_OA` | Administración | **1** |
| el segundo | `CMN_EN_ABAST_JEFE` | Abastecimiento | **2** |

```bash
sqlcmd -S 192.168.40.75 -U developer_anin -d DBSIGCM -b -I -i db/90_pruebas/S911__cmn_devolucion_au.sql
```

Repetible y se limpia solo: reconoce lo suyo por la marca `S911` en el sustento.
Para la entrada 3 hay que llevar un expediente hasta `CMN_EN_ABAST_ESP` a mano,
derivándolo desde Abastecimiento.

---

## 3. Puente · el pedido en SIGA

Entre el Anexo 4 y el requerimiento hay un paso **fuera del SGCM**: el área
usuaria entra a SIGA y registra su pedido eligiendo el ítem del cuadro. Ese
pedido es el que aparece en el combo del requerimiento.

Además, en SIGA el pedido lo **autoriza** el responsable del centro de costo
(`SIG_PEDIDOS.ESTADO` de `'0'` a `'1'`). El SGCM todavía no comprueba esa
autorización: es el defecto 4 de `INIT.md`.

Para no depender de SIGA, los recorridos de abajo arrancan de datos sembrados.

---

## 4. Tramo B · Requerimiento a notificación

| # | DNI | Perfil | Acción | Estado resultante |
|---|---|---|---|---|
| 1 | 46183970 | AU · Especialista | Nuevo requerimiento: pedido SIGA, ítems y proveedor → **Elaborar documento técnico** | `REQ_DOC_PENDIENTE` |
| 2 | 44687266 | AU · Jefe | **Derivar al Jefe** *(evita la firma del especialista y el V°B° del coordinador, que no tiene cuenta)* | `REQ_PEND_FIRMA_AU` |
| 3 | 44687266 | AU · Jefe | **Firmar** y remitir a la OA 🖊 | `REQ_EN_EVAL_OA` |
| 4 | 46025999 | Of. Administración | Derivar a Abastecimiento | `REQ_EN_ABAST_JEFE` |
| 5 | 09086695 | Abast · Jefe | Derivar al Coordinador | `REQ_EN_ABAST_COORD` |
| 6 | 42551460 | Abast · Coordinador | Derivar a la DEC | `REQ_EN_EVAL_DEC` |
| 7 | 45648851 | Abast · Especialista | Declarar conformidad | `REQ_CONFORME` |
| 8 | 45648851 | Abast · Especialista | Iniciar indagación de mercado *(invita al locador por correo)* | `REQ_INDAGACION_MERCADO` |
| 9 | 45648851 | Abast · Especialista | Iniciar filtros de idoneidad *(exige el Anexo 6 cargado)* | `REQ_FILTROS` |
| 10 | 45648851 | Abast · Especialista | Enviar filtros al Coordinador | `REQ_FILTROS_COORD` |
| 11 | 42551460 | Abast · Coordinador | Enviar filtros al Jefe | `REQ_FILTROS_JEFE` |
| 12 | 09086695 | Abast · Jefe | Confirmar filtros | `REQ_CCP_SOLICITADO` |
| 13 | 45648851 | Abast · Especialista | Cargar la CCP *(N.° CCP, SIAF, monto igual al Anexo 5, PDF de la CCP y memo de la UP)* | `REQ_CCP_CARGADA` |
| 14 | 45648851 | Abast · Especialista | Generar cuadro de adquisición 📤 | `REQ_CUADRO_GENERADO` |
| 15 | 45648851 | Abast · Especialista | Emitir orden de servicio 📤 | `REQ_OS_EMITIDA` |
| 16 | 45648851 | Abast · Especialista | **Notificar orden** | `REQ_NOTIFICADO` |

**El paso 16 hace tres cosas a la vez:** manda el correo al locador con copia al
área usuaria, **abre un expediente de pago por cada entregable** y **da de alta
al locador como usuario externo del SSO** (sistema SGCM-E, perfil
`ADMINISTRADO_EXT`).

> **Ojo con la contraseña del locador.** La función del SSO la deriva de
> `SHA512(documento + año)` y responde «se le enviará las credenciales a su
> correo», pero **ese correo no lo manda nadie todavía**. Para probar el portal
> hay que fijarla a mano en `login.tm_login_usuario_externo`.

**Pendiente:** entre el paso 15 y el 16, en SIGA una persona de Logística aprueba
la orden y la compromete en SIAF. El SGCM lo **muestra** pero no lo exige.

### 4 bis · Las observaciones del requerimiento

A diferencia del CMN, **en Requerimiento el coordinador del área usuaria sí
interviene**: es su circuito propio, no un descuido.

**Quién puede observar, y a dónde manda el expediente:**

| Desde | Quién | DNI | Acción | Va a |
|---|---|---|---|---|
| `REQ_PEND_VB_AU` | AU · Coordinador | 41159236 | Observar documento | `REQ_OBSERVADO` |
| `REQ_PEND_FIRMA_AU` | AU · Jefe **o Secretaria** | 44687266 · **40597381** | Observar documento | `REQ_OBSERVADO` |
| `REQ_EN_EVAL_OA` | Of. Administración | 46025999 | Observar desde OA | `REQ_OBS_AU_JEFE` |
| `REQ_EN_ABAST_JEFE` | Abast · Jefe **o Secretaria** | 09086695 · **46970816** | Observar y devolver al Jefe AU | `REQ_OBS_AU_JEFE` |
| `REQ_EN_EVAL_DEC` | Abast · Especialista / Coordinador | 45648851 · 42551460 | Observar desde la DEC | `REQ_OBSERVADO` |
| `REQ_FILTROS` | Abast · Especialista / Coordinador | 45648851 · 42551460 | Devolver al Área usuaria / Observar | `REQ_OBSERVADO` |

Todas exigen comentario.

**La bajada, cuando la observación llega al jefe:**

| # | Estado | Quién | DNI | Acción | Pasa a |
|---|---|---|---|---|---|
| 1 | `REQ_OBS_AU_JEFE` | AU · Jefe **o Secretaria** | 44687266 · **40597381** | Derivar al Coordinador del Área usuaria | `REQ_OBS_AU_COORD` |
| 2 | `REQ_OBS_AU_COORD` | AU · Coordinador | **41159236** | Enviar al Especialista para subsanar | `REQ_OBSERVADO` |
| 3 | `REQ_OBSERVADO` | AU · Especialista | 46183970 · 43552822 | **Firma especialista** 🖊 | `REQ_PEND_VB_AU` |

El paso 3 devuelve el expediente al circuito normal: coordinador → jefe → firma
→ OA. **Exige firma del especialista**, así que la secretaría no lo cubre.

**Archivar** es la otra salida: el Coordinador (`REQ_ARCHIVAR_VB`) o el Jefe y su
Secretaria (`REQ_ARCHIVAR_FIRMA`) pueden anular el expediente con comentario.

---

## 5. Tramo C · Entregables y pagos

Un expediente **por cada entregable**, cada uno con su ciclo completo.

| # | DNI | Perfil | Acción | Documento | Estado resultante |
|---|---|---|---|---|---|
| 1 | *(locador)* | `PROVEEDOR` | Presentar entregable y RHE | informe + RHE (PDF y XML) | `PAG_ENTREGABLE_PRESENTADO` |
| 2 | 46183970 | AU · Especialista | Aprobar conformidad técnica *(aquí se calcula el atraso)* | — | `PAG_CONFORMIDAD_PEND_FIRMA` |
| 3 | 44687266 | AU · Jefe | **Generar Anexo 11** y **firmar** 🖊 📤 | **Anexo 11** | `PAG_CONFORMIDAD_APROBADA` |
| 4 | 45648851 | Abast · Especialista | Marcar el checklist, **Generar Anexo 9** *(y 10 si hay mora)*, liquidar | **Anexo 9** + **Anexo 10** | `PAG_EXPEDIENTE_LIQUIDADO` |
| 5 | 17400217 | Contabilidad | Registrar devengado SIAF | — | `PAG_DEVENGADO_APROBADO` |
| 6 | 10712503 | Tesorería | Registrar giro y abono CCI | nota de pago + constancia *(+ papeleta si hay penalidad)* | `PAG_PAGO_EFECTUADO` **(cierre)** |

**Orden dentro del paso 4:** marcar el checklist **antes** de generar el Anexo 9,
porque el PDF refleja lo que está en pantalla.

**El Anexo 10 es condicional.** La Directiva lo pide «de corresponder»: sin mora
el botón dice sólo «Generar Anexo 9».

### 5 bis · Las observaciones de pagos

| Desde | Quién | DNI | Acción | Va a | Quién subsana y con qué |
|---|---|---|---|---|---|
| `PAG_ENTREGABLE_PRESENTADO` | AU · Especialista | 46183970 | Observar entregable | `PAG_OBSERVADO_AU` | el **locador**, con «Subsanar observaciones» |
| `PAG_EXPEDIENTE_LIQUIDADO` | Contabilidad | 17400217 | Devolver a DEC con observaciones contables | `PAG_OBS_UC_DEC` | **45648851**, «Remitir subsanado a Contabilidad» |
| `PAG_EXPEDIENTE_LIQUIDADO` | Contabilidad | 17400217 | Devolver al Área usuaria | `PAG_OBS_UC_AU` | **46183970** o **44687266**, «Remitir subsanado» |

Las tres de ida exigen comentario; las de vuelta, no. Ninguna exige firma.

Aquí **no hay secretaría**: el módulo de pagos no le da acciones ni a
`AREA_SECRETARIA` ni a `ABAST_SECRETARIA` más allá de ver la bandeja.

### Qué mirar en la pantalla

- **La píldora del estado abre la trazabilidad**: quién movió el expediente, a
  dónde y cuándo, más las observaciones y los hitos de SIGA.
- El expediente **no desaparece** de la bandeja de la unidad cuando avanza: queda
  como tramitado, sin acciones y sin la marca de pendiente.
- El detalle lista los **documentos** del expediente con su estado de firma.

---

## 4 ter. Tramo B½ · Ejecución contractual (entre la orden y el pago)

El contrato (`EJE-*`) **nace solo** cuando se notifica la orden (paso final del
tramo B) y aparece en «Ejecución contractual» para el área usuaria, la DEC y el
proveedor. Para un **servicio** no hay nada que hacer aquí salvo mirar el plazo,
registrar incidencias y, al final, culminar: el entregable se presenta y se
conforma en el tramo C. Para un **bien** la entrega física se recorre aquí.

**Antes que nada**, el AU fija el lugar de entrega en la pestaña *Contrato*:
sin eso el proveedor no tiene el botón «Anunciar entrega».

Ruta **Almacén** (lugar = Sede Central):

| # | DNI | Perfil | Dónde | Acción | Estado de la entrega |
|---|---|---|---|---|---|
| 1 | 46183970 | AU · Especialista | *Contrato* | Lugar de entrega = Sede Central, **Guardar** | — |
| 2 | *(proveedor)* | `PROVEEDOR` | *Entregas* | **Anunciar entrega**: entregable, guía de remisión, bienes | `EJE_ENT_POR_AUTORIZAR_ALMACEN` |
| 3 | 45648851 | Abast · Especialista | *Entregas* · icono 🚪 | Autorizar ingreso a Almacén | `EJE_ENT_POR_DESIGNAR_VERIFICADOR` |
| 4 | 44687266 | AU · Jefe | *Entregas* · icono 👤✓ | Designar responsable de verificación *(alguien del área)* | `EJE_ENT_EN_VERIFICACION_ALMACEN` |
| 5a | 45648851 | Abast · Especialista | icono ✓ | **Conforme** + guía suscrita (PDF) | `EJE_ENT_RECEPCIONADA_ALMACEN` |
| 6a | 45648851 | Abast · Especialista | icono 📦 | Entregar al AU con **N.° Pecosa** | `EJE_ENT_ENTREGADA_AU` **(fin)** |
| 5b | 45648851 | Abast · Especialista | icono ⚠ | **Observado** + detalle + acta de incumplimiento (PDF) | `EJE_ENT_OBSERVADA` |
| 6b | *(proveedor)* | `PROVEEDOR` | icono 🚚 | Confirmar retiro de los bienes | `EJE_ENT_RETIRADA` **(fin)** |

Ruta **Sede desconcentrada** (lugar = Sede desconcentrada + dirección): los
pasos 3 y 4 se funden en uno del **AU · Especialista** (autorizar ingreso en
sede), el 5 lo da el mismo especialista, y tras la recepción la DEC cierra con
«Registrar guía suscrita en Almacén» → `EJE_ENT_GUIA_REGISTRADA`.

Después de recepcionar, el proveedor **presenta el entregable en el tramo C**
(paso 1 de pagos); la pestaña *Entregables* del contrato muestra cómo va cada
uno sin salir de la pantalla.

**Incidencias (7.3.3):** el AU las registra en su pestaña con tipo
(incidencia / incumplimiento / riesgo) y número de SGD; la DEC las atiende con
una respuesta. No mueven el contrato.

**Culminar** (AU · Jefe, pie del modal) sólo pasa cuando **todos** los
entregables tienen conformidad en el tramo C y no queda ninguna entrega abierta;
si no, la rutina dice cuántos faltan.

Con `S914` el recorrido de bienes ya está dado hasta el final y sólo queda
mirarlo, o anunciar una tercera entrega como proveedor y seguirla a mano.

---

## 5 ter. El correo que cambia en el SSO

El SSO manda sobre `sigcm.Usuario`, y estas pruebas comprueban que eso se cumple
de verdad. Salen del defecto del **2026-09-09**: se cambió el correo de una
cuenta en el SSO a las 00:33 y el aviso del Anexo 4 de la 01:03 se fue igual a la
dirección anterior. Quedó registrado en `cmn.NotificacionAnexo4` de la base
desplegada, y se «arregló solo» a las 09:59 cuando alguien volvió a entrar.

### Por qué pasaba, en dos frases

`sigcm.Usuario` es una **réplica** del padrón del SSO, y sólo se reconciliaba
cuando alguien **ingresaba**. Con un token de ocho horas, quien ya estaba dentro
trabajaba toda la jornada contra la foto de la mañana. Encima, la orden de
servicio guardaba una **copia congelada** del correo del área usuaria tomada al
registrarla, y la notificación leía esa copia y no el dato vigente.

### Dónde se prueba cada cosa

**El SSO de desarrollo redirige al servidor desplegado, no a `localhost:4200`.**
Eso parte las pruebas en dos y conviene tenerlo claro antes de empezar:

| Qué se prueba | Dónde | Cómo |
|---|---|---|
| La rutina resuelve el correo en vivo (C) | cualquier `DBSIGCM` | `S913`, sin navegador |
| El refresco antes de notificar (A) | **desplegado** `192.168.20.111:9047` | a mano, abajo |
| El refresco programado (B) | **desplegado** | a mano, abajo |

Contra `localhost:4200` no se puede recorrer el ingreso por SSO: `url_sistema`
del sistema 73 apunta al desplegado. Si hace falta probar A y B en local, el
camino es `acceso_local: "true"` en el `appsettings.json` del backend — pero
**ojo: con `acceso_local` encendido el ingreso no pasa por el SSO y el padrón no
se sincroniza nunca**, así que ese modo sirve para todo menos para esto.

### Prueba 1 · La rutina, sin navegador

```bash
sqlcmd -S 192.168.40.75 -U developer_anin -d DBSIGCM -b -I -i db/90_pruebas/S913__correo_sso_desfasado.sql
```

Cubre cuatro casos y devuelve código distinto de cero si alguno falla:

| Caso | Qué monta | Esperado |
|---|---|---|
| 1 | La copia congelada y el correo vigente **difieren** | gana el vigente |
| 2 | La persona ya **no tiene** correo vigente (baja en el SSO) | cae a la copia; la orden se notifica igual |
| 3 | CMN, que ya resolvía en vivo | sigue resolviendo en vivo |
| 4 | El candado de `paSincronizarPadronSso` | está puesto |

No deja rastro: manipula dentro de una transacción y hace `ROLLBACK`. El caso 3
queda **OMITIDO** si la base no tiene ninguna solicitud CMN con el Anexo 4
firmado; eso no es un fallo, es que falta el dato.

**Que la prueba tiene dientes** está comprobado: aplicando la versión anterior de
`F010` el caso 1 falla con el mensaje exacto del defecto.

### Prueba 2 · El refresco antes de notificar, en el desplegado

Ésta es la que reproduce el defecto real de punta a punta.

1. Entra al sistema con una cuenta y **deja la sesión abierta**. No la cierres en
   ningún momento: el defecto vivía justo ahí.
2. Con la sesión abierta, cambia el correo en el SSO:

```bash
psql -h 192.168.20.111 -p 5434 -U postgres -d saa_ -c "UPDATE login.td_login_usuario_correo SET correo_electronico = 'prueba.nueva@anin.gob.pe' WHERE id_usuario = 6 AND activo;"
```

3. Comprueba que la réplica **todavía tiene el correo viejo**. Tiene que tenerlo:
   nadie ha vuelto a entrar.

```bash
sqlcmd -S 192.168.40.74 -U w_sgcmenores -d DBSIGCM -b -I -Q "SELECT Cuenta, Correo FROM sigcm.Usuario WHERE Cuenta = '44687266'"
```

4. **Sin cerrar sesión**, dispara una notificación desde la pantalla: firma el
   Anexo 4 y usa *Notificar al área usuaria*, o notifica una orden de servicio.
5. Vuelve a mirar la réplica y, sobre todo, a quién se envió:

```bash
sqlcmd -S 192.168.40.74 -U w_sgcmenores -d DBSIGCM -b -I -Q "SELECT TOP 3 Destinatario, Copia, EnviadaEn FROM cmn.NotificacionAnexo4 ORDER BY EnviadaEn DESC"
```

**Esperado:** el destinatario es `prueba.nueva@anin.gob.pe`. Antes del arreglo
era el anterior, y la fila quedaba en esa tabla como prueba.

Acuérdate de dejar el correo como estaba al terminar.

### Prueba 3 · El refresco programado, en el desplegado

`PadronSso` está **apagado por defecto** en el `appsettings.json` versionado. En
el desplegado se enciende:

```json
"PadronSso": { "Habilitado": true, "IntervaloSegundos": 900, "EsperaInicialSegundos": 30 }
```

Al arrancar el backend, el log tiene que decir una de estas dos, y hay que mirar
cuál:

```
info: PadronSsoWorker[0] Refresco programado del padron SSO habilitado cada 900 s.
info: PadronSsoWorker[0] Refresco programado del padron SSO deshabilitado. ...
```

Con él encendido, cada vuelta escribe el resumen y, si hay accesos que no se
pudieron traducir, los saca como **warning** — ésos son personas que no van a
poder entrar:

```
info: Padron SSO reconciliado. Resumen: {"PadronRecibido":24,"UnidadesAlta":0,...}
warn: El padron trae 1 acceso(s) que no se pudieron traducir: [{"Cuenta":"32885691",...,"Motivo":"El cod_perfil no esta mapeado en sigcm.PerfilSso."}]
```

Para comprobarlo **sin esperar quince minutos**, baja el intervalo al mínimo
—`"IntervaloSegundos": 60`— cambia un correo en el SSO, espera un minuto y mira
`sigcm.Usuario` sin que nadie haya ingresado:

```bash
sqlcmd -S 192.168.40.74 -U w_sgcmenores -d DBSIGCM -b -I -Q "SELECT TOP 5 Disparador, PadronRecibido, Fecha FROM sigcm.SincronizacionSso ORDER BY Fecha DESC"
```

La columna `Disparador` distingue quién lo pidió: `INGRESO` (alguien entró),
`NOTIFICACION` (se iba a mandar un correo) o `MANTENIMIENTO` (el worker o el
panel). Si sólo aparece `INGRESO`, el worker no está corriendo.

### Prueba 4 · Que el worker y un ingreso no se pisen

Con el worker encendido, la reconciliación dejó de ser cosa de una sola persona a
la vez. Las tres operaciones tocan las mismas filas y el **cierre** de
asignaciones es el peligroso: dos sesiones recorriendo `UsuarioRol` en orden
distinto es la receta del interbloqueo. Por eso la rutina toma un
`sp_getapplock` de transacción.

Comprobado con dos sesiones: mientras una lo retiene, la otra no lo consigue
(`-1`) y sale sin reconciliar en vez de esperar o de interbloquearse. El caso 4
de `S913` verifica que el candado sigue en la rutina.

### Lo que este arreglo NO cubre

El correo del **locador** no lo gobierna el SSO: sale del Anexo 5 y se guarda en
`OrdenServicio.CorreoLocador`, `ExpedientePago.CorreoLocador` e
`InvitacionCotizacion.Destinatario`. Si el locador se equivocó al escribirlo, se
corrige en el Anexo 5, no aquí.

Y sigue abierto el defecto 3 de `INIT.md` §5: al locador **nadie le envía su
contraseña** del portal externo.

---

## 6. Datos sembrados, para no recorrerlo todo

Las semillas de prueba viven en **`db/90_pruebas/`**, con prefijo `S9xx`. No van
a QA ni a producción, son **repetibles** y **se limpian solas**.

| Script | Qué deja |
|---|---|
| `S909__datos_prueba_pago.sql` | `REQ-PRU-PAGO-0001` en `REQ_OS_EMITIDA` · locador **persona jurídica** · 3 entregables de S/ 1,500, dos ya presentados **en plazo** |
| `S910__datos_prueba_pago_penalidad.sql` | `REQ-PRU-PAGO-0002` en `REQ_OS_EMITIDA` · locador **persona natural** · 2 entregables de S/ 2,000: el 1 llega **10 días tarde** (S/ 166.70 de penalidad) y el 2 en plazo |
| `S911__cmn_devolucion_au.sql` | Dos CMN que ya recorrieron el flujo, parados antes de la observación: uno en la bandeja de **Administración** y otro en la de **Abastecimiento** |
| `S912__pagos_entregables_presentados.sql` | Da el **paso 1 de pagos** sobre los expedientes que la base ya tiene abiertos: los deja en `PAG_ENTREGABLE_PRESENTADO`, listos para el paso 2. No siembra requerimientos ni órdenes |
| `S913__correo_sso_desfasado.sql` | **No siembra nada: comprueba.** Que el correo vigente del SSO gana a la copia congelada en la orden de servicio. Cuatro casos, `ROLLBACK` al final, código distinto de cero si alguno falla |
| `S914__prueba_ejecucion_bienes.sql` | `REQ-PRU-EJEC-0001` (**bien**, OTI) en `REQ_NOTIFICADO` con su contrato `EJE-*` en Sede Central · entrega 1 **conforme** hasta la Pecosa, entrega 2 **observada** con acta y retirada · una incidencia atendida · el culminar responde `estado 0`. Usa los perfiles de prueba de `S900`, así que corre en local |

`S912` es para el **servidor desplegado**, donde los requerimientos ya existen y
lo único que falta es el paso del locador. Toca sólo el esquema `pago` —y, si el
locador no está en el padrón, su terna `PROVEEDOR`, que es la misma cuenta con
la que entra al portal externo.

```bash
sqlcmd -S 192.168.40.75 -U developer_anin -d DBSIGCM -b -I -i db/90_pruebas/S909__datos_prueba_pago.sql
sqlcmd -S 192.168.40.75 -U developer_anin -d DBSIGCM -b -I -i db/90_pruebas/S910__datos_prueba_pago_penalidad.sql
sqlcmd -S 192.168.40.75 -U developer_anin -d DBSIGCM -b -I -i db/90_pruebas/S911__cmn_devolucion_au.sql
sqlcmd -S 192.168.40.75 -U developer_anin -d DBSIGCM -b -I -i db/90_pruebas/S913__correo_sso_desfasado.sql
```

```bash
sqlcmd -S 192.168.40.74 -U w_sgcmenores -d DBSIGCM -b -I -i db/90_pruebas/S912__pagos_entregables_presentados.sql
```

Entre `S909` y `S910` quedan cubiertos los cuatro casos que el módulo de pagos
distingue: locador jurídico y natural, entregable con penalidad y sin ella. Los
tres son repetibles: correrlos otra vez reinicia su tramo sin tocar nada más.

---

## 6 bis. Antes de una presentación

Tres cosas que se olvidan y se notan en vivo:

1. **La firma.** `firma.omitir_dispositivo` en `src/assets/config/config.json`
   tiene que ir en **`false`** en el equipo donde se expone, o el sistema no
   pedirá el token y el paso de firma pasará de largo. En `true` sólo para
   ensayar sin dispositivo.
2. **El worker de integración.** `IntegracionSiga` en el `appsettings.json` del
   backend: en `Modo: "real"` escribe en `SIGA_1750` cada 30 segundos por su
   cuenta. Decidir si va encendido.
3. **Los datos.** Correr las tres semillas de arriba justo antes, para arrancar
   desde un punto conocido. Y **cambiar de usuario en cada transferencia**: un
   expediente que le toca a otro perfil no muestra sus acciones.

El backend hay que **matarlo y relevantarlo** después de compilar (`INIT.md`
§3.2); si no, un endpoint nuevo responde 404 aunque esté en el repo.

---

## 7. Dónde escribe el sistema en SIGA

| Tramo | Paso | Quién | DNI | Qué escribe |
|---|---|---|---|---|
| CMN | Firma del Anexo 3 | Abast · Jefe | 09086695 | `SIG_CUADRO_MODIFICADO_DET` + `SIG_SOLICITUD_MODIFICACION` |
| CMN | Firma del Anexo 4 | Abast · Jefe | 09086695 | aprueba la solicitud: el ítem queda **pedible** |
| Requerimiento | Generar cuadro | Abast · Especialista | 45648851 | `SIG_CUADRO_ADQUISICION` |
| Requerimiento | Emitir O/S | Abast · Especialista | 45648851 | `SIG_ORDEN_ADQUISICION` *(pendiente de aprobar en SIGA)* |
| Pagos | Firmar Anexo 11 | AU · Jefe | 44687266 | `FLAG_RECEPCION` + `FECHA_RECEPCION` |

Y **lo que el sistema lee de SIGA sin escribir**: los pedidos del área usuaria
(combo del requerimiento) y el estado de la orden con su expediente SIAF
(bandeja de pagos).

**Lo que el SGCM no hace y sigue siendo de una persona dentro de SIGA:** autorizar
el pedido, y aprobar y comprometer la orden en SIAF.
