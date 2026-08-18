# Desarrollo vs. local — reporte de comparación

Fecha: 2026-08-18
Fuente A: `Proyecto/anin_bdsgmc/sgcm_script` — copia de objetos de `DBSIGCM` en
`192.168.40.75`, generada 2026-08-18 12:00, la versión que hoy funciona con el
front y el back.
Fuente B: `SIGCM_SERVER` — la serie de migraciones, recién reinstalada en
`localhost\SQLSERVER25`.

---

## 1. La pregunta del compat level

> `SIGA_1750` está en 100 y `DBSIGCM` en 160. Si vamos a trabajar con datos de
> SIGA e incluso a registrar en sus tablas, ¿no deberían ser las dos 100?

**No. Y forzar `DBSIGCM` a 100 rompería el sistema entero.**

El nivel de compatibilidad es **una propiedad de cada base, no del servidor ni
de la conexión**. Lo que gobierna una consulta es el compat de la base **desde
la que se ejecuta**, no el de la base cuyas tablas toca. No existe "conflicto de
compat" entre bases como sí existe el conflicto de intercalación (error 468).

### Qué se pierde exactamente a compat 100

Medido en este equipo, misma instancia, dos bases idénticas salvo el compat:

| Construcción | compat 160 | compat 100 |
|---|---|---|
| `OPENJSON` | 1 fila | `Invalid object name 'OPENJSON'` |
| `OPENJSON ... WITH (esquema)` | 1 fila | error de sintaxis, **el lote no compila** |
| `GENERATE_SERIES` | 5 filas | `Invalid object name` |
| `STRING_SPLIT` | 2 filas | `Invalid object name` |
| `FOR JSON PATH` | funciona | funciona |
| `JSON_OBJECT` | funciona | funciona |

`OPENJSON` es el corazón del contrato con el backend: **cada rutina invocable
recibe un `nvarchar(max)` con JSON y lo desarma con `OPENJSON`**. A compat 100
no es que el sistema ande lento: no compila.

### Cómo se escribe entonces en SIGA, que está en 100

Exactamente como ya está diseñado, y funciona. Probado en este equipo:

```
base_de_ejecucion | compat_ejecucion | compat_destino
DBSIGCM           | 160              | 100
-> 3 filas insertadas en la base compat 100, parseadas con OPENJSON
```

El procedimiento vive en `DBSIGCM` (160), ahí desarma el JSON con `OPENJSON`, y
el `INSERT` aterriza en la tabla de la base en compat 100 a través del sinónimo.
El JSON **nunca entra a SIGA**: a SIGA llegan columnas normales — `varchar`,
`int`, `datetime`. SIGA no necesita saber que existe el JSON, igual que no
necesita saber que existe el SIGCM.

### Y no se debe tocar el compat de SIGA

`SIGA_1750` es del MEF, no nuestra. Subirle el compat cambia el optimizador y
las semánticas de sus propias consultas, con el aplicativo SIGA encima. Es un
riesgo sin ninguna contrapartida: no ganamos nada, porque nuestro código no
corre en su contexto.

**Regla:** `DBSIGCM` en 160, `SIGA_1750` como esté, y nunca al revés.

---

## 2. Comparación de objetos

94 objetos en el volcado de desarrollo, 84 en la base local.

| Resultado | Cantidad |
|---|---|
| Idénticos | 60 |
| Con diferencias | 22 |
| Solo en desarrollo | 12 |
| Solo en local | 2 (las secuencias) |

### Lo que NO divergió — y es la buena noticia

**Las 34 tablas comunes son idénticas, columna por columna, tipo por tipo.**
Los 14 sinónimos también, y apuntan a `SIGA_1750` en los dos lados. El modelo de
datos es el mismo. Toda la divergencia está en el código.

### Lo que divergió: una reescritura a T-SQL de 2008

Los 22 objetos con diferencias y los 12 que solo existen en desarrollo responden
a un solo patrón. Desarrollo eliminó **toda** construcción posterior a SQL Server
2008 y la sustituyó a mano:

| Construcción | Desde | Reemplazo en desarrollo |
|---|---|---|
| `OPENJSON`, `JSON_VALUE` | 2016 | `fnJsonToken`, `fnJsonTexto`, `fnJsonEntero`, `fnJsonLeerValor`, `fnJsonArray` — un tokenizador carácter por carácter |
| `ISJSON` | 2016 | `fnEsJson` — compara el primer y el último carácter |
| Escapado con `STRING_ESCAPE`/`FOR JSON` | 2016 | `fnJsonEscape`, `fnJsonValorTexto` |
| `SEQUENCE` / `NEXT VALUE FOR` | 2012 | tabla `sigcm.Correlativo` con `UPDLOCK, HOLDLOCK` |
| `THROW` | 2012 | `RAISERROR` |
| `CONCAT` | 2012 | operador `+` |
| `TRY_CONVERT` | 2012 | `fnTryFecha`, `fnTryGuid` |
| `DECLARE @x tipo = valor` | 2008 | `DECLARE` + `SET` en dos líneas |

Son **462 llamadas** a las funciones propias repartidas por el código.

`sigcm.fnSumarDiasHabiles` es el caso que lo retrata: las dos versiones son
funcionalmente idénticas; lo único que cambia es que la inicialización en línea
del `DECLARE` se partió en dos sentencias.

### Por qué se hizo

Por la premisa que aparece en la documentación que se le pasó al otro
desarrollador:

> "En este proyecto, SIGA / DBSIGCM van en 100. Por eso los scripts evitan
> OPENJSON, CREATE SEQUENCE e ISJSON."

