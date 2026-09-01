# SSO — lo que hay que provisionar fuera de nuestra base

Scripts que se ejecutan **en la base del SSO institucional** (PostgreSQL, esquema
`login`), no en `DBSIGCM`. Son el equivalente de `SIGA/integracion/usp_ext_*.sql`:
código versionado que corre en una base ajena y que el instalador **no** aplica.

## Por qué existe esta carpeta

El SIGCM sólo **lee** del SSO: identidad, `cod_perfil` y centro de costo. Toda la
traducción a roles vive en `db/20_seed/S005`, que sí viaja versionado.

Pero hay cosas que no se resuelven de nuestro lado: si nadie tiene el perfil de
administrador asignado en el SSO, nadie puede abrir el panel de accesos, por más
que el mapeo esté sembrado. Eso es un cambio de **datos en un sistema ajeno**, y
hasta ahora sólo existía como prosa en `CONTEXTO.md` y como una fila hecha a mano
en el servidor de desarrollo.

Una fila hecha a mano no sobrevive a un despliegue. Por eso está aquí.

## Los scripts

| Script | Qué hace | ¿Aprobado? |
|---|---|---|
| `S01__acceso_administrador.sql` | Da el perfil `P0001 ADMINISTRADOR` del sistema `S0073` a la persona que se indique | sí, aplicado en desarrollo el 2026-08-28 |

Se ejecutan con `psql` y llevan su propio parámetro:

```bash
psql -h <host> -p <puerto> -U <usuario> -d saa_ -v dni=44687266 -f sso/S01__acceso_administrador.sql
```

Todos son **idempotentes**: correrlos dos veces no duplica nada.

## La regla que gobierna estos scripts

**Nunca se resuelve por identificador numérico.** Los `id_perfil_sistema`,
`id_perfil` e `id_dependencia` **son distintos en cada ambiente**. En desarrollo
el `P0001` del SGCM es el `id_perfil_sistema` 194; en producción será otro. Peor
todavía: en desarrollo Cruz ya tenía un `P0001` activo del `id_perfil_sistema`
184, que es de **otro sistema** (el 66), y buscar por `cod_perfil` sin mirar el
sistema lleva a concluir que ya estaba resuelto cuando no lo estaba.

Por eso los scripts resuelven siempre por **códigos**: `cod_sistema`,
`cod_perfil`, `dni`, `cod_dependencia`. Si un código no existe, el script avisa y
no escribe nada, en vez de insertar contra un identificador equivocado.

**Y nunca tocan contraseñas.** Ni las crean, ni las cambian, ni las leen. El
SIGCM no guarda contraseñas y estos scripts tampoco las manejan: sólo asignan
perfiles a cuentas que ya existen.

## Pendiente, no incluido a propósito

**`COORDINADOR DE UNIDAD`.** El SSO no tiene perfil de coordinador para el área
usuaria — su único `COORDINADOR` es `PE083`, que es de Abastecimiento. CMN no lo
necesita, pero **Requerimiento sí**: su árbol declara el escalón y hoy está
vacío, cosa que el panel de accesos muestra en ámbar.

No hay script porque la decisión no está tomada. Cuando se tome, son tres pasos:
una fila en `login.tm_login_perfil`, una en `login.td_login_perfil_sistema`
apuntando al sistema `S0073`, los accesos de cada persona que ejerza el cargo, y
una fila más en `db/20_seed/S005` mapeándolo a `AREA_COORDINADOR`.

Se deja sin escribir a propósito: un script listo para correr invita a correrlo,
y agregar perfiles al SSO institucional no es una decisión de este repositorio.
Ver `CONTEXTO.md`, entrada del 2026-08-27, donde están las cuatro opciones
evaluadas.

## Ojo con el verificador de `instalar.ps1`

`instalar.ps1` revisa todos los `.sql` del repositorio buscando construcciones de
SQL Server 2025 — entre ellas el tipo `json`, que en PostgreSQL es perfectamente
válido y que la propia función del SSO devuelve. Por eso esta carpeta está
**exenta** de esa verificación: la premisa de la regla es "esto corre en SQL
Server 2022", y estos scripts no corren ahí.
