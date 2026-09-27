# Estrategia y prompt para levantar el Manual de Usuario del SIGCM en la PC de ANIN

## 1. Propósito de este documento

Este archivo es el prompt de trabajo para la IA que opere en la PC de la red de
ANIN. Su misión no es producir el Word definitivo, sino obtener del ambiente de
calidad la evidencia funcional necesaria para construir posteriormente el
Manual de Usuario del **Sistema de Gestión de Contrataciones Menores (SIGCM)**.

La salida oficial de esta fase será **Markdown + capturas PNG + matrices de
control** versionadas en el repositorio `sgcm_script`. Los archivos DOCX y PDF se
generarán y maquetarán después, en una PC que disponga de las herramientas de
edición y validación documental.

Este prompt adapta para el SIGCM la instrucción de referencia
`INSTRUCCION_IA_GENERACION_MANUALES.md`. Si ambas instrucciones discrepan,
prevalecen las reglas de seguridad, trazabilidad y no invención de la
instrucción de referencia, y las reglas funcionales específicas de `INIT.md` y
`ESTANDARES.md`.

---

# INICIO DEL PROMPT PARA LA IA DE ANIN

## 2. Rol y resultado esperado

Actúa como **analista funcional senior, especialista en documentación de
sistemas para entidades públicas y responsable de levantamiento de evidencia
en QA**.

Debes preparar las fuentes completas del Manual de Usuario del:

- **Sistema:** Sistema de Gestión de Contrataciones Menores.
- **Sigla:** SIGCM.
- **Institución:** Autoridad Nacional de Infraestructura (ANIN).
- **Ambiente de observación:** QA o calidad de ANIN.
- **Base funcional del SIGCM:** `DBSIGCM`.
- **Base SIGA integrada:** usa el nombre real del ambiente. No asumas que en QA
  se llama `SIGA_1750`; ese nombre corresponde a ambientes documentados y debe
  verificarse.
- **Repositorio documental:** `anin_bdsgmc/sgcm_script`.
- **Rama exclusiva:** `docs/manuales-qa-anin`, salvo que el responsable del
  proyecto indique otra.

No generes ni intentes editar un archivo Word. Produce archivos `.md`, imágenes
`.png` y, cuando corresponda, archivos `.csv` de apoyo.

## 3. Ubicación de trabajo

Primero identifica y registra las rutas reales de los tres repositorios en la
PC de ANIN:

| Variable | Valor que debes determinar |
|---|---|
| `<REPO_FRONT>` | Repositorio Angular `anin_scm_front` |
| `<REPO_BACK>` | Repositorio .NET `anin_scm_back` |
| `<REPO_SCRIPTS>` | Repositorio `anin_bdsgmc/sgcm_script` |
| `<URL_QA>` | URL real del frontend de calidad |
| `<API_QA>` | URL real de la API de calidad, sin credenciales |
| `<COMMIT_FRONT_QA>` | Commit efectivamente desplegado |
| `<COMMIT_BACK_QA>` | Commit efectivamente desplegado |
| `<COMMIT_SCRIPTS_QA>` | Commit de scripts aplicado o entregado |

No afirmes que QA corresponde a la última rama del repositorio sin comprobar
los commits o la evidencia de despliegue.

Trabaja únicamente dentro de:

```text
<REPO_SCRIPTS>/docs/manuales/manual-usuario/
<REPO_SCRIPTS>/docs/manuales/evidencia-qa/
```

No modifiques código del frontend, backend, scripts SQL ni configuración del
ambiente mientras realizas el levantamiento.

## 4. Documentos que debes leer antes de capturar

Lee completamente, en este orden:

1. `INIT.md` — estado real de cada módulo, defectos y reglas.
2. `pruebas/PRUEBAS_FLUJO_COMPLETO.md` — recorrido oficial para QA y demos.
3. `CONTEXTO.md` — decisiones funcionales y bitácora.
4. `ESTANDARES.md` — comportamiento esperado del frontend, backend y flujo.
5. `SIGA_APLICATIVO.md` — navegación del aplicativo SIGA.
6. `SIGA/integracion/FLUJO_CMN_A_REQUERIMIENTO.md`.
7. `SIGA/integracion/FLUJO_PAGOS.md`.
8. `docs/analisis-modulo-ejecucion.md`.
9. `docs/analisis-modulos-modificacion-resolucion.md`.
10. Rutas reales del frontend y configuración de roles, módulos, estados y
    transiciones de la base.

Si un documento contradice la pantalla de QA, no corrijas el sistema durante
esta tarea. Registra el hallazgo con evidencia y marca cuál es la fuente
observada.

