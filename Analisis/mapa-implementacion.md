# Mapa de implementación del SIGCM

Qué se construyó, en qué orden, por qué, y qué falta. Sirve para retomar el
trabajo sin releer código y para no repetir decisiones ya tomadas.

Las reglas funcionales están en [`reglas-negocio-mockup.md`](reglas-negocio-mockup.md);
las convenciones de código, en [`../Proyecto/ESTANDARES.md`](../Proyecto/ESTANDARES.md).

---

## 1. Cronología

### Etapa 1 — Decisión de arquitectura (ADR)

Cuatro decisiones que gobiernan todo lo demás:

- **ADR-001** El backend es un puente: toda la lógica vive en la base, con JSON
  de entrada y de salida. Una rutina invocable = un parámetro JSON, una fila con
  una columna de texto.
- **ADR-002** La v1 cubre **solo la modificación** del CMN, no su programación
  inicial.
- **ADR-003** La escritura hacia SIGA arranca en **modo simulación**. El
  procedimiento homologado dentro de SIGA es un entregable aparte que requiere
  autorización formal del propietario.
- **ADR-004** Los maestros de SIGA se leen, nunca se escriben.

### Etapa 2 — Primera encarnación: PostgreSQL

Modelo completo en PostgreSQL 14 (`SIGCM/db`), con trece esquemas de tres letras
y los maestros replicados como tablas espejo más un sincronizador. **Se conserva
intacta como referencia.**

### Etapa 3 — Migración a SQL Server

Al confirmarse que SIGCM convive con SIGA **en la misma instancia**, se rehízo
sobre SQL Server 2022 (`SIGCM_SERVER/db`). No fue una traducción: compartir
instancia invalidó suposiciones del espejo.

Los seis cambios que importan:

1. **Los maestros son vistas, no espejo.** Ocho tablas + bitácora → diez vistas.
   Replicar 17 000 filas dentro del mismo servidor no compra nada y cuesta un
   sincronizador que hay que operar. Desaparecen `mst.sincronizacion` y
   `itg.pa_sincronizar_maestros`.
2. **Trece esquemas → diez**, agrupados por *autoridad sobre el dato* más uno por
   módulo.
3. **Línea base 2022 (compat 160)** aunque el entorno local sea 2025. Queda
   prohibido el tipo `json` nativo.
4. **Las rutinas son procedimientos, no funciones**: SQL Server prohíbe DML
   dentro de una función.
5. **Auditoría**: cuarteto por operación en cada tabla + `sigcm.EventoAuditoria`
   para lo que se intentó hacer, incluidos los intentos denegados.
6. **Los arreglos se volvieron tablas hijas** (`TransicionRol`,
   `TipoDocumentoFirma`), con clave foránea real.

### Etapa 4 — Cierre del módulo CMN (backend y frontend)

- Backend migrado a SQL Server y reorganizado **un controlador por esquema**.
- Ingreso local sin SSO para poder recorrer el flujo fuera de la red de la ANIN.
- `gestion-cmn` reescrito contra el backend real, con las acciones tomadas de la
  máquina de estados.
- `ESTANDARES.md` con las convenciones de los tres frentes.

---

## 2. Qué es una «semilla»

Término usado en todo el proyecto: los archivos de `db/20_seed`.

Una **semilla** es un script que carga los **datos de configuración** que el
sistema necesita para funcionar, en contraposición a los datos que capturan los
usuarios. No son datos de prueba: son parte del producto.

| Archivo | Qué siembra |
|---|---|
| `S000__numeros.sql` | Tabla auxiliar `dbo.Numero`, para materializar los 48 períodos |
| `S001__roles_estados_transiciones.sql` | Módulos, tipos de contratación, **roles**, matriz de acceso, **estados**, tipos de documento y **transiciones** |
| `S002__plazos_directiva.sql` | Los plazos de la Directiva |

Cuando digo *«está sembrado»* o *«hay que tocar la semilla»*, me refiero a esto:
por ejemplo, que la transición `CMN_FIRMAR_A3` exija un documento firmado **no
está en el código**, es una fila de `sigcm.Transicion` que puso `S001`. Cambiar
esa regla es cambiar un dato, no recompilar.

