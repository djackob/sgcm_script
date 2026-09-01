/*
===============================================================================
  SIGCM - F009 : Panel de mantenimiento del SSO
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]
  Bloque de errores: 51700-51749

  QUE RESUELVE
  ------------
  Hoy, cuando alguien no puede entrar al sistema, la respuesta existe pero solo
  se alcanza con sqlcmd contra un servidor al que no todos tienen acceso: esta
  en Descartes de sigcm.SincronizacionSso y en las ternas de sigcm.UsuarioRol.
  Eso convierte una pregunta de treinta segundos -"por que Fulano no entra"- en
  una investigacion.

  Este procedimiento arma, de una sola vez, lo que esa pantalla necesita:

    Resumen         cuanta gente hay, cuantas ternas, cuando fue la ultima
                    sincronizacion y con que resultado.
    Padron          las ternas vigentes: quien, con que rol, en que unidad.
    Perfiles        el mapeo cod_perfil -> rol, con cuanta gente usa cada uno.
    Arbol           las aristas de derivacion, con cuantos puestos ocupados
                    alcanza cada una.
    Unidades        las unidades con centro de costo, si tramitan o originan.
    Sincronizaciones las ultimas corridas, con sus altas, bajas y DESCARTES.

  POR QUE TODO EN UN SOLO PAYLOAD Y NO UNA RUTINA POR SECCION
  Porque es un tablero, no seis pantallas: se mira entero o no se mira. Son
  veinte ternas y catorce perfiles; partirlo en seis llamadas costaria seis
  viajes para pintar una sola vista. Si alguna seccion crece hasta necesitar
  paginado, se le da su propia rutina ese dia.

  SOLO LECTURA. Aqui no se edita nada: la configuracion sigue viniendo de la
  semilla (S005, S006, S007), que es la que viaja a produccion versionada. La
  unica accion del panel es disparar la sincronizacion, y esa vive en F008.

  Idempotente.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

/*
  Entrada: { "Actor": { ... } }
  Salida : { "estado":1, "Resumen":{...}, "Padron":[...], "Perfiles":[...],
             "Arbol":[...], "Unidades":[...], "Sincronizaciones":[...] }

  SOLO ADMIN_SISTEMA. El padron es la nomina de quien accede al sistema con que
  autoridad; no es informacion de trabajo diario. El control esta aqui y no solo
  en el menu del frontend: un menu que no muestra la opcion no impide llamar al
  endpoint.
*/
CREATE OR ALTER PROCEDURE sigcm.paObtenerPanelSso
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF @parametro IS NULL OR ISJSON(@parametro) <> 1
            THROW 51700, 'JSON incorrecto.', 1;

        DECLARE @IdUsuario uniqueidentifier, @Cuenta varchar(120),
                @NombreCompleto varchar(250), @Cargo varchar(180),
                @CodigoRol varchar(40), @IdUnidad uniqueidentifier,
                @CentroCosto varchar(15), @EsTitular bit,
                @Ip varchar(45), @Equipo varchar(50), @Programa varchar(50),
                @CorrelacionId uniqueidentifier;

        EXEC sigcm.paResolverActor @parametro,
             @IdUsuario OUTPUT, @Cuenta OUTPUT, @NombreCompleto OUTPUT, @Cargo OUTPUT,
             @CodigoRol OUTPUT, @IdUnidad OUTPUT, @CentroCosto OUTPUT, @EsTitular OUTPUT,
             @Ip OUTPUT, @Equipo OUTPUT, @Programa OUTPUT, @CorrelacionId OUTPUT;

        IF @CodigoRol <> 'ADMIN_SISTEMA'
            THROW 51701, 'NO_AUTORIZADO: el panel del SSO es del administrador del sistema.', 1;

        DECLARE @Hoy date = CONVERT(date, GETDATE());

        /* ---- Padron ---------------------------------------------------- */
        DECLARE @Padron nvarchar(max) = (
            SELECT Cuenta         = u.Cuenta,
                   IdUsuarioSso   = u.IdUsuarioSso,
                   Documento      = u.DocumentoIdentidad,
                   NombreCompleto = CONCAT_WS(' ', u.Nombres, u.Apellidos),
                   Cargo          = u.Cargo,
                   Correo         = u.Correo,
                   CodigoRol      = ur.CodigoRol,
                   Rol            = r.Nombre,
                   CodigoUnidad   = n.Codigo,
                   Unidad         = n.Nombre,
                   Sigla          = n.Sigla,
                   CentroCosto    = n.CentroCostoSiga,
                   /* De donde vino esta cuenta. Distinguirlo importa: la
                      reconciliacion solo gobierna a las del SSO. */
                   Origen         = CASE WHEN u.IdUsuarioSso IS NULL THEN 'LOCAL' ELSE 'SSO' END,
                   Desde          = CONVERT(varchar(10), ur.VigenteDesde, 23)
              FROM sigcm.UsuarioRol AS ur
              JOIN sigcm.Usuario    AS u ON u.IdUsuario = ur.IdUsuario
              JOIN sigcm.Unidad     AS n ON n.IdUnidad  = ur.IdUnidad
              JOIN sigcm.Rol        AS r ON r.CodigoRol = ur.CodigoRol
             WHERE ur.Activo = 1 AND u.Activo = 1 AND n.Activo = 1
               AND ur.VigenteDesde <= @Hoy
               AND (ur.VigenteHasta IS NULL OR ur.VigenteHasta >= @Hoy)
             ORDER BY n.Nombre, r.Nombre, u.Cuenta
               FOR JSON PATH);

        /* ---- Perfiles del SSO ------------------------------------------ */
        /*
          Cuanta gente usa cada mapeo es la columna que dice si una fila sigue
          viva. Un perfil mapeado que nadie ejerce puede ser correcto -todavia
          no le asignaron el acceso a nadie- o puede ser un resto de una
          reorganizacion; verlo es el primer paso para saberlo.
        */
        DECLARE @Perfiles nvarchar(max) = (
            SELECT CodigoPerfilSso = m.CodigoPerfilSso,
                   NombreSso       = m.NombreSso,
                   CodigoRol       = m.CodigoRol,
                   Rol             = r.Nombre,
                   Observacion     = m.Observacion,
                   Activo          = m.Activo,
                   Personas = (SELECT COUNT(DISTINCT ur.IdUsuario)
                                 FROM sigcm.UsuarioRol AS ur
                                 JOIN sigcm.Usuario AS u2 ON u2.IdUsuario = ur.IdUsuario
                                WHERE ur.CodigoRol = m.CodigoRol
                                  AND u2.IdUsuarioSso IS NOT NULL
                                  AND ur.Activo = 1 AND ur.VigenteHasta IS NULL)
              FROM sigcm.PerfilSso AS m
              JOIN sigcm.Rol       AS r ON r.CodigoRol = m.CodigoRol
             ORDER BY m.CodigoPerfilSso
               FOR JSON PATH);

        /* ---- Arbol de derivacion --------------------------------------- */
        /*
          PuestosOcupados dice si la arista sirve para algo hoy. Una arista con
          cero no esta mal declarada: es un escalon que existe en el flujo y que
          nadie ocupa -exactamente el caso del coordinador de area usuaria, que
          el SSO todavia no declara-. Verlo en la pantalla evita que alguien lo
          descubra recien cuando un jefe no encuentra a quien derivar.
        */
        DECLARE @Arbol nvarchar(max) = (
            SELECT CodigoModulo     = d.CodigoModulo,
                   Modulo           = mo.Nombre,
                   CodigoRolOrigen  = d.CodigoRolOrigen,
                   RolOrigen        = ro.Nombre,
                   CodigoRolDestino = d.CodigoRolDestino,
                   RolDestino       = rd.Nombre,
                   Alcance          = d.Alcance,
                   Orden            = d.Orden,
                   Descripcion      = d.Descripcion,
                   Activo           = d.Activo,
                   PuestosOcupados = (SELECT COUNT(DISTINCT ur.IdUnidad)
                                        FROM sigcm.UsuarioRol AS ur
                                       WHERE ur.CodigoRol = d.CodigoRolDestino
                                         AND ur.Activo = 1 AND ur.VigenteHasta IS NULL),
                   /*
                     Y de esos, cuantos los sostiene gente REAL del SSO.
                     La distincion no es cosmetica: en un entorno con los usuarios
                     ficticios de S900 el escalon del coordinador de area usuaria
                     aparece ocupado por cinco cuentas locales, y el hueco que
                     este panel existe para mostrar queda tapado. En produccion,
                     sin datos de prueba, PuestosOcupados y PuestosSso coinciden.
                   */
                   PuestosSso = (SELECT COUNT(DISTINCT ur.IdUnidad)
                                   FROM sigcm.UsuarioRol AS ur
                                   JOIN sigcm.Usuario AS us ON us.IdUsuario = ur.IdUsuario
                                  WHERE ur.CodigoRol = d.CodigoRolDestino
                                    AND us.IdUsuarioSso IS NOT NULL
                                    AND ur.Activo = 1 AND ur.VigenteHasta IS NULL)
              FROM sigcm.RolDerivacion AS d
              JOIN sigcm.Modulo AS mo ON mo.CodigoModulo    = d.CodigoModulo
              JOIN sigcm.Rol    AS ro ON ro.CodigoRol       = d.CodigoRolOrigen
              JOIN sigcm.Rol    AS rd ON rd.CodigoRol       = d.CodigoRolDestino
             ORDER BY d.CodigoModulo, ro.Nombre, d.Orden
               FOR JSON PATH);

        /* ---- Unidades --------------------------------------------------- */
        DECLARE @Unidades nvarchar(max) = (
            SELECT Codigo        = n.Codigo,
                   Nombre        = n.Nombre,
                   Sigla         = n.Sigla,
                   CentroCosto   = n.CentroCostoSiga,
                   IdDependenciaSso = n.IdDependenciaSso,
                   UnidadPadre   = p.Sigla,
                   EsAreaUsuaria = n.EsAreaUsuaria,
                   Tramitadora   = CONVERT(bit, CASE WHEN t.CentroCosto IS NULL THEN 0 ELSE 1 END),
                   Personas = (SELECT COUNT(DISTINCT ur.IdUsuario)
                                 FROM sigcm.UsuarioRol AS ur
                                WHERE ur.IdUnidad = n.IdUnidad
                                  AND ur.Activo = 1 AND ur.VigenteHasta IS NULL)
              FROM sigcm.Unidad AS n
              LEFT JOIN sigcm.Unidad AS p ON p.IdUnidad = n.IdUnidadPadre
              LEFT JOIN sigcm.UnidadTramitadora AS t
                     ON t.CentroCosto = n.CentroCostoSiga AND t.Activo = 1
             WHERE n.Activo = 1
             ORDER BY n.CentroCostoSiga, n.Nombre
               FOR JSON PATH);

        /* ---- Ultimas sincronizaciones ----------------------------------- */
        /*
          Descartes viaja tal cual, que es lo que responde la pregunta "por que
          Fulano no entra": trae la cuenta, el cod_perfil, el centro de costo y
          el motivo exacto.
        */
        DECLARE @Sinc nvarchar(max) = (
            SELECT TOP (20)
                   Fecha            = CONVERT(varchar(19), s.Fecha, 120),
                   Disparador       = s.Disparador,
                   CuentaDisparo    = s.CuentaDisparo,
                   PadronRecibido   = s.PadronRecibido,
                   UnidadesAlta     = s.UnidadesAlta,
                   UsuariosAlta     = s.UsuariosAlta,
                   AsignacionesAlta = s.AsignacionesAlta,
                   AsignacionesBaja = s.AsignacionesBaja,
                   Descartes        = JSON_QUERY(COALESCE(s.Descartes, '[]'))
              FROM sigcm.SincronizacionSso AS s
             ORDER BY s.IdSincronizacion DESC
               FOR JSON PATH);

        /* ---- Resumen ----------------------------------------------------- */
        DECLARE @UltimaFecha varchar(19), @UltimosDescartes int = 0;

        SELECT TOP (1) @UltimaFecha = CONVERT(varchar(19), s.Fecha, 120),
               @UltimosDescartes = (SELECT COUNT(*) FROM OPENJSON(COALESCE(s.Descartes, '[]')))
          FROM sigcm.SincronizacionSso AS s
         ORDER BY s.IdSincronizacion DESC;

        SELECT @resultado = (
            SELECT 1 AS estado,
                   'OK' AS mensaje,
                   Resumen = JSON_QUERY((
                       SELECT PersonasSso = (SELECT COUNT(*) FROM sigcm.Usuario
                                              WHERE IdUsuarioSso IS NOT NULL AND Activo = 1),
                              PersonasLocales = (SELECT COUNT(*) FROM sigcm.Usuario
                                                  WHERE IdUsuarioSso IS NULL AND Activo = 1),
                              TernasVigentes = (SELECT COUNT(*) FROM sigcm.UsuarioRol
                                                 WHERE Activo = 1 AND VigenteHasta IS NULL),
                              Unidades = (SELECT COUNT(*) FROM sigcm.Unidad WHERE Activo = 1),
                              PerfilesMapeados = (SELECT COUNT(*) FROM sigcm.PerfilSso WHERE Activo = 1),
                              AristasArbol = (SELECT COUNT(*) FROM sigcm.RolDerivacion WHERE Activo = 1),
                              UltimaSincronizacion = @UltimaFecha,
                              DescartesUltima = @UltimosDescartes
                       FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)),
                   Padron           = JSON_QUERY(COALESCE(@Padron,   '[]')),
                   Perfiles         = JSON_QUERY(COALESCE(@Perfiles, '[]')),
                   Arbol            = JSON_QUERY(COALESCE(@Arbol,    '[]')),
                   Unidades         = JSON_QUERY(COALESCE(@Unidades, '[]')),
                   Sincronizaciones = JSON_QUERY(COALESCE(@Sinc,     '[]'))
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT @resultado = (
            SELECT 0 AS estado, ERROR_MESSAGE() AS mensaje, ERROR_NUMBER() AS codigo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @resultado;
    END CATCH
END
GO

PRINT 'F009 aplicada: panel de mantenimiento del SSO.';
GO