**`DBSIGCM` nunca estuvo en 100.** Está en 160 en desarrollo y en 160 aquí; lo
confirma la misma consulta que originó esta discusión. El trabajo fue correcto y
disciplinado, pero resolvía una restricción que no existe.

### Qué cuesta mantenerlo

Medido en este equipo con un sobre realista de 3 589 caracteres (actor +
solicitud + 30 ítems), 200 repeticiones:

| Operación | Nativo | Funciones propias | Factor |
|---|---|---|---|
| Leer un valor (`Actor.Usuario`) | 1 ms | 158 ms | **158x** |
| Validar el JSON | 8 ms | 7 ms | similar |

Y hay un problema de correctitud, no solo de velocidad:

```
ISJSON   sobre '{esto no es json, pero abre y cierra llave}' -> 0
fnEsJson sobre '{esto no es json, pero abre y cierra llave}' -> 1
```

Las tablas llevan `CHECK (fnEsJson(...) = 1)` donde el diseño original tenía
`CHECK (ISJSON(...) = 1)`. Esa restricción **acepta JSON corrupto**.

El costo real en producción es peor que 158x: el tokenizador es una función
escalar con un `WHILE` por carácter, y `fnJsonTexto` vuelve a recorrer la cadena
en cada llamada. Con 261 llamadas a `fnJsonValorTexto` y 105 a `fnJsonTexto` en
el código, un registro de 30 ítems recorre el sobre completo cientos de veces.

---

## 3. Recomendación

**Adoptar el modelo de datos y las mejoras funcionales de desarrollo, y revertir
la reescritura de 2008 a las construcciones nativas.**

Tres razones para no quedarse con la versión de desarrollo tal cual: es 158x más
lenta en la operación más frecuente del sistema, su validación de JSON acepta
basura, y son ~2 000 líneas de parser propio que hay que mantener y depurar en
lugar de usar lo que el motor ya trae probado.

Y una razón para no descartarla: **es la que hoy funciona con el front y el
back**, y varios de sus procedimientos son más largos que los nuestros.

### Verificación: la diferencia de tamaño NO es funcionalidad

Se revisó objeto por objeto. La conclusión es que **los 34 objetos divergentes
son plomería, sin una sola diferencia funcional**:

- 18 de los 22 objetos con diferencias están saturados de llamadas al parser
  propio (de 3 a 63 llamadas cada uno). Ese es todo el crecimiento.
- `paListarMaestroSiga` (12 516 vs. 5 093 caracteres, la mayor brecha) atiende
  **exactamente los mismos 9 maestros** en las dos versiones: CATALOGO,
  CENTRO_COSTO, CUADRO_VIGENTE, ETAPA_CENTRO, FUENTE_FINANC, META, TAREA, TECHO,
  UNIDAD_MEDIDA.
- `cmn.vwAgrupacionSiga` es la misma consulta; solo cambia
  `STRING_AGG(...) WITHIN GROUP (ORDER BY ...)` por el truco
  `STUFF(... FOR XML PATH(''))`, que además es una subconsulta correlacionada por
  fila y por lo tanto más lenta.
- `fnSumarDiasHabiles` difiere solo en que la inicialización en línea del
  `DECLARE` se partió en `DECLARE` + `SET`.
- `fnCodigoItemSiga` no es lógica de negocio: es `CONCAT_WS('.', ...)`
  reimplementado con `STUFF`. También es plomería.

**Consecuencia:** revertir a las construcciones nativas no pierde nada. La serie
de migraciones de `SIGCM_SERVER` ya es, objeto por objeto, la versión optimizada
de lo que hoy corre en desarrollo.

### Orden propuesto

1. Confirmar con el otro desarrollador que la premisa del compat 100 se descarta
   — es una decisión de a dos, y todo lo demás depende de ella.
2. Por cada uno de los 22 objetos con diferencias, revisar el diff real y separar
   *cambio de plomería* (revertir a nativo) de *cambio funcional* (conservar).
   El CSV adjunto los lista.
3. `sigcm.Correlativo` vs. secuencias: aquí desarrollo tiene un argumento
   legítimo, porque una tabla de correlativos permite reiniciar la numeración por
   año y una `SEQUENCE` no. Decidirlo por el requisito, no por el compat.
4. Las 12 funciones propias se eliminan al revertir. Ninguna se rescata:
   `fnCodigoItemSiga` resultó ser `CONCAT_WS` reimplementado.
5. Reinstalar con `instalar.ps1 -Recrear` y correr las pruebas del front y el
   back contra el resultado.

### Sobre git

La copia `sgcm_script` es **una foto, no un historial**: un archivo por objeto
con el estado de la base en un instante. Sirve para verificar, no para versionar
— no dice en qué orden aplicar nada ni cómo pasar de la versión de ayer a la de
hoy.

Lo que va a git como fuente de verdad es la serie de migraciones de
`SIGCM_SERVER/db` (`V*` DDL, `F*` API, `S*` semilla), que sí tiene orden,
es idempotente y ya está probada de punta a punta. El volcado por objeto se
mantiene como artefacto de verificación: se regenera desde la base y se compara,
que es justo lo que hizo este reporte.

Dos cosas que conviene montar de una vez:

- `instalar.ps1 -SoloVerificar` como hook de pre-commit: no deja subir un script
  con construcciones que desarrollo rechazaría.
- Una tabla de migraciones aplicadas (DbUp, que ya estaba previsto y es .NET como
  el backend), para dejar de reejecutar la serie completa en cada despliegue.

---

## Anexos

- `reporte_desarrollo_vs_local.csv` — los 96 objetos con su estado.
- `SIGCM_SERVER/00_servidor/C000B__diagnostico_motor.sql` — el diagnóstico de
  motor y capacidades que sustenta la sección 1.
