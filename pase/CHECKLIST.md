# Checklist para el ejecutor (calidad)

Tres archivos: `01_SIGA.sql`, `02_DBSIGCM.sql`, `03_SSO.sql`.

## Antes

- [ ] SQL Server 2022, `sqlcmd` en el PATH
- [ ] Base SIGA ya restaurada (anotar el **nombre real**)
- [ ] Login de la aplicación SIGCM ya creado por el DBA
- [ ] Copiar `parametros.ejemplo.ps1` → `parametros.ps1`
- [ ] **No** poner contraseñas en `parametros.ps1`

## Diagnóstico

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\instalar_calidad.ps1 -SoloDiagnostico
```

- [ ] Aparece el motor 2022 y el nombre de la base SIGA

## Instalación SQL Server (orden fijo)

```powershell
.\instalar_calidad.ps1
```

- [ ] `01_SIGA.sql` (no recrea SIGA)
- [ ] `02_DBSIGCM.sql` (no borra DBSIGCM; C900 sin `[ERROR]`)

## SSO (PostgreSQL, opcional)

```powershell
.\aplicar_sso.ps1
```

- [ ] `03_SSO.sql` con el DNI del administrador `S0073`

## Prohibido

- Borrar o recrear SIGA
- `DROP DATABASE` / recrear DBSIGCM
- Publicar API/front desde este paquete (no están incluidos)
