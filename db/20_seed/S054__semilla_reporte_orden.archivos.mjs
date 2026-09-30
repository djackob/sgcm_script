/*
  S054 (archivos) - PDFs de la contratacion de prueba PRU-OC-0001 para el
  reporte de expediente por orden. Solo QA.

  Genera en el file server los archivos que referencia S054__semilla_reporte_orden.sql
  (y los que la semilla del modulo Ejecucion dejo referenciados sin archivo).
  El contenido sale de los datos de QA de esa orden; cada hoja lleva la marca
  de documento de prueba.

  Uso (desde sgcm_front, que tiene pdf-lib):
    node ..\sgcm_script\db\20_seed\S054__semilla_reporte_orden.archivos.mjs [raiz]
  raiz por defecto: \\vasg.anin.gob.pe\DESARROLLO
*/
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(join(process.cwd(), 'package.json'));
const { PDFDocument, StandardFonts, rgb } = require('pdf-lib');

const RAIZ = process.argv[2] || '\\\\vasg.anin.gob.pe\\DESARROLLO';

const ORDEN = {
  numero: 'PRU-OC-0001',
  requerimiento: 'REQ-PRU-EJEC-0001',
  denominacion: 'Adquisición de equipos de cómputo para la OTI (prueba del módulo Ejecución)',
  unidad: 'OFICINA DE TECNOLOGÍAS DE LA INFORMACIÓN',
  proveedor: 'DISTRIBUIDORA DE PRUEBA E.I.R.L.',
  documentoProveedor: 'DNI 43724871',
  monto: 'S/ 25,000.00',
  fechaOrden: '14/09/2026',
  inicio: '16/09/2026',
  fin: '20/10/2026',
  plazo: '35 días calendario',
  lugar: 'Sede central'
};

const DOCUMENTOS = [
  {
    carpeta: 'requerimiento', archivo: 'QA-SEMILLA-PRU-OC-0001-EETT.pdf',
    titulo: 'ESPECIFICACIONES TÉCNICAS DEL BIEN (ANEXO 1)',
    datos: [['Requerimiento', ORDEN.requerimiento], ['Área usuaria', ORDEN.unidad], ['Denominación', ORDEN.denominacion],
            ['Cantidad', '20 equipos de cómputo, en dos entregas de 10'], ['Valor estimado', ORDEN.monto]],
    cuerpo: 'Características mínimas: procesador de 8 núcleos, 16 GB de memoria RAM, 512 GB SSD, monitor de 24", garantía de 3 años on-site. '
      + 'Lugar de entrega: sede central. Plazo: 35 días calendario desde el día siguiente de notificada la orden.'
  },
  {
    carpeta: 'requerimiento', archivo: 'QA-SEMILLA-PRU-OC-0001-DISPONIBILIDAD.pdf',
    titulo: 'DISPONIBILIDAD PRESUPUESTAL',
    datos: [['Requerimiento', ORDEN.requerimiento], ['Área usuaria', ORDEN.unidad], ['Monto', ORDEN.monto], ['Año fiscal', '2026']],
    cuerpo: 'Se informa que existe disponibilidad presupuestal para atender el requerimiento indicado, con cargo a la meta y clasificador del área usuaria.'
  },
  {
    carpeta: 'requerimiento', archivo: 'QA-SEMILLA-PRU-OC-0001-CCP.pdf',
    titulo: 'CERTIFICACIÓN DE CRÉDITO PRESUPUESTARIO',
    datos: [['Requerimiento', ORDEN.requerimiento], ['Monto certificado', ORDEN.monto], ['Año fiscal', '2026']],
    cuerpo: 'La Unidad de Presupuesto certifica el crédito presupuestario para la adquisición de equipos de cómputo de la OTI.'
  },
  {
    carpeta: 'requerimiento', archivo: 'QA-SEMILLA-PRU-OC-0001-ORDEN-COMPRA.pdf',
    titulo: `ORDEN DE COMPRA N.° ${ORDEN.numero}`,
    datos: [['Fecha', ORDEN.fechaOrden], ['Proveedor', ORDEN.proveedor], ['Documento', ORDEN.documentoProveedor],
            ['Requerimiento', ORDEN.requerimiento], ['Descripción', ORDEN.denominacion], ['Monto total', ORDEN.monto],
            ['Plazo de entrega', ORDEN.plazo], ['Lugar de entrega', ORDEN.lugar]],
    cuerpo: 'Entregas: lote 1 (10 equipos) y lote 2 (10 equipos). Pago por entrega conforme, previa conformidad del área usuaria.'
  },
  {
    carpeta: 'ejecucion', archivo: 'PRUEBA-GUIA-1.pdf',
    titulo: 'GUÍA DE REMISIÓN T001-000101',
    datos: [['Orden', ORDEN.numero], ['Remitente', ORDEN.proveedor], ['Destino', 'ANIN - sede central'], ['Entrega', '1 (lote 1)'],
            ['Fecha', '18/09/2026'], ['Detalle', '10 equipos de cómputo según EETT, lote 1']],
    cuerpo: 'Documento emitido por el proveedor al momento del ingreso de los bienes al almacén.'
  },
  {
    carpeta: 'ejecucion', archivo: 'PRUEBA-GUIA-1-VB.pdf',
    titulo: 'GUÍA DE REMISIÓN T001-000101 (SUSCRITA)',
    datos: [['Orden', ORDEN.numero], ['Entrega', '1 (lote 1)'], ['Verificación', 'CONFORME - 18/09/2026'],
            ['Observación', 'Cumple las EETT. Visto bueno del AU en la guía.']],
    cuerpo: 'Guía con el visto bueno del área usuaria y la recepción de almacén.'
  },
  {
    carpeta: 'ejecucion', archivo: 'PRUEBA-PECOSA-1.pdf',
    titulo: 'PEDIDO-COMPROBANTE DE SALIDA PECOSA-2026-0001',
    datos: [['Orden', ORDEN.numero], ['Entrega', '1 (lote 1)'], ['Destino', ORDEN.unidad], ['Fecha', '18/09/2026'],
            ['Bienes', '10 equipos de cómputo']],
    cuerpo: 'Salida de almacén de los bienes recibidos conformes con destino al área usuaria.'
  },
  {
    carpeta: 'ejecucion', archivo: 'PRUEBA-GUIA-2.pdf',
    titulo: 'GUÍA DE REMISIÓN T001-000102',
    datos: [['Orden', ORDEN.numero], ['Remitente', ORDEN.proveedor], ['Destino', 'ANIN - sede central'], ['Entrega', '2 (lote 2)'],
            ['Fecha', '18/09/2026'], ['Detalle', '10 equipos de cómputo, lote 2']],
    cuerpo: 'Documento emitido por el proveedor al momento del ingreso de los bienes al almacén.'
  },
  {
    carpeta: 'ejecucion', archivo: 'PRUEBA-ACTA-2.pdf',
    titulo: 'ACTA DE INCUMPLIMIENTO Y RETIRO DE BIENES',
    datos: [['Orden', ORDEN.numero], ['Entrega', '2 (lote 2)'], ['Verificación', 'OBSERVADO - 18/09/2026'],
            ['Motivo', 'Los equipos no cumplen la memoria mínima exigida en las EETT.']],
    cuerpo: 'El proveedor retira los bienes observados y queda obligado a reponerlos conforme a las especificaciones técnicas.'
  },
  {
    carpeta: 'modificacion', archivo: 'QA-SEMILLA-PRU-OC-0001-AMP-SOLICITUD.pdf',
    titulo: 'CARTA DE SOLICITUD DE AMPLIACIÓN DE PLAZO',
    datos: [['Orden', ORDEN.numero], ['Proveedor', ORDEN.proveedor], ['Fecha', '18/09/2026'], ['Días solicitados', '2'],
            ['Fin vigente', ORDEN.fin], ['Asunto', 'Ampliación tardía de la DEC']],
    cuerpo: 'El proveedor solicita la ampliación del plazo de entrega por hechos ajenos a su voluntad ocurridos hasta el 17/09/2026.'
  },
  {
    carpeta: 'modificacion', archivo: 'QA-SEMILLA-PRU-OC-0001-AMP-INFORME-AU.pdf',
    titulo: 'INFORME DE OPINIÓN DEL ÁREA USUARIA (AMPLIACIÓN)',
    datos: [['Orden', ORDEN.numero], ['Área usuaria', ORDEN.unidad], ['Fecha', '18/09/2026'], ['Opinión', 'NO PROCEDE']],
    cuerpo: 'Sin sustento técnico. La solicitud no acredita el hecho generador ni su incidencia en el plazo de entrega.'
  }
];

