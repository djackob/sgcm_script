# cambios-anin-20260820 — los dos procedimientos de la firma

Lo que llegó del otro desarrollador el **2026-08-20**, tal como llegó. Son las
dos rutinas de lectura del CMN con el cambio que hacía falta para la firma:

| Objeto | Qué agrega |
|---|---|
| `cmn/paListarSolicitud.sql` | `DocumentoSistemaAnexo3` y `DocumentoSistemaAnexo4` en cada fila de la bandeja |
| `cmn/paObtenerSolicitud.sql` | los mismos dos campos en la cabecera del detalle |

**No se ejecutan.** Como el resto de `_snapshot/`, esto es material de
comparación; la fuente de verdad es la serie de `db/`. El cambio funcional ya
está portado a [`db/10_api/F002__cmn_solicitud.sql`](../../db/10_api/F002__cmn_solicitud.sql).

## Por qué se portó en vez de aplicarse

Aplicarlos tal cual habría roto la base por dos motivos independientes.

**1. Están escritos en el dialecto del volcado de desarrollo.** Usan
`sigcm.fnEsJson`, `fnJsonTexto`, `fnJsonEntero`, `fnJsonValorTexto` y
`fnTryGuid`, más `FOR XML PATH` para armar el JSON a mano. Esas cinco funciones
**no existen en `DBSIGCM`**: son de la reescritura a nivel SQL Server 2008 que
describe [`_snapshot/README.md`](../README.md), hecha sobre la premisa
equivocada de que la base iba en compatibilidad 100. Los procedimientos habrían
compilado —SQL Server resuelve las funciones en tiempo de ejecución— y habrían
fallado en la primera llamada. La base va en **compat 160**, con `OPENJSON`,
`JSON_VALUE`, `FOR JSON` y `THROW` nativos.

**2. Son de la versión anterior del flujo.** Esa copia es de antes del Anexo 4
múltiple, así que su bandeja no devuelve `AreaUsuaria`, `SiglaArea`, `IdPaquete`
ni `CodigoAnexo4`. Aplicarla habría dejado la pantalla de Abastecimiento sin
saber de qué área es cada expediente y sin poder agrupar las filas de un mismo
Anexo 4 —la iteración del 2026-08-20 completa—, a cambio de agregar dos campos.

## Qué se tomó

El cambio, no el archivo: los dos campos, resueltos con
`cmn.fnDocumentoVigente`, una función inline que devuelve la versión vigente del
documento vivo de un tipo para un expediente. Los cuatro `OUTER APPLY` del
original —dos rutinas por dos tipos de documento— son la misma consulta de tres
tablas repetida; una sola definición evita que se separen.
