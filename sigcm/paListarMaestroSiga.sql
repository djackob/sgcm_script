/*
  Base    : DBSIGCM
  Esquema : sigcm
  Objeto  : sigcm.paListarMaestroSiga
  Tipo    : SQL_STORED_PROCEDURE
  Extraido: 2026-08-18 11:59:35
*/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* ========================================================================== */
/* 5. sigcm.paListarMaestroSiga                                              */
/* ========================================================================== */

/*
  Punto unico de lectura de los maestros de SIGA para los formularios. Un solo
  procedimiento en vez de ocho: el frontend pide un maestro por nombre y recibe
  siempre la misma forma de respuesta.

  LAS TRES MEDIDAS DE CONVIVENCIA CON SIGA ESTAN AQUI, y se aplican aunque en la
  copia local no cambien nada. En produccion si:

    LOCK_TIMEOUT 5000      antes que colgar la pantalla del usuario esperando un
                           bloqueo de SIGA, se falla rapido y con mensaje claro.
    DEADLOCK_PRIORITY LOW  ante un interbloqueo entre SIGCM y SIGA, la victima
                           somos nosotros. Nunca abortamos una transaccion de SIGA.
    OPTION (MAXDOP 1)      no robamos hilos paralelos del pool que SIGA necesita.
                           Son lecturas de pocas paginas; no ganan nada con
                           paralelismo.

  Toda consulta va filtrada por AnoEje + SecEjec, y por CentroCosto cuando el
  maestro lo admite. Consultar SIGA sin filtro esta prohibido.
*/
CREATE   PROCEDURE sigcm.paListarMaestroSiga
    @parametro nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET LOCK_TIMEOUT 5000;
    SET DEADLOCK_PRIORITY LOW;

    DECLARE @resultado nvarchar(max);

    BEGIN TRY
        IF sigcm.fnEsJson(@parametro) <> 1
            RAISERROR('JSON incorrecto.', 16, 1);

        DECLARE @Maestro     varchar(40),
                @AnoEje      smallint,
                @SecEjec     int,
                @CentroCosto varchar(15),
                @Texto       varchar(200),
                @Limite      int,
                @errMaestro  nvarchar(300);

        SET @Maestro     = sigcm.fnJsonTexto(@parametro, 'Maestro');
        SET @AnoEje      = CONVERT(smallint, sigcm.fnJsonEntero(@parametro, 'AnoEje'));
        SET @SecEjec     = sigcm.fnJsonEntero(@parametro, 'SecEjec');
        SET @CentroCosto = sigcm.fnJsonTexto(@parametro, 'CentroCosto');
        SET @Texto       = sigcm.fnJsonTexto(@parametro, 'Texto');
        SET @Limite      = sigcm.fnJsonEntero(@parametro, 'Limite');

        IF NULLIF(LTRIM(RTRIM(@Maestro)), '') IS NULL
            RAISERROR('VALIDACION_PAYLOAD: falta Maestro.', 16, 1);
        IF @SecEjec IS NULL
            RAISERROR('VALIDACION_PAYLOAD: falta SecEjec.', 16, 1);
        IF @AnoEje IS NULL SET @AnoEje = YEAR(GETDATE());

        /* Tope duro: el frontend no debe poder pedir el catalogo entero. */
        SET @Limite = CASE WHEN @Limite IS NULL OR @Limite <= 0 THEN 200
                           WHEN @Limite > 500 THEN 500
                           ELSE @Limite END;

        DECLARE @Datos nvarchar(max);

        IF @Maestro = 'CENTRO_COSTO'
            SET @Datos = N'[' + ISNULL(STUFF((
                SELECT N',' + N'{'
                    + N'"CentroCosto":'  + sigcm.fnJsonValorTexto(t.CentroCosto)
                    + N',"NombreDepend":' + sigcm.fnJsonValorTexto(t.NombreDepend)
                    + N',"Abreviado":'    + sigcm.fnJsonValorTexto(t.Abreviado)
                    + N',"TipoDepend":'   + sigcm.fnJsonValorTexto(t.TipoDepend)
                    + N',"Activo":'       + CASE WHEN t.Activo IS NULL THEN N'null' WHEN t.Activo = 1 THEN N'true' ELSE N'false' END
                    + N'}'
                FROM (
                    SELECT TOP (@Limite) CentroCosto, NombreDepend, Abreviado, TipoDepend, Activo
                      FROM siga.vwCentroCosto
                     WHERE AnoEje = @AnoEje AND SecEjec = @SecEjec
                       AND (@Texto IS NULL OR NombreDepend LIKE '%' + @Texto + '%'
                                           OR CentroCosto  LIKE @Texto + '%')
                     ORDER BY CentroCosto
                ) AS t
                FOR XML PATH(N''), TYPE
            ).value(N'.', N'nvarchar(max)'), 1, 1, N''), N'') + N']';

        ELSE IF @Maestro = 'META'
            SET @Datos = N'[' + ISNULL(STUFF((
                SELECT N',' + N'{'
                    + N'"SecFunc":'   + CASE WHEN t.SecFunc IS NULL THEN N'null' ELSE CONVERT(nvarchar(20), t.SecFunc) END
                    + N',"Nombre":'    + sigcm.fnJsonValorTexto(t.Nombre)
                    + N',"Meta":'      + sigcm.fnJsonValorTexto(t.Meta)
                    + N',"Finalidad":' + sigcm.fnJsonValorTexto(t.Finalidad)
                    + N',"ActProy":'   + sigcm.fnJsonValorTexto(t.ActProy)
                    + N',"Activo":'    + CASE WHEN t.Activo IS NULL THEN N'null' WHEN t.Activo = 1 THEN N'true' ELSE N'false' END
                    + N'}'
                FROM (
                    SELECT TOP (@Limite) SecFunc, Nombre, Meta, Finalidad, ActProy, Activo
                      FROM siga.vwMeta
                     WHERE AnoEje = @AnoEje AND SecEjec = @SecEjec
                       AND (@Texto IS NULL OR Nombre LIKE '%' + @Texto + '%')
                     ORDER BY SecFunc
                ) AS t
                FOR XML PATH(N''), TYPE
            ).value(N'.', N'nvarchar(max)'), 1, 1, N''), N'') + N']';

        ELSE IF @Maestro = 'FUENTE_FINANC'
            SET @Datos = N'[' + ISNULL(STUFF((
                SELECT N',' + N'{'
                    + N'"Origen":'        + sigcm.fnJsonValorTexto(t.Origen)
                    + N',"FuenteFinanc":'  + sigcm.fnJsonValorTexto(t.FuenteFinanc)
                    + N',"Descripcion":'   + sigcm.fnJsonValorTexto(t.Descripcion)
                    + N',"MontoAsignado":' + CASE WHEN t.MontoAsignado IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), t.MontoAsignado) END
                    + N',"Activo":'        + CASE WHEN t.Activo IS NULL THEN N'null' WHEN t.Activo = 1 THEN N'true' ELSE N'false' END
                    + N'}'
                FROM (
                    SELECT TOP (@Limite) Origen, FuenteFinanc, Descripcion, MontoAsignado, Activo
                      FROM siga.vwFuenteFinanc
                     WHERE AnoEje = @AnoEje AND SecEjec = @SecEjec
                     ORDER BY Origen, FuenteFinanc
                ) AS t
                FOR XML PATH(N''), TYPE
            ).value(N'.', N'nvarchar(max)'), 1, 1, N''), N'') + N']';

        ELSE IF @Maestro = 'TAREA'
        BEGIN
            IF @CentroCosto IS NULL
                RAISERROR('VALIDACION_PAYLOAD: TAREA exige CentroCosto. En SIGA la tarea vive por centro de costo.', 16, 1);
            SET @Datos = N'[' + ISNULL(STUFF((
                SELECT N',' + N'{'
                    + N'"TipoTarea":'   + sigcm.fnJsonValorTexto(t.TipoTarea)
                    + N',"NivelTarea":'  + sigcm.fnJsonValorTexto(t.NivelTarea)
                    + N',"CodigoTarea":' + sigcm.fnJsonValorTexto(t.CodigoTarea)
                    + N',"NombreTarea":' + sigcm.fnJsonValorTexto(t.NombreTarea)
                    + N',"GrupoTarea":'  + sigcm.fnJsonValorTexto(t.GrupoTarea)
                    + N',"TipoUso":'     + sigcm.fnJsonValorTexto(t.TipoUso)
                    + N',"Activo":'      + CASE WHEN t.Activo IS NULL THEN N'null' WHEN t.Activo = 1 THEN N'true' ELSE N'false' END
                    + N'}'
                FROM (
                    SELECT TOP (@Limite) TipoTarea, NivelTarea, CodigoTarea, NombreTarea, GrupoTarea, TipoUso, Activo
                      FROM siga.vwTarea
                     WHERE AnoEje = @AnoEje AND SecEjec = @SecEjec AND CentroCosto = @CentroCosto
                       AND (@Texto IS NULL OR NombreTarea LIKE '%' + @Texto + '%')
                     ORDER BY CodigoTarea
                ) AS t
                FOR XML PATH(N''), TYPE
            ).value(N'.', N'nvarchar(max)'), 1, 1, N''), N'') + N']';
        END

        ELSE IF @Maestro = 'UNIDAD_MEDIDA'
            SET @Datos = N'[' + ISNULL(STUFF((
                SELECT N',' + N'{'
                    + N'"UnidadMedida":' + sigcm.fnJsonValorTexto(t.UnidadMedida)
                    + N',"Nombre":'       + sigcm.fnJsonValorTexto(t.Nombre)
                    + N',"Abreviatura":'  + sigcm.fnJsonValorTexto(t.Abreviatura)
                    + N',"Activo":'       + CASE WHEN t.Activo IS NULL THEN N'null' WHEN t.Activo = 1 THEN N'true' ELSE N'false' END
                    + N'}'
                FROM (
                    SELECT TOP (@Limite) UnidadMedida, Nombre, Abreviatura, Activo
                      FROM siga.vwUnidadMedida
                     WHERE (@Texto IS NULL OR Nombre LIKE '%' + @Texto + '%')
                     ORDER BY Nombre
                ) AS t
                FOR XML PATH(N''), TYPE
            ).value(N'.', N'nvarchar(max)'), 1, 1, N''), N'') + N']';

        ELSE IF @Maestro = 'CATALOGO'
        BEGIN
            /* El area usuaria busca por descripcion, nunca por codigo. Full-Text
               no esta instalado en la instancia; sobre las 5 239 filas del
               catalogo de la ejecutora un LIKE tarda 28 ms medidos. */
            SET @Datos = N'[' + ISNULL(STUFF((
                SELECT N',' + N'{'
                    + N'"CodigoItem":'   + sigcm.fnJsonValorTexto(t.CodigoItem)
                    + N',"TipoBien":'     + sigcm.fnJsonValorTexto(t.TipoBien)
                    + N',"GrupoBien":'    + sigcm.fnJsonValorTexto(t.GrupoBien)
                    + N',"ClaseBien":'    + sigcm.fnJsonValorTexto(t.ClaseBien)
                    + N',"FamiliaBien":'  + sigcm.fnJsonValorTexto(t.FamiliaBien)
                    + N',"ItemBien":'     + sigcm.fnJsonValorTexto(t.ItemBien)
                    + N',"Descripcion":'  + sigcm.fnJsonValorTexto(t.Descripcion)
                    + N',"UnidadMedida":' + sigcm.fnJsonValorTexto(t.UnidadMedida)
                    + N',"PrecioRef":'    + CASE WHEN t.PrecioRef IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), t.PrecioRef) END
                    + N',"Activo":'       + CASE WHEN t.Activo IS NULL THEN N'null' WHEN t.Activo = 1 THEN N'true' ELSE N'false' END
                    + N'}'
                FROM (
                    SELECT TOP (@Limite) CodigoItem, TipoBien, GrupoBien, ClaseBien,
                           FamiliaBien, ItemBien, Descripcion, UnidadMedida, PrecioRef, Activo
                      FROM siga.vwCatalogoItem
                     WHERE SecEjec = @SecEjec
                       AND Activo = 1
                       AND (@Texto IS NULL OR Descripcion LIKE '%' + @Texto + '%'
                                           OR CodigoItem  LIKE @Texto + '%')
                     ORDER BY Descripcion
                ) AS t
                FOR XML PATH(N''), TYPE
            ).value(N'.', N'nvarchar(max)'), 1, 1, N''), N'') + N']';
        END

        ELSE IF @Maestro = 'CUADRO_VIGENTE'
        BEGIN
            IF @CentroCosto IS NULL
                RAISERROR('VALIDACION_PAYLOAD: CUADRO_VIGENTE exige CentroCosto.', 16, 1);
            SET @Datos = N'[' + ISNULL(STUFF((
                SELECT N',' + N'{'
                    + N'"SecCuadro":'      + CASE WHEN t.SecCuadro IS NULL THEN N'null' ELSE CONVERT(nvarchar(20), t.SecCuadro) END
                    + N',"SecItem":'        + CASE WHEN t.SecItem IS NULL THEN N'null' ELSE CONVERT(nvarchar(20), t.SecItem) END
                    + N',"SecCuaModSal":'   + CASE WHEN t.SecCuaModSal IS NULL THEN N'null' ELSE CONVERT(nvarchar(20), t.SecCuaModSal) END
                    + N',"CodigoItem":'     + sigcm.fnJsonValorTexto(t.CodigoItem)
                    + N',"TipoBien":'       + sigcm.fnJsonValorTexto(t.TipoBien)
                    + N',"GrupoBien":'      + sigcm.fnJsonValorTexto(t.GrupoBien)
                    + N',"ClaseBien":'      + sigcm.fnJsonValorTexto(t.ClaseBien)
                    + N',"FamiliaBien":'    + sigcm.fnJsonValorTexto(t.FamiliaBien)
                    + N',"ItemBien":'       + sigcm.fnJsonValorTexto(t.ItemBien)
                    + N',"UnidadMedida":'   + sigcm.fnJsonValorTexto(t.UnidadMedida)
                    + N',"PrecioUnit":'     + CASE WHEN t.PrecioUnit IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), t.PrecioUnit) END
                    + N',"EstadoSiga":'     + sigcm.fnJsonValorTexto(t.EstadoSiga)
                    + N',"ProcedenciaDesc":'+ sigcm.fnJsonValorTexto(t.ProcedenciaDesc)
                    + N',"MotivoDesc":'     + sigcm.fnJsonValorTexto(t.MotivoDesc)
                    + N',"CantAno0":'       + CASE WHEN t.CantAno0 IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), t.CantAno0) END
                    + N',"CantAno1":'       + CASE WHEN t.CantAno1 IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), t.CantAno1) END
                    + N',"CantAno2":'       + CASE WHEN t.CantAno2 IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), t.CantAno2) END
                    + N',"CantAno3":'       + CASE WHEN t.CantAno3 IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), t.CantAno3) END
                    + N',"TipoTarea":'      + sigcm.fnJsonValorTexto(t.TipoTarea)
                    + N',"NivelTarea":'     + sigcm.fnJsonValorTexto(t.NivelTarea)
                    + N',"CodigoTarea":'    + sigcm.fnJsonValorTexto(t.CodigoTarea)
                    + N',"SecFunc":'        + CASE WHEN t.SecFunc IS NULL THEN N'null' ELSE CONVERT(nvarchar(20), t.SecFunc) END
                    + N',"Origen":'         + sigcm.fnJsonValorTexto(t.Origen)
                    + N',"FuenteFinanc":'   + sigcm.fnJsonValorTexto(t.FuenteFinanc)
                    + N',"Clasificador":'   + sigcm.fnJsonValorTexto(t.Clasificador)
                    + N',"TipoUso":'        + sigcm.fnJsonValorTexto(t.TipoUso)
                    + N'}'
                FROM (
                    SELECT TOP (@Limite) SecCuadro, SecItem, SecCuaModSal,
                           CodigoItem = sigcm.fnCodigoItemSiga(TipoBien, GrupoBien, ClaseBien, FamiliaBien, ItemBien),
                           TipoBien, GrupoBien, ClaseBien, FamiliaBien, ItemBien,
                           UnidadMedida, PrecioUnit, EstadoSiga, ProcedenciaDesc, MotivoDesc,
                           CantAno0, CantAno1, CantAno2, CantAno3,
                           TipoTarea, NivelTarea, CodigoTarea, SecFunc, Origen, FuenteFinanc,
                           Clasificador, TipoUso
                      FROM siga.vwCuadroVigenteItem
                     WHERE AnoEje = @AnoEje AND SecEjec = @SecEjec AND CentroCosto = @CentroCosto
                     ORDER BY SecItem
                ) AS t
                FOR XML PATH(N''), TYPE
            ).value(N'.', N'nvarchar(max)'), 1, 1, N''), N'') + N']';
        END

        ELSE IF @Maestro = 'TECHO'
        BEGIN
            /* Solo las filas con CentroCosto: las de centro nulo son de
               agregacion y no corresponden a un area usuaria concreta.

               MontoTecho0 y MontoUsado0 son del anio base y son los unicos
               confiables. El techo de los anios 1 a 3 NO se ha localizado.
               Se devuelve MontoProg1..3. Ver la nota en siga.vwTechoPresupuesto. */
            SET @Datos = N'[' + ISNULL(STUFF((
                SELECT N',' + N'{'
                    + N'"Secuencia":'        + CASE WHEN t.Secuencia IS NULL THEN N'null' ELSE CONVERT(nvarchar(20), t.Secuencia) END
                    + N',"CentroCosto":'      + sigcm.fnJsonValorTexto(t.CentroCosto)
                    + N',"FaseCuadro":'       + sigcm.fnJsonValorTexto(t.FaseCuadro)
                    + N',"SecFunc":'          + CASE WHEN t.SecFunc IS NULL THEN N'null' ELSE CONVERT(nvarchar(20), t.SecFunc) END
                    + N',"SecFuncProp":'      + CASE WHEN t.SecFuncProp IS NULL THEN N'null' ELSE CONVERT(nvarchar(20), t.SecFuncProp) END
                    + N',"Origen":'           + sigcm.fnJsonValorTexto(t.Origen)
                    + N',"FuenteFinanc":'     + sigcm.fnJsonValorTexto(t.FuenteFinanc)
                    + N',"Clasificador":'     + sigcm.fnJsonValorTexto(t.Clasificador)
                    + N',"MontoTecho0":'      + CASE WHEN t.MontoTecho0 IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), t.MontoTecho0) END
                    + N',"MontoUsado0":'      + CASE WHEN t.MontoUsado0 IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), t.MontoUsado0) END
                    + N',"MontoDisponible0":' + CASE WHEN t.MontoTecho0 IS NULL OR t.MontoUsado0 IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), t.MontoTecho0 - t.MontoUsado0) END
                    + N',"MontoProg1":'       + CASE WHEN t.MontoProg1 IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), t.MontoProg1) END
                    + N',"MontoProg2":'       + CASE WHEN t.MontoProg2 IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), t.MontoProg2) END
                    + N',"MontoProg3":'       + CASE WHEN t.MontoProg3 IS NULL THEN N'null' ELSE CONVERT(nvarchar(40), t.MontoProg3) END
                    + N'}'
                FROM (
                    SELECT TOP (@Limite) Secuencia, CentroCosto, FaseCuadro, SecFunc, SecFuncProp,
                           Origen, FuenteFinanc, Clasificador,
                           MontoTecho0, MontoUsado0, MontoProg1, MontoProg2, MontoProg3
                      FROM siga.vwTechoPresupuesto
                     WHERE AnoEje = @AnoEje AND SecEjec = @SecEjec
                       AND CentroCosto IS NOT NULL
                       AND (@CentroCosto IS NULL OR CentroCosto = @CentroCosto)
                     ORDER BY CentroCosto, Clasificador
                ) AS t
                FOR XML PATH(N''), TYPE
            ).value(N'.', N'nvarchar(max)'), 1, 1, N''), N'') + N']';
        END

        ELSE IF @Maestro = 'ETAPA_CENTRO'
            SET @Datos = N'[' + ISNULL(STUFF((
                SELECT N',' + N'{'
                    + N'"CentroCosto":' + sigcm.fnJsonValorTexto(t.CentroCosto)
                    + N',"Estado":'      + sigcm.fnJsonValorTexto(t.Estado)
                    + N',"FlagPadre":'   + sigcm.fnJsonValorTexto(t.FlagPadre)
                    + N',"FlagModif":'   + sigcm.fnJsonValorTexto(t.FlagModif)
                    + N',"FechaReg":'    + CASE WHEN t.FechaReg IS NULL THEN N'null' ELSE N'"' + CONVERT(varchar(23), t.FechaReg, 126) + N'"' END
                    + N'}'
                FROM (
                    SELECT TOP (@Limite) CentroCosto, Estado, FlagPadre, FlagModif, FechaReg
                      FROM siga.vwCuadroEtapaCentro
                     WHERE AnoEje = @AnoEje AND SecEjec = @SecEjec
                       AND (@CentroCosto IS NULL OR CentroCosto = @CentroCosto)
                     ORDER BY CentroCosto
                ) AS t
                FOR XML PATH(N''), TYPE
            ).value(N'.', N'nvarchar(max)'), 1, 1, N''), N'') + N']';

        ELSE
        BEGIN
            SET @errMaestro = 'VALIDACION_PAYLOAD: maestro desconocido "' + ISNULL(@Maestro, '')
                + '". Validos: CENTRO_COSTO, META, FUENTE_FINANC, TAREA, UNIDAD_MEDIDA, '
                + 'CATALOGO, CUADRO_VIGENTE, TECHO, ETAPA_CENTRO.';
            RAISERROR(@errMaestro, 16, 1);
        END

        SET @resultado = N'{"estado":1,"maestro":' + sigcm.fnJsonValorTexto(@Maestro)
                       + N',"datos":' + ISNULL(@Datos, N'[]')
                       + N',"mensaje":"OK"}';

        SELECT @resultado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @resultado = N'{"estado":0,"mensaje":' + sigcm.fnJsonValorTexto(ERROR_MESSAGE())
                       + N',"codigo":' + CONVERT(nvarchar(20), ERROR_NUMBER())
                       + N',"datos":[]}';
        SELECT @resultado;
    END CATCH
END
GO
