SET NOCOUNT ON;
EXEC sigcm.paListarMaestroSiga N'{"Maestro":"CATALOGO","SecEjec":1750,"Texto":"PAPEL LUSTRE","Limite":2}';
EXEC sigcm.paListarMaestroSiga N'{"Maestro":"TAREA","SecEjec":1750,"AnoEje":2026}';
EXEC sigcm.paListarMaestroSiga N'{"Maestro":"NO_EXISTE","SecEjec":1750}';
SELECT sigcm.fnSumarDiasHabiles('2026-07-27', 3) AS tres_habiles_desde_lunes_27jul;
