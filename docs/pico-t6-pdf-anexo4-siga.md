# Pico T6 — PDF Anexo 4 desde SIGA

**Fecha pico automático:** 2026-09-18  
**Decisión de producto (misma fecha):** flujo **manual** — no descarga automática.

## Veredicto automático

SIGA **no** guarda ni expone el PDF del Anexo 4 (solo `SIG_SOLICITUD_GRUPO` + aprobación BD vía `usp_ext_aprobar_solicitud_cmn`). No hay USP/BLOB/ruta de archivo.

## Flujo adoptado (S044)

```
Generar A4 (pdfmake auxiliar, sin firma digital SGCM)
        ↓
Jefe Abast: «Aprobar en SIGA…»  →  CONSOLIDAR_CMN  →  CMN_A4_PEND_DOC_SIGA
        ↓
Esp. o Jefe Abast: modal subir PDF firmado del SIGA
  1. Reemplaza el documento auxiliar del SGCM
  2. Guardar → correo (F013) + CMN_FINALIZADO
```

- Semilla: `db/20_seed/S044__cmn_a4_subir_firmado_siga.sql`
- Transiciones: `CMN_ABAST_JEFE_FIRMAR_A4` (sin firma, encola SIGA), `CMN_ABAST_SUBIR_A4_SIGA` (subir + cerrar)
- Front: selector PDF en el panel de acción al subir
