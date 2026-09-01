# SIGCM — base de datos

Serie de scripts que construye `DBSIGCM`, la base del Sistema Integrado de
Gestión de Contrataciones Menores del ANIN. Es la **fuente de verdad** del
esquema: si un objeto no está aquí, no existe.

> **¿Primera vez en el proyecto?** El punto de entrada no es este archivo, es
> [`LEEME.md`](LEEME.md): trae el prompt de arranque, el mapa de los cuatro
> bloques y las reglas. Este README cubre sólo la base de datos.

## Regla número uno

La línea base es **SQL Server 2022, compatibilidad 160**. No es una preferencia:
es la versión del servidor de desarrollo del ANIN, medida el 2026-08-18 con
`00_servidor/C000B__diagnostico_motor.sql` (16.0.4262.2, Developer, sobre Rocky
Linux). El resultado completo está en `docs/entorno-desarrollo-20260818.txt`.

Las máquinas de desarrollo local corren SQL Server 2025, que es más permisivo.
Por eso `instalar.ps1` revisa el código fuente **antes** de tocar la base y
rechaza cualquier construcción de 2025 (el tipo `json` nativo, `JSON_ARRAYAGG`,
`REGEXP_LIKE`). Sin ese paso, un script que funciona aquí falla allá.

`SIGA_1750` está en compatibilidad 100 y **así se queda**: es base del MEF, con
su aplicativo encima. Que esté en 100 no obliga a `DBSIGCM` a nada — el nivel de
compatibilidad gobierna la consulta según la base desde la que se ejecuta, no
según las tablas que toca. El razonamiento completo, con las mediciones, está en
`docs/comparacion-desarrollo-vs-local.md`.

## Estructura

| Carpeta | Qué contiene | Se ejecuta en |
|---|---|---|
| `00_servidor/` | Preflight, creación de la base, sinónimos, inventario | `master` |
| `db/00_ddl/` | `V*` — tablas, vistas, restricciones | `DBSIGCM` |
| `db/10_api/` | `F*` — procedimientos y funciones del contrato | `DBSIGCM` |
| `db/15_siga/` | `W*` — escritor hacia SIGA, en simulación por ADR-003 | `DBSIGCM` |
| `db/20_seed/` | `S*` — configuración: roles, estados, plazos | `DBSIGCM` |
| `db/90_pruebas/` | `S900` — usuarios ficticios, solo local | `DBSIGCM` |
| `docs/` | Reportes de entorno y de comparación entre entornos | — |
| `pruebas/` | Consultas sueltas de humo, no forman parte de la serie | — |
| `_snapshot/` | Fotos de un entorno en una fecha, para verificar | — |

El orden exacto de aplicación está en `db/README.md`. Los prefijos mandan:
`V` antes que `F`, `F` antes que `S`, y dentro de cada grupo por número.

## Instalar

```powershell
# Instalación o actualización normal, respeta DBSIGCM y reescribe usp_ext en SIGA
.\instalar.ps1

# Rearmar desde cero: BORRA DBSIGCM (no SIGA) y reaplica toda la serie + usp_ext
.\instalar.ps1 -Recrear

# Con los usuarios ficticios para probar sin SSO (solo local)
.\instalar.ps1 -Recrear -ConDatosPrueba

# Solo revisar el código fuente, sin conectarse a ninguna base
.\instalar.ps1 -SoloVerificar

# Contra el servidor de desarrollo
.\instalar.ps1 -Servidor "192.168.40.75" -Usuario developer_anin
```

Toda corrida deja bitácora en `_bitacora\`, que no se versiona.

## Cómo trabajar entre dos

Los scripts son **idempotentes y ordenados**, no un volcado de la base. Eso es
lo que permite que dos personas avancen sin pisarse.

1. **Nunca se edita un script ya aplicado en desarrollo.** Si hay que cambiar
   una tabla, entra un `V0NN` nuevo con el `ALTER`. Editar el `V` viejo hace que
   quien ya lo aplicó nunca reciba el cambio.
2. **Un cambio, una rama, un PR.** La rama se nombra por el objeto que toca:
   `v010-correlativo`, `f002-listar-solicitud`.
3. **Antes de subir**, `.\instalar.ps1 -SoloVerificar`. Antes de aprobar,
   `.\instalar.ps1 -Recrear` en local y que termine en verde.
4. **Los `F*` sí se editan en su sitio**: son `CREATE OR ALTER`, se reaplican
   completos en cada corrida y no acumulan historia. Las tablas no.

### La serie y el volcado

En `_snapshot/desarrollo-20260818/` está la copia objeto-por-objeto que se
extrajo de `DBSIGCM` en el servidor de desarrollo el 2026-08-18 — los 96
archivos que ocupaban la raíz de este repositorio antes de esta reorganización.

Se conserva, pero **no es la fuente de verdad**. Un volcado es una foto, no un
historial: no dice en qué orden aplicar nada, ni cómo pasar de la versión de
ayer a la de hoy, y cada merge sobre él es un conflicto del archivo completo del
procedimiento. Sirve para verificar que un entorno quedó como se esperaba: se
regenera y se compara contra la serie, que es exactamente lo que produjo
`docs/comparacion-desarrollo-vs-local.md`.

Cuando la serie y un volcado discrepan, manda la serie y el entorno se reinstala.

## Pendientes conocidos

- **Homologación de `usp_ext_registrar_item_cmn`.** Es el procedimiento que
  corre dentro de `SIGA_1750` y hace el `INSERT`. Está entregado al ANIN para
  revisión y todavía no instalado en desarrollo ni en producción. Hasta que lo
  esté, `W001` solo puede correr en simulación. Es un trámite, no código.
- **`W001` implementa `INCLUIR_ITEM` y `EXCLUIR_ITEM`.**
  `MODIFICAR_CANTIDADES` y `CONSOLIDAR_CMN` todavía devuelven un error explícito.
- **El worker de integración está implementado en el backend.** Se despliega
  apagado y en simulación por defecto; cada ambiente debe habilitarlo de forma
  explícita. Usa `sp_getapplock` para que una sola réplica drene la cola y llama
  a `integracion.paEscribirCuadroModificado` sin reimplementar reglas de SIGA.
- `V011` / `S004`: indagación de mercado, cuadro de cotizaciones (Anexo 8), CCP
  y orden.
- Falta una tabla de migraciones aplicadas (DbUp) para dejar de reejecutar la
  serie completa en cada despliegue.

## Estado verificado

Probado de punta a punta en local el 2026-08-18, contra la copia restaurada de
`SIGA_1750`: registro de solicitud, las seis transiciones hasta
`CMN_VALIDAR_UA`, encolado y drenaje en modo real. Escribió la cabecera 170 y su
ítem en `SIG_CUADRO_NECESIDAD` / `_DET` (`CANT_03 = 40`, `MNTO_TOTAL = 500.00`) y
dejó la correspondencia en `integracion.MapeoCmn`.

La exclusión se verificó el 2026-08-19 sobre el ítem `01.01 / 1 / 1`: W001 dejó
la operación `COMPLETADO`, creó el mapeo con estado `E`, conservó las cantidades
en `SIG_CUADRO_MODIFICADO_DET_ORI`, creó la solicitud SIGA 442 en estado `2`
(V.B. Jefe) con sus cuatro detalles anuales y actualizó las filas 2026–2029 de
`SIG_CUADRO_MODIFICADO_DET`. Una segunda ejecución recuperó la misma solicitud
442 sin duplicar cabeceras, detalles ni estados documentales.
