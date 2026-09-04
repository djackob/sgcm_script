# Recorrido de pruebas: CMN → Requerimiento → Pagos

Cómo recorrer el sistema entero, de punta a punta, con las cuentas de prueba del
ambiente de desarrollo. Última verificación contra la base: **2026-09-04**.

> Este documento es el guion. Lo que explica **por qué** cada paso hace lo que
> hace está en `SIGA/integracion/FLUJO_CMN_A_REQUERIMIENTO.md` (el tramo CMN →
> pedido) y en `SIGA/integracion/FLUJO_PAGOS.md` (el tramo de pagos y la
> integración con SIGA). El estado de cada módulo, en `INIT.md` §4.

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
| 10712503 | MANUEL CORONADO VELEZ | `TESORERIA` | UT |
| — | locador de prueba | `PROVEEDOR` | portal externo |

**Roles sin cuenta real:** `AREA_COORDINADOR` no tiene ninguna cuenta del SSO, y
por eso los recorridos de abajo esquivan su visto bueno. `OPP` ya no interviene:
la CCP la carga la DEC.

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

**Ruta de observación:** la OA (46025999) o el Especialista de Abastecimiento
(45648851) pueden observar; la observación baja hasta el Especialista del área
usuaria (46183970), que subsana, y vuelve a subir firmada por el Jefe.

**El paso 9 es el importante:** ahí el ítem queda pedible en SIGA. No hace falta
que ningún logístico mueva nada a mano.

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

### Rutas de observación

| Desde | Quién | Acción | A dónde | Quién subsana |
|---|---|---|---|---|
| `PAG_ENTREGABLE_PRESENTADO` | 46183970 | Observar entregable | `PAG_OBSERVADO_AU` | el locador |
| `PAG_EXPEDIENTE_LIQUIDADO` | 17400217 | Devolver a DEC | `PAG_OBS_UC_DEC` | 45648851 |
| `PAG_EXPEDIENTE_LIQUIDADO` | 17400217 | Devolver al Área usuaria | `PAG_OBS_UC_AU` | 46183970 / 44687266 |

Las tres de ida exigen comentario; las de vuelta, no.

### Qué mirar en la pantalla

- **La píldora del estado abre la trazabilidad**: quién movió el expediente, a
  dónde y cuándo, más las observaciones y los hitos de SIGA.
- El expediente **no desaparece** de la bandeja de la unidad cuando avanza: queda
  como tramitado, sin acciones y sin la marca de pendiente.
- El detalle lista los **documentos** del expediente con su estado de firma.

---

## 6. Datos sembrados, para no recorrerlo todo

Las semillas de prueba viven en **`db/90_pruebas/`**, con prefijo `S9xx`. No van
a QA ni a producción, son **repetibles** y **se limpian solas**.

| Script | Qué deja |
|---|---|
| `S909__datos_prueba_pago.sql` | `REQ-PRU-PAGO-0001` en `REQ_OS_EMITIDA` · locador **persona jurídica** · 3 entregables de S/ 1,500, dos ya presentados **en plazo** |
| `S910__datos_prueba_pago_penalidad.sql` | `REQ-PRU-PAGO-0002` en `REQ_OS_EMITIDA` · locador **persona natural** · 2 entregables de S/ 2,000: el 1 llega **10 días tarde** (S/ 166.70 de penalidad) y el 2 en plazo |

```bash
sqlcmd -S 192.168.40.75 -U developer_anin -d DBSIGCM -b -I -i db/90_pruebas/S909__datos_prueba_pago.sql
```

Entre los dos quedan cubiertos los cuatro casos que el módulo distingue: locador
jurídico y natural, entregable con penalidad y sin ella. Correrlos otra vez
reinicia el tramo de pagos sin tocar nada más.

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
