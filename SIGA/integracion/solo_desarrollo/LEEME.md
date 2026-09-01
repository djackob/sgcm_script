# Solo desarrollo local

Estos scripts **modifican usuarios, menús, privilegios o claves de SIGA**.
Sirven para homologar en la copia local (`GLUNA`, `IRIVERA`, `HBOJORQUEZ`,
`SIGAMEF`). **No forman parte de `instalar.ps1` y no se despliegan a
producción.**

En producción los usuarios de SIGA los administra el ANIN / el MEF. El SIGCM
solo instala procedimientos `usp_ext_*` (objetos de integración), nunca filas
de `USERS`, `USERS_MENU`, `SEG_ROL_*` ni `SIG_PERSONAL`.

## Cómo se ejecutan (solo en esta máquina)

Hace falta la variable `entorno=DESARROLLO`. Sin ella `sqlcmd` aborta y no
toca la base:

```powershell
sqlcmd -S localhost -d SIGA_1750 -E -b -v entorno="DESARROLLO" `
       -i clonar_perfil_sigamef_a_gluna.sql
```

| Archivo | Qué toca |
|---|---|
| `clonar_perfil_sigamef_a_gluna.sql` | Menú y rol de GLUNA desde SIGAMEF |
| `reparar_menu_gluna_ejecutora.sql` | Menú de GLUNA en ejecutora 1750 |
| `elevar_privilegios_gluna_pedidos.sql` | Privilegios de GLUNA en pedidos |
| `otorgar_aprobacion_servicio_gluna.sql` | Autorización de servicios para GLUNA |
| `resetear_claves_homologacion_gluna.sql` | Claves de usuarios de la copia local |
| `ajustar_perfil_hbojorquez_logistica.sql` | Perfil logístico de HBOJORQUEZ |
| `habilitar_autorizacion_hbojorquez.sql` | Opción 04 y empleado de HBOJORQUEZ |
| `habilitar_tipo_servicio_irivera_autorizacion.sql` | Tipo Servicio en opción 04 para IRIVERA |
| `homologar_visibilidad_autorizacion_001067_gluna.sql` | Visibilidad del pedido 001067 para GLUNA |
