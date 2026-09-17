# SIGCM — Pase a calidad

Tres scripts SQL, uno por base. Quien los ejecuta es un usuario de ANIN.
Quien los envía no tiene acceso al servidor de calidad.

No incluye frontend, backend, contraseñas ni datos de prueba.

Fecha del paquete: **2026-09-17**.

| Archivo | Base | Efecto |
|---|---|---|
| `01_SIGA.sql` | SIGA (SQL Server) | Instala `usp_ext_*` y concede `EXECUTE`. **No recrea SIGA.** |
| `02_DBSIGCM.sql` | DBSIGCM (SQL Server) | Crea la base si falta y aplica el modelo. **No la borra.** |
| `03_SSO.sql` | SSO (PostgreSQL) | Perfiles del sistema `S0073`. Opcional. |

---

## 1. Qué debe existir ANTES

| Requisito | Notas |
|---|---|
| SQL Server **2022** | Misma línea base que desarrollo ANIN |
| Base **SIGA** ya restaurada | El nombre suele **no** ser `SIGA_1750` |
| `sqlcmd` en el PATH | O SSMS, ejecutando cada archivo a mano |
| Cuenta con `dbcreator` **o** `DBSIGCM` creada y `db_owner` | |
| Login de la aplicación SIGCM **ya creado** por el DBA | Estos scripts no crean logins ni manejan claves |
| Autorización del dueño de SIGA | `01_SIGA.sql` escribe procedimientos en SIGA; el final de `02_DBSIGCM.sql` concede SELECT |

**No aplicar** datos de prueba ni scripts de `solo_desarrollo`.

---

## 2. Cómo ejecutarlo (recomendado)

Copiar `parametros.ejemplo.ps1` a `parametros.ps1` y completar servidor, nombre
real de SIGA, `DBSIGCM` y login de la aplicación. **Sin contraseñas en el archivo.**

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\instalar_calidad.ps1 -SoloDiagnostico
.\instalar_calidad.ps1
```

Orden interno: primero `01_SIGA.sql`, después `02_DBSIGCM.sql`.

SSO (otra instancia, hace falta `psql`):

```powershell
.\aplicar_sso.ps1
```

---

## 3. Cómo ejecutarlo a mano (sqlcmd / SSMS)

Sustituir `SIGA_XXXX` por el nombre real. La contraseña no va en el comando si
usa autenticación de Windows (`-E`). Con usuario SQL, `sqlcmd` pide o usa
`SQLCMDPASSWORD`.

```text
sqlcmd -S "<servidor>" -d master -E -b -I -C ^
       -v bdSiga="SIGA_XXXX" -v loginApp="w_sgcmenores" ^
       -i 01_SIGA.sql

sqlcmd -S "<servidor>" -d master -E -b -I -C ^
       -v bdSiga="SIGA_XXXX" -v bdSigcm="DBSIGCM" -v loginApp="w_sgcmenores" ^
       -i 02_DBSIGCM.sql
```

PostgreSQL:

```text
psql -h <host> -p 5432 -U <usuario> -d saa_ ^
     -v dni=44687266 -v cod_dependencia=D0001 ^
     -f 03_SSO.sql
```

En SSMS: abrir cada `.sql`, en modo SQLCMD (`Consulta > SQLCMD`), cambiar los
`:setvar` del encabezado al nombre real de SIGA, y ejecutar. **Primero SIGA,
después DBSIGCM.**

---

## 4. Lo que este paquete NO instala

API y front van por otro canal, con configuración **del ambiente**:

- Cadena `cnx_sigcm` → instancia y `DBSIGCM` de calidad
- Front `config.json` → `apiUrl` de calidad
- `acceso_local` = `false` (SSO institucional)
- Firma digital: `firma.omitir_dispositivo` = `false` en calidad

---

## 5. Si algo falla

1. El instalador **aborta al primer error** (`sqlcmd -b`).
2. Los scripts son **idempotentes**: corregir y volver a ejecutar el mismo archivo.
3. El inventario al final de `02_DBSIGCM.sql` no debe listar `[ERROR]`.
4. Si las vistas `siga.*` fallan: falta el `GRANT SELECT` del final de `02_DBSIGCM.sql`
   o el nombre de SIGA no coincide.
5. Si CMN/cuadro/orden no escriben en SIGA: faltó `01_SIGA.sql`. Si el INSERT
   falla, el DBA debe dejar `usp_ext_*` como `EXECUTE AS OWNER`.

---

## 6. Qué no enviar

Contraseñas, `appsettings.json`, datos de prueba, volcado de SIGA.

Para regenerar los 3 `.sql` y el zip desde el repo:

```powershell
.\pase\empacar_pase.ps1
```
