# Plan de tickets — Módulo Requerimiento (especificación 18/09/2026)

Fuente: adaptación UI por objeto, multipedido SIGA, TDR Anexo 3, workflow AU, adjuntos, cotización, idoneidad, CCP/O/S.  
Baseline: `jack5` (`sgcm_front`, `sgcm_back`, `sgcm_script`).  
Fecha del plan: 2026-09-18.

Orden = prioridad de negocio + dependencias. No abrir el siguiente bloque crítico hasta cerrar el anterior, salvo tickets marcados como **paralelos**.

---

## Cómo leer cada ticket

| Campo | Significado |
|---|---|
| **Capas** | `script` / `front` / `back` |
| **Semillas** | `S*` nuevas o a tocar |
| **Depende de** | Tickets previos |
| **Aceptación** | Criterio de demo |

---

## Estado actual (resumen)

| # | Bloque | Estado | Prioridad |
|---|---|---|---|
| 1 | Ocultar Anexo 5 / objetos no-locación | **PARCIAL** | Crítica |
| 2 | Multipedido + CUI / metas | **PARCIAL** | Alta |
| 3 | Anexo 3 TDR rediseño | **YA** (detalles menores) | Media |
| 4 | Workflow AU (salto Coord / GP) | **PARCIAL** | Alta |
| 5 | Adjuntos complementarios | **PARCIAL** | Media |
| 6 | Cotización Word + Correo Cotización | **PARCIAL** | Crítica |
| 7 | Idoneidad + eval TDR + devolver | **YA** (gaps menores) | Media |
| 8 | CCP 4 archivos + O/S 3 firmas + SSO | **PARCIAL** | Crítica |

Locación ≤ 8 UIT está avanzada. Los huecos grandes son: objetos Bien/Servicio/Consultoría, evidencia “Correo de Cotización”, 4.º archivo CCP, circuito firmas O/S Esp→Coord→Jefe, Coordinador AU opcional.

---

## Tickets

### T1 — Objeto de contratación: ocultar Anexo 5 (crítica)

| | |
|---|---|
| **Capas** | front (+ validación `F005` si hace falta) |
| **Semillas** | Tipos doc `S003` ya existen (`REQ_EETT_BIEN`, `REQ_TDR_SERVICIO`, `REQ_TDR_CONSULTORIA`) |
| **Depende de** | — |
| **D3** | Selector **encima** de las pestañas. Bien/Servicio/Consultoría activos. |
| **Aceptación** | Locación → Anexo 5 + proveedor + Anexo 3. Bienes/Servicios/Consultorías → sin Anexo 5 ni proveedor; pestaña Datos + Anexo 1/2/4. |

### T2 — Correo de Cotización (evidencia print/PDF) (crítica)

| | |
|---|---|
| **Capas** | front + script (`F011`/`F008`) + tipo documento |
| **Semillas** | `S0xx` tipo `REQ_CORREO_COTIZACION` (obligatorio en transición Abast) |
| **Depende de** | — (paralelo a T1) |
| **Aceptación** | Especialista Abast no avanza sin adjuntar PDF/captura del correo de cotización. |

### T3 — Plantillas Word Anexo 6/7 en repo (crítica)

| | |
|---|---|
| **Capas** | front `assets/plantillas` |
| **Semillas** | — |
| **Depende de** | — (paralelo) |
| **Aceptación** | Tras No Objeción / indagación se generan `.docx` con datos del TDR; CCI/banco/firma libres. |

### T4 — CCP: 4 archivos (crítica)

| | |
|---|---|
| **Capas** | front `modal-cargar-ccp` + `F008` |
| **Semillas** | extender `S007` (Memo ida, CCP Abast, Memo respuesta Presupuesto, CCP aprobada) |
| **Depende de** | — |
| **Aceptación** | Carga múltiple de los 4 sustentos; validación completa antes de continuar. |

### T5 — O/S: subir PDF SIGA + 3 firmas Esp→Coord→Jefe + SSO (crítica)  *[D1]*

| | |
|---|---|
| **Capas** | front + `F003`/`F008` |
| **Semillas** | `TipoDocumentoFirma` para `REQ_ORDEN_SERVICIO`; estados de firma |
| **Depende de** | T4 |
| **D1** | Solo se firma el PDF del SIGA (o uno ya firmado subido como documento). **No** se firma el PDF generado en web. |
| **Aceptación** | Especialista sube PDF O/S SIGA (o adjunto ya firmado). Si no viene firmado: Esp→Coord→Jefe. Al firmar Jefe: notifica + SSO locador (DNI) + credenciales. |

### T6 — _(absorbido en T5 por D1)_

La opción “subir PDF SIGA” es el camino principal de T5; no hay ticket aparte de generación web a firmar.

