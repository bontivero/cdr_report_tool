#!/bin/bash
set -euo pipefail

# Determinar el directorio del script (resolviendo enlaces simbólicos si es necesario)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Función de ayuda
usage() {
    echo "Uso: $0 [archivo_configuracion]"
    echo "Si no se especifica archivo, se busca por defecto: ${SCRIPT_DIR}/$(basename "$0" .sh).conf"
    exit 1
}

# Manejo de argumentos: puede tener 0 o 1 argumento
if [ $# -gt 1 ]; then
    usage
elif [ $# -eq 1 ]; then
    CONFIG_FILE="$1"
else
    # Sin argumentos: usar archivo por defecto (mismo nombre con extensión .conf)
    base_name="$(basename "$0" .sh)"
    CONFIG_FILE="${SCRIPT_DIR}/${base_name}.conf"
    echo "No se especificó archivo de configuración. Usando por defecto: $CONFIG_FILE"
fi

# Verificar que el archivo de configuración existe
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Archivo de configuración no encontrado: $CONFIG_FILE"
    exit 1
fi

# Cargar configuración
source "$CONFIG_FILE"

# Valores por defecto (después de cargar configuración para que puedan ser sobreescritos)
: ${FILE_PATTERN:="*"}
: ${OUTPUT_DIR:="${SCRIPT_DIR}/cdr_reports"}
: ${MAX_RETRIES:=3}
: ${RETRY_DELAY:=3600}  # 1 hora en segundos

# Crear directorio de salida si no existe
mkdir -p "$OUTPUT_DIR"

# Nombre del archivo de reporte (incluye nombre del servicio y fecha)
OUTPUT_FILE="${OUTPUT_DIR}/cdr_report_${SERVICE_NAME}_$(date +%Y%m%d).txt"

# Validar variables obligatorias básicas
: ${SERVICE_NAME:?}
: ${BASE_PATH:?}
: ${CDR_OFFSETS:?}  # Debe ser una lista (ej. "-3 -2")
# PROC_OFFSETS debe ser un array asociativo definido en la configuración

# Validar el método de extracción de fecha: separador o posición fija
if [ -n "${FIELD_SEPARATOR:-}" ] && [ -n "${DATE_FIELD_INDEX:-}" ]; then
    # Modo separador
    EXTRACTION_MODE="separator"
    : ${DATE_FIELD_FORMAT:?}  # Requerido en este modo
elif [ -n "${DATE_FIELD_START:-}" ] && [ -n "${DATE_FIELD_LENGTH:-}" ]; then
    # Modo posición fija
    EXTRACTION_MODE="fixed"
    : ${DATE_FIELD_FORMAT:?}  # También requerido para generar la cadena objetivo
else
    echo "ERROR: Debe definir FIELD_SEPARATOR+DATE_FIELD_INDEX o DATE_FIELD_START+DATE_FIELD_LENGTH en la configuración."
    exit 1
fi

# Función para contar CDRs en un directorio de procesamiento
count_cdrs() {
    local proc_dir="$1"
    local target_string="$2"
    local count=0
    if [ -d "$proc_dir" ]; then
        if [ "$EXTRACTION_MODE" = "separator" ]; then
            # Modo separador: usar awk con FIELD_SEPARATOR y comparar campo específico
            count=$(find "$proc_dir" -maxdepth 1 -type f -name "$FILE_PATTERN" -print0 2>/dev/null | \
                    xargs -0 -r zcat 2>/dev/null | \
                    awk -F"$FIELD_SEPARATOR" -v idx="$DATE_FIELD_INDEX" -v val="$target_string" \
                        '$idx == val {c++} END {print c+0}')
        else
            # Modo posición fija: extraer substring con start y length
            count=$(find "$proc_dir" -maxdepth 1 -type f -name "$FILE_PATTERN" -print0 2>/dev/null | \
                    xargs -0 -r zcat 2>/dev/null | \
                    awk -v start="$DATE_FIELD_START" -v len="$DATE_FIELD_LENGTH" -v val="$target_string" \
                        '{ if (substr($0, start, len) == val) c++ } END {print c+0}')
        fi
    fi
    echo "$count"
}

# Función principal que genera el reporte
generate_report() {
    local tmp_out=$(mktemp)
    # Redirigir toda la salida al archivo temporal (incluyendo errores)
    (
        set -e
        # Cabecera general
        echo "*************************************($(date +"%d/%m/%Y-%H:%M"))************************************"
        echo "  "
        echo "SERVICIO DE $SERVICE_NAME" 
        echo "***********************"

        for cdr_offset in ${CDR_OFFSETS[@]}; do
            # Fecha del CDR a buscar (en el formato del campo)
            target_string=$(date -d "$cdr_offset days" +"$DATE_FIELD_FORMAT")
            cdr_display=$(date -d "$cdr_offset days" +%d/%m/%Y)
            echo "CDRs DEL DÍA $cdr_display"
            echo "--------------------------------------------"

            # Obtener offsets de procesamiento para este CDR (del array asociativo)
            proc_offsets=(${PROC_OFFSETS[$cdr_offset]})
            for proc_offset in "${proc_offsets[@]}"; do
                proc_dir="${BASE_PATH}/$(date -d "$proc_offset days" +%Y%m%d)"
                proc_display=$(date -d "$proc_offset days" +%d/%m/%Y)
                count=$(count_cdrs "$proc_dir" "$target_string")
                echo "Procesados en el día ($proc_display): $count   "
            done
            echo "  "
        done

        # Marcador de éxito
        echo "### REPORT COMPLETED SUCCESSFULLY ON $(date) ###"
    ) > "$tmp_out" 2>&1
    local status=$?
    if [ $status -eq 0 ]; then
        mv "$tmp_out" "$OUTPUT_FILE"
        echo "Reporte guardado en $OUTPUT_FILE"
        return 0
    else
        echo "Error al generar el reporte (código $status). Revise el archivo temporal $tmp_out" >&2
        rm -f "$tmp_out"
        return $status
    fi
}

# Bucle de reintentos
for attempt in $(seq 1 $MAX_RETRIES); do
    echo "Intento $attempt para el servicio $SERVICE_NAME"
    if generate_report; then
        exit 0
    else
        if [ $attempt -lt $MAX_RETRIES ]; then
            echo "Intento $attempt falló. Reintentando en $RETRY_DELAY segundos..." >&2
            sleep $RETRY_DELAY
        else
            echo "ERROR: Todos los $MAX_RETRIES intentos fallaron." >&2
            exit 1
        fi
    fi
done