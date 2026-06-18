# Guion de Video — Bloque 5: RFFT Post-Procesamiento y Testbench

**Duración objetivo:** 3:00 min · **Locución:** ~437 palabras · ritmo sugerido 140–150 palabras/min

---

## Escena 1 — Apertura (0:00–0:15)
**En pantalla:** Figura 1, diagrama de arquitectura (pág. 3) — interconexión general del Bloque 5.

Este es el Bloque 5: la última pieza del pipeline RFFT. Aquí el espectro que calculamos antes se convierte, literalmente, en la imagen que ves en el LCD. Veamos cómo funciona, y cómo comprobamos que funciona bien.

## Escena 2 — Visión general (0:15–0:37)
**En pantalla:** Misma Figura 1, resaltando la entrada Z[k] a la izquierda y la salida hacia el LCD a la derecha.

Recibe Z de k del Bloque 4: 1024 bins complejos. Los recombina en un espectro real, X de k, y decima el resultado a 512 bins pares para cubrir de 0 a 24 kilohercios en pantalla. Todo esto cruzando dos relojes: el del sistema, a 27 megahercios, y el de píxel, a 40.5.

## Escena 3 — Los cuatro módulos (0:37–1:07)
**En pantalla:** Cuadro 1, tabla de módulos (pág. 2), o la misma Figura 1 resaltando cada bloque en orden: rfft_recombine → spectrum_buffer → spectrum_draw → block5_lcd_drawer.

Son cuatro módulos. rfft_recombine hace la recombinación matemática, reutilizando el butterfly del Bloque 3. spectrum_buffer calcula una magnitud aproximada y la guarda en una RAM ping-pong de doble reloj, resolviendo ahí mismo el cruce de dominios. spectrum_draw dibuja las barras, los ejes y las etiquetas de frecuencia con una fuente de 5 por 7 píxeles. Y block5_lcd_drawer es el wrapper que integra a los dos últimos y marca la frontera entre relojes.

## Escena 4 — El corazón: la FSM de rfft_recombine (1:07–1:31)
**En pantalla:** Figura 2, diagrama de estados (pág. 5).

Por dentro, rfft_recombine primero captura los 1024 bins de entrada en una memoria interna. Después, para cada uno de los 512 bins de salida, prepara direcciones, espera la latencia de la RAM y la ROM de twiddles, registra los operandos y dispara el butterfly: cinco ciclos por bin. En total, unos 3584 ciclos de reloj por cuadro completo.

## Escena 5 — Cruce de dominios de reloj (1:31–1:55)
**En pantalla:** Figura 3, separación de dominios clk / clk_pix (pág. 9).

Ese cruce de dominios pasa por spectrum_buffer. Cada vez que termina un cuadro, invierte el banco de escritura; un sincronizador de dos flip-flops lleva ese cambio al reloj de píxel, que siempre lee el banco contrario para evitar tearing. Y una bandera de primer cuadro mantiene la pantalla en negro hasta que hay datos reales que mostrar.

## Escena 6 — El testbench: tb_rfft_recombine (1:55–2:41)
**En pantalla:** Figura 1 del documento de testbench (pág. 3) — diagrama de bloques: driver, DUT, twiddle ROM, checker.

Para verificar rfft_recombine de forma aislada, construimos tb_rfft_recombine. El testbench inyecta los 1024 bins de entrada con el protocolo fft_valid y fft_done, y captura los 512 bins de salida. Cada uno se compara contra un modelo dorado calculado en Python con NumPy, usando un tono de prueba de 3 kilohercios que produce un pico justo en el bin 64 de la pantalla. El verificador acepta hasta 4 LSB de tolerancia —suficiente para el redondeo de la ROM de twiddles y del butterfly, pero ni uno más: cualquier error mayor indicaría un bug real. También confirma que lleguen exactamente los 512 bins y que la señal de fin de cuadro aparezca dentro de 20 mil ciclos.

## Escena 7 — Resultado y cierre (2:41–3:00)
**En pantalla:** Captura de consola "TB RECOMBINE: PASS" (pág. 7) y tabla de testbenches relacionados, #11–#13 (pág. 8).

El resultado: PASS, los 512 bins dentro de tolerancia. Esta misma recombinación se valida otra vez en cadena, junto al resto del pipeline, en el testbench 11; y de extremo a extremo —desde la entrada UART hasta los píxeles del LCD— en el testbench 13.

---

**Nota de ritmo:** el guion tiene ~437 palabras; a 140–150 palabras por minuto encaja justo en 3 minutos. Si al grabar te sale más lento —algo normal con tantos nombres de señales—, las Escenas 3 y 6 son las más fáciles de recortar sin perder información clave.