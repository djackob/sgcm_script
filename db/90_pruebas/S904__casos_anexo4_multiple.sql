/*
===============================================================================
  SIGCM - S904 : Cuatro Anexos 3 listos para probar el Anexo 4 multiple
  Motor  : SQL Server 2022 (compat 160)
  Ambito : [DBSIGCM]   NO escribe en SIGA.

  ---------------------------------------------------------------------------
  QUE HACE
  ---------------------------------------------------------------------------
  Registra CUATRO solicitudes de modificacion del CMN, una por area usuaria
  real, y las deja en CMN_BORRADOR. De ahi en adelante el recorrido es manual,
  desde la pantalla, con los perfiles de /acceso-local: es lo que se quiere
  probar.

  No las hace avanzar ni una transicion. Registrar es lo tedioso —cada Anexo 3
  son 48 periodos por item y una decena de coordenadas presupuestales que tienen
  que existir en SIGA—; recorrer el flujo es lo interesante.

  ---------------------------------------------------------------------------
  DE DONDE SALEN ESTAS COORDENADAS
  ---------------------------------------------------------------------------
  De consultar SIGA_1750 con las tres condiciones que hacen que la inclusion sea
  VISIBLE en el aplicativo (ANALISIS_CMN.md, seccion 4ter):

      1. SIG_CUADRO_X_CENTRO.estado = '4'
      2. SIG_CUADRO_X_CENTRO.flag_da_aprob habilitado
      3. techo libre en esa meta y clasificador

  Las cuatro areas cumplen 1 y 3, que es lo que hace falta. La 2 —flag_da_aprob—
  SOLO la pide la pantalla "Demanda Adicional", que NO usamos: lo que registra el
  SIGCM se verifica en Modificacion de C.M.N. > Bienes, Servicios y Obras, y esa
  ruta no mira la bandera.

  Y aunque hiciera falta, no se habilitaria desde aqui: sobre SIGA_1750 solo
  escribe el flujo. Ver SIGA_APLICATIVO.md.

  ---------------------------------------------------------------------------
  POR QUE ESTAS CUATRO Y NO OTRAS
  ---------------------------------------------------------------------------
      centro         area   meta   clasificador       libre 2026   items
      01.07.05.03    OTI     15    2.3. 2  9. 1  1     123 994       18
      01.07.05.01    UDS     11    2.3. 2  5. 1 99     360 731       36
      01.07.05.02    US      14    2.3. 2  9. 1  1     102 999      192
      01.07.04       ORH     18    2.3. 2  7. 3  1      68 700      147

  Son las de cuadro pequeno con holgura: en un centro con 4 000 lineas no se
  distingue la que acaba de registrarse. Los grandes (SEI 01.02.01, con doce
  millones libres) sirven para probar el techo, no para mirar la pantalla.

  Las cantidades van de setiembre a diciembre a proposito: lo que estas areas ya
  tienen cargado esta en meses anteriores, asi que la linea nueva salta a la
  vista. Y solo en el ano base: si la inclusion suma cero a los anos 1 a 3, no
  puede empeorar su techo, y varios de esos techos ya vienen sobregirados de
  antes.

  Idempotente: si ya existen las cuatro solicitudes de este script, no las
  duplica. Para rehacerlas desde cero, ejecutar antes la seccion de limpieza.
===============================================================================
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @r TABLE (j nvarchar(max));
DECLARE @j nvarchar(max), @p nvarchar(max);
DECLARE @AnoEje int = 2026, @SecEjec int = 1750;

/* -------------------------------------------------------------------------- */
/* Los cuatro casos                                                            */
/* -------------------------------------------------------------------------- */