### T7 — Workflow AU: Coordinador opcional + Gerente Proyecto (alta)  *[D2]*

| | |
|---|---|
| **Capas** | seeds + front destinos |
| **Semillas** | `S0xx` + rol/perfil **Gerente de Proyecto** (distinto de Coordinador AU) |
| **Depende de** | — (paralelo a T1–T4) |
| **D2** | GP ≠ Coordinador. |
| **Aceptación** | Dependencia simple: Esp/PF → Jefe. Compleja: Esp → Coord y/o GP → Jefe. |

### T8 — Multipedido: CC en grilla + CUI/nombre en encabezado PDF (alta)

| | |
|---|---|
| **Capas** | front `form-pedido` + `anexo3.pdfmake` (+ Anexo 5 si aplica) |
| **Semillas** | — (maestro SIGA ya trae `TipoActProy` / nombre) |
| **Depende de** | — |
| **Aceptación** | Cada pedido muestra CC. Si inversión: encabezado/PDF con CUI + nombre del proyecto. |

### T9 — Adjuntos complementarios no obligatorios (media)

| | |
|---|---|
| **Capas** | front registro/detalle + `F003`/`F005` |
| **Semillas** | `S0xx` tipo adjunto genérico |
| **Depende de** | T1 (todos los objetos) |
| **Aceptación** | Zona `file_upload` en Bienes/Servicios/Consultorías/Locación; no bloquea el flujo. |

### T10 — Post-idoneidad: editar Anexo 5 o cancelar (media)

| | |
|---|---|
| **Capas** | front + seeds |
| **Semillas** | extender `S014` / anulaciones |
| **Depende de** | — |
| **Aceptación** | Tras devolver por impedimento/perfil: AU puede cambiar propuesta (Anexo 5) o cancelar el requerimiento. |

### T11 — Anexo 3: Marco Legal visible solo lectura en UI (media)

| | |
|---|---|
| **Capas** | front |
| **Semillas** | — |
| **Depende de** | — |
| **Aceptación** | Sección 1 visible en pantalla (no editable); PDF sin cambio de contenido. |

### T12 — Punto Focal como formulador (media)

| | |
|---|---|
| **Capas** | SSO + front |
| **Semillas** | perfiles SSO / `PerfilSso` |
| **Depende de** | T7 |
| **Aceptación** | PF puede formular Anexo 5/TDR con el mismo circuito que Especialista AU. |

---

## Orden de ejecución sugerido

```
MVP (cerrar primero):
  T1 (objeto / Anexo 5)  ║  T2 (Correo Cotización)  ║  T3 (plantillas Word)
  T4 (4 CCP) → T5 (PDF SIGA + firmas + SSO)   [T6 absorbido]

En paralelo / después:
  T7 (workflow AU + perfil GP)  ║  T8 (CUI / CC grilla)
  T9 adjuntos → T10 post-idoneidad → T11 marco legal UI → T12 punto focal
```

---

## Ya cubierto (no reabrir salvo regresión)

- Anexo 3 TDR: plazo heredado, entregables prorrateados, experiencia específica check, conformidad + informe previo, AU bloqueada.
- Idoneidad 5 checks + eval cumplimiento TDR + devolver a AU.
- Multipedido básico + denominación única.
- Invitación cotización / paquete integridad (falta evidencia “Correo Cotización” y `.docx` en repo).

---

## Decisiones de negocio (CERRADAS — 2026-09-18)

| # | Decisión | Impacto en tickets |
|---|---|---|
| **D1** | Solo se firma el PDF que viene del SIGA (o el usuario sube uno **ya firmado** como documento). No se firma el PDF generado en web. | **T5/T6:** flujo = subir PDF SIGA → circuito firmas **o** adjuntar PDF ya firmado. Quitar generación web como documento a firmar. |
| **D2** | **Gerente de Proyecto** es un **perfil distinto** del Coordinador AU. | **T7:** rol/perfil propio + transición intermedia opcional. |
| **D3** | Bien / Servicio / Consultoría **entran en el release**. El selector de objeto sale del tab Anexo 5 y se coloca **encima de las pestañas**; según la elección el sistema muestra u oculta Anexo 5 / proveedor / documento técnico (Anexo 1/2/3/4). | **T1:** alcance completo de objetos + UI del selector. |

### Ajustes a tickets por D1–D3

- **T1:** selector arriba; tabs dinámicas; Locación → Anexo 5 + Anexo 3; resto → Datos + Anexo 1/2/4 (sin Anexo 5 ni proveedor).
- **T5 + T6:** fusionar en la práctica: no hay “firmar PDF generado en SGCM”; hay “subir O/S SIGA” y opcionalmente “adjuntar ya firmada”.
- **T7:** semilla/rol `GERENTE_PROYECTO` (o nombre SSO acordado), no reutilizar Coordinador.
