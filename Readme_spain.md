# Herramienta de Reporte de CDRs

## Descripción general

Esta herramienta genera reportes diarios del conteo de registros de detalles de llamadas (CDR) para múltiples servicios (Voz, SMS, GPRS, Recarga, Roaming). Escanea archivos CDR (comprimidos o no), cuenta cuántos registros de un día dado fueron procesados en días posteriores y produce reportes formateados. La herramienta es altamente configurable para adaptarse a diferentes formatos de archivo (campos delimitados o ancho fijo) y puede programarse vía cron con reintentos automáticos en caso de fallo.

## Características

- **Soporte multi-servicio**: Configuraciones separadas para cada servicio (fácilmente extensible).
- **Extracción flexible de campos**:
  - **Campos delimitados** (ej. pipe `|`, coma, espacio) – especifique separador e índice del campo.
  - **Ancho fijo** – especifique posición inicial y longitud.
- **Formato de fecha configurable** dentro de los archivos CDR (ej. `%Y%m%d`, `%d/%m/%Y`).
- **Cuenta CDRs de un día específico** que aparecen en directorios de diferentes días de procesamiento.
- **Soporta archivos comprimidos y no comprimidos** mediante la variable `COMPRESSED` (`true` para `.gz`, `false` para texto plano).
- **Rutas flexibles** (no limitadas a `BASE_PATH/YYYYMMDD`): use plantillas con `{date}`, `{service}`, `{hour}` para adaptarse a estructuras complejas (ej. `ruta/{date}/{service}/{hour}/backup`).
- **Logging automático**: configure `LOG_FILE` para registrar cada ejecución, reintentos y errores.
- **Creación automática del directorio de salida** (por defecto `./cdr_reports` relativo al script, puede cambiarse).
- **Mecanismo de reintentos**: si falla la generación del reporte, el script reintenta hasta 3 veces con 1 hora de espera.
- **Marcador de éxito** en el archivo de reporte para verificar la finalización correcta.
- **Fácil integración con cron** con un solo comando por servicio.
- **Ligero**: escrito en Bash puro, usa herramientas estándar (`find`, `zcat`/`cat`, `grep`, `awk`).

## Requisitos

- **Bash** 3.2 o superior (probado en 3.2.51).
- Utilidades Unix estándar: `date`, `find`, `xargs`, `zcat` (si hay compresión), `cat`, `grep`, `awk`, `mkdir`, `mv`, `sleep`.
- **Acceso** a los directorios de respaldo de CDR (permisos de lectura).


## Configuración
Variables generales
Variable	            Descripción	                                                                 Requerida	  Por defecto
SERVICE_NAME	        Nombre del servicio (se usa en encabezados del reporte).	                   Sí	          –
BASE_PATH	            Ruta base a los directorios de respaldo (si no se usa PATH_TEMPLATE).	       Sí*	        –
PATH_TEMPLATE	        Plantilla de ruta flexible (reemplaza a BASE_PATH si se define).	           No	          –
FILE_PATTERN	        Patrón de archivos a procesar (ej. *.gz, *).	                               No	          *
OUTPUT_DIR	          Directorio donde se guardarán los reportes.	                                 No	          ./cdr_reports
CDR_OFFSETS	          Lista de offsets (días desde hoy) para los cuales reportar CDRs.	           Sí	          –
PROC_OFFSETS_X	      Para cada offset de CDR, lista de offsets de procesamiento a buscar.	       Sí	          –
MAX_RETRIES	          Número de reintentos en caso de fallo.	                                     No	          3
RETRY_DELAY	          Segundos de espera entre reintentos.	                                       No	          3600 (1 hora)
COMPRESSED	          true si los archivos están comprimidos con gzip, false si son texto plano.	 No	          false
LOG_FILE	            Ruta completa al archivo de log (si se define, se activa el logging).	       No	          (vacío, sin logs)
FIELD_SEPARATOR	      Carácter separador de campos (ej. |, ,, ).	                                 Sí**	        –
DATE_FIELD_INDEX	    Índice del campo que contiene la fecha (1‑based).	                           Sí**	        –
DATE_FIELD_START	    Posición inicial (1‑based) para extracción por ancho fijo.	                 Sí**	        –
DATE_FIELD_LENGTH	    Longitud del campo de fecha (ancho fijo).	                                   Sí**	        –
DATE_FIELD_FORMAT	    Formato de la fecha dentro del archivo (ej. %Y%m%d, %d/%m/%Y).	             Sí	          –
HOUR_RANGE	          Lista de valores para {hour} en PATH_TEMPLATE (ej. 00 01 02 ... 23).	       No	      (se genera automático)