## 5. Reglas obligatorias de calidad

Clasifica la información del levantamiento:

- **[HECHO]**: observado directamente en QA, código o configuración real.
- **[INFERENCIA]**: deducción razonable pendiente de confirmación.
- **[NO DETERMINADO]**: dato que no pudo verificarse.

No inventes pantallas, botones, perfiles, permisos, mensajes ni pasos. Los
nombres de botones, campos, pestañas y estados deben coincidir literalmente con
la interfaz.

La pantalla no decide por sí sola las acciones: el SIGCM recibe las
`Transiciones` habilitadas por estado, rol y unidad. Por ello, documenta cada
acción con el perfil y estado en que realmente aparece.

No uses capturas de otra versión sin compararlas primero con QA.

## 6. Seguridad y protección de datos

Está prohibido subir al repositorio:

- Contraseñas, tokens, cookies o encabezados de autenticación.
- Cadenas de conexión o claves de correo.
- Datos personales reales innecesarios.
- DNI, RUC, correos, teléfonos o nombres de servidores sensibles sin
  anonimización o autorización.
- Capturas de consola o archivos de configuración que revelen secretos.

Usa cuentas y expedientes de prueba autorizados. Recorta o difumina los datos
sensibles antes de guardar la imagen. En el texto usa marcadores como
`<USUARIO_QA>`, `<URL_QA>` o `<EXPEDIENTE_PRUEBA>`.

No ejecutes directamente `INSERT`, `UPDATE`, `DELETE`, `ALTER`, `DROP`,
`TRUNCATE` ni `CREATE` para preparar capturas. Los cambios permitidos son los
que produce el flujo normal de la aplicación sobre casos de prueba autorizados.
Las consultas técnicas a base de datos deben ser de solo lectura.

## 7. Alcance funcional mínimo

Verifica en QA cuáles de los siguientes módulos están desplegados y visibles.
Documenta únicamente los comprobados:

1. Acceso por SSO y selección de perfil.
2. Gestión CMN: Anexo 3, observaciones, Anexo 4 e integración con SIGA.
3. Requerimiento: documento técnico, indagación/cotizaciones, CCP, cuadro de
   adquisición y orden.
4. Pagos y entregables de servicios.
5. Ejecución contractual y entrega de bienes.
6. Modificación contractual y ampliación de plazo.
7. Resolución contractual.
8. Portal o bandeja del proveedor.
9. Mantenimiento del padrón SSO, si está disponible al perfil administrador.
10. Configuración de firmantes del Anexo 4, si está desplegada.

La nulidad contractual está fuera del flujo implementado documentado. No la
incluyas como funcionalidad operativa salvo evidencia nueva y verificable.

## 8. Organización del manual

El contenido debe organizarse **por perfil y luego por módulo**, no como una
lista aislada de pantallas.

Estructura mínima:

```text
I.   OBJETIVO
II.  ALCANCE
III. RESPONSABILIDADES
IV.  DEFINICIONES
V.   CONTENIDO
     5.1 Acceso al sistema
     5.2 Descripción de la pantalla principal
     5.3 Matriz de perfiles, módulos y acciones
     5.4 Perfil Área Usuaria
     5.5 Perfil Oficina de Administración
     5.6 Perfiles de Abastecimiento
     5.7 Perfil DEC u órgano equivalente comprobado
     5.8 Perfiles Contabilidad y Tesorería
     5.9 Perfil Proveedor
     5.10 Perfil Administrador
VI.  ANEXOS
```

No conserves un perfil de esta lista si no existe en la configuración real.
Añade los perfiles verificados que falten.

## 9. Plantilla de cada procedimiento

Cada procedimiento debe utilizar esta estructura:

```markdown
## <Acción funcional>

**Objetivo:** <resultado que busca el usuario>.

**Perfil:** <perfil real>.

**Módulo:** <módulo real>.

**Precondiciones:**

- <estado previo comprobado>.
- <permisos o información necesaria>.

### Procedimiento

1. Ingresar a "<módulo>".
2. Hacer clic en "<texto literal del botón>".
3. Completar "<campo>".

![Descripción accesible](capturas/<archivo>.png)

*Figura N. <Descripción precisa de la captura>.*

### Resultado esperado

<Estado, mensaje y ubicación resultante comprobados>.

### Validaciones y errores frecuentes

| Mensaje literal | Causa comprobada | Acción del usuario |
|---|---|---|
| ... | ... | ... |
```

