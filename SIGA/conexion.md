# Estrategia directa para explorar SIGA MEF y su base de datos

## Objetivo

Este documento explica a otra IA cómo reconstruir rápidamente un flujo funcional de SIGA MEF y relacionarlo con sus tablas SQL Server. Resume la estrategia usada para revisar dos casos:

- Cuadro Multianual de Necesidades (CMN).
- Orden de Servicio.

El principio es trabajar en dos pistas y conciliarlas:

1. Observar el flujo real en el aplicativo, sin grabar información.
2. Consultar la estructura y los datos de SQL Server en modo lectura.

No asumir nombres de tablas ni significados de estados únicamente por intuición. Cada conclusión debe tener evidencia de pantalla, metadatos, claves, relaciones y registros reales.

## Datos técnicos conocidos

| Elemento | Valor |
|---|---|
| Carpeta del aplicativo | `C:\SIGA_MEF` |
| Ejecutable | `C:\SIGA_MEF\siga.exe` |
| Instancia SQL Server | `localhost\SQLSERVER25` |
| Puerto indicado | `1433` |
| Base SIGA identificada | `SIGA_1750` |
| Base inicial de la conexión | `master` |
| Aplicativo observado | SIGA 26.01 |
| Autenticación SQL alternativa | Usuario `admin_siga`; solicitar la contraseña al operador mediante un canal seguro |

La cadena de Navicat entregada apunta inicialmente a `master`. Para revisar el contenido funcional hay que cambiar explícitamente a `SIGA_1750` después de conectarse.

No escribir credenciales en scripts, documentos, parámetros de línea de comandos, capturas ni bitácoras. Cuando el equipo permita autenticación integrada de Windows, preferirla.

## 1. Conexión rápida a SQL Server

### Opción preferida: autenticación integrada

Comprobar conectividad y enumerar bases:

```powershell
sqlcmd -S "localhost\SQLSERVER25" -E -Q "SET NOCOUNT ON; SELECT @@SERVERNAME AS servidor, DB_NAME() AS base_actual; SELECT name FROM sys.databases ORDER BY name;"
```

Abrir directamente la base SIGA:

```powershell
sqlcmd -S "localhost\SQLSERVER25" -d "SIGA_1750" -E -Q "SET NOCOUNT ON; SELECT DB_NAME() AS base_actual;"
```

### Opción alternativa: autenticación SQL

Usar el usuario `admin_siga`, pero solicitar la contraseña de forma segura. Evitar colocarla en `conexion.md` o en una orden que quede registrada en el historial. Si se usa una biblioteca, recibirla mediante un secreto o variable específica del proceso.

Ejemplo conceptual:

```text
Servidor: localhost\SQLSERVER25
Base inicial: master
Base funcional: SIGA_1750
Usuario: admin_siga
Contraseña: <SOLICITAR_SECRETO>
```

## 2. Exploración segura del aplicativo

### Regla operativa

La primera revisión debe ser de solo lectura:

- Abrir consultas, listados, menús y detalles existentes.
- No usar `Grabar`, `Aprobar`, `Consolidar`, `Anular` ni `Eliminar`.
- No cambiar cantidades, precios, estados o responsables.
- Si se abre un registro, salir sin guardar.
- Tomar capturas solo de la ventana SIGA; evitar escritorio, correo u otras aplicaciones.

### Secuencia de exploración

1. Ejecutar `C:\SIGA_MEF\siga.exe`.
2. Ingresar con un usuario funcional autorizado. La credencial debe ser proporcionada por el operador y no documentarse.
3. Seleccionar el módulo que corresponde al proceso.
4. Enumerar el menú completo y registrar la ruta exacta.
5. Abrir el listado principal y anotar:
   - título de la ventana;
   - año y unidad ejecutora;
   - filtros;
   - botones;
   - columnas de la grilla;
   - estados visibles;
   - accesos para abrir un detalle.
6. Abrir un registro existente y anotar los campos de cabecera, detalle, totales y auditoría visibles.
7. Revisar el menú `Archivo` y los atajos, pero no ejecutar una grabación.
8. Elegir uno o dos registros de ejemplo y conservar sus claves visibles para buscarlos después en SQL Server.

### Cuando la interfaz no expone bien los controles

SIGA es una aplicación de escritorio antigua. Puede ser necesario combinar:

- Automatización de ventanas de Windows para localizar títulos, controles y menús.
- Enumeración Win32 del menú para obtener la jerarquía y los identificadores de comandos.
- Captura de la ventana mediante `PrintWindow`, que evita fotografiar todo el escritorio.
- Inspección visual de la grilla y de la barra de estado.

No empezar desensamblando el ejecutable. Primero obtener el flujo visible y usar la base para confirmarlo. Buscar texto dentro de binarios solo sirve como evidencia complementaria de nombres de ventanas, mensajes SQL o cambios de estado.

## 3. Descubrimiento rápido de tablas

### Buscar tablas por palabras del proceso

```sql
USE SIGA_1750;
GO

SELECT s.name AS esquema, t.name AS tabla
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
WHERE t.name LIKE '%CUADRO%NECES%'
   OR t.name LIKE '%CMN%'
   OR t.name LIKE '%ORDEN%'
   OR t.name LIKE '%SERVICIO%'
ORDER BY t.name;
```

La búsqueda de nombres solo genera candidatos. Después hay que inspeccionar columnas, claves, relaciones, volumen y fechas.

### Inventario de columnas

```sql
SELECT
    s.name AS esquema,
    t.name AS tabla,
    c.column_id,
    c.name AS columna,
    ty.name AS tipo,
    c.max_length,
    c.precision,
    c.scale,
    c.is_nullable,
    dc.definition AS valor_default
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.columns AS c ON c.object_id = t.object_id
JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
LEFT JOIN sys.default_constraints AS dc
  ON dc.parent_object_id = c.object_id
 AND dc.parent_column_id = c.column_id
WHERE t.name IN (
    'SIG_CUADRO_NECESIDAD',
    'SIG_CUADRO_NECESIDAD_DET'
)
ORDER BY t.name, c.column_id;
```

Cambiar la lista por las tablas candidatas del flujo de Orden de Servicio cuando se analice ese caso.

### Claves primarias

```sql
SELECT
    OBJECT_SCHEMA_NAME(i.object_id) AS esquema,
    OBJECT_NAME(i.object_id) AS tabla,
    i.name AS clave,
    ic.key_ordinal,
    c.name AS columna
FROM sys.indexes AS i
JOIN sys.index_columns AS ic
  ON ic.object_id = i.object_id
 AND ic.index_id = i.index_id
JOIN sys.columns AS c
  ON c.object_id = ic.object_id
 AND c.column_id = ic.column_id
WHERE i.is_primary_key = 1
  AND OBJECT_NAME(i.object_id) IN (
      'SIG_CUADRO_NECESIDAD',
      'SIG_CUADRO_NECESIDAD_DET'
  )
ORDER BY tabla, ic.key_ordinal;
```

### Relaciones foráneas

```sql
SELECT
    OBJECT_NAME(fkc.parent_object_id) AS tabla_hija,
    pc.name AS columna_hija,
    OBJECT_NAME(fkc.referenced_object_id) AS tabla_padre,
    rc.name AS columna_padre,
    fk.name AS restriccion
FROM sys.foreign_key_columns AS fkc
JOIN sys.foreign_keys AS fk
  ON fk.object_id = fkc.constraint_object_id
JOIN sys.columns AS pc
  ON pc.object_id = fkc.parent_object_id
 AND pc.column_id = fkc.parent_column_id
JOIN sys.columns AS rc
  ON rc.object_id = fkc.referenced_object_id
 AND rc.column_id = fkc.referenced_column_id
WHERE OBJECT_NAME(fkc.parent_object_id) IN (
    'SIG_CUADRO_NECESIDAD',
    'SIG_CUADRO_NECESIDAD_DET'
)
ORDER BY tabla_hija, fk.name, fkc.constraint_column_id;
```

### Disparadores y procedimientos existentes

```sql
SELECT OBJECT_SCHEMA_NAME(parent_id) AS esquema,
       OBJECT_NAME(parent_id) AS objeto,
       name AS trigger_name,
       is_disabled
FROM sys.triggers
WHERE OBJECT_NAME(parent_id) IN (
    'SIG_CUADRO_NECESIDAD',
    'SIG_CUADRO_NECESIDAD_DET'
);

SELECT s.name AS esquema, o.name, o.type_desc
FROM sys.objects AS o
JOIN sys.schemas AS s ON s.schema_id = o.schema_id
WHERE o.type IN ('P', 'V', 'FN', 'IF', 'TF')
  AND (o.name LIKE '%CMN%' OR o.name LIKE '%ORDEN%SERV%')
ORDER BY o.type_desc, o.name;
```

## 4. Estrategia para relacionar pantalla y base

Usar un registro real y distintivo de la pantalla. Para localizarlo en SQL Server, combinar varios valores, no solo la descripción:

- Año.
- Unidad ejecutora.
- Centro de costo o área usuaria.
- Número o secuencia.
- Meta.
- Fuente/rubro.
- Código de ítem.
- Monto total.
- Fecha o estado.

Después:

1. Buscar el registro en tablas candidatas.
2. Identificar la cabecera mediante su clave primaria.
3. Buscar los detalles con la misma clave más la secuencia del ítem.
4. Seguir las claves foráneas hacia catálogos, centros, metas, proveedores, fuentes y techos.
5. Comparar exactamente lo visible en pantalla con las columnas encontradas.
6. Revisar otros registros del mismo tipo para distinguir reglas de valores accidentales.
7. Agrupar por campos de estado y fase para inferir el ciclo de vida.
8. Confirmar la inferencia con la ruta funcional del aplicativo o mensajes internos.

### Consultas exploratorias recomendadas

```sql
-- Volumen y última actividad de una tabla candidata.
SELECT COUNT(*) AS filas,
       MIN(FECHA_REG) AS primera_fecha,
       MAX(FECHA_REG) AS ultima_fecha
FROM dbo.<TABLA>;

-- Distribución de estados para un ejercicio y ejecutora.
SELECT ESTADO, COUNT(*) AS filas
FROM dbo.<TABLA>
WHERE ANO_EJE = '2026'
  AND SEC_EJEC = '001750'
GROUP BY ESTADO
ORDER BY ESTADO;

-- Muestra limitada; nunca consultar toda una tabla grande sin filtro.
SELECT TOP (20) *
FROM dbo.<TABLA>
WHERE ANO_EJE = '2026'
  AND SEC_EJEC = '001750'
ORDER BY FECHA_REG DESC;
```

Si una tabla no tiene `FECHA_REG`, revisar primero sus columnas y elegir su fecha o secuencia equivalente.

## 5. Caso CMN: ruta y mapa confirmado

### Ruta funcional

```text
Módulo Logística
  → Programación
    → Programación del C.M.N.
      → Bienes, Servicios y Obras
```

Ventanas observadas:

- `Registro de C.M.N. por Área Usuaria`.
- `Fase Consolidación y Aprobación del C.M.N. por Área Usuaria`.

La pantalla de detalle muestra actividad operativa, fuente/rubro, meta, tipo de uso, ítem, descripción, clasificador, unidad, monto total y cantidades físicas programadas.

### Tablas núcleo

| Tabla | Función |
|---|---|
| `SIG_CUADRO_NECESIDAD` | Cabecera del CMN. |
| `SIG_CUADRO_NECESIDAD_DET` | Ítems, precios, cantidades e importes mensuales del año base y tres años siguientes. |

Claves confirmadas:

```text
Cabecera:
ANO_EJE + SEC_EJEC + CENTRO_COSTO + SECUENCIA + FASE_CUADRO

Detalle:
clave de cabecera + ITEM_SEC
```

### Tablas de validación o soporte

| Tabla | Uso |
|---|---|
| `SIG_CENTRO_COSTO` | Área usuaria o centro de costo. |
| `META` | Meta presupuestaria. |
| `FUENTE_FINANC_EJEC` | Fuente de financiamiento. |
| `CATALOGO_BIEN_SERV` | Ítem, descripción y unidad. |
| `SIG_TECHO_PRESUPUESTO` | Techo y saldo del año base y tres años siguientes. |
| `SIG_META_PROPUESTA` | Asociación programática. |
| `SIG_METAS_PROP_X_CENTRO` | Relación meta–centro. |
| `SIG_MP_CENTRO_RUBRO` | Relación centro–meta–rubro. |
| `SIG_CUA_NEC_DET_ID` | Identificadores o kits opcionales; no fue necesario para el alta ordinaria analizada. |
| `SIG_CUADRO_MODIFICADO_CMN` | Modificaciones posteriores, no alta inicial. |

### Hallazgos que aceleran la revisión

- La cabecera tiene los datos de área, tarea, meta, fuente, clasificador, fase y tipo.
- El detalle tiene el catálogo, precio, unidad, estado y 48 cantidades: 12 meses por cuatro años.
- Existen cantidades e importes del año base y variantes `_ANNO_01`, `_ANNO_02` y `_ANNO_03`.
- En la instalación revisada, el alta inicial quedó asociada al estado `5` y la consolidación/aprobación al estado `6`.
- No se observaron disparadores en las dos tablas núcleo; la auditoría se almacena explícitamente en campos como `CUSER_ID`, `EQUIPO_REG` y `FECHA_REG`.
- El techo debe comprobarse por centro, fase, fuente, meta, clasificador y periodo antes de insertar.

Los significados de estados fueron inferidos a partir de datos y comportamiento real. Deben revalidarse si cambia la versión o configuración de SIGA.

## 6. Caso Orden de Servicio: estrategia puntual

### Exploración en el aplicativo

1. Entrar al módulo Logística.
2. Localizar la opción de Adquisiciones correspondiente a Órdenes de Servicio.
3. Abrir el listado y anotar año, número de orden, estado, proveedor, expediente, fecha y monto.
4. Abrir una orden existente y registrar:
   - cabecera de la orden;
   - proveedor y RUC;
   - requerimiento o pedido de origen;
   - meta, fuente, clasificador y centro de costo;
   - detalle de servicios;
   - cantidades, precios, impuestos y totales;
   - fechas, estado y auditoría.
5. Revisar el menú `Archivo` para identificar `Nuevo`, `Grabar`, `Recuperar`, `Imprimir` y `Salir`, sin guardar.
6. Elegir una orden existente con número y monto distintivos para rastrearla en SQL Server.

### Descubrimiento en SQL Server

Buscar primero por nombres y luego por columnas:

```sql
SELECT s.name AS esquema, t.name AS tabla
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
WHERE t.name LIKE '%ORDEN%'
   OR t.name LIKE '%SERVICIO%'
   OR t.name LIKE '%ADQUIS%'
   OR t.name LIKE '%PROVEEDOR%'
   OR t.name LIKE '%PEDIDO%'
ORDER BY t.name;
```

Después buscar columnas características en todas las tablas candidatas:

```sql
SELECT OBJECT_SCHEMA_NAME(c.object_id) AS esquema,
       OBJECT_NAME(c.object_id) AS tabla,
       c.name AS columna
FROM sys.columns AS c
WHERE c.name LIKE '%ORDEN%'
   OR c.name LIKE '%RUC%'
   OR c.name LIKE '%PROVEEDOR%'
   OR c.name LIKE '%EXPEDIENTE%'
   OR c.name LIKE '%PEDIDO%'
   OR c.name LIKE '%MONTO%'
ORDER BY tabla, c.column_id;
```

Cruzar el número de orden, año, ejecutora, proveedor, monto y fecha visibles. Cuando aparezca una coincidencia:

1. Determinar si la tabla es cabecera, detalle, presupuesto, proveedor o seguimiento.
2. Extraer la clave primaria completa.
3. Identificar las claves foráneas.
4. Buscar detalles con esa clave.
5. Seguir el documento de origen: requerimiento, pedido, expediente o proceso de adquisición.
6. Revisar las tablas de proveedor, meta, fuente, clasificador, centro de costo y auditoría.
7. Agrupar estados y comparar órdenes de distintas etapas.

La revisión anterior del caso Orden de Servicio dejó un manual y evidencias dentro de `C:\SIGA_MEF\entregables`. Úselos como referencia visual, pero vuelva a confirmar nombres de tablas y reglas directamente en `SIGA_1750` antes de construir una integración.

## 7. Cómo diseñar una integración sin dañar SIGA

No insertar directamente hasta terminar el mapa y homologarlo. El orden correcto es:

1. Identificar cabecera y detalle.
2. Enumerar columnas obligatorias, valores predeterminados y longitudes.
3. Obtener claves primarias, foráneas, índices únicos y disparadores.
4. Identificar todas las tablas maestras y controles presupuestales.
5. Observar cómo cambian estados y auditoría durante el flujo oficial.
6. Diseñar un procedimiento almacenado transaccional que reciba datos de negocio, no columnas arbitrarias.
7. Validar catálogos, duplicidad, techo, estado y permisos antes de insertar.
8. Usar bloqueo de concurrencia al generar secuencias.
9. Insertar siempre cabecera y detalle en una sola transacción.
10. Dejar la aprobación, consolidación, compromiso o devengado en el flujo oficial de SIGA.
11. Probar primero en una copia de homologación.

### Prueba de compilación sin instalar ni alterar datos

Para validar un procedimiento de integración, envolver su creación en una transacción y revertirla:

```sql
BEGIN TRANSACTION;
GO

-- CREATE PROCEDURE ...

GO
IF XACT_STATE() <> 0
    ROLLBACK TRANSACTION;
GO
```

Antes y después, comparar conteos de cabecera y detalle y comprobar que el procedimiento no quedó persistido en `sys.procedures`.

## 8. Método de documentación para otra IA

La salida final debe contener únicamente evidencia útil:

1. Ruta exacta del menú.
2. Nombre de cada pantalla.
3. Secuencia operativa del alta.
4. Mapa `campo visible → tabla.columna`.
5. Tablas núcleo y tablas maestras.
6. Claves primarias y relaciones.
7. Estados y transiciones, indicando si son confirmados o inferidos.
8. Reglas de techo, duplicidad, catálogo y auditoría.
9. Riesgos y pasos que no deben automatizarse.
10. Consultas de conciliación para demostrar que pantalla y base representan el mismo registro.

## Checklist rápido

- [ ] Conexión a `localhost\SQLSERVER25` comprobada.
- [ ] Cambio explícito a `SIGA_1750` realizado.
- [ ] Usuario y contraseña fuera de scripts y documentos.
- [ ] Ruta del menú registrada.
- [ ] Un registro real localizado en pantalla y SQL Server.
- [ ] Cabecera, detalle y claves confirmados.
- [ ] Tablas maestras y controles identificados.
- [ ] Estados comparados con más de un registro.
- [ ] No se grabaron cambios durante la exploración.
- [ ] Integración probada solo en homologación y dentro de transacciones controladas.

## Resultado práctico

Para ir directo al grano, una IA debe empezar por el aplicativo para obtener las claves visibles y la secuencia funcional; inmediatamente después debe usar `sys.tables`, `sys.columns`, claves primarias, claves foráneas y distribuciones de estados en `SIGA_1750`. El mapa queda confirmado únicamente cuando un mismo caso coincide en pantalla, cabecera, detalle, catálogos, presupuesto y auditoría.