* BASE_PATH es obligatorio a menos que se defina PATH_TEMPLATE.
** Se debe usar o bien el par FIELD_SEPARATOR+DATE_FIELD_INDEX o bien el par DATE_FIELD_START+DATE_FIELD_LENGTH.
Entendiendo CDR_OFFSETS y PROC_OFFSETS_X

    CDR_OFFSETS: lista de días (offsets desde hoy) para los que se desea ver el conteo de CDRs.
    Ejemplo: (-3 -2) significa reportar CDRs de hace 3 días y hace 2 días.

    PROC_OFFSETS_X: para cada offset de CDR (X = valor absoluto del offset, sin signo), una lista de offsets de procesamiento (también relativos a hoy) que serán revisados.
    Ejemplo:

        PROC_OFFSETS_3="-3 -2 -1" → para CDRs de hace 3 días, busca en los directorios de hace 3, 2 y 1 día.

        PROC_OFFSETS_2="-2 -1" → para CDRs de hace 2 días, busca en directorios de hace 2 y 1 día.

    Los nombres de los directorios se construyen como BASE_PATH/YYYYMMDD (modo tradicional) o mediante la PATH_TEMPLATE si se define.

Sintaxis de PATH_TEMPLATE (rutas flexibles)

Puede contener los siguientes marcadores, que se reemplazan automáticamente:

    {date} → fecha de procesamiento en formato AAAAMMDD (ej. 20260315).

    {service} → valor de SERVICE_NAME.

    {hour} → cada valor de HOUR_RANGE (si no se define HOUR_RANGE, se usa 00 01 02 ... 23).

Ejemplo:
  ```text
  PATH_TEMPLATE="/datos/{date}/{service}/{hour}/backup"
  ```

Esto generará rutas como /datos/20260315/voice/00/backup, /datos/20260315/voice/01/backup, etc.

Si la plantilla no contiene {hour}, se asume una sola ruta por fecha de procesamiento.
Uso
Ejecución básica

Ejecute el script con un archivo de configuración:
  ```bash
  ./reporte_cdr.sh /ruta/a/config.conf
  ```

Si coloca el archivo de configuración junto al script con el mismo nombre base (ej. reporte_cdr.conf), puede ejecutarlo sin argumentos:
  ```bash
  ./reporte_cdr.sh
  ```

Usando el script auxiliar create_service_script.sh
  ```bash
  ./create_service_script.sh nombre-servicio /ruta/a/config.conf
  ```

Ejecución del script de servicio resultante
  ```bash
  ./reporte_nombre-servicio.sh > /ruta/log/service.log 2>&1 &
  ```

Salida (reporte)

