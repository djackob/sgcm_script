# Copiar este archivo a parametros.ps1 (junto a instalar_calidad.ps1) y completar.
# NO ponga contraseñas aqui. El instalador las pide por teclado.

$ParametrosCalidad = @{
    Servidor  = "tcp:SERVIDOR_CALIDAD,1433"   # host, instancia o host,puerto
    Usuario   = "usuario_sql_instalacion"     # vacio = autenticacion de Windows
    Base      = "DBSIGCM"
    BaseSiga  = "SIGA_XXXX"                   # nombre REAL de la base SIGA en calidad
    LoginApp  = "w_sgcmenores"                # login SQL o ANIN\cuenta del pool IIS
    Confiar   = $true                         # $true si sqlcmd 18+ (certificado)
}

# SSO institucional (PostgreSQL). Solo para aplicar_sso.ps1
$ParametrosSso = @{
    Host     = "host-sso-calidad"
    Puerto   = 5432
    Base     = "saa_"
    Usuario  = "usuario_sso"
    DniAdmin = "44687266"                     # persona que tendra P0001 en S0073
    CodDependencia = "D0001"                  # dependencia para PE099 (S02)
}
