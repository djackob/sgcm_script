# Capturas del Manual de verificación

Guardar aquí las cinco capturas de pantalla del aplicativo SIGA, **con estos
nombres exactos**, y volver a ejecutar:

```bash
python ../generar_manual_verificacion.py
```

| Archivo | Qué debe mostrar |
|---|---|
| `01-menu-modificacion-bienes.png` | El menú `Programación → Modificación de C.M.N. → Bienes, Servicios y Obras` desplegado |
| `02-modificacion-por-area-usuaria.png` | La pantalla *Modificación de C.M.N. por Área Usuaria* con las líneas del SIGCM visibles (`I` en Incl/Excl) |
| `03-menu-solicitud-modificacion.png` | El menú `Programación → Modificación de C.M.N. → Solicitud de Modificación` |
| `04-filtro-area-usuaria.png` | El *Filtro para Búsqueda de Datos* del área usuaria |
| `05-solicitud-aprobada.png` | La solicitud abierta, con su estado y el sustento `INCLUSION CMN INTEGRADA DESDE SIGCM` |

Mientras falte alguna, el documento se genera igual y deja en su lugar un
recuadro que dice cuál falta: el manual sirve desde el primer día y mejora
cuando se agregan las imágenes, en vez de no existir hasta tenerlas todas.

## Recomendaciones para la captura

- **PNG**, no JPG: son pantallas con texto pequeño y el JPG lo emborrona.
- Recortar a la ventana útil. La pantalla de *Modificación de C.M.N.* es muy
  apaisada; si se captura el escritorio entero, al reducirla al ancho de la
  página el texto queda ilegible. El script avisa por consola cuando una imagen
  supera una relación de 3,2:1.
- Si hay que resaltar una fila, hacerlo con un recuadro rojo fino, como en las
  capturas de la versión 1.0.
- **Sin datos de personas reales** que no correspondan al entorno de prueba.
