# Reglas de negocio del SIGCM según el mockup

Fuente: `mockup/sigcm/README.md` y `mockup/sigcm/app.js`, contrastados contra lo
ya implementado en `SIGCM_SERVER/db`. El mockup es la **especificación funcional
aprobada**: lo que aquí se describe es lo que el sistema debe hacer, y cualquier
diferencia con la implementación es una desviación a corregir, no una variante.

Alcance de este documento: **Gestión CMN** y **Requerimiento a Notificación**.
Los otros cuatro módulos del mockup (Ejecución, Pago, Modificación-Ampliación,
Resolución) quedan fuera hasta que estos dos estén cerrados.

Cada regla lleva un identificador (`CMN-nn`, `REQ-nn`) para poder citarla en un
commit, en una tarea o en un comentario de código.

---

## 1. Perfiles y matriz de acceso

El acceso presenta **12 opciones para nueve grupos funcionales**. Área usuaria y
Unidad de Abastecimiento se desagregan porque sus tareas, firmas y autorizaciones
**no son intercambiables** — ésa es la razón, y por eso no se pueden colapsar en
un solo perfil por área.

| Perfil del mockup | Código en la base |
|---|---|
| Área usuaria · Jefe | `AREA_JEFE` |
| Área usuaria · Especialista | `AREA_ESPECIALISTA` |
| Oficina de Administración | `OA` |
| Unidad de Abastecimiento · Jefe | `ABAST_JEFE` |
| Unidad de Abastecimiento · Coordinador | `ABAST_COORDINADOR` |
| Unidad de Abastecimiento · Especialista | `ABAST_ESPECIALISTA` |
| DAI | `DAI` |
| Planeamiento y Presupuesto (OPP) | `OPP` |
| Unidad de Contabilidad | `CONTABILIDAD` |
| Unidad de Tesorería | `TESORERIA` |
| Mesa de Partes | `MESA_PARTES` |
| Proveedor | `PROVEEDOR` |

Además, la base define `MAX_AUT_ADMIN` (segunda firma del Anexo 4),
`ADMIN_SISTEMA` y dos cuentas técnicas (`SVC_INTEGRACION`, `SVC_CONCILIACION`).
Las técnicas **no operan pantallas**.

**ACC-01** — Matriz módulo ↔ perfil:

| Módulo | Perfiles con acceso |
|---|---|
| Gestión CMN | Unidad de Abastecimiento; Oficina de Administración; Área usuaria |
| Requerimiento a Notificación | Área usuaria; OA; DAI; Unidad de Abastecimiento; OPP |

**ACC-02** — Tras el ingreso se abre directamente **Mi bandeja**. El menú lateral
contiene únicamente Mi bandeja y los módulos autorizados. Se retiraron Inicio,
Expedientes, Alertas, Reportes y Auditoría de la navegación, junto con la
búsqueda global y el centro superior de notificaciones.

**ACC-03** — Las pantallas de módulo muestran directamente su encabezado y su
bandeja. Se retiraron los bloques «Flujo por perfil», «Responsabilidades del
perfil» y las acciones rápidas.

> **Estado**: implementado. `sigcm.RolModulo` es la matriz y `sigcm.Modulo.Ruta`
> la navegación; el menú se arma desde ahí. La bandeja de CMN ya cumple ACC-03.

---

## 2. Gestión CMN

Modificación del Cuadro Multianual de Necesidades conforme a la **Directiva
N.° 0007-2025-EF/54.01**: generación del **Anexo 3** (solicitud de modificación) y
del **Anexo 4** (aprobación de modificaciones).

### 2.1 Responsabilidades

**CMN-01** — **Área usuaria · Especialista**: verifica la disponibilidad en SIAF,
registra y sustenta el Anexo 3, administra sus ítems, atiende observaciones y
deriva al Jefe cuando se requiere firma o envío externo. **No firma y no envía.**

**CMN-02** — **Área usuaria · Jefe**: firma digitalmente el Anexo 3, aprueba su
envío o reenvío, recepciona formalmente las observaciones y recepciona el Anexo 4
individual o consolidado para cerrar el flujo.

**CMN-03** — **Oficina de Administración**: revisa el Anexo 3 firmado. Puede
observarlo y devolverlo al Área usuaria o, si está conforme, derivarlo a
Abastecimiento. **No registra solicitudes.**

**CMN-04** — **Unidad de Abastecimiento**: revisa el Anexo 3, registra si la
inclusión es **ordinaria o urgente**, observa o aprueba. Con solicitudes
conformes genera, firma y envía el Anexo 4, individual o consolidado.

