# SIGCM — Punto de continuidad

Para retomar el trabajo sin reconstruir el contexto. Estado verificado contra la
base y los repositorios el **2026-08-13**.

---

## 1. Qué leer, y en qué orden

No hace falta leerlo todo. Estos seis archivos, en este orden, dan el contexto
completo en unas 1 500 líneas:

| # | Archivo | Qué aporta |
|---|---|---|
| 1 | `Analisis/continuidad.md` | Este archivo: estado y mapa |
| 2 | `Proyecto/ESTANDARES.md` | **Cómo se escribe código aquí.** El backend es un puente; toda la lógica vive en la base. Léelo antes de tocar nada |
| 3 | `Analisis/reglas-negocio-mockup.md` | Las reglas funcionales numeradas (`CMN-nn`, `REQ-nn`, `PLZ-nn`). Es la especificación aprobada |
| 4 | `SIGCM_SERVER/db/README.md` | Modelo de datos, contrato con el backend, orden de ejecución de los scripts |
| 5 | `SIGCM_SERVER/db/10_api/F002__cmn_solicitud.sql` | El patrón de toda rutina de negocio. Si escribes una nueva, cópiala de aquí |
| 6 | `Proyecto/anin_scm_front/src/app/modules/gestion-cmn/gestion-cmn.component.ts` | El patrón de toda pantalla: la bandeja no decide acciones, las pregunta |

`Analisis/mapa-implementacion.md` cuenta la historia y las decisiones tomadas;
útil para entender *por qué* algo es como es, no imprescindible para avanzar.

---

## 2. La regla que gobierna todo

**El backend .NET no tiene lógica de negocio.** Recibe un JSON, le pone el bloque
`Actor` desde la sesión, llama a un procedimiento y devuelve lo que conteste.

Una rutina invocable = **un parámetro JSON, una fila con una columna de texto**.
La respuesta siempre trae `estado`: `1` se hizo, `0` no se hizo y `mensaje`
explica por qué.

Si estás escribiendo un `if` de negocio en C# o TypeScript, está en el lugar
equivocado.

---

## 3. Los tres repositorios… que son dos

| Componente | Ubicación | Repositorio |
|---|---|---|
| Backend | `Proyecto/anin_scm_back` | `github.com/djackob/sgcm_back`, rama `dev_mrz` |
| Frontend | `Proyecto/anin_scm_front` | `github.com/djackob/sgcm_front`, rama `dev_mrz` |
| **Base de datos** | `SIGCM_SERVER/db` | **NINGUNO — sin versionar** |
| **Análisis** | `Analisis/` | **NINGUNO — sin versionar** |
| **Estándares** | `Proyecto/ESTANDARES.md` | **NINGUNO — sin versionar** |

> **Pendiente y urgente.** Los scripts de base de datos y los documentos de
> análisis no están en ningún repositorio. Quien clone `sgcm_back` obtiene un
> backend que invoca procedimientos que no existen en su base. Hace falta un
> tercer repositorio (`sgcm_db`) o moverlos dentro de uno de los dos.

---

## 4. Mapa de archivos

### 4.1 Base de datos — `SIGCM_SERVER/`

Motor: **SQL Server 2022, compat 160**. Base `DBSIGCM`, convive con `SIGA_1750`
en la misma instancia. Todos los scripts son **idempotentes**.

```
00_servidor/          C000 preflight · C001 crear base · C002 permisos · C003 sinónimos SIGA
db/00_ddl/            V001 organización y seguridad
                      V002 workflow y documentos
                      V003 observaciones, plazos, auditoría
                      V004 las 10 vistas sobre SIGA
                      V005 módulo CMN
                      V006 outbox de integración
                      V007 ruta e icono por módulo (el menú sale de aquí)
                      V008 columnas de archivo del documento
                      V009 módulo Requerimiento
db/10_api/            F001 actor, auditoría, correlativo, maestros SIGA
                      F002 CMN: registrar, obtener, listar
                      F003 documentos, firmas, versionado
                      F004 motor de transiciones y trazabilidad
                      F005 Requerimiento: registrar, obtener, listar
                      F006 acceso y armado de la sesión
db/15_siga/           W001 escritor del cuadro modificado (SOLO SIMULACIÓN, ADR-003)
db/20_seed/           S000 números · S001 config CMN · S002 plazos · S003 config Requerimiento
db/90_pruebas/        S900 datos de prueba — NO instalar en QA ni producción
```

**18 rutinas invocables** hoy: 11 en `sigcm`, 3 en `cmn`, 3 en `requerimiento`,
más `paResolverActor` que es interna.

### 4.2 Backend — `Proyecto/anin_scm_back`

```
anin.dataAccess/DaProceso.cs          TODO el acceso a datos. No hay ORM ni repositorios
anin.util/UT_File.cs                  file server: SubirArchivo(stream, nombre, carpeta)
anin.util/UT_Configuracion.cs         lee appsettings.json
anin.scm/Startup.cs                   JWT, CORS y UseStaticFiles [AMBIENTE]
anin.scm/appsettings.json             3 bloques marcados [AMBIENTE]
anin.scm/Controllers/
  ControladorPuente.cs                BASE DE TODO: arma el bloque Actor desde el JWT
  SigcmController.cs                  maestros SIGA, transiciones, trazabilidad, documentos
  CmnController.cs                    Anexo 3: registrar, obtener, listar
  RequerimientoController.cs          registrar, obtener, listar
  GeneralController.cs                subir y descargar archivos (no es puente: toca disco)
  AccesoController.cs                 ingreso local sin SSO, apagable por configuración
  TokenController.cs                  ingreso por SSO institucional (no tocar)
  Integracion/Ejecucion/Pago/Ampliacion/Resolucion   declarados vacíos, como sus esquemas
  OperacionController.cs / ProcesoDato.cs / TestController.cs   heredados, PostgreSQL, sin uso
```

### 4.3 Frontend — `Proyecto/anin_scm_front/src/app`

```
core/services/
  metodo.service.ts        TODA llamada HTTP pasa por aquí. GET ?ipInput={json}, POST form-urlencoded
  acceso.service.ts        ingreso local
  documento.service.ts     genera el PDF con pdfmake y lo sube. Genérico, no sabe qué es un anexo
  session.service.ts       sesión cifrada en sessionStorage (clave data_scm)
  sso-login.service.ts     cierre de sesión según el origen (SSO o local)
core/interceptor/          auth (Bearer + 401) y loader
core/guards/guard.service.ts   compara el menú de la sesión contra la ruta
modules/acceso-local/      selector de perfil, reemplaza al SSO en local
modules/gestion-cmn/
  gestion-cmn.component.*  bandeja: filtros, paginación, acciones desde la máquina de estados
  documentos/anexo3.plantilla.ts   función pura: solicitud → definición pdfmake
  modals/modal-registro/   formulario del Anexo 3 con catálogo y cuadro vigente
  modals/modal-detalle/    visor: datos, documentos y trazabilidad
  models/cmn.model.ts      formas que devuelven las rutinas (PascalCase, como las columnas)
  services/cmn.service.ts  un método por endpoint, sin lógica
shared/components/input-archivos/   subida de adjuntos (declarado en SharedModule)
shared/services/maestra.service.ts  subirArchivo / descargarArchivo
styles/                    sistema visual GLOBAL: page, tables, buttons, modals, forms
```

**Regla de estilos:** lo general va en `src/styles`, el `.scss` del componente
solo lleva lo propio de esa pantalla. La paleta ya existe; no inventar colores.

---

## 5. Hasta dónde llega el avance

### 5.1 Gestión CMN

Estados sembrados: **12**. Transiciones: **15**.

| Tramo | Base | Backend | Frontend | Probado en navegador |
|---|:--:|:--:|:--:|:--:|
| Registrar Anexo 3 (con catálogo y cuadro vigente) | ✅ | ✅ | ✅ | ✅ |
| Generar Anexo 3 → PDF, subida y registro | ✅ | ✅ | ✅ | ✅ |
| Firmar Anexo 3 | ✅ | ✅ | ✅ | ✅ |
| Enviar a OA | ✅ | ✅ | ⚠️ genérico | ❌ |
| OA observa / deriva a Abastecimiento | ✅ | ✅ | ⚠️ genérico | ❌ |
| Abastecimiento observa / valida | ✅ | ✅ | ⚠️ genérico | ❌ |
| Tipo de inclusión: ordinario o urgente (CMN-10) | ❌ | ❌ | ❌ | ❌ |
| Generar Anexo 4 | ✅ | ✅ | ❌ sin plantilla | ❌ |
| Anexo 4 **consolidado** de 2+ solicitudes (CMN-12/13/14) | ❌ | ❌ | ❌ | ❌ |
| Recepcionar Anexo 4 | ✅ | ✅ | ⚠️ genérico | ❌ |
| Ciclo observación → recepción → subsanación (CMN-15..20) | ✅ | ✅ | ⚠️ parcial | ❌ |

**⚠️ genérico** = el botón aparece y la transición se ejecuta, porque la bandeja
pinta lo que devuelve la máquina de estados. Falta lo específico: plantilla del
Anexo 4, captura del tipo de inclusión, y distinguir «observación por
recepcionar» de «recepcionada, por subsanar», que en el mockup son dos acciones
distintas del área usuaria.

### 5.2 Requerimiento a Notificación

Estados: **11**. Transiciones: **16**. Reglas cubiertas: REQ-01 a REQ-14.

| Tramo | Base | Backend | Frontend |
|---|:--:|:--:|:--:|
| Registro con pedidos SIGA e ítems | ✅ | ✅ | ❌ |
| Validaciones: 8 UIT, condición CMN, 10 días hábiles, monto | ✅ | ✅ | ❌ |
| Documentos por objeto (EETT, TDR, Anexo 5) | ✅ tipos sembrados | ✅ | ❌ sin plantillas |
| Flujo hasta revisión de la DEC | ✅ | ✅ | ❌ |
| Indagación de mercado, Anexo 8, CCP, orden | ❌ V010 | ❌ | ❌ |

**No hay ninguna pantalla de Requerimiento.** El módulo se opera solo por API.

### 5.3 Transversal

| Pieza | Estado |
|---|---|
| Ingreso local sin SSO, 5 perfiles | ✅ probado |
| Menú desde `RolModulo` + `Modulo.Ruta` | ✅ probado |
| Documentos: registrar, firmar, versionar, invalidar firma | ✅ probado |
| File server: subir, servir por `/files` | ✅ probado |
| Generación de PDF en el navegador (pdfmake, MIT) | ✅ probado |
| Trazabilidad: historial, observaciones, cola SIGA | ✅ |
| Escritura real hacia SIGA | ❌ solo simulación (ADR-003) |
| Firmador institucional | ❌ punto de integración listo en `paFirmarDocumento` |
| Vista de pedidos SIGA (`siga.vwPedido`) | ❌ **no existe** — los pedidos se guardan sin validar |

---

## 6. Cómo levantar el ambiente

```bash
sqlcmd -S "localhost\SQLSERVER25" -d DBSIGCM -E -b -I -i SIGCM_SERVER/db/90_pruebas/S900__datos_prueba.sql
```

```bash
cd Proyecto/anin_scm_back/anin.scm && dotnet run --urls http://localhost:5120
```

```bash
cd Proyecto/anin_scm_front && npm install && npx ng serve
```

Entrar por **http://localhost:4200/acceso-local** y elegir perfil.

Para recorrer un flujo hay que **cerrar sesión y cambiar de perfil en cada
transferencia**: la bandeja solo muestra lo que espera una acción del rol activo.

| Cuenta | Rol | Unidad |
|---|---|---|
| `prueba.especialista` | Área usuaria · Especialista | UO-PRUEBA (centro 01.01) |
| `prueba.jefe` | Área usuaria · Jefe | UO-PRUEBA (centro 01.01) |
| `prueba.oa` | Oficina de Administración | UO-OA |
| `prueba.abastecim` | Abastecimiento · Coordinador | UO-ABAST |
| `prueba.abastecim` | Abastecimiento · Jefe | UO-ABAST |

Configuración por ambiente: buscar la etiqueta `[AMBIENTE]` en
`appsettings.json` (3 bloques) y en `Startup.cs` (1 bloque). En `config.json` del
front, la clave gemela `apiUrl_PRODUCCION`.

### Estado de los datos de prueba

| Expediente | Estado |
|---|---|
| CMN-2026-000001 | `CMN_VALIDADO_UA` — documento insertado a mano en una sesión previa |
| CMN-2026-000002 | `CMN_A3_FIRMADO` |
| CMN-2026-000003 / 000004 | `CMN_PEND_FIRMA_A3` — sin documento generado |
| CMN-2026-000005 | `CMN_A3_FIRMADO` — el único con PDF real generado por pdfmake |
| REQ-2026-000001 | `REQ_DOC_PENDIENTE` |

---

## 7. Decisiones abiertas — no resolver escribiendo código

Requieren pronunciamiento funcional. Las dos primeras **bloquean el Anexo 4**.

1. ¿El Anexo 4 individual sigue permitido, o todo envío debe ser consolidado
   desde dos solicitudes? (CMN-12)
2. ¿Qué subrol de Abastecimiento firma el Anexo 4, y cómo se representa la
   segunda firma de la máxima autoridad administrativa? (CMN-24)
3. ¿Cómo se desagrega DAI internamente?
4. ¿Número máximo de propuestas del Anexo 5? El mockup usa cinco.
5. ¿La excepción de una cotización aplica a toda Locación de persona natural?
6. ¿La notificación final copia solo al Jefe, o también al Especialista?
7. **El techo multianual no está donde el espejo suponía**: `PPTO_ANNO_01..03`
   está en cero en las 2 375 filas de 2026. Hoy el control de techo solo puede
   hacerse sobre el año base. ¿Se acepta en la v1?
8. **Valor oficial de la UIT** por año, para `requerimiento.ParametroAnio`.
   Sembrado 2026 = S/ 5 500 → tope S/ 44 000, tomado del mockup.

---

## 8. Qué hacer a continuación

En este orden:

1. **Versionar la base de datos y el análisis** (§3). Es lo único que hoy puede
   perderse sin remedio.
2. **Frontend de Requerimiento**: bandeja y formulario de registro. La API está
   completa y probada; es trabajo de pantalla, sin incógnitas.
3. **Plantillas de documento** de Requerimiento: EETT, TDR y Anexo 5, con el
   patrón de `anexo3.plantilla.ts`. Ojo con REQ-08: en Locación el orden es
   Anexo 5 → firma → TDR → firma.
4. **Cerrar CMN**: tipo de inclusión, plantilla del Anexo 4 y ciclo de
   observación completo. El consolidado espera la decisión 1.
5. `V010`/`S004`: indagación de mercado, Anexo 8, CCP y orden.
6. `siga.vwPedido`, para validar los pedidos contra SIGA en vez de guardarlos sin
   verificar.

### Trampas conocidas

- **No matar procesos ajenos.** Si `dotnet build` falla con `MSB3021`/`MSB3027`,
  hay una instancia del backend corriendo (a menudo desde Visual Studio).
  Compilar a otra carpeta con `-o` en vez de matarla.
- **El puerto 4200 es del desarrollador.** Para pruebas automatizadas, usar otro.
- Las tablas `#temporales` con columnas `varchar` necesitan
  `COLLATE DATABASE_DEFAULT`, o los joins contra las vistas de SIGA fallan con el
  error 468.
- `sqlcmd` necesita `-I` (`QUOTED_IDENTIFIER ON`) o los índices filtrados fallan.
- En `EXEC rutina @p`, el parámetro debe ser una variable: T-SQL no admite
  expresiones ahí.
