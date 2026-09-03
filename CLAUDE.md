# Instrucciones para sesiones de IA

**Lee [`INIT.md`](INIT.md) antes de tocar nada.** Es el documento de entrada del
proyecto: reglas, estado de cada módulo, defectos abiertos y cómo levantar el
ambiente. Este archivo sólo existe para llevarte allí.

Lo mínimo, por si no lo lees entero:

- **La lógica de negocio vive en la base de datos.** El backend es un puente; el
  frontend pinta lo que la base le dice que se puede hacer.
- **No se agrega texto informativo que nadie pidió** en las pantallas
  (`ESTANDARES.md` §4.7). La explicación va en un comentario del código.
- **Tener el `.sql` en el repo no es tenerlo en la base.** Comprueba que el
  objeto existe antes de decir que algo quedó probado.
- **Las semillas se aplican por orden alfabético.** Una semilla no puede sembrar
  el permiso de una transición que crea otra posterior.
- **Todo cambio de flujo termina con su script de prueba** en `db/90_pruebas/`.

Al cerrar una iteración: anótala en la bitácora de `CONTEXTO.md` §6 y actualiza
en `INIT.md` la sección 4 (estado) y la 5 (defectos abiertos).
