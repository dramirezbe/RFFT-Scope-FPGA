SLIDES.md — Prompt para IA: presentación del proyecto RFFT-Scope-FPGA

Objetivo
- Encargar a una IA (generador de diapositivas) la creación de una presentación clara y atractiva sobre el proyecto "RFFT Scope completo (Bloques 1–5)".
- Entregar: estructura de diapositivas, sugerencias visuales e imágenes/diagramas, y un guión hablado (speaker notes) por cada diapositiva.

Instrucciones generales para la IA
- Idioma: español.
- Audiencia: ingenieros electrónicos/FPGA y público técnico con nociones de DSP; mantener accesible para asistentes técnicos no expertos en Verilog.
- Estilo visual: mínimo y profesional; paleta sugerida: azul oscuro (#0B3D91), cian suave (#2EC4B6), gris claro (#F4F4F8), acentos anaranjados (#FF7F50) para resaltar. Tipografía: Sans-serif para títulos, monoespaced para fragmentos de código (p.ej. Consolas o Roboto Mono).
- Formato entregable: para cada diapositiva devuélveme (1) título, (2) contenido en bullets (máx. 6 líneas), (3) imagen/diagrama sugerido con descripción y proporciones (ej. 16:9), (4) lista de activos a generar (nombres de archivos sugeridos y tipo: SVG/PNG/PGM), (5) guión hablado (máximo 5 frases completas) y (6) duración sugerida (20–90 s).
- Generar también: un resumen de 1 página (handout), una diapositiva de cierre con pasos siguientes y contactos.

Contenido y estructura recomendada (solicitar a la IA que siga o mejore esta secuencia)
1) Portada
- Título: "RFFT Scope — Pipeline RFFT completo sobre Tang Primer 20K"
- Subtítulo: breve tagline.
- Imagen sugerida: collage pequeño (FPGA board + LCD + onda/spectrum). Archivo: cover_collage.png (16:9).
- Guión: presentador, objetivo general y duración estimada.

2) Resumen ejecutivo / TL;DR
- Bullets: propósito, resultado (espectro en LCD), HW principal (ESP32, MAX9814, Tang Primer 20K), pipeline B1→B5.
- Visual: una sola línea de tiempo/pipeline con iconos para cada bloque. Archivo: overview_pipeline.svg.

3) Motivación y uso
- Por qué: espectrómetro en tiempo real, coste y portabilidad, demo con audio vía UART.
- Visual: foto de la placa (si hay) o mockup.

4) Arquitectura global (bloque alto nivel)
- Mostrar diagrama claro de dominio de reloj y flujo de datos (UART→B1→B2→B3/B4→B5→LCD).
- Incluir velocidades importantes: `clk=27MHz`, `clk_pix=40.5MHz`, UART 921600, fs=48kHz, N=2048.
- Archivo: block_diagram.svg (16:9). Proveer alt-text detallado.

5) Bloque 1 — UART, packing y pipeline inicial
- Explicar: recepción UART 921600, packing a muestras complejas z[n]=x[2n]+j x[2n+1], FIFOs y parámetros `CLK_FREQ`/`BAUD`.
- Visual: diagrama con señal temporal simple (bytes→muestras). Archivo: b1_uart_pack.svg.

6) Bloque 2 — Bit-reverse
- Función y por qué necesario para FFT en memoria secuencial.
- Visual: ejemplo gráfico de índices antes/después (N=2048). Archivo: b2_bitreverse.svg.

7) Bloque 3 — Twiddle ROM y Butterfly
- Explicar la ROM de twiddles, `butterfly_radix2` y los .hex/.mi.
- Visual: estructura de mariposa y acceso a ROM. Archivo: b3_twiddle_butterfly.svg.

8) Bloque 4 — Complex FFT core (fixes y detalles)
- Explicar la core, controller de etapas, working memory, y los fixes integrados (FIX-5, FIX-6). Señalar saturación Q15 y limitaciones.
- Visual: diagrama de pipeline de etapas y latencias; destacar prefetch y corrección de salida corrida. Archivo: b4_complex_fft.svg.

9) Bloque 5 — Recombinación RFFT y drawer
- Matemática clave (Xe, Xo, recombinación): incluir fórmulas en bloque KaTeX.
- Reutiliza `butterfly_radix2` para recombinación y uso de `twiddles_recomb` (1025 entries).
- Señalar salida: 512 bins (pares), calibración 46.88 Hz/px y eje 0–24kHz.
- Visual: diagrama de recombinación (Z[k], Z*[N−k] → X[k]) y ejemplo de barra única. Archivo: b5_recomb.svg y sample_frame.pgm (resultado de TB E2E).