DECLARE @Caso TABLE (
    n              int IDENTITY(1,1),
    Area           varchar(10),
    Unidad         varchar(30),
    Cuenta         varchar(120),
    CentroCosto    varchar(15),
    SecFunc        int,            /* meta */
    Clasificador   varchar(20),
    TipoTarea      varchar(1),
    NivelTarea     varchar(1),
    CodigoTarea    int,
    GrupoBien      varchar(2),
    ClaseBien      varchar(2),
    FamiliaBien    varchar(4),
    ItemBien       varchar(4),
    Descripcion    varchar(120),
    PrecioUnitario decimal(16,6),
    CantMes        int,            /* por cada uno de los cuatro meses */
    Sustento       nvarchar(400)
);

INSERT INTO @Caso (Area, Unidad, Cuenta, CentroCosto, SecFunc, Clasificador,
                   TipoTarea, NivelTarea, CodigoTarea,
                   GrupoBien, ClaseBien, FamiliaBien, ItemBien, Descripcion,
                   PrecioUnitario, CantMes, Sustento)
VALUES
 ('OTI', 'UO-OTI', 'prueba.oti.esp', '01.07.05.03', 15, '2.3. 2  9. 1  1',
  '1','C',104, '17','01','0003','2399', 'SERVICIO DE SOPORTE TECNICO DE SISTEMA',
  500.00, 3,
  N'Se requiere soporte tecnico especializado para los sistemas de informacion institucionales durante el ultimo cuatrimestre, no previsto en la programacion inicial.'),

 ('UDS', 'UO-UDS', 'prueba.uds.esp', '01.07.05.01', 11, '2.3. 2  5. 1 99',
  '1','C',106, '17','01','0003','0097', 'SERVICIO DE DESARROLLO DE SOFTWARE',
  800.00, 3,
  N'Desarrollo de los modulos pendientes del sistema de gestion, cuya necesidad se identifico despues de aprobado el cuadro multianual.'),

 ('US',  'UO-US',  'prueba.us.esp',  '01.07.05.02', 14, '2.3. 2  9. 1  1',
  '1','C',107, '60','20','0001','0166', 'MANTENIMIENTO PREVENTIVO DE COMPUTADORAS',
  250.00, 5,
  N'Mantenimiento preventivo del parque de computadoras antes del cierre del ejercicio, para asegurar la continuidad operativa.'),

 ('ORH', 'UO-ORH', 'prueba.orh.esp', '01.07.04',    18, '2.3. 2  7. 3  1',
  '1','C',234, '35','20','0001','0194', 'CAPACITACION EN GESTION DE RECURSOS HUMANOS',
  450.00, 2,
  N'Capacitacion del personal de la oficina en el sistema administrativo de gestion de recursos humanos, requerida por la actualizacion normativa.');

/* -------------------------------------------------------------------------- */
/* Registro                                                                    */
/* -------------------------------------------------------------------------- */

DECLARE @n int = 1, @tot int = (SELECT COUNT(*) FROM @Caso);
DECLARE @Area varchar(10), @Unidad varchar(30), @Cuenta varchar(120),
        @CentroCosto varchar(15), @SecFunc int, @Clasificador varchar(20),
        @TipoTarea varchar(1), @NivelTarea varchar(1), @CodigoTarea int,
        @GrupoBien varchar(2), @ClaseBien varchar(2), @FamiliaBien varchar(4),
        @ItemBien varchar(4), @Descripcion varchar(120),
        @Precio decimal(16,6), @CantMes int, @Sustento nvarchar(400);
DECLARE @Actor nvarchar(400);
DECLARE @creadas int = 0, @existentes int = 0, @errores int = 0;

PRINT '===========================================================';
PRINT ' S904 - Casos de prueba para el Anexo 4 multiple';
PRINT '===========================================================';

