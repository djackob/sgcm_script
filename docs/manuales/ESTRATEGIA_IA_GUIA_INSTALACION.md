# Estrategia y prompt para levantar la Guía de Instalación del SIGCM en la PC de ANIN

## 1. Propósito de este documento

Este archivo instruye a la IA de la PC de ANIN para preparar una **Guía de
Instalación y Actualización del SIGCM** basada en la instalación real de QA y en
los artefactos versionados.

La guía debe ser ejecutable por un administrador autorizado, pero la IA que
realiza el levantamiento no debe instalar, actualizar ni reconfigurar QA sin una
orden explícita. Su trabajo es inspeccionar, contrastar, documentar y obtener
evidencia no sensible.

La salida de esta fase es Markdown, diagramas y capturas técnicas. El DOCX/PDF
institucional se generará posteriormente en otra PC.

---

# INICIO DEL PROMPT PARA LA IA DE ANIN

## 2. Rol

Actúa como **especialista senior en despliegue de aplicaciones .NET y Angular,
administración SQL Server y elaboración de procedimientos operativos para
entidades públicas**.

Debes construir las fuentes de una guía que cubra:

- Instalación nueva.
- Actualización de una instalación existente.
- Configuración por ambiente.
- Validación posterior.
- Reversión y recuperación.
- Diagnóstico de fallos frecuentes.

## 3. Principios del SIGCM que debes respetar

1. La base propia se llama `DBSIGCM`.
2. La base SIGA se verifica por ambiente. En desarrollo documentado aparece
   `SIGA_1750`, pero en QA puede tener otro nombre.
3. Nunca se recrea ni borra SIGA.
4. Una actualización normal de `DBSIGCM` debe respetar los datos.
5. `-Recrear` borra `DBSIGCM` y no debe usarse en QA salvo autorización formal,
   respaldo verificado y ventana aprobada.
6. Los scripts SQL son idempotentes y se aplican en orden.
7. No se instalan datos de prueba ni scripts `solo_desarrollo` en QA.
8. Frontend, backend, base SIGCM, extensiones SIGA y SSO tienen canales y
   permisos distintos.
9. La configuración local o de APP-SIGA no pertenece a este proyecto. No uses
   `DBAPPSIGA` ni `DBSIGA`.

## 4. Fuentes obligatorias

Lee completamente:

1. `INIT.md`.
2. `README.md`.
3. `db/README.md`.
4. `sso/README.md`.
5. `ESTANDARES.md`, especialmente configuración por ambiente.
6. `docs/instalar-en-desarrollo.md`.
7. `docs/comparacion-desarrollo-vs-local.md`.
8. `pase/LEEME.md`.
9. `pase/CHECKLIST.md`.
10. `pase/instalar_calidad.ps1`.
11. `pase/empacar_pase.ps1` y `pase/generar_sql.ps1`.
12. `instalar.ps1`.
13. Archivos de proyecto y configuración del frontend y backend.
14. Configuración real de QA, únicamente para inspección y sin copiar secretos.

## 5. Datos que debes determinar en QA

Registra el valor verificado o `[NO DETERMINADO]`:

| Área | Dato |
|---|---|
| Control de versiones | Repositorios, ramas y commits desplegados |
| Servidor web | IIS u otro mecanismo, versión y roles instalados |
| Frontend | Ruta publicada, URL, configuración y `web.config` |
| Backend | Ruta publicada, pool/proceso, runtime .NET, URL y health check |
| SQL Server | Versión, edición, compatibilidad y nombre de instancia |
| SIGCM | Nombre `DBSIGCM`, propietario, usuario técnico y permisos requeridos |
| SIGA | Nombre real de la base, autorización y procedimientos `usp_ext_*` |
| SSO | Host lógico, base, cliente y scripts requeridos |
| Archivos | Ruta compartida, identidad que accede y permisos mínimos |
| Firma | URLs y componentes requeridos, sin secretos |
| Correo | Mecanismo y puerto, sin usuario o contraseña real |
| Red | DNS, puertos, proxy, certificados y reglas necesarias |
| Operación | Logs, servicio, workers, monitoreo, backup y responsables |

No publiques direcciones, cuentas o rutas sensibles si ANIN no autoriza su
inclusión. Usa marcadores parametrizables.

## 6. Seguridad

Está prohibido incluir:

- Contraseñas o secretos reales.
- Cadenas de conexión completas.
- Tokens, API keys o claves de firma.
- Certificados privados.
- Datos personales.
- Archivos `appsettings.json` o equivalentes sin saneamiento.

Usa siempre:

```text
<SERVIDOR_SQL>
<INSTANCIA_SQL>
<BASE_SIGA_QA>
<LOGIN_APLICACION>
<CONTRASEÑA>
<URL_FRONT_QA>
<URL_API_QA>
<URL_SSO>
<RUTA_ARCHIVOS>
<CERTIFICADO_TLS>
```

## 7. Separación de escenarios

La guía debe distinguir claramente:

### 7.1 Instalación nueva

- Prerrequisitos de infraestructura.
- Creación o provisión previa de cuentas y bases.
- Instalación de extensiones autorizadas en SIGA.
- Creación y aplicación del modelo en `DBSIGCM`.
- Configuración SSO.
- Publicación de backend.
- Publicación de frontend.
- Configuración de archivos, firma, correo y workers.
- Validación integral.

### 7.2 Actualización

- Respaldo y punto de retorno.
- Confirmación de versión actual.
- Ventana y responsables.
- Actualización idempotente de scripts.
- Sustitución controlada del backend y frontend.
- Reinicio y verificación.
- Pruebas de humo.

### 7.3 Reversión

- Cuándo se activa.
- Quién autoriza.
- Restauración del artefacto anterior de frontend/backend.
- Tratamiento de cambios de base: no prometas rollback automático si los
  scripts no lo implementan.
- Restauración desde respaldo, sólo por el DBA autorizado.
- Validación posterior.

## 8. Procedimiento de levantamiento

### Fase 1 — Inventario sin cambios

1. Registrar versiones del sistema operativo y runtimes.
2. Registrar componentes instalados y su origen.
3. Identificar rutas de publicación y procesos.
4. Identificar sitios, pools, bindings y certificados, saneando valores.
5. Verificar versión de SQL Server y bases existentes con consultas de solo
   lectura.
6. Identificar logs y mecanismos de arranque.
7. Registrar commits o paquetes desplegados.

### Fase 2 — Contraste con los instaladores

1. Ejecutar únicamente `instalar.ps1 -SoloVerificar` si está autorizado y no
   requiere conexión ni modifica bases.
2. Leer `pase/instalar_calidad.ps1` y contrastar parámetros con QA.
3. Confirmar qué scripts fueron aplicados y por qué mecanismo.
4. Verificar que los archivos de prueba y `solo_desarrollo` no formen parte del
   pase.
5. Identificar actividades manuales no automatizadas.

### Fase 3 — Reconstrucción del despliegue

Documenta el orden exacto:

```text
Prerrequisitos → respaldo → diagnóstico → extensiones SIGA → DBSIGCM →
SSO → backend → frontend → archivos/firma/correo → workers → pruebas de humo
```

Si el orden real de QA difiere, registra la diferencia y su justificación.

### Fase 4 — Validación

Define verificaciones sin efectos destructivos:

- Respuesta HTTP del frontend.
- Respuesta esperada de API existente: un endpoint protegido puede devolver
  `401`; un `404` puede indicar ruta o despliegue incorrecto.
- Conectividad de la API con `DBSIGCM`.
- Existencia de objetos críticos.
- Inventario C900 sin errores.
- Login SSO con cuenta autorizada.
- Lectura/escritura de archivos mediante el flujo de aplicación.
- Estado controlado de `IntegracionSiga` y `PadronSso`.
- Prueba funcional mínima aprobada por ANIN.

No actives un worker real ni dispares una escritura en SIGA sólo para preparar
la guía. Documenta cómo se valida dentro de una ventana autorizada.

## 9. Estructura de la guía

```text
I.    Introducción
II.   Objetivo
III.  Alcance, audiencia y responsabilidades
IV.   Arquitectura de despliegue
V.    Requisitos previos
      5.1 Hardware confirmado o pendiente
      5.2 Software y versiones
      5.3 Red, DNS, puertos y certificados
      5.4 Cuentas y permisos
      5.5 Respaldo y ventana de cambio
VI.   Preparación de artefactos
VII.  Instalación de base de datos
      7.1 SIGA
      7.2 DBSIGCM
      7.3 SSO
VIII. Instalación del backend
IX.   Instalación del frontend
X.    Configuración por ambiente
XI.   Puesta en servicio
XII.  Validación y pruebas de humo
XIII. Actualización del sistema
XIV.  Reversión y recuperación
XV.   Solución de problemas
XVI.  Checklist de entrega
XVII. Anexos
```

## 10. Plantilla para cada procedimiento de instalación

```markdown
## <Nombre del procedimiento>

**Objetivo:** <resultado técnico>.

**Responsable:** <rol, no nombre personal>.

**Ambiente:** <QA/Producción>.

**Impacto esperado:** <servicio afectado y duración si está confirmada>.

**Prerrequisitos:**

- <respaldo o permiso>.
- <herramienta y versión>.

### Parámetros

| Parámetro | Descripción | Ejemplo seguro |
|---|---|---|

### Procedimiento

1. <Acción verificable>.
2. <Comando parametrizado y sin secretos>.

### Verificación

- <comando o resultado esperado>.

### Reversión

- <procedimiento real o declaración de que requiere restauración DBA>.

### Evidencia

![Descripción](capturas/GI-<AREA>-<NNN>-<accion>.png)

*Figura N. <Descripción y fuente>.*
```

## 11. Comandos y configuración

Todos los comandos deben:

- Usar parámetros y marcadores.
- Indicar desde qué carpeta se ejecutan.
- Señalar si son de solo lectura o si modifican el ambiente.
- Separar PowerShell, `sqlcmd`, SSMS y `psql`.
- Evitar contraseñas en línea de comandos.
- Incluir resultado esperado y código de salida cuando sea relevante.

No copies directamente ejemplos con servidores o credenciales de desarrollo.

## 12. Archivos de salida

```text
docs/manuales/guia-instalacion/
├── README.md
├── 01-introduccion-alcance.md
├── 02-arquitectura-despliegue.md
├── 03-prerrequisitos.md
├── 04-preparacion-artefactos.md
├── 05-instalacion-base-datos.md
├── 06-instalacion-backend.md
├── 07-instalacion-frontend.md
├── 08-configuracion-ambiente.md
├── 09-puesta-servicio-validacion.md
├── 10-actualizacion.md
├── 11-reversion-recuperacion.md
├── 12-solucion-problemas.md
├── CHECKLIST_INSTALACION.md
├── MATRIZ_PARAMETROS.md
├── MATRIZ_PRERREQUISITOS.md
├── MATRIZ_TRAZABILIDAD.md
├── PENDIENTES_ANIN.md
├── diagramas/
└── capturas/
```

## 13. Capturas y evidencias

Usa nombres como:

```text
GI-IIS-001-sitios.png
GI-API-002-runtime.png
GI-BD-003-version-sql.png
GI-BD-004-inventario-final.png
GI-LOG-005-arranque-api.png
```

Recorta toda información no necesaria. Cada captura debe indicar fecha, fuente,
ambiente y qué requisito demuestra.

## 14. Lista de control obligatoria

- [ ] Se identificó el nombre real de SIGA en QA.
- [ ] Se confirmó que la base propia es `DBSIGCM`.
- [ ] Se diferenciaron instalación nueva, actualización y reversión.
- [ ] No se recomienda `-Recrear` en QA.
- [ ] No se incluyen scripts de prueba ni `solo_desarrollo`.
- [ ] Los pasos de base respetan el orden SIGA → DBSIGCM → SSO.
- [ ] Backend y frontend tienen procedimiento y validación independientes.
- [ ] Se documentan certificados, archivos, firma, correo y workers sin secretos.
- [ ] Los comandos usan marcadores y no contienen contraseñas.
- [ ] Toda afirmación tiene fuente o marca pendiente.
- [ ] No existen referencias a `DBAPPSIGA` ni `DBSIGA`.
- [ ] No se cambió QA durante el levantamiento.
- [ ] `git diff --check` no reporta errores.

## 15. Cierre

No generes ni edites DOCX. Entrega Markdown, diagramas y capturas saneadas, más
un resumen con:

1. Topología y versiones verificadas.
2. Procedimiento de instalación reconstruido.
3. Actividades manuales no automatizadas.
4. Riesgos y puntos sin rollback automático.
5. Datos pendientes de infraestructura, DBA o seguridad.
6. Commit documental generado.

# FIN DEL PROMPT PARA LA IA DE ANIN
