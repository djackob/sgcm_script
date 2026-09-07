# Observaciones — Mesa de trabajo Abastecimiento / AU

Fuente: reuniones con usuarios de Abastecimiento y Área Usuaria (septiembre 2026).  
Documento vivo: se actualiza con lo vertido en cada mesa.

Leyenda de estado:

| Estado | Significado |
|---|---|
| **Hecho** | Implementado en código / semilla / BD local |
| **Parcial** | Base lista; falta UI operativa, asignación SSO o ajuste de flujo |
| **Pendiente** | Aún no desarrollado |

---

## I. Módulo de gestión de CMN y modificaciones (Anexos 3 y 4)

1. **Notificación al "Punto Focal"**  
   Al completarse la aprobación del CMN, la notificación automática no debe enviarse únicamente al Jefe de la AU, sino también al Punto Focal / especialista de la oficina requirente.  
   **Estado: Parcial** — Columna `sigcm.UsuarioRol.EsPuntoFocal` (V030); F013 prioriza focales en CC (si no hay, mantiene coord/especialistas). Falta pantalla SSO para marcar quién es punto focal.

2. **Integración de múltiples solicitudes en un solo Anexo 4**  
   Consolidar inclusiones/exclusiones de distintas Áreas Usuarias en un Anexo 4 unificado para firma en lote.  
   **Estado: Hecho** — Paquete `cmn.Paquete` / `paGenerarAnexo4` / firma lote en front.

3. *(mesa anterior)* Finalizar CMN al firmar Anexo 4 (sin recepción del jefe AU).  
   **Estado: Hecho** — S020; destino `CMN_FINALIZADO`.

4. *(mesa anterior)* Corregir envío de correo tras firma del Anexo 4.  
   **Estado: Parcial** — Cuerpo F013 actualizado (ya no pide recepción); SMTP configurado. Validar en caliente con servidor institucional.

5. *(mesa anterior)* Limpieza de trazabilidad (ocultar firmas/derivaciones preliminares de Abastecimiento).  
   **Estado: Hecho** — Visor CMN filtra hitos internos.

6. *(mesa anterior)* Perfil Secretaria de Abastecimiento (derivar sin firmar).  
   **Estado: Parcial** — Rol `ABAST_SECRETARIA` + TransicionRol (S021). Falta asignar usuarios en SSO.

---

## II. Perfiles, roles y bandejas de derivación

1. **Perfil de "Punto Focal" en el Área Usuaria**  
   Rol de especialista administrativo de la AU: formular requerimiento inicial (Anexo 5 y TDR), recibir alertas de observaciones técnicas y coordinar el expediente antes de derivarlo a la firma del Jefe de la AU.  
   **Estado: Pendiente** — Hoy el especialista AU ya formula; falta formalizar el perfil “Punto Focal” (permisos/bandeja/alertas) distinto o como marca sobre `AREA_ESPECIALISTA`.

2. **Visaciones y vistos buenos intermedios (Área Usuaria)**  
   Antes de la firma del Jefe AU (p. ej. Inversiones), permitir que Especialista o Gerente de Proyecto registre un V.B. / visación digital en el requerimiento, asumiendo responsabilidad técnica previa al despacho del Jefe.  
   **Estado: Pendiente** — Requiere transición/documento de V.B. en el circuito AU de Requerimiento.

---

## III. Módulo de formulación de requerimientos y TDR (Anexo 5 y Anexo 3)

1. **Denominación única con múltiples metas (mapeo de inversiones)**  
   Un TDR asociado a varios pedidos SIGA (metas / CUI distintos) para un solo locador; denominación única en cabecera y metas/pedidos en grilla.  
   **Estado: Hecho** — Registro Anexo 5 con N pedidos; denominación única.

2. **Asistente de validación para correos electrónicos**  
   Validar formato del correo del locador y sugerir dominios (@gmail.com, @outlook.com, etc.).  
   **Estado: Hecho** — `form-proveedor` con validación + datalist de dominios.

3. **Bloqueo y heredabilidad del Área de Conformidad**  
   Autocompletar con la oficina emisora de cabecera y bloquear edición manual.  
   **Estado: Hecho** — Campo bloqueado en TDR Anexo 3.

4. **Informe de validación previa (V.B. de terceros)**  
   Check opcional: la conformidad exige informe previo de otra unidad / especialista (ej. validación funcional antes de conformidad OTI).  
   **Estado: Hecho** — Check + campo en TDR; sale en PDF si está activo.

5. *(mesa anterior)* Experiencia específica opcional (check); experiencia general siempre obligatoria.  
   **Estado: Hecho**.

6. *(mesa anterior)* Reescribir ayuda del Objetivo de la contratación (resultado técnico de las actividades).  
   **Estado: Hecho**.

---

## IV. Módulo de indagación de mercado y contratación

1. **Disparador y gestión de la "Debida Diligencia"**  
   Abastecimiento no envía a cotizar sin pasar controles de debida diligencia: check obligatorio + carga PDF antes de habilitar “Enviar a Cotizar”.  
   **Estado: Pendiente** — Hoy la DD vive en filtros de idoneidad posteriores a la cotización.

2. **Validación del correo del locador y check de cotización**  
   Envío automático de Anexo 6 / TDR / DJ Anexo 7 al correo del Anexo 5; al retornar, el especialista de Abastecimiento valida el archivo y marca check para adjuntarlo al expediente.  
   **Estado: Parcial** — Existe envío de indagación / respuesta locador; falta el check formal de “cotización validada y adjuntada” como puerta de avance.

3. **Exclusión del perfil de Presupuesto**  
   UP no accede al sistema web; CCP por SGD externo. El sistema solo muestra “Solicitado a CCP” y permite a Abastecimiento cargar PDFs de la CCP aprobada.  
   **Estado: Pendiente** — Aún hay flujo/UI hacia OPP (memo, previsión). Hay que retirar UP del circuito web y dejar solo marca + carga CCP en Abastecimiento.

4. *(mesa anterior)* Visor en Contabilidad/Pagos de documentos de fase preparatoria (TDR, Anexo 6, RNP, SUNAT, CCP) sin volver a cargar.  
   **Estado: Pendiente**.

---

## Orden sugerido de lo pendiente

1. Debida Diligencia como puerta antes de “Enviar a Cotizar”  
2. Excluir UP / simplificar CCP (solo estado + carga PDF Abastecimiento)  
3. Check de cotización validada al retorno del locador  
4. Perfil Punto Focal formal + UI para marcar `EsPuntoFocal`  
5. V.B. intermedio AU antes de firma del Jefe  
6. Visor de documentos preparatorios en Pagos  

---

## V. Ajustes UX Anexo 5 / Anexo 3 TDR (mesa 2026-09-04)

1. **Denominación debajo de Pedidos +**  
   El campo «Denominación de la contratación» debe ir como cabecera debajo del botón Pedidos +.  
   **Estado: Hecho**

2. **Validación UIT legible e inline**  
   Miles con coma; «x» → «por»; mensaje en texto pequeño rojo junto al campo (no modal al pulsar Guardar).  
   **Estado: Hecho**

3. **Ocultar ítems por defecto del Anexo 3 en el formulario**  
   No mostrar en pantalla los bloques de solo lectura (marco legal, textos fijos, etc.); sí en el PDF.  
   **Estado: Hecho**

4. **Viñetas y tabulaciones en impresión del Anexo 3**  
   Respetar viñetas/sangrías al generar el PDF.  
   **Estado: Hecho**

5. **Placeholders cortos en campos editables**  
   En lugar del párrafo ejemplo, iniciales por sección (ej. «finalidad 1»).  
   **Estado: Hecho**

6. **Intro de actividades (sección 5) como label**  
   «Las actividades que realizará el CONTRATISTA…» es label en el form; sí se imprime en el reporte.  
   **Estado: Hecho**

7. **Días calendario acumulativos (no sumatoria de tramos)**  
   Cada campo es el día límite acumulado (30, 50, 60, 120); el último = plazo.  
   **Estado: Hecho**

8. **Números en literal en entregables**  
   Ej.: «hasta los cinco (05) días…».  
   **Estado: Hecho**

9. **Otras Penalidades = sección 12**  
   No subordinada al 11; renumerar consideraciones siguientes.  
   **Estado: Hecho**

10. **Validaciones del Anexo 3 junto al campo**  
    Mensajes en rojo bajo la caja (o foco a la sección), no solo modal.  
    **Estado: Hecho**

11. **Administrador de textos por defecto del Anexo 3**  
    Los textos fijos/plantilla deben vivir en un administrador (cambian con directiva).  
    **Estado: Pendiente** — hoy están hardcodeados en `anexo3-tdr.plantilla.ts`.

---

*Última actualización: 2026-09-04 — bloque V (ajustes UX Anexo 5/3).*