10) LCD / Drawer y sincronización de relojes
- Explicar `clk_pix` PLL 40.5 MHz, buffer ping-pong y gating `first_done` para evitar basura en inicio.
- Visual: snapshot del PGM generado (`rfft_scope_frame.pgm`) con anotaciones. Archivo: lcd_frame_annotated.png.

11) Verificación y pruebas (Icarus Verilog)
- Comandos clave para reproducir tests y E2E (incluir fragmentos de terminal). Indicar tolerancias de golden (±4–5 LSB) y TB que detecta X explícitamente.
- Visual: capturas de waveform o salida del test; histograma de errores. Archivo: verif_commands.txt y tb_snapshot.png.
- Lógica de verificación (Sección 3 del documento de diseño): bottom-up, cada bloque se valida por separado antes de integrar; referencia = modelo dorado de Python (`numpy.fft.rfft`) con factor de escala 1/1024; tolerancia ±2 LSB (sistema) / ±4–5 LSB (FFT/recomb).
- Runner reproducible: `cd verification_plan && ./run_tests.sh` ejecuta las 13 pruebas RTL una a una y deja logs en `verification_plan/results/`.
- Resultado actual: **13/13 PASS, 0 FAIL** (ver tabla abajo). Enfoque adicional: todas dirigidas a acotar el error del congelamiento del micrófono.
- Visual sugerido: tabla de cobertura por bloque + captura del resumen "PASS: 13 FAIL: 0". Archivo: verif_table.svg, verif_summary.png.

11b) Plan de verificación dirigido al error (caso de estudio)
- Contar la historia: síntoma = "la gráfica del micrófono se actualiza unos segundos y se congela". En vez de perseguir el síntoma, se verifica cada etapa del camino de datos para acotar la causa.
- Camino: `MAX9814 → ADC(ESP32) → UART TX │ uart_rx → fifo → buffer → pack → bit-rev → FFT → recomb → LCD`. Las pruebas 1–13 cubren todo el lado FPGA; la prueba HIL cubre el front-end físico.
- Conclusión (mensaje clave de la diapositiva): como las 13 pruebas RTL pasan, el fallo queda **acotado al emisor (firmware TX del ESP32)** — perdía el tiempo real (log por bloque ~5 ms + UART ~44.5 ms > presupuesto 46.4 ms) y desbordaba el buffer del ADC sin recuperarse. Esto demuestra el valor de la lógica de verificación, no solo el arreglo.

| # | Prueba | Bloque / etapa | Causa que descarta |
|---|---|---|---|
| 1 | uart_rx | B1 recepción UART (fix 2 bytes de cola) | Tramas mal desensambladas / desincronización |
| 2 | ram_buffer | B1/B2 buffer dual-port | Lectura/escritura de muestras corrupta |
| 3 | pack | B1 FIFO + ping-pong + pack | Pérdida de muestras / empaquetado |
| 4 | e2e_block1 | B1 cadena UART→muestras | Camino de entrada completo |
| 5 | bit_reverse | B2 permutación bit-reversa | Orden de entrada al FFT |
| 6 | permutation | B2 controlador de permutación | Direccionamiento de la RAM |
| 7 | permutation_1024 | B2 permutación N=1024 | Igual, a tamaño real |
| 8 | permutation_ready_pause | B2 handshake ready/pause | Bloqueos por backpressure |
| 9 | complex_fft_core | B3+B4 FFT 1024-pt | Aritmética Q15 / twiddles / escala |
| 10 | rfft_recombine | B5 recombinación 1025 bins | DC/Nyquist y bins mal recuperados |
| 11 | chain_b2b4recomb | B2→B4→B5 | Integración FFT+recombinación |
| 12 | block1_2_fusion | B1→B2 | Integración entrada+permutación |
| 13 | scope_e2e | Pipeline completo UART→LCD | Camino punta a punta |
| HIL | mic_record_test | ESP32+MAX9814 (manual) | Etapa física mic→ADC→muestras (grabar y escuchar) |

- Activos de esta sección: `verif_table.svg` (la tabla anterior), `verif_summary.png` (salida del runner), referencia a [verification_plan/README.md](verification_plan/README.md) y [examples/Block1_MAX9814/mic_record_test/README.md](examples/Block1_MAX9814/mic_record_test/README.md).

