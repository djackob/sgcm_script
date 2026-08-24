# Volcados de verificación

Cada carpeta es una foto de los objetos de `DBSIGCM` en un entorno y una fecha,
un archivo por objeto, extraída de la base y no escrita a mano.

**No son la fuente de verdad.** Eso es la serie de `db/`. Estos volcados sirven
para una sola cosa: comprobar que un entorno quedó como la serie dice que debía
quedar. Se regeneran y se comparan; no se editan.

| Carpeta | Origen | Fecha |
|---|---|---|
| `desarrollo-20260818/` | `DBSIGCM` en `192.168.40.75` | 2026-08-18 12:00 |
| `cambios-anin-20260820/` | Entrega del otro desarrollador — los dos procedimientos de la firma | 2026-08-20 |

## desarrollo-20260818

Es el estado que hoy funciona con el front y el back, y el que se comparó contra
la serie en `docs/comparacion-desarrollo-vs-local.md`. De esa comparación:

- Las 34 tablas comunes y los 14 sinónimos son **idénticos** a los que produce
  la serie. El modelo de datos nunca divergió.
- Los 34 objetos que sí divergen son **plomería, sin diferencia funcional**:
  este volcado reemplaza `OPENJSON`, `STRING_AGG`, `CONCAT_WS`, `SEQUENCE`,
  `THROW` y `CONCAT` por implementaciones manuales de nivel SQL Server 2008.
- Ese reemplazo se hizo sobre una premisa equivocada —que `DBSIGCM` iba en
  compatibilidad 100— y cuesta caro: leer un valor con el parser manual resultó
  158 veces más lento que `JSON_VALUE`, y su validador da por bueno un JSON
  corrupto que `ISJSON` rechaza.

Por eso la serie de `db/` usa las construcciones nativas: desarrollo es SQL
Server 2022 y las admite todas.

## cambios-anin-20260820

Los dos procedimientos de lectura del CMN que llegaron del otro desarrollador
con el cambio de la firma. Traen el dato que faltaba —la ruta del PDF ya subido
al file server— pero escritos en el dialecto del volcado de arriba y sobre la
versión del flujo anterior al Anexo 4 múltiple. **El cambio se portó a
`db/10_api/F002__cmn_solicitud.sql`; estos archivos no se ejecutan.** El porqué
está en [`cambios-anin-20260820/LEEME.md`](cambios-anin-20260820/LEEME.md).