Distinto es `db/90_pruebas/S900__datos_prueba.sql`, que sí son **datos de
prueba**: cuatro usuarios ficticios y tres unidades. Ése **no se instala en
producción**.

---

## 3. Estado por componente

### 3.1 Base de datos — `SIGCM_SERVER/db`

| Script | Contenido | Estado |
|---|---|---|
| `00_servidor/C000..C003` | Preflight, creación de `DBSIGCM`, permisos de lectura sobre SIGA, sinónimos | Aplicado |
| `00_ddl/V001` | Organización, seguridad, catálogos | Aplicado |
| `00_ddl/V002` | Workflow y documentos | Aplicado |
| `00_ddl/V003` | Observaciones, plazos, auditoría | Aplicado |
| `00_ddl/V004` | Vistas sobre SIGA (10) | Aplicado |
| `00_ddl/V005` | `cmn.Solicitud`, `SolicitudItem`, `SolicitudItemPeriodo` | Aplicado |
| `00_ddl/V006` | Outbox de integración y mapeo | Aplicado |
| `00_ddl/V007` | `Ruta` e `Icono` por módulo, para el menú | Aplicado |
| `00_ddl/V008` | Columnas de archivo del documento | Aplicado |
| `00_ddl/V009` | Requerimiento: núcleo del registro | Aplicado |
| `00_ddl/V010` | Requerimiento: cotizaciones, CCP y orden | **PENDIENTE** |
| `10_api/F001` | Utilitarios: actor, auditoría, correlativo, maestros SIGA | Aplicado |
| `10_api/F002` | CMN: registrar, obtener, listar solicitud | Aplicado |
| `10_api/F003` | Documentos, firmas e invalidación por versión | Aplicado y probado |
| `10_api/F004` | Transiciones, encolado y trazabilidad | Aplicado |
| `10_api/F005` | Requerimiento: registrar, obtener, listar | Aplicado y probado |
| `10_api/F006` | Acceso y armado de la sesión | Aplicado |
| `15_siga/W001` | Escritor del cuadro modificado | Solo simulación (ADR-003) |
| `20_seed/S000..S003` | Semillas | Aplicado |
| `90_pruebas/S900` | Datos de prueba | Aplicado (solo local) |

El orden de ejecución completo, con el comando para levantar un ambiente nuevo,
está en [`../SIGCM_SERVER/db/README.md`](../SIGCM_SERVER/db/README.md).

Inventario verificado: 30 tablas, 13 vistas, 14 sinónimos, 1 secuencia.
Todos los scripts son idempotentes, comprobado con dos pasadas.

**Rendimiento medido** contra `SIGA_1750`: un ítem del cuadro 7 ms; los 4 175
ítems de un centro de costo 17 ms; búsqueda por texto en el catálogo 28 ms.

### 3.2 Backend — `Proyecto/anin_scm_back`

| Pieza | Estado |
|---|---|
| `DaProceso` sobre SQL Server, JSON como `SqlParameter` | Hecho |
| `ControladorPuente`: bloque `Actor` desde el JWT, centralizado | Hecho |
| `SigcmController`: maestros, transiciones, trazabilidad | Hecho |
| `CmnController`: registrar, obtener, listar solicitud | Hecho |
| `AccesoController`: ingreso local, apagable por configuración | Hecho |
| `IntegracionController` | Declarado sin endpoints (la cola la mueve el worker) |
| `Requerimiento`, `Ejecucion`, `Pago`, `Ampliacion`, `Resolucion` | Declarados vacíos, como sus esquemas |
| Endpoints de documentos y archivos | **PENDIENTE** |

### 3.3 Frontend — `Proyecto/anin_scm_front`

| Pieza | Estado |
|---|---|
| Ingreso local `/acceso-local` | Hecho |
| Bandeja `gestion-cmn` con filtros, paginación y acciones desde la máquina de estados | Hecho |
| Modal de registro del Anexo 3, con búsqueda en catálogo y cuadro vigente | Hecho |
| Visor del expediente con trazabilidad | Hecho (muestra datos, **no** el documento) |
| Estilos: footer de modal y patrón campo+botón en la capa global | Hecho |
| Módulo Requerimiento | **PENDIENTE** |