12) Síntesis y despliegue
- Pasos: `gw_sh final/build_rfft_scope.tcl`, `openFPGALoader ... rfft_scope.fs`. Mencionar recomendaciones sobre `$readmemh` y versiones Gowin.
- Visual: checklist y pointer a `final/src/rfft_scope.cst` para pines. Archivo: synth_flow.svg.

13) Limitaciones y lecciones aprendidas
- Bugs encontrados (detalle de FIX-5 y FIX-6), saturación y cómo afecta visualización; consejos para futuras mejoras.
- Visual: pequeña comparación before/after del bin offset.

14) Demo en vivo (guion)
- Pasos para demo: arrancar ESP32 → enviar tono 3 kHz por UART → observar barra en LCD (columna esperada ≈ x≈128). Indicar duración y qué mostrar en pantalla.
- Visual: lista de pasos rápidos y captura del PGM de ejemplo.

15) Conclusión y siguientes pasos
- Resumen, mejoras propuestas (mejor manejo de saturación, calibración dinámica, soporte multi-ventana), llamada a la acción.

16) Créditos y contacto
- Referencias a archivos del repo: decir explícitamente dónde buscar fuentes.
- Incluir links a: [final/README.md](final/README.md) y top: [final/src/rfft_scope_top.v](final/src/rfft_scope_top.v).

Requerimientos concretos para los guiones (speaker notes)
- Para cada diapositiva, entregar: (a) versión corta (3 bullets para leer), (b) versión larga (guión hablado, 4–6 frases), (c) puntos de discusión para preguntas (2–3 preguntas sugeridas).
- Incluir tiempos estimados por diapositiva.

Activos a generar y nombres sugeridos
- `cover_collage.png` (16:9)
- `overview_pipeline.svg` (16:9)
- `block_diagram.svg` (16:9)
- `b1_uart_pack.svg`, `b2_bitreverse.svg`, `b3_twiddle_butterfly.svg`, `b4_complex_fft.svg`, `b5_recomb.svg`
- `sample_frame.pgm` y `lcd_frame_annotated.png`
- `verif_commands.txt`, `tb_snapshot.png`, `synth_flow.svg`
- `verif_table.svg` (tabla de cobertura de las 13 pruebas) y `verif_summary.png` (salida del runner `run_tests.sh`, "PASS: 13 FAIL: 0")
- Para cada imagen, incluir alt-text y una breve nota sobre cómo generarla (herramienta recomendada: Inkscape para SVG; matplotlib/numpy para PGM).

Extras opcionales (pedir a la IA que ofrezca)
- Versión reducida de 8 diapositivas para una charla lightning de 10 minutos.
- Versión técnica extendida con apéndices (código clave en `src/block4/`, tests unitarios y scripts `scripts/gen_e2e_vectors.py`).
- Guía de impresión (handout) y fichero `SLIDES_HANDOUT.md` resumido.

Contexto y referencias en el repo (para enriquecer el contenido)
- Leer: [final/README.md](final/README.md) para descripción global y verificación.
- Top-level FPGA: [final/src/rfft_scope_top.v](final/src/rfft_scope_top.v)
- Recombinador: `final/src/block5/rfft_recombine.v` (referir). (si desea: localizar y adjuntar fragmentos de código para destacar)
- Plan de verificación reproducible: [verification_plan/README.md](verification_plan/README.md) + [verification_plan/run_tests.sh](verification_plan/run_tests.sh) (13 pruebas RTL, logs en `results/`).
- Prueba HIL de micrófono (grabar/escuchar audio): [examples/Block1_MAX9814/mic_record_test/README.md](examples/Block1_MAX9814/mic_record_test/README.md).

Instrucción final al modelo IA
- Genera la lista completa de diapositivas con todos los campos requeridos (título, bullets, imagen sugerida con descripción, assets, guión hablado, duración) lista para exportar a un generador de presentaciones.
- Ofrece además las 3 variantes opcionales (short, normal, extended) y un ZIP de activos recomendable.

---
Notas para mí (autor del prompt)
- El archivo `final/README.md` contiene detalles útiles sobre fixes y verificación; sugerir que la IA los cite en la sección de lecciones aprendidas.
- El público objetivo aprecia fórmulas (usar KaTeX) y visuales claros (diagramas SVG con bloques y flechas).