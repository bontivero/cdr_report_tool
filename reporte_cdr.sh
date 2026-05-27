#!/bin/bash
# Versión con logging automático y soporte para archivos comprimidos o no
set -euo pipefail

# Determinar el directorio del script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
    echo "Uso: $0 [archivo_configuracion]"
    echo "Si no se especifica archivo, se busca por defecto: ${SCRIPT_DIR}/$(basename "$0" .sh).conf"
    exit 1
}

if [ $# -gt 1 ]; then
    usage
elif [ $# -eq 1 ]; then
    CONFIG_FILE="$1"
else
    base_name="$(basename "$0" .sh)"
    CONFIG_FILE="${SCRIPT_DIR}/${base_name}.conf"
    echo "No se especificó archivo de configuración. Usando por defecto: $CONFIG_FILE"
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Archivo de configuración no encontrado: $CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

# Valores por defecto
: ${FILE_PATTERN:="*"}
: ${OUTPUT_DIR:="${SCRIPT_DIR}/cdr_reports"}
: ${MAX_RETRIES:=3}
: ${RETRY_DELAY:=3600}          # 1 hora
: ${COMPRESSED:=false}          # Por defecto, los archivos no están comprimidos
: ${LOG_FILE:=""}               # Si está vacío, no se genera log

# Crear directorios necesarios
mkdir -p "$OUTPUT_DIR"
if [[ -n "$LOG_FILE" ]]; then
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || {
        echo "ERROR: No se puede crear directorio para LOG_FILE: $LOG_FILE" >&2
        LOG_FILE=""
    }
fi

OUTPUT_FILE="${OUTPUT_DIR}/cdr_report_${SERVICE_NAME}_$(date +%Y%m%d).txt"

# Función de logging
log_msg() {
    local level="$1"
    local msg="$2"
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $msg" >> "$LOG_FILE"
    fi
    # Mostrar en consola según nivel
    if [[ "$level" == "ERROR" ]]; then
        echo "$msg" >&2
    elif [[ "$level" == "INFO" ]]; then
        echo "$msg"
    fi
}

# Validaciones obligatorias
: ${SERVICE_NAME:?}
: ${BASE_PATH:?}
: ${CDR_OFFSETS:?}

if [ -n "${FIELD_SEPARATOR:-}" ] && [ -n "${DATE_FIELD_INDEX:-}" ]; then
    EXTRACTION_MODE="separator"
    : ${DATE_FIELD_FORMAT:?}
elif [ -n "${DATE_FIELD_START:-}" ] && [ -n "${DATE_FIELD_LENGTH:-}" ]; then
    EXTRACTION_MODE="fixed"
    : ${DATE_FIELD_FORMAT:?}
else
    log_msg "ERROR" "Debe definir FIELD_SEPARATOR+DATE_FIELD_INDEX o DATE_FIELD_START+DATE_FIELD_LENGTH."
    exit 1
fi

# Determinar el comando de descompresión/lectura según COMPRESSED
if [ "$COMPRESSED" = "true" ]; then
    DECOMPRESS_CMD="zcat"
else
    DECOMPRESS_CMD="cat"
fi

# Función para contar CDRs
count_cdrs() {
    local proc_date="$1"
    local cdr_date="$2"
    local count=0

    # Si existe PATH_TEMPLATE, usamos el modo flexible
    if [[ -n "${PATH_TEMPLATE:-}" ]]; then
        local base_path_tmp="${PATH_TEMPLATE//\{date\}/$proc_date}"
        base_path_tmp="${base_path_tmp//\{service\}/$SERVICE_NAME}"
        
        if [[ "$base_path_tmp" == *"{hour}"* ]]; then
            for hour in ${HOUR_RANGE:-}; do
                local path_with_hour="${base_path_tmp//\{hour\}/$hour}"
                if [[ -d "$path_with_hour" ]]; then
                    # Buscar archivos, descomprimir/leer y contar coincidencias
                    local add
                    add=$(find "$path_with_hour" -type f -name "$FILE_PATTERN" -exec sh -c "$DECOMPRESS_CMD \"\$1\" | grep -c \"$cdr_date\"" _ {} \; 2>/dev/null | awk '{sum+=$1} END {print sum}')
                    count=$((count + add))
                fi
            done
        else
            if [[ -d "$base_path_tmp" ]]; then
                count=$(find "$base_path_tmp" -type f -name "$FILE_PATTERN" -exec sh -c "$DECOMPRESS_CMD \"\$1\" | grep -c \"$cdr_date\"" _ {} \; 2>/dev/null | awk '{sum+=$1} END {print sum}')
            fi
        fi
    else
        # Modo tradicional: BASE_PATH/fecha
        local proc_dir="${BASE_PATH}/$proc_date"
        if [[ -d "$proc_dir" ]]; then
            count=$(find "$proc_dir" -maxdepth 1 -type f -name "$FILE_PATTERN" -exec sh -c "$DECOMPRESS_CMD \"\$1\" | grep -c \"$cdr_date\"" _ {} \; 2>/dev/null | awk '{sum+=$1} END {print sum}')
        fi
    fi
    echo "$count"
}

# Generación del reporte
generate_report() {
    local tmp_out
    tmp_out=$(mktemp -p "$OUTPUT_DIR" reporte_XXXXXX.txt)
    trap "rm -f '$tmp_out'" EXIT

    (
        set +e   # No abortamos por errores menores dentro del subshell
        echo "*************************************($(date +"%d/%m/%Y-%H:%M"))************************************"
        echo "  "
        echo "SERVICIO DE $SERVICE_NAME" 
        echo "***********************"

        for cdr_offset in ${CDR_OFFSETS[@]}; do
            # Fecha del CDR (target) en el formato que viene en los archivos
            target_string=$(date -d "$cdr_offset days" +"$DATE_FIELD_FORMAT")
            cdr_display=$(date -d "$cdr_offset days" +%d/%m/%Y)
            # Fecha del CDR en formato YYYYMMDD para comparación interna
            cdr_date_yyyymmdd=$(date -d "$cdr_offset days" +%Y%m%d)

            echo "CDRs DEL DIA $cdr_display"
            echo "--------------------------------------------"

            # Construir nombre de variable dinámica para PROC_OFFSETS (soporta Bash 3.x)
            offset_clean="${cdr_offset#-}"
            var_name="PROC_OFFSETS_${offset_clean}"
            proc_offsets=(${!var_name})

            for proc_offset in "${proc_offsets[@]}"; do
                proc_date_yyyymmdd=$(date -d "$proc_offset days" +%Y%m%d)
                proc_display=$(date -d "$proc_offset days" +%d/%m/%Y)
                count=$(count_cdrs "$proc_date_yyyymmdd" "$target_string")
                echo "Procesados en el dia ($proc_display): $count   "
            done
            echo "  "
        done

        echo "### REPORT COMPLETED SUCCESSFULLY ON $(date) ###"
    ) > "$tmp_out" 2>&1

    local status=$?
    if [ $status -eq 0 ]; then
        mv "$tmp_out" "$OUTPUT_FILE"
        log_msg "INFO" "Reporte generado exitosamente: $OUTPUT_FILE"
        echo "Reporte guardado en $OUTPUT_FILE"
        return 0
    else
        log_msg "ERROR" "Fallo al generar reporte (código $status). Temporal: $tmp_out"
        echo "Error al generar el reporte (codigo $status). Revise el archivo temporal $tmp_out" >&2
        return $status
    fi
}

# Bucle principal con reintentos
log_msg "INFO" "Iniciando reporte para servicio $SERVICE_NAME"
for attempt in $(seq 1 $MAX_RETRIES); do
    log_msg "INFO" "Intento $attempt de $MAX_RETRIES"
    echo "Intento $attempt para el servicio $SERVICE_NAME"
    if generate_report; then
        log_msg "INFO" "Proceso completado con éxito."
        exit 0
    else
        if [ $attempt -lt $MAX_RETRIES ]; then
            log_msg "WARNING" "Intento $attempt falló. Reintentando en $RETRY_DELAY segundos..."
            echo "Intento $attempt fallo. Reintentando en $RETRY_DELAY segundos..." >&2
            sleep $RETRY_DELAY
        else
            log_msg "ERROR" "Todos los $MAX_RETRIES intentos fallaron."
            echo "ERROR: Todos los $MAX_RETRIES intentos fallaron." >&2
            exit 1
        fi
    fi
done