### 2.2 Estados

**CMN-05** — Secuencia de estados del mockup y su correspondencia con la base:

| Mockup (`CMN_STATE`) | Base (`sigcm.Estado`) | Rol responsable |
|---|---|---|
| Registrar Anexo 3 | `CMN_BORRADOR` | `AREA_ESPECIALISTA` |
| Por firmar AU | `CMN_PEND_FIRMA_A3` | `AREA_JEFE` |
| Firmado Anexo 3 | `CMN_A3_FIRMADO` | `AREA_JEFE` |
| En evaluación OA | `CMN_EN_EVAL_OA` | `OA` |
| En evaluación UA / Derivado a UA | `CMN_EN_EVAL_UA` | `ABAST_ESPECIALISTA` |
| Observado | `CMN_OBSERVADO` | `AREA_ESPECIALISTA` |
| — | `CMN_VALIDADO_UA` | `ABAST_COORDINADOR` |
| Generar Anexo 4 | `CMN_PEND_FIRMA_A4` | `ABAST_JEFE` |
| Firmar digitalmente Anexo 4 | `CMN_A4_FIRMADO` | `ABAST_JEFE` |
| Enviar Anexo 4 | `CMN_A4_ENVIADO` | `AREA_JEFE` |
| Recepcionar Anexo 4 → Fin | `CMN_FINALIZADO` | — |

**Diferencias detectadas al contrastar** (ninguna es un error, pero deben quedar
por escrito):

- `CMN_VALIDADO_UA` **no existe en el mockup**. La base lo introduce para separar
  «Abastecimiento aprobó» de «hay que generar el Anexo 4», que en el mockup son
  el mismo momento (`anexo3_approved`). Es el punto donde se encola la escritura
  a SIGA, así que la separación es necesaria.
- El mockup tiene dos estados de notificación de observación
  (`NOTIFICAR_OBSERVACION`, `RECEPCIONAR_NOTIFICACION`) que la base modela como
  un solo estado `CMN_OBSERVADO` más el ciclo de vida de `sigcm.Observacion`
  (creada → recepcionada → subsanada → cerrada). **Falta verificar** que la
  pantalla pueda distinguir «observación por recepcionar» de «observación
  recepcionada, por subsanar», que en el mockup son dos acciones distintas del
  Área usuaria.
- El mockup usa `CMN_ANULADO` sin nombrarlo; la base lo define con dos
  transiciones de anulación (desde borrador y desde pendiente de firma).

### 2.3 Flujo principal

**CMN-06** — El Área usuaria registra el Anexo 3 con su sustento y **al menos un
ítem**.

**CMN-07** — Si lo prepara el Especialista, lo deriva al Jefe. El Jefe revisa y
**firma digitalmente** el documento.

**CMN-08** — El Jefe envía el Anexo 3 a OA; el expediente queda *En evaluación OA*.

**CMN-09** — OA revisa la integridad del documento: si observa, la notificación
llega **al Jefe** del Área usuaria; si está conforme, deriva a Abastecimiento.

**CMN-10** — Abastecimiento revisa el Anexo 3 y selecciona el **tipo de
inclusión: Ordinario o Urgente**.

**CMN-11** — Si Abastecimiento observa, notifica al Área usuaria. Si aprueba, el
expediente queda listo para generar el Anexo 4.

**CMN-12** — Abastecimiento genera y firma el Anexo 4. Puede procesarlo
individualmente **o seleccionar dos o más solicitudes conformes** para generar un
único Anexo 4 consolidado.

**CMN-13** — Abastecimiento envía el Anexo 4 al Área usuaria. En el envío
consolidado se crea **una sola entrada de recepción** con la referencia de todos
los expedientes incluidos.

**CMN-14** — El Jefe del Área usuaria recepciona el Anexo 4. La recepción
finaliza la entrada consolidada **y todos los expedientes relacionados**.

### 2.4 Observación y subsanación

**CMN-15** — OA y Abastecimiento pueden registrar el **motivo** de la observación.

**CMN-16** — El Área usuaria debe **recepcionar la notificación antes de
corregir**. Son dos pasos, no uno.

**CMN-17** — La subsanación permite modificar el sustento **y el contenido
completo** del Anexo 3.

**CMN-18** — Si se actualiza un Anexo 3 ya firmado, **la firma anterior se
invalida** y el Jefe debe firmar nuevamente.

**CMN-19** — Una observación de OA retorna **a OA** después de la subsanación.
Una observación de Abastecimiento retorna **directamente a Abastecimiento**.