WHILE @n <= @tot
BEGIN
    SELECT @Area = Area, @Unidad = Unidad, @Cuenta = Cuenta,
           @CentroCosto = CentroCosto, @SecFunc = SecFunc, @Clasificador = Clasificador,
           @TipoTarea = TipoTarea, @NivelTarea = NivelTarea, @CodigoTarea = CodigoTarea,
           @GrupoBien = GrupoBien, @ClaseBien = ClaseBien,
           @FamiliaBien = FamiliaBien, @ItemBien = ItemBien, @Descripcion = Descripcion,
           @Precio = PrecioUnitario, @CantMes = CantMes, @Sustento = Sustento
      FROM @Caso WHERE n = @n;

    /* Idempotencia: se reconoce por el sustento, que es unico por caso. */
    IF EXISTS (SELECT 1 FROM cmn.Solicitud
                WHERE CentroCosto = @CentroCosto AND AnoEje = @AnoEje
                  AND Activo = 1 AND Sustento = @Sustento)
    BEGIN
        PRINT '  [YA EXISTE] ' + @Area + ' (' + @CentroCosto + ')';
        SET @existentes = @existentes + 1;
        SET @n = @n + 1;
        CONTINUE;
    END

    SET @Actor = N'"Actor":{"Usuario":"' + @Cuenta
               + N'","Rol":"AREA_ESPECIALISTA","Unidad":"' + @Unidad
               + N'","Equipo":"S904","Programa":"S904"}';

    SET @p = N'{' + @Actor + N',
      "Solicitud": { "AnoEje": ' + CONVERT(varchar(4), @AnoEje)
        + N', "SecEjec": ' + CONVERT(varchar(10), @SecEjec)
        + N', "CentroCosto": "' + @CentroCosto + N'",
                     "TipoOperacion": "MODIFICACION",
                     "Sustento": "' + REPLACE(@Sustento, '"', '\"') + N'",
                     "TipoInclusion": "ORDINARIA" },
      "Items": [ { "TipoMovimiento": "INCLUSION",
                   "TipoTarea": "' + @TipoTarea + N'", "NivelTarea": "' + @NivelTarea + N'",
                   "CodigoTarea": ' + CONVERT(varchar(10), @CodigoTarea)
        + N', "SecFunc": ' + CONVERT(varchar(10), @SecFunc) + N',
                   "Origen": "1", "FuenteFinanc": "00",
                   "Clasificador": "' + @Clasificador + N'",
                   "TipoRecurso": "1", "TipoPpto": 1, "TipoUso": "C",
                   "TipoBien": "S", "GrupoBien": "' + @GrupoBien + N'",
                   "ClaseBien": "' + @ClaseBien + N'",
                   "FamiliaBien": "' + @FamiliaBien + N'", "ItemBien": "' + @ItemBien + N'",
                   "DescripcionServicio": "' + @Descripcion + N'",
                   "UnidadMedida": 107,
                   "PrecioUnitario": ' + CONVERT(varchar(20), @Precio) + N',
                   "Periodos": [ {"AnoOffset":0,"Mes":9, "Cantidad":' + CONVERT(varchar(10), @CantMes) + N'},
                                 {"AnoOffset":0,"Mes":10,"Cantidad":' + CONVERT(varchar(10), @CantMes) + N'},
                                 {"AnoOffset":0,"Mes":11,"Cantidad":' + CONVERT(varchar(10), @CantMes) + N'},
                                 {"AnoOffset":0,"Mes":12,"Cantidad":' + CONVERT(varchar(10), @CantMes) + N'} ] } ] }';

    DELETE FROM @r; INSERT INTO @r EXEC cmn.paRegistrarSolicitud @p;
    SELECT @j = j FROM @r;

    IF JSON_VALUE(@j, '$.estado') <> '1'
    BEGIN
        PRINT '  [FALLO] ' + @Area + ' (' + @CentroCosto + '): '
            + ISNULL(JSON_VALUE(@j, '$.mensaje'), @j);
        SET @errores = @errores + 1;
    END
    ELSE
    BEGIN
        PRINT '  [OK] ' + @Area + ' (' + @CentroCosto + ') -> '
            + JSON_VALUE(@j, '$.Codigo')
            + '   S/ ' + CONVERT(varchar(20), CONVERT(decimal(18,2), @Precio * @CantMes * 4));
        SET @creadas = @creadas + 1;
    END

    SET @n = @n + 1;
END

/* -------------------------------------------------------------------------- */
/* Resumen                                                                     */
/* -------------------------------------------------------------------------- */

PRINT '';
PRINT '  Creadas: ' + CONVERT(varchar(10), @creadas)
    + '   Ya existian: ' + CONVERT(varchar(10), @existentes)
    + '   Con error: ' + CONVERT(varchar(10), @errores);

SELECT bloque = 'LISTO PARA PROBAR',
       Area        = u.Sigla,
       Expediente  = s.Codigo,
       s.CentroCosto,
       Estado      = e.CodigoEstado,
       Items       = (SELECT COUNT(*) FROM cmn.SolicitudItem i
                       WHERE i.IdSolicitud = s.IdSolicitud AND i.Activo = 1),
       MontoTotal  = (SELECT ISNULL(SUM(pp.Monto),0)
                        FROM cmn.SolicitudItem i
                        JOIN cmn.SolicitudItemPeriodo pp ON pp.IdSolicitudItem = i.IdSolicitudItem
                       WHERE i.IdSolicitud = s.IdSolicitud),
       IngresarComo = (SELECT TOP 1 us.Cuenta FROM sigcm.UsuarioRol ur
                         JOIN sigcm.Usuario us ON us.IdUsuario = ur.IdUsuario
                        WHERE ur.IdUnidad = u.IdUnidad AND ur.CodigoRol = 'AREA_ESPECIALISTA')
  FROM cmn.Solicitud AS s
  JOIN sigcm.Expediente AS e ON e.IdExpediente = s.IdExpediente
  JOIN sigcm.Unidad AS u ON u.IdUnidad = e.IdUnidadOrigen
 WHERE s.ProgramaCreacionAuditoria = 'S904' AND s.Activo = 1 AND e.Anulado = 0
 ORDER BY u.Sigla;

PRINT '';
PRINT '  RECORRIDO EN LA PANTALLA, con /acceso-local:';
PRINT '   1. Especialista del area  -> Generar Anexo 3';
PRINT '   2. Jefe del area          -> Firmar Anexo 3 y Enviar a la OA';
PRINT '   3. prueba.oa              -> Derivar al Jefe de Abastecimiento';
PRINT '   4. prueba.abast.jefe      -> Derivar al Coordinador';
PRINT '   5. prueba.abastecim       -> Derivar al Especialista';
PRINT '   6. prueba.abast.esp       -> Conformar y firmar el Anexo 3';
PRINT '   7. prueba.abastecim       -> Firmar Anexo 3';
PRINT '   8. prueba.abast.jefe      -> Firmar Anexo 3   <<< SE REGISTRA EN SIGA';
PRINT '   9. Repetir 1 a 8 con las otras areas';
PRINT '  10. prueba.abast.esp       -> marcar las cuatro y "Generar Anexo 4 multiple"';
PRINT '  11. prueba.abastecim       -> Firmar Anexo 4';
PRINT '  12. prueba.abast.jefe      -> Firmar Anexo 4  <<< SE APRUEBA EN SIGA';
PRINT '';
PRINT '  ORDINARIA frente a EXTRAORDINARIA: lo declara el AREA USUARIA al';
PRINT '  registrar el Anexo 3, no Abastecimiento. Estos cuatro casos quedan';
PRINT '  ORDINARIOS, asi que su Anexo 4 solo se genera un viernes; para probar';
PRINT '  cualquier dia, registre uno a mano marcandolo EXTRAORDINARIA y';
PRINT '  justificando la urgencia.';
PRINT '';
PRINT '  Para VER el registro en el aplicativo SIGA:';
PRINT '    Logistica > Programacion > Modificacion de C.M.N. > Bienes, Servicios y Obras';
PRINT '    Ano 2026, el area usuaria, Tipo = Servicio.';
PRINT '  Y el estado del tramite en > Solicitud de Modificacion:';
PRINT '    V.B. Jefe = Anexo 3 firmado     Aprobado = Anexo 4 firmado';
GO
