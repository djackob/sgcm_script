# Continuar el trabajo desde una maquina de la red del ANIN

Este documento es un traspaso. Lo escribio la sesion que trabajo desde el equipo
local el 2026-08-26, para que otra sesion pueda seguir desde una maquina de la
red del ANIN (por escritorio remoto) sin volver a averiguar nada.

Es autocontenido: no hace falta el historial de la conversacion anterior.

---

## El objetivo

Dejar el SIGCM funcionando en el **servidor de desarrollo del ANIN**,
`192.168.40.75`, base `DBSIGCM`, contra `SIGA_1750`.

## Por que se trabaja desde una maquina remota y no desde el equipo local

Porque la VPN no llega. Medido el 2026-08-26 con GlobalProtect conectado y
funcionando (tunel arriba, DNS interno resolviendo):

| Destino | Puerto | Resultado |
|---|---|---|
| `192.168.40.75` (SQL desa) | 1433 | bloqueado |
| `192.168.40.75` | 3389 / 445 | bloqueado |
| `192.168.40.71` | 3389 | bloqueado |
| `192.168.40.1` | 443 | bloqueado |
| `192.168.20.13` (DNS interno) | 53 | abierto |
| `172.16.3.66` (escritorio remoto) | 3389 | abierto |
| `172.16.3.66` | 445 / 135 / 5985 | bloqueado |

O sea: la subred de servidores `192.168.40.0/24` esta cerrada entera para el
perfil externo, y a los escritorios solo pasa RDP. **No es problema de Navicat,
del driver ODBC ni de la red del celular** — el error tipico
(`Named Pipes Provider ... 64`) enganna, porque el driver intenta TCP, no pasa, y
cae a named pipes antes de rendirse. No pierdas tiempo depurando ese lado.

Hay un pedido de regla de firewall en curso (por User-ID, no por IP de tunel,
porque GlobalProtect asigna la IP desde un pool y cambia entre reconexiones).
Mientras no salga, se trabaja desde la maquina remota.

---

## Lo que ya esta probado y no hay que repetir

Todo esto se corrio en el equipo local contra `localhost\SQLSERVER25`:

- `.\instalar.ps1 -SoloVerificar` → **151 archivos, 0 usos de construcciones de
  SQL Server 2025**. La serie es apta para desarrollo, que es 2022.
- Serie completa en modo actualizacion → **31 scripts aplicados, 0 fallidos**.
- `C000C__permisos_instalacion.sql` → corre limpio.
- `desa.ps1 -SoloDiagnostico` → pasa las cuatro etapas.

Lo unico que no se pudo probar desde el equipo local es la conexion real a
`192.168.40.75`. **Eso es exactamente lo que toca hacer aqui.**

---

## Los pasos, en orden

### 1. Verificar que esta maquina si llega al servidor

```powershell
Test-NetConnection 192.168.40.75 -Port 1433
```

Si da `False`, esta maquina tampoco llega. Antes de rendirse, probar desde el
segundo salto (`192.168.40.71`), que esta en la misma subred del servidor.

### 2. Revisar el codigo fuente

```powershell
.\instalar.ps1 -SoloVerificar
```

Debe decir `[OK] Ningun script usa construcciones de SQL Server 2025`. No se
conecta a ninguna base.

### 3. Diagnosticar sin tocar nada

```powershell
.\desa.ps1 -SoloDiagnostico
```

Detecta la version de `sqlcmd`, prueba el 1433, pide la contrasena una sola vez
y corre `C000C`, que es solo lectura y dice si la cuenta puede instalar.

**Este paso es el que importa.** El archivo de credenciales de desarrollo dice
*"Permiso: Lectura (verificar si es de escritura tambien)"*, y con solo lectura
la serie muere en `C001`, que necesita `CREATE DATABASE`. `C000C` lo responde
antes de empezar.

Si sale que la cuenta no puede crear la base, hay que pedirle al DBA `dbcreator`
o que cree `DBSIGCM` vacia y de `db_owner` sobre ella. No insistir por otro lado.

### 4. Instalar

```powershell
.\desa.ps1
```

Repite el diagnostico, muestra que va a hacer y pide confirmacion antes de
escribir. Modo actualizacion: respeta los datos existentes.

### 5. Guardar la bitacora

Queda en `_bitacora\`. Copiarla a `\\tsclient\D\...` para poder revisarla desde
el equipo local.

---

## Reglas que no se negocian

- **Nunca `-Recrear` contra `192.168.40.75`.** Borra la base compartida entera:
  expedientes, solicitudes, documentos, cola de integracion. Se pierde el trabajo
  de las dos personas del equipo y hay que rehacer las pruebas desde cero. Si
  alguna vez hiciera falta, se acuerda antes con el otro desarrollador.
- **Nunca `UPDATE` ni `DELETE` a mano sobre `SIGA_1750`.** Sobre SIGA solo se
  escribe por el flujo del sistema. Si un caso quedo mal, se corrige el sistema y
  se rehace el caso.
- **`C002__acceso_lectura_siga.sql` no es parte de la serie, a proposito.**
  Concede permisos dentro de SIGA, que es base de otro dueno, y requiere
  autorizacion del propietario. Se ejecuta a mano donde corresponda.
- **Las credenciales no estan en el repo y no deben entrar.** Estan en archivos
  locales del equipo del usuario. Si hacen falta, se le piden a el.

---

## Que esperar del resultado

Instalar la serie **no** hace que el CMN se escriba en SIGA, y eso es por diseno
(ADR-003). Las operaciones se acumulan en `integracion.Operacion` y nadie las
vacia todavia. `W001` corre en **simulacion** por defecto: hace toda la
traduccion y deja en `ResponseJson` lo que habria mandado, sin tocar SIGA.

Para que se escriba de verdad hacen falta tres cosas, y la primera es un tramite,
no programacion: que el equipo de SIGA instale y autorice
`usp_ext_registrar_item_cmn` dentro de `SIGA_1750`. Hasta que eso pase, no hay
escritura posible en desarrollo ni en produccion. No es un bloqueo para el resto:
todo el flujo del CMN funciona igual.

El detalle completo esta en [instalar-en-desarrollo.md](instalar-en-desarrollo.md).

---

## Contexto del proyecto que conviene tener a mano

- El backend .NET es un puente sin logica: todo vive en funciones de base de
  datos con JSON de entrada y de salida.
- `DBSIGCM` va en nivel de compatibilidad **160**. Que SIGA este en 100 no obliga
  a nada; bajarla rompe `OPENJSON` y con el todo el contrato.
- Local es SQL Server 2025, desarrollo es 2022. La linea base del codigo es 2022,
  y el paso de verificacion existe para que nada de 2025 se cuele.
- Las entregas de `CAMBIOS_ANIN` vienen una version atras y en dialecto SQL 2008;
  ejecutarlas tal cual rompe la base. Hay que portarlas.

Los documentos de fondo son `CONTEXTO.md`, `ESTANDARES.md` y `LEEME.md` en la
raiz del repositorio.