async function generar(doc) {
  const pdf = await PDFDocument.create();
  const normal = await pdf.embedFont(StandardFonts.Helvetica);
  const negrita = await pdf.embedFont(StandardFonts.HelveticaBold);
  const pagina = pdf.addPage([595.28, 841.89]);
  const { width, height } = pagina.getSize();
  const margen = 56;
  let y = height - margen;

  const centrado = (texto, fuente, tam) => {
    pagina.drawText(texto, { x: (width - fuente.widthOfTextAtSize(texto, tam)) / 2, y, size: tam, font: fuente });
    y -= tam + 8;
  };
  const parrafo = (texto, fuente, tam, x = margen, ancho = width - 2 * margen) => {
    let linea = '';
    for (const palabra of texto.split(' ')) {
      const prueba = linea ? `${linea} ${palabra}` : palabra;
      if (fuente.widthOfTextAtSize(prueba, tam) > ancho) {
        pagina.drawText(linea, { x, y, size: tam, font: fuente });
        y -= tam + 4;
        linea = palabra;
      } else {
        linea = prueba;
      }
    }
    if (linea) {
      pagina.drawText(linea, { x, y, size: tam, font: fuente });
      y -= tam + 4;
    }
  };

  centrado('AUTORIDAD NACIONAL DE INFRAESTRUCTURA', negrita, 10);
  y -= 6;
  centrado(doc.titulo, negrita, 13);
  pagina.drawRectangle({ x: margen, y: y - 4, width: width - 2 * margen, height: 18, color: rgb(1, 0.95, 0.8) });
  centrado('DOCUMENTO DE PRUEBA - AMBIENTE QA', negrita, 9);
  y -= 16;

  for (const [etiqueta, valor] of doc.datos) {
    pagina.drawText(`${etiqueta}:`, { x: margen, y, size: 10, font: negrita });
    parrafo(String(valor), normal, 10, margen + 130, width - 2 * margen - 130);
    y -= 4;
  }
  y -= 12;
  parrafo(doc.cuerpo, normal, 10);

  pagina.drawText(`${ORDEN.numero} · ${ORDEN.requerimiento} · ${doc.archivo}`,
    { x: margen, y: 36, size: 7, font: normal, color: rgb(0.4, 0.4, 0.4) });
  return pdf.save();
}

for (const doc of DOCUMENTOS) {
  const carpeta = join(RAIZ, doc.carpeta);
  mkdirSync(carpeta, { recursive: true });
  writeFileSync(join(carpeta, doc.archivo), await generar(doc));
  console.log(`${doc.carpeta}\\${doc.archivo}`);
}