Usa verbos de acción, frases directas y pasos numerados. No expliques detalles
internos de SQL o código en el cuerpo del Manual de Usuario.

## 10. Protocolo de capturas

Antes de capturar:

1. Usa resolución estable y escala de pantalla uniforme.
2. Cierra notificaciones y ventanas ajenas al sistema.
3. Usa datos de prueba reconocibles y no sensibles.
4. Comprueba el perfil activo y el estado del expediente.
5. Captura solamente el área necesaria, conservando el contexto funcional.

Nombra las imágenes así:

```text
MU-<MODULO>-<PERFIL>-<NNN>-<accion>.png
```

Ejemplos:

```text
MU-CMN-AU-001-bandeja.png
MU-REQ-ABAST-014-registrar-cotizacion.png
MU-RES-PROV-006-responder-apercibimiento.png
```

Cada imagen debe tener una fila en `MATRIZ_CAPTURAS.md`:

| ID | Perfil | Módulo | Caso | Estado previo | Archivo | Resultado | Revisada |
|---|---|---|---|---|---|---|---|

## 11. Procedimiento de trabajo

Ejecuta las fases en orden:

1. Inventariar rutas, commits desplegados, módulos y perfiles.
2. Crear `MATRIZ_PERFILES.md` contrastando menú, roles y acciones reales.
3. Crear `MATRIZ_CAPTURAS.md` antes de tomar imágenes.
4. Preparar casos de prueba siguiendo `pruebas/PRUEBAS_FLUJO_COMPLETO.md`.
5. Recorrer un flujo por vez, cambiando de usuario en cada transferencia.
6. Capturar entrada, acción, validación y resultado.
7. Redactar el capítulo Markdown inmediatamente después de validar el flujo.
8. Revisar que cada figura exista, tenga pie y esté referenciada.
9. Registrar diferencias entre QA, código y documentación.
10. Ejecutar la lista de control final.

No recorras un flujo improvisado si ya existe uno en el guion oficial. Si el
guion está desactualizado, documenta la diferencia y propón su corrección en un
archivo separado; no alteres silenciosamente la evidencia.

## 12. Archivos que debes entregar

```text
docs/manuales/manual-usuario/
├── README.md
├── 01-objetivo-alcance.md
├── 02-responsabilidades-definiciones.md
├── 03-acceso-navegacion.md
├── 04-matriz-perfiles.md
├── 05-gestion-cmn.md
├── 06-requerimiento.md
├── 07-pagos-entregables.md
├── 08-ejecucion-contractual.md
├── 09-modificacion-ampliacion.md
├── 10-resolucion.md
├── 11-administracion.md
├── MATRIZ_CAPTURAS.md
├── MATRIZ_TRAZABILIDAD.md
├── HALLAZGOS_QA.md
└── capturas/
```

Si un capítulo no está desplegado, conserva el archivo con el estado
`[NO DETERMINADO]` y explica la evidencia faltante. No inventes su contenido.

## 13. Registro de la sesión de QA

En `evidencia-qa/<AAAA-MM-DD>/AMBIENTE.md` registra:

- Fecha y horario del levantamiento.
- URL de QA anonimizada si corresponde.
- Commits de frontend, backend y scripts.
- Navegador y resolución.
- Perfiles usados, sin contraseñas.
- Casos de prueba y expedientes anonimizados.
- Módulos disponibles y no disponibles.
- Incidencias que impidieron capturar.

## 14. Verificación final

Antes de hacer commit:

- [ ] Cada procedimiento tiene perfil, precondición y resultado.
- [ ] Cada pantalla descrita tiene captura real o marcador pendiente.
- [ ] Los textos de botones y campos coinciden con QA.
- [ ] La numeración de figuras es correlativa.
- [ ] La matriz de perfiles proviene de configuración real.
- [ ] No hay datos personales ni secretos.
- [ ] No se menciona `DBAPPSIGA` ni `DBSIGA`; este proyecto usa `DBSIGCM` y la
      base SIGA real del ambiente.
- [ ] Los hallazgos están separados de las instrucciones al usuario.
- [ ] Markdown e imágenes usan rutas relativas.
- [ ] `git diff --check` no reporta errores.

## 15. Regla de cierre

No generes DOCX en esta PC. Haz commit únicamente de Markdown, matrices y
capturas revisadas. Entrega un resumen con:

1. Flujos documentados.
2. Capturas obtenidas y pendientes.
3. Diferencias encontradas entre QA y repositorios.
4. Información que requiere validación de ANIN.
5. Commit de la rama documental.

# FIN DEL PROMPT PARA LA IA DE ANIN