---

## 4. Verificado en ejecución

Contra `DBSIGCM` y `SIGA_1750` reales, no contra mocks:

| Prueba | Resultado |
|---|---|
| Ingreso local y armado del menú desde `RolModulo` | OK |
| Registro del Anexo 3 → `CMN-2026-000002`, 48 períodos materializados | OK |
| Transición `CMN_GENERAR_A3` (Borrador → Por firmar) | OK |
| El expediente sale de la bandeja del Especialista al cambiar de responsable | OK |
| Cambio de perfil: el Jefe ve el mismo expediente con «Firmar Anexo 3» | OK |
| Visor del Anexo 3 y trazabilidad | OK |
| Cierre de sesión local y retorno al selector | OK |
| **Firma del Anexo 3 en adelante** | **Bloqueado — ver §5** |

---

## 5. El bloqueo que hubo: F003 *(resuelto)*

`CMN_FIRMAR_A3` está sembrada con `DocumentoRequerido =
CMN_ANEXO_3_SOLICITUD_MODIFICACION`, y el motor exige que ese documento exista,
esté vigente y **firmado** (error `51218`).

**No existe ninguna rutina que cree documentos ni registre firmas.** Las tablas
están (`sigcm.Documento`, `DocumentoVersion`, `DocumentoExpediente`) y la semilla
ya define quién firma cada anexo, pero F003 nunca se escribió.

La única fila de documento en la base pertenece a `CMN-2026-000001` y fue
**insertada a mano** (`UsuarioCreacionAuditoria = 'prueba'`, `Programa` nulo)
para saltar esta misma puerta. El hueco ya se había topado y se rodeó.

**Consecuencia**: el flujo CMN no podía pasar de *Por firmar Anexo 3*.

**Resuelto.** `F003` implementa `paRegistrarDocumento`, `paFirmarDocumento` y
`paListarDocumento`, con el versionado que invalida la firma al corregir un
documento ya firmado (CMN-18). Verificado sobre `CMN-2026-000002`: registrar el
documento, rechazo del especialista al intentar firmar —`51614`, sólo firma
`AREA_JEFE`—, firma del Jefe y la transición `CMN_FIRMAR_A3` completada.

El punto de integración del firmador institucional queda contenido en
`paFirmarDocumento`: cuando devuelva un PDF con la firma incrustada, esa rutina
recibirá el nuevo `GeneradoDocumento` y su huella. Ninguna otra rutina, endpoint
ni pantalla cambia, porque todas preguntan por el **estado** de la versión, no
por cómo se firmó.

---

## 6. Plan para documentos y archivos

Diseño acordado, alineado con la convención de archivos ya vigente en la casa.

### 6.1 Dos casos que no hay que confundir

| | **Documento generado** | **Archivo adjunto** |
|---|---|---|
| Qué es | Anexo 3, Anexo 4: los produce el sistema desde los datos | Sustentos, Anexo 4 externo firmado |
| Quién lo crea | El backend | El usuario, desde el navegador |
| Se versiona y se firma | Sí | No |
| Pieza | `sigcm.Documento` + F003 | `app-input-archivos` |

El componente `app-input-archivos` **no sirve para generar los anexos**: sube lo
que el usuario elige. Los anexos los arma el sistema. Comparten el destino —el
file server— y las dos columnas que los identifican.

### 6.2 Almacenamiento

Misma convención que los otros sistemas de la ANIN:

```jsonc
"appSettings": {
  "rutafile": "D:\\file\\",                    // raíz física
  "urlfile":  "https://localhost:7198/files"   // raíz pública
}
```

Una carpeta por módulo bajo la raíz: `D:\file\cmn\`, `D:\file\requerimiento\`.
El nombre del archivo generado lleva el código del expediente y la versión:
`cmn/CMN-2026-000002-anexo3-v1.pdf`. Así el archivo se identifica solo, sin
consultar la base.

En `Startup.cs`, para servir la carpeta en local:

```csharp
app.UseStaticFiles(new StaticFileOptions
{
    FileProvider = new PhysicalFileProvider(@"D:\file"),
    RequestPath  = "/files"
});
```

Se marca con la etiqueta `[AMBIENTE]`, igual que `appsettings.json`: en QA y
producción **se comenta**, porque ahí el file server lo publica IIS.

### 6.3 Columnas

`sigcm.DocumentoVersion` **ya tiene** `Payload`, `ArchivoUri` y `ArchivoHash`,
que cubren el caso. Para no tener dos vocabularios de archivo en la misma casa,
se propone en `V008` renombrar a la convención vigente:

| Actual | Propuesto | Contenido |
|---|---|---|
| `ArchivoUri` | `GeneradoDocumento` | URL pública completa |
| — | `NombreDocumento` | Nombre visible: «Anexo 3 - CMN-2026-000002.pdf» |
| `ArchivoHash` | se conserva | Huella del archivo firmado |

Ambas `varchar(1000)`, como en el resto de los sistemas.

Para los **adjuntos** del usuario, el mismo par de columnas se agrega a la tabla
que corresponda cuando se defina qué se adjunta y dónde.

### 6.4 Generación del PDF

Tres caminos, con su costo real:

1. **Backend genera el PDF** *(recomendado)*. El documento firmado debe ser
   idéntico para todos y no puede depender del navegador de quien lo abrió. La
   huella (`ArchivoHash`) solo tiene sentido si el archivo es reproducible.
   Falta decidir la librería: **QuestPDF** es la más cómoda en .NET 8, pero su
   licencia Community tiene condiciones por facturación que **hay que verificar
   para una entidad pública** antes de adoptarla. Alternativas sin esa duda:
   `wkhtmltopdf` vía DinkToPdf, o Chromium headless.
2. **Frontend imprime a PDF** desde el visor. Es lo que hoy hace el visor, y es
   gratis, pero el resultado varía según navegador y márgenes: sirve para leer,
   no para archivar como documento firmado.
3. **Híbrido**: el front renderiza, el usuario imprime a PDF y lo sube por
   `app-input-archivos`. Descartado — convierte un documento del sistema en un
   adjunto manual y pierde la trazabilidad de versión.

**Decisión pendiente**: la librería del camino 1. Es lo único que bloquea F003.

### 6.5 Estado del componente `app-input-archivos`

Está copiado en `shared/components/input-archivos`, pero **hoy no funciona**:

- depende de `MaestraService` (`subirArchivo`, `descargarArchivo`), y
  `shared/services/` **no existe** en este proyecto;
- es `standalone: false` y **no está declarado** en `SharedModule`;
- el backend no tiene el endpoint de subida que ese servicio invoca.

Son tres piezas a completar antes de poder usarlo. Ninguna es grande.

Contrato que ya define el componente, y que el endpoint debe respetar:

```json
{ "estado": 1,
  "documento_original": "Prueba 7.pdf",
  "documento_sistema": "https://.../files/cmn/8f3a....pdf" }
```

Y el evento que emite al padre: `nombre_original_documento` y
`generado_nombre_documento`, que el formulario guarda en `NombreDocumento` y
`GeneradoDocumento`.

---

## 7. Orden de trabajo propuesto

1. **Decidir la librería de PDF** (§6.4). Bloquea todo lo demás.
2. **F003**: `paGenerarDocumento`, `paFirmarDocumento`, invalidación por versión
   (CMN-18). Desbloquea la firma del Anexo 3.
3. **V008**: columnas de archivo con la convención de la casa (§6.3).
4. **Backend**: endpoints de documento y de subida de archivos.
5. **Frontend CMN**: generar, ver y firmar el anexo; completar el circuito hasta
   el Anexo 4 consolidado y probarlo de punta a punta con los cinco perfiles.
6. **Requerimiento**: recién cuando CMN esté cerrado y verificado. Su modelo de
   datos no existe todavía (`requerimiento` es un esquema vacío).

Las siete decisiones funcionales pendientes están en la §5 de
[`reglas-negocio-mockup.md`](reglas-negocio-mockup.md). Las que afectan a CMN son
la 1 y la 2, y hacen falta **antes** del paso 5.