Los reportes se guardan en OUTPUT_DIR (por defecto ./cdr_reports) con el nombre cdr_report_<SERVICE_NAME>_<AAAAMMDD>.txt. Cada reporte contiene:

    Una cabecera con timestamp.

    Para cada día de CDR, una sección con los conteos por día de procesamiento.

    Un marcador de éxito al final (### REPORT COMPLETED SUCCESSFULLY ON ... ###).

Logging automático

Si define LOG_FILE en la configuración, el script escribirá entradas como:
  ```text
  [2026-03-18 10:30:45] [INFO] Iniciando reporte para servicio VOICE
  [2026-03-18 10:30:46] [ERROR] Intento 1 falló: código 1
  [2026-03-18 10:30:46] [WARNING] Reintentando en 3600 segundos...
  [2026-03-18 11:30:46] [INFO] Reporte generado exitosamente: /var/log/cdr_reports/cdr_report_VOICE_20260318.txt
  ```

Los niveles usados son INFO, WARNING, ERROR. El log es acumulativo (modo append). Puede rotarlo externamente con logrotate.
Mecanismo de reintentos

Si la generación del reporte falla (la función generate_report retorna un código distinto de cero), el script espera RETRY_DELAY segundos (default 3600) y vuelve a intentar. Después de MAX_RETRIES intentos, termina con error. Esto asegura que fallos transitorios (ej. archivos aún no disponibles, problemas de red) se manejen sin intervención humana.

El marcador de éxito al final del reporte solo se escribe si la generación se completa sin errores. El script verifica el estado de salida de generate_report, que a su vez captura el éxito de toda la operación (incluyendo la creación del archivo temporal y el movimiento final).
Ejemplos de configuración
Ejemplo 1: Estructura tradicional (fija) con logging --> Ver fichero de configuración de ejemplo voice.conf.example
Ejemplo 2: Ruta flexible con horas, sin compresión --> Ver fichero de configuración de ejemplo other.conf.example
Ejemplo 3: Extracción por ancho fijo, sin horas --> Ver fichero de configuración de ejemplo recharge.conf.example


Solución de problemas

    Archivo de configuración no encontrado: Verifique la ruta o que el archivo por defecto exista junto al script.

    Extracción de campos no funciona:

        Revise la primera línea de un archivo CDR de muestra: zcat /ruta/archivo.gz | head -n 1 (o cat si no está comprimido).

        Ajuste FIELD_SEPARATOR / DATE_FIELD_INDEX o DATE_FIELD_START / DATE_FIELD_LENGTH según corresponda.

        Verifique que DATE_FIELD_FORMAT coincida exactamente con la cadena extraída.

    No se encuentran archivos: En modo tradicional, el script solo escanea subdirectorios con nombre exacto AAAAMMDD bajo BASE_PATH. En modo flexible, verifique que las rutas generadas existan y tengan archivos que coincidan con FILE_PATTERN.

    Permiso denegado: Asegúrese de que el script tenga permisos de ejecución y que el usuario que lo ejecuta tenga acceso de lectura a los directorios CDR y de escritura a OUTPUT_DIR y al directorio de LOG_FILE (si se usa).

    Bucle de reintentos infinito: Si el script falla repetidamente, revise los mensajes de error en el archivo temporal (se muestra en stderr) o en el log. También puede inspeccionar el último reporte para ver si contiene el marcador de éxito.

    El log no se escribe: Compruebe que el directorio padre de LOG_FILE exista y sea escribible. El script intenta crearlo automáticamente, pero puede fallar por permisos.

    Problemas con date -d en sistemas no GNU: Si usa BSD/macOS, debe reemplazar date -d por date -j -v-3d +%Y%m%d. El script asume un entorno Linux estándar.

    Compatibilidad con Bash 3.x: El script usa arrays indexados y nombres de variables dinámicas (PROC_OFFSETS_X) para funcionar en versiones antiguas de Bash (como 3.2). No usa arrays asociativos.

Mantenimiento y logs

    El script genera logs automáticos si LOG_FILE está definido. Úselos para monitorear fallos y el rendimiento.

    Para rotar logs, configure logrotate con un archivo como:
    ```text
    /var/log/cdr_reports/*.log {
      daily
      rotate 30
      compress
      delaycompress
      missingok
      notifempty
    }
    ```
    
    Programe el script en cron (por ejemplo, cada hora) para obtener reportes periódicos. Asegúrese de usar rutas absolutas en la configuración.

    Revise el directorio de salida periódicamente para eliminar reportes antiguos si es necesario.