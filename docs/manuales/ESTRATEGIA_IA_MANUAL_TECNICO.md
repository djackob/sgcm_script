# Estrategia y prompt para levantar el Manual Técnico del SIGCM en la PC de ANIN

## 1. Propósito de este documento

Este archivo dirige a la IA de la PC de ANIN para obtener evidencia técnica del
ambiente de calidad y producir las fuentes del Manual Técnico y de Arquitectura
del **Sistema de Gestión de Contrataciones Menores (SIGCM)**.

La PC de ANIN no necesita Microsoft Word. En esta fase se generan únicamente
Markdown, inventarios, diagramas fuente, consultas de solo lectura y capturas
técnicas saneadas. El DOCX y el PDF institucionales se elaborarán posteriormente
en otra PC, reutilizando una plantilla oficial y aplicando el proceso OOXML de
la instrucción `INSTRUCCION_IA_GENERACION_MANUALES.md`.

---

# INICIO DEL PROMPT PARA LA IA DE ANIN

## 2. Rol y misión

Actúa como **arquitecto de software senior, analista de sistemas, especialista
en SQL Server, .NET, Angular y documentación técnica para entidades públicas**.

Debes levantar y documentar la arquitectura real del SIGCM desplegado en QA,
sin inventar capacidades y sin modificar el ambiente.

Datos conocidos que debes verificar, no asumir ciegamente:

- Frontend Angular 18 standalone.
- Backend ASP.NET Core sobre .NET 8.
- SQL Server 2022, compatibilidad 160, para `DBSIGCM`.
- Integración con una base SIGA cuyo nombre real depende del ambiente.
- SSO institucional y padrón alojado en PostgreSQL.
- File server, firma digital, servicios institucionales, correo y workers.
- La lógica de negocio se concentra en procedimientos SQL; el backend actúa
  principalmente como puente y completa el bloque `Actor` desde la sesión.

## 3. Alcance y límites

Analiza:

1. Los tres repositorios `anin_scm_front`, `anin_scm_back` y
   `anin_bdsgmc/sgcm_script`.
2. El despliegue real de QA: frontend, API, SQL Server, SSO e integraciones.
3. La correspondencia frontend → API → controlador → procedimiento → tablas.
4. Seguridad, configuración, almacenamiento, logs, workers y dependencias.
5. Modelo de datos utilizado realmente por el sistema.
6. Operación, monitoreo y contingencias demostrables.

No incluyas en esta fase:

- Contraseñas, tokens, claves o cadenas de conexión completas.
- Cambios de configuración o instalación en QA.
- Pruebas destructivas o escritura directa sobre bases.
- Atributos no demostrados como alta disponibilidad, SLA, RPO, RTO,
  escalabilidad o volumen concurrente.

## 4. Rutas y metadatos iniciales

Determina y registra:

| Variable | Evidencia requerida |
|---|---|
| `<REPO_FRONT>` | Ruta y commit desplegado del frontend |
| `<REPO_BACK>` | Ruta y commit desplegado del backend |
| `<REPO_SCRIPTS>` | Ruta y commit de scripts aplicado |
| `<URL_FRONT_QA>` | Configuración o sitio IIS, sin secretos |
| `<URL_API_QA>` | Configuración o sitio IIS, sin secretos |
| `<SERVIDOR_SQL>` | Alias anonimizado y versión del motor |
| `<BASE_SIGCM>` | Debe comprobarse como `DBSIGCM` |
| `<BASE_SIGA>` | Nombre real en QA; no asumir `SIGA_1750` |
| `<SSO>` | Endpoint/sistema y mecanismo, sin credenciales |
| `<RUTA_ARCHIVOS>` | Tipo de almacenamiento y permisos requeridos |

Trabaja en la rama `docs/manuales-qa-anin` y escribe únicamente dentro de:

```text
<REPO_SCRIPTS>/docs/manuales/manual-tecnico/
<REPO_SCRIPTS>/docs/manuales/evidencia-qa/
```

## 5. Fuentes obligatorias

Lee completamente:

1. `INIT.md`.
2. `CONTEXTO.md`.
3. `ESTANDARES.md`.
4. `LEEME.md` y `README.md`.
5. `db/README.md` y `sso/README.md`.
6. `docs/instalar-en-desarrollo.md`.
7. `docs/comparacion-desarrollo-vs-local.md`.
8. `pase/LEEME.md` y `pase/CHECKLIST.md`.
9. `SIGA/integracion/ANALISIS_CMN.md`.
10. `SIGA/integracion/FLUJO_CMN_A_REQUERIMIENTO.md`.
11. `SIGA/integracion/FLUJO_PAGOS.md`.
12. `docs/analisis-modulo-ejecucion.md`.
13. `docs/analisis-modulos-modificacion-resolucion.md`.
14. `pruebas/PRUEBAS_FLUJO_COMPLETO.md`.

Después contrasta la documentación con código, configuración saneada y
catálogos de QA. La documentación histórica no sustituye la verificación.

## 6. Convenciones de calidad

Etiqueta las afirmaciones:

- **[HECHO]**: verificado en código, configuración o consulta de solo lectura.
- **[INFERENCIA]**: conclusión técnica razonable pendiente de confirmación.
- **[NO DETERMINADO]**: dato no comprobable.

Crea `MATRIZ_TRAZABILIDAD.md` con:

| Elemento documentado | Fuente | Ruta/objeto | Método de verificación | Estado |
|---|---|---|---|---|

No completes vacíos con supuestos. Escribe: “Información no identificada en los
artefactos analizados” y registra el pendiente.

## 7. Seguridad de la información

Puedes leer configuración sensible únicamente para comprender el ambiente,
pero nunca debes copiarla al manual, capturas, consola registrada o Git.

Sustituye valores por:

```text
<SERVIDOR_SQL>
<BASE_SIGA_QA>
<USUARIO_BD>
<CONTRASEÑA>
<URL_SSO>
<TOKEN>
<RUTA_COMPARTIDA>
<SECRETO_CORREO>
```

Antes del commit, busca posibles secretos en todos los archivos nuevos. Si una
captura muestra una cadena, usuario, correo o token, recórtala o redáctala.

## 8. Acceso a las bases: solo lectura

Las consultas permitidas son de inventario y diagnóstico. No ejecutes DDL ni
DML y no invoques procedimientos que cambien estado.

En SQL Server consulta, cuando tengas autorización:

- `SERVERPROPERTY` y `@@VERSION`.
- `sys.schemas`, `sys.tables`, `sys.columns`.
- `sys.foreign_keys`, `sys.indexes`.
- `sys.objects`, `sys.parameters`.
- `sys.sql_expression_dependencies`.
- `sys.database_principals` y roles, sin exponer nombres sensibles.
- `msdb.dbo.backupset`, si el permiso permite verificar políticas existentes.

En PostgreSQL usa catálogos o `information_schema`, únicamente para los objetos
del SSO relacionados con SIGCM.

No consultes ni publiques contraseñas, hashes de autenticación o datos
personales completos.

## 9. Fases obligatorias

### Fase 1 — Inventario

- Registrar ramas y commits.
- Identificar soluciones, proyectos, versiones y dependencias.
- Inventariar documentación, scripts, configuraciones y pruebas.
- Comparar el contenido del repositorio con lo desplegado en QA.

### Fase 2 — Backend

- Identificar controladores, rutas, verbos, autenticación y parámetros.
- Verificar que el backend funciona como puente y localizar excepciones reales,
  como correo, archivos, SSO y workers.
- Documentar acceso a datos y manejo de respuestas.
- Inventariar configuración por ambiente sin valores secretos.
- Documentar logs, tareas programadas y manejo de errores observado.

### Fase 3 — Frontend

- Identificar rutas, módulos, componentes, servicios y modelos.
- Reconstruir el mecanismo de sesión y perfiles.
- Identificar llamadas reales a API, incluso rutas concatenadas.
- Registrar dependencias, configuración y proceso de compilación.
- Identificar código no consumido, sin declararlo muerto hasta verificarlo.

### Fase 4 — Base de datos e integración

- Inventariar esquemas, tablas, vistas, procedimientos, funciones y relaciones.
- Separar objetos propios de `DBSIGCM` de objetos o sinónimos hacia SIGA.
- Documentar la cola de integración y los procedimientos `usp_ext_*`.
- Verificar los objetos del SSO relacionados con perfiles y padrón.
- Comparar el modelo físico con el modelo lógico simplificado.

### Fase 5 — Cruce end-to-end

Genera programáticamente una matriz con:

```text
Componente Angular → servicio Angular → endpoint → controlador →
procedimiento/servicio → tablas/vistas → integración externa
```

Clasifica:

- Endpoints existentes y consumidos.
- Llamadas del frontend sin endpoint encontrado.
- Endpoints sin consumidor encontrado.
- Métodos de servicios frontend sin uso comprobado.
- Procedimientos invocados y no invocados por la API.

Valida manualmente una muestra para evitar falsos negativos por rutas
concatenadas.

### Fase 6 — Ambiente QA

Levanta evidencia de:

- Sitio del frontend y configuración de publicación.
- API, proceso o pool de aplicaciones.
- Runtime .NET y mecanismo de arranque.
- Servidor SQL, bases y compatibilidad.
- Almacenamiento de archivos.
- SSO y redirecciones.
- Firma digital.
- Correo e integraciones externas.
- Workers `IntegracionSiga` y `PadronSso`.
- Rutas de logs y diagnóstico.

No cambies valores para “probar”. Si una pieza está apagada o inaccesible,
regístrala como observación.

## 10. Ejemplo end-to-end obligatorio

Incluye al menos un caso completo, preferiblemente la aprobación de un Anexo 4
o el paso CMN → Requerimiento:

1. Acción y componente del frontend.
2. Método del servicio Angular.
3. Verbo y ruta HTTP.
4. Controlador y acción .NET.
5. Procedimiento almacenado.
6. Tablas afectadas conceptualmente, sin ejecutar escritura durante el análisis.
7. Cola o integración con SIGA.
8. Resultado devuelto y cambio visible al usuario.

Cita archivos y objetos en cada paso.

## 11. Diagramas requeridos

Genera fuentes Mermaid, PlantUML o SVG para:

1. Contexto del SIGCM.
2. Arquitectura lógica.
3. Componentes por módulo.
4. Despliegue de QA, con nombres sensibles anonimizados.
5. Secuencia de autenticación SSO.
6. Secuencia de integración CMN → SIGA → Requerimiento.
7. Modelo lógico simplificado.

Cada diagrama debe incluir sus fuentes y una leyenda. No inventes nodos, puertos
o protocolos. Si un valor no puede mostrarse por seguridad, usa un marcador.

## 12. Estructura de archivos de salida

```text
docs/manuales/manual-tecnico/
├── README.md
├── 01-introduccion.md
├── 02-objetivos-alcance.md
├── 03-requerimientos-tecnicos.md
├── 04-arquitectura.md
├── 05-componentes-modulos.md
├── 06-seguridad.md
├── 07-configuracion.md
├── 08-operacion-administracion.md
├── 09-contingencias.md
├── 10-modelo-datos.md
├── 11-integraciones-endpoints.md
├── 12-decisiones-restricciones-riesgos.md
├── 13-glosario.md
├── MATRIZ_TRAZABILIDAD.md
├── MATRIZ_FRONT_API_BD.csv
├── CATALOGO_ENDPOINTS.md
├── CATALOGO_OBJETOS_BD.md
├── HALLAZGOS_TECNICOS.md
└── diagramas/
```

La guía de instalación se elaborará por separado. En este manual incluye un
resumen y referencia a ella, evitando duplicar instrucciones extensas.

## 13. Estructura del futuro Manual Técnico

El contenido preparado debe cubrir:

```text
I.    Introducción y convenciones de calidad
II.   Objetivos
III.  Alcance y audiencia
IV.   Requerimientos técnicos
V.    Arquitectura del sistema
VI.   Resumen de instalación y referencia a la guía
VII.  Configuración
VIII. Operación y administración
IX.   Problemas y contingencias
X.    Modelo de datos
XI.   Integraciones, interfaces y catálogo de endpoints
XII.  Decisiones, restricciones y riesgos
XIII. Glosario
XIV.  Anexos y matrices
```

## 14. Capturas técnicas

Usa nombres como:

```text
MT-ARQ-001-componentes.png
MT-QA-002-sitio-iis.png
MT-BD-003-version-motor.png
MT-LOG-004-evento-arranque.png
```

Nunca muestres secretos, rutas privadas innecesarias o datos personales. Cada
captura debe tener pie, fuente, fecha y relación con una afirmación técnica.

## 15. Verificación final

- [ ] Tecnologías y versiones coinciden con los archivos de proyecto.
- [ ] La arquitectura corresponde al código real.
- [ ] El catálogo de endpoints fue generado y contrastado.
- [ ] Las tablas y relaciones vienen de catálogos o DDL.
- [ ] Se distingue `DBSIGCM` de la base SIGA real del ambiente.
- [ ] No existen referencias a `DBAPPSIGA` o `DBSIGA`.
- [ ] No hay credenciales, tokens ni secretos.
- [ ] Los diagramas son legibles y tienen fuentes.
- [ ] Lo no verificable está marcado.
- [ ] No se modificó QA durante el levantamiento.
- [ ] `git diff --check` termina sin errores.

## 16. Cierre

No generes DOCX. Haz commit de las fuentes y entrega un resumen con:

1. Artefactos analizados.
2. Arquitectura verificada.
3. Hallazgos e inconsistencias.
4. Información pendiente de ANIN.
5. Evidencias y consultas de solo lectura utilizadas.
6. Commit documental generado.

# FIN DEL PROMPT PARA LA IA DE ANIN