**CMN-20** — El documento corregido **no puede reenviarse** hasta contar con la
nueva firma del Jefe.

### 2.5 Ítems y documentos

**CMN-21** — Cada ítem contiene código, descripción, unidad de medida, cantidad y
valor.

**CMN-22** — Por cada ítem se registra **exclusión o inclusión, nunca ambas**; el
grupo seleccionado exige cantidad y valor completos.

**CMN-23** — La tabla es dinámica pero **debe conservar al menos un ítem**.

**CMN-24** — El Anexo 3 muestra el responsable del Área usuaria. El Anexo 4
representa **dos firmantes**: responsable de Abastecimiento y máxima autoridad
administrativa.

**CMN-25** — Ambos anexos disponen de **visor, impresión/PDF, huella y firma
digital simulada**.

---

## 3. Requerimiento a Notificación

Desde el registro de la necesidad hasta la emisión y notificación de la orden.

### 3.1 Registro inicial

**REQ-01** — El registro captura: denominación, objeto, DEC, disponibilidad
presupuestal, condición CMN, monto, ATE, RUC, plazo, sustento y **uno o más
pedidos SIGA**.

**REQ-02** — Los datos presupuestales y del pedido **se precargan desde SIGA**;
los campos derivados de SIGA son de **solo lectura**.

**REQ-03** — Si la necesidad **está incluida en el CMN**, se solicita el Anexo 1
firmado.

**REQ-04** — Si **no está incluida**, se habilita el acceso a Gestión CMN y se
exige seleccionar un **Anexo 4 finalizado** o adjuntar un Anexo 4 firmado. Éste
es el punto de unión entre los dos módulos.

**REQ-05** — Se registra la evidencia del saldo disponible o de la habilitación
aprobada.

**REQ-06** — El monto debe ser **mayor que cero y no superar ocho UIT**. Para
2026 el prototipo usa **S/ 44 000**.

### 3.2 Documentos según el objeto

**REQ-07** — Cuatro tipos de objeto o prestación: **Bien, Servicio, Consultoría y
Locación**.

| Objeto | Documento | Formato |
|---|---|---|
| Bien | EETT | Anexo 1 (pp. 21–26) |
| Servicio | TDR | Anexo 2 (pp. 27–31) |
| Locación | propuesta del Área usuaria **y luego** TDR | Anexo 5 (p. 42) → Anexo 3 (pp. 32–37) |
| Consultoría | TDR | Anexo 4 (pp. 38–41) |

**REQ-08** — En **Locación** el orden es obligatorio: **Anexo 5 → firma del Jefe
→ TDR Anexo 3 → firma del Jefe**. El Anexo 5 admite **entre una y cinco
propuestas**; no exige terna.

**REQ-09** — Los pedidos SIGA vinculados se reflejan en ambos documentos y **no
se vuelven a capturar**.

**REQ-10** — Cada formato tiene formulario y visor independientes. La firma
digital corresponde **al Jefe o titular del Área usuaria**; el Especialista
elabora y deriva.

**REQ-11** — El requerimiento inicial es editable **solo** mientras está en
borrador o durante una subsanación formalmente recepcionada. Fuera de esas
etapas, el formulario funciona como **visor de solo lectura**.

### 3.3 Flujo principal

**REQ-12** — El Especialista registra el requerimiento y vincula uno o más
pedidos SIGA.

**REQ-13** — Se elaboran los documentos según el objeto.

**REQ-14** — El Jefe aprueba y remite:
- DEC = Unidad de Abastecimiento → Área usuaria → **OA** → Abastecimiento
- DEC = DAI → Área usuaria → **DAI**, sin pasar por OA

**REQ-15** — OA revisa el expediente completo, **incluidos los visores
impresos**. Puede observar o derivar.

**REQ-16** — En Abastecimiento, el **Especialista** recepciona y revisa; el
**Coordinador** registra el resultado: conforme, observado, o con mejoras sujetas
a no objeción.

**REQ-17** — Si está conforme, el Especialista inicia la **indagación de
mercado**. Locación requiere **una** cotización válida; los demás objetos
requieren **dos o más**, salvo excepción validada.

**REQ-18** — Las consultas u observaciones de mercado retornan al Área usuaria.
Si la respuesta **modifica el TDR**, se genera una nueva versión, el Jefe vuelve
a firmarla y se remite a la DEC mediante SGD.

**REQ-19** — El Área usuaria valida técnicamente la cotización u ofertas. Si no
cumplen, **la indagación se reinicia**.

**REQ-20** — El Coordinador confirma el proveedor seleccionado:
- una sola cotización de Locación → **no** se genera el Anexo 8
- dos o más cotizaciones válidas → se genera y suscribe el **Anexo 8, Cuadro de
  Cotizaciones**

**REQ-21** — El Coordinador registra la solicitud de **CCP o previsión** en SIAF
WEB y la remite por SGD a OPP.

**REQ-22** — OPP aprueba u observa. Si observa, devuelve a la DEC para corregir y
solicitar nuevamente. Si aprueba, remite la CCP a la DEC. **OPP no aprueba el
cuadro de cotizaciones.**

**REQ-23** — El Especialista recepciona la CCP; el Coordinador verifica la
integridad del expediente y lo deja listo para perfeccionamiento.

**REQ-24** — El **Jefe de Abastecimiento** emite la orden: **OC** para bienes,
**OS** para servicios, consultorías o Locación.

**REQ-25** — El Especialista notifica la orden al proveedor por correo
institucional, **con copia al Jefe del Área usuaria**, y finaliza el flujo.

### 3.4 Observación y subsanación

**REQ-26** — OA o la DEC pueden observar el expediente.

**REQ-27** — El Área usuaria primero **recepciona** la observación y después abre
la subsanación integral.

**REQ-28** — La subsanación puede corregir datos generales, pedidos SIGA, Anexo 5
y documento técnico; **no se limita** al pedido inicialmente observado.

**REQ-29** — Si se modifica un anexo firmado, **se invalida la firma anterior** y
se exige nueva firma del Jefe. (Misma regla que CMN-18.)

**REQ-30** — En la ruta de Abastecimiento, la subsanación **conserva el circuito**
Área usuaria → Jefe → OA → Abastecimiento.

**REQ-31** — La falta de cotizaciones produce reiteraciones; tras los intentos
simulados, el expediente puede **retornar al Área usuaria para reformulación**.

---

## 4. Plazos de la Directiva

Aplicables a los dos módulos. La base los tiene sembrados en `S002__plazos_directiva.sql`.

| Regla | Plazo |
|---|---|
| **PLZ-01** Requerimiento presentado antes del inicio previsto | 10 días hábiles |
| **PLZ-02** Revisión y subsanación del requerimiento, por etapa | hasta 2 días hábiles |
| **PLZ-03** Cotización | hasta 3 días hábiles, ampliable |
| **PLZ-04** Cotizaciones mínimas | 2, salvo excepción; Locación de persona natural acepta 1 |
| **PLZ-05** Consultas de mercado al Área usuaria: pronunciamiento | 1 día hábil |
| **PLZ-06** Validación técnica | 2 días hábiles |
| **PLZ-07** CCP / previsión presupuestal | 1 día hábil |
| **PLZ-08** Conformidad | 7 días calendario; 20 para consultorías o con pruebas |
| **PLZ-09** Subsanación del entregable | no mayor al 30 % del plazo del entregable |
| **PLZ-10** Penalidades por mora y otras | tope conjunto 10 % |
| **PLZ-11** Pago: remisión a Contabilidad | 3 días hábiles |
| **PLZ-12** Control previo y subsanación | 2 días hábiles |

Los días hábiles se calculan con `sigcm.fnSumarDiasHabiles`, que descuenta fines
de semana y los feriados de `sigcm.DiaNoHabil`.

---

## 5. Decisiones funcionales pendientes

El propio mockup las deja abiertas. **Ninguna debe resolverse escribiendo
código**: requieren pronunciamiento del área funcional.

1. ¿El Anexo 4 CMN individual sigue permitido, o todo envío debe ser consolidado
   desde dos solicitudes?
2. ¿Qué subrol de Abastecimiento firma el Anexo 4, y cómo se representa la
   segunda firma de la máxima autoridad administrativa?
3. ¿Cómo se desagrega DAI internamente? Hoy está representado como una sola DEC.
4. ¿Número máximo de propuestas del Anexo 5? El mockup usa el límite físico de
   cinco filas del formato.
5. ¿La excepción de una cotización y la no generación del Anexo 8 aplican a toda
   Locación de persona natural?
6. ¿La notificación final copia solo al Jefe del Área usuaria, o también al
   Especialista responsable?

Se suma una séptima, detectada al contrastar con la base:

7. El techo presupuestal multianual **no se ha localizado en SIGA**:
   `PPTO_ANNO_01..03` está en cero en las 2 375 filas de 2026. Hoy el control de
   techo solo puede hacerse sobre el año base. ¿Se acepta esa limitación en la
   v1?
