# Bloque 4: Controlador FFT Compleja (`complex_fft_core`)

Este directorio contiene el diseño de hardware, los scripts de soporte numérico y el entorno de verificación para el **Bloque 4 (Core de la FFT Compleja)**. Este componente actúa como el procesador central del sistema DSP, diseñado de forma optimizada para la FPGA **Tang Primer 20K** (chip Gowin GW2A-LV18).

El sistema calcula una FFT de 1024 puntos utilizando el algoritmo de **Diezmado en el Tiempo (DIT) Radix-2** operando en formato de punto fijo **Q15**.

---

## 🤝 Integración del Bloque 3 (Mariposa Radix-2)

La arquitectura de este módulo se fundamenta en la reutilización y el control estricto del **Bloque 3 (`butterfly_radix2.v`)**:
* El Bloque 4 se encarga de toda la infraestructura macro: la máquina de estados, el direccionamiento coordinado de la memoria RAM de doble puerto (`working_memory`) y la geometría de saltos (*stride*) a lo largo de las 10 etapas de procesamiento.
* Durante la fase de cómputo activo, el sistema invoca dinámicamente al Bloque 3 como su **núcleo aritmético dedicado**, inyectándole los datos e-o y los factores de giro de la ROM (`twiddle_rom`) para resolver las mariposas matemáticas en paralelo, aprovechando los bloques DSP nativos del silicio.

---

## 📂 Mapa y Descripción de Archivos

El ecosistema de desarrollo para este módulo está compuesto por los siguientes archivos especializados:

### 1. Módulos de Hardware (Códigos Verilog `.v`)
* **`complex_fft_core.v`**: Módulo de nivel superior (*Top-level*). Implementa la FSM global de 6 estados que gobierna la carga del bloque por flujo *Valid/Ready*, la inicialización secuencial de las etapas y el flujo de streaming final.
* **`fft_stage_controller.v`**: Subcontrolador intermedio. Administra un pipeline síncrono de 3 ciclos por mariposa y aplica el desplazamiento aritmético hacia la derecha (división por 2) para mitigar el desbordamiento (*overflow*) acumulativo.
* **`butterfly_radix2.v`**: *Módulo del Bloque 3 integrado*. Unidad operativa que procesa sumas y restas complejas saturadas en un ciclo de reloj.

### 2. Scripts de Automatización (Código Python `.py`)
* **`tb_complex_fft.py`**: Motor matemático basado en NumPy. Genera un tono analógico puro de prueba, lo cuantiza a enteros Q15, reordena los índices bajo la permutación **Bit-Reversal** y exporta tanto los estímulos de entrada como el espectro ideal escalado por 1/1024.

### 3. Vectores de Datos e Historial (Archivos `.hex` y `.vcd`)
* **`input_br.hex`**: Archivo de texto plano con los datos de entrada formateados en hexadecimal de 32 bits (16 MSB para la parte Real y 16 LSB para la Imaginaria), dispuestos en orden de bits invertidos.
* **`expected_fft.hex`**: Vector de comparación "Golden Standard" con los resultados frecuenciales exactos generados por software.
* **`tb_complex_fft.vcd`**: Archivo de volcado de ondas de tiempo (*Value Change Dump*), ideal para depurar retardos de memoria o estados críticos mediante GTKWave.

### 4. Banco de Pruebas (Testbench Verilog)
* **`tb_complex_fft.v`**: Entorno de simulación automatizado. Instancia el Core, gestiona el reloj y reset, lee los datos desde `input_br.hex` respetando el flujo síncrono y compara la salida física del hardware contra `expected_fft.hex`, validando una tolerancia estricta de ±2 LSB debido al ruido de truncamiento matemático.

---

## ⚙️ Flujo Operativo de la FSM Central

El control implementado dentro de `complex_fft_core.v` mitiga cuellos de botella mediante 6 estados secuenciales:

1. **`S_IDLE`**: Reposo. Mantiene la bandera `br_ready = 1` lista para recibir datos del bus externo tras el pulso de `start`.
2. **`S_LOAD_DATA`**: Fase de absorción. Lee un dato complejo por ciclo de reloj hasta completar las 1024 muestras indexadas en Bit-Reversal.
3. **`S_INIT_STAGE`**: Configura la geometría matemática de la etapa actual (cálculo de límites de grupos y distancias de saltos o *stride*).
4. **`S_RUN_STAGE`**: Cede los buses de la RAM al subcontrolador de pipeline y entra en retención segura hasta recibir la señal `sc_done`.
5. **`S_CHECK_STAGE`**: Incrementa el contador de etapas y evalúa si ya se ejecutaron las 10 etapas ($\log_2(1024)$). Si terminó, pasa a la salida.
6. **`S_OUTPUT_STREAM`**: Lee la memoria interna de forma secuencial y entrega los bines en su orden espectral natural acompañados por la señal `fft_valid`.

---

## 🛠️ Instrucciones de Compilación y Verificación

Para ejecutar la simulación local de hardware y validar la precisión matemática frente a los vectores generados, corre los siguientes comandos en tu terminal de Fedora:

### Paso 1: Regenerar los vectores numéricos
```bash
python3 tb_complex_fft.py
```

### Paso 2: Compilar el hardware con Icarus Verilog
```bash
iverilog -o tb_complex_fft tb_complex_fft.v complex_fft_core.v fft_stage_controller.v butterfly_radix2.v
```

### Paso 3: Ejecutar la simulación con el motor vvp
```bash
vvp tb_complex_fft
```

### Resultado esperado en consola
El verificador automatizado analizará cada bin de frecuencia entregado por tu circuito de hardware y, si todo el procesamiento lógico concuerda, desplegará lo siguiente:
```text
─────────────────────────────────
Bins verificados : 1024
Errores > 2 LSB: 0
✓ PASS — Precisión dentro de tolerancia
─────────────────────────────────
```

---
*Nota de Ingeniería: Esta versión incluye la resolución de los fallos de deadlock en el handshake de entrada, la corrección del desfase indexado en la carga de memoria, la conexión permanente del bus flotante de lectura y la inclusión del estado de almacenamiento del nodo inferior de la mariposa.*
```
