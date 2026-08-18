# SIGCM — base de datos

Serie de scripts que construye `DBSIGCM`, la base del Sistema Integrado de
Gestión de Contrataciones Menores del ANIN. Es la **fuente de verdad** del
esquema: si un objeto no está aquí, no existe.

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
| `db/15_siga/` | `W*` — escritor hacia SIGA (todavía vacía, ADR-003) | `DBSIGCM` |
| `db/20_seed/` | `S*` — configuración: roles, estados, plazos | `DBSIGCM` |
| `db/90_pruebas/` | `S900` — usuarios ficticios, solo local | `DBSIGCM` |
| `docs/` | Reportes de entorno y de comparación entre entornos | — |
| `pruebas/` | Consultas sueltas de humo, no forman parte de la serie | — |
| `_snapshot/` | Fotos de un entorno en una fecha, para verificar | — |

El orden exacto de aplicación está en `db/README.md`. Los prefijos mandan:
`V` antes que `F`, `F` antes que `S`, y dentro de cada grupo por número.

## Instalar

```powershell
# Instalación o actualización normal, respeta la base existente
.\instalar.ps1

# Rearmar desde cero: BORRA DBSIGCM y la recrea igual a desarrollo
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

- `db/15_siga/W001__escritor_cuadro_modificado.sql` no existe todavía. La
  escritura real hacia SIGA está en modo simulación por ADR-003: las
  transiciones encolan en `integracion.Operacion` y nadie vacía esa cola.
  `SIGA/integracion/usp_ext_registrar_item_cmn.sql` es el procedimiento del lado
  de SIGA que hace el `INSERT`, y está entregado para homologación, sin instalar.
- `V010` / `S004`: indagación de mercado, cuadro de cotizaciones (Anexo 8), CCP
  y orden.
- Falta una tabla de migraciones aplicadas (DbUp) para dejar de reejecutar la
  serie completa en cada despliegue.
