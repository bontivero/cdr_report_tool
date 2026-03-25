#!/bin/bash
# Versión final para Bash 3.x con soporte para archivos comprimidos o no
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

mkdir -p "$OUTPUT_DIR"
OUTPUT_FILE="${OUTPUT_DIR}/cdr_report_${SERVICE_NAME}_$(date +%Y%m%d).txt"

# Validaciones básicas
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
    echo "ERROR: Debe definir FIELD_SEPARATOR+DATE_FIELD_INDEX o DATE_FIELD_START+DATE_FIELD_LENGTH."
    exit 1
fi

# Determinar el comando de descompresión según COMPRESSED
if [ "$COMPRESSED" = "true" ]; then
    DECOMPRESS_CMD="zcat"
else
    DECOMPRESS_CMD="cat"
fi

# Función para contar CDRs
count_cdrs() {
    local proc_dir="$1"
    local target_string="$2"
    local count=0
    if [ -d "$proc_dir" ]; then
        if [ "$EXTRACTION_MODE" = "separator" ]; then
            count=$(find "$proc_dir" -maxdepth 1 -type f -name "$FILE_PATTERN" -print0 2>/dev/null | \
                    xargs -0 -r "$DECOMPRESS_CMD" 2>/dev/null | \
                    awk -F"$FIELD_SEPARATOR" -v idx="$DATE_FIELD_INDEX" -v val="$target_string" \
                        '$idx == val {c++} END {print c+0}')
        else
            count=$(find "$proc_dir" -maxdepth 1 -type f -name "$FILE_PATTERN" -print0 2>/dev/null | \
                    xargs -0 -r "$DECOMPRESS_CMD" 2>/dev/null | \
                    awk -v start="$DATE_FIELD_START" -v len="$DATE_FIELD_LENGTH" -v val="$target_string" \
                        '{ if (substr($0, start, len) == val) c++ } END {print c+0}')
        fi
    fi
    echo "$count"
}

generate_report() {
    # Variable global dentro de la función (sin local) para que el trap la vea
    tmp_out=$(mktemp -p "$OUTPUT_DIR" reporte_XXXXXX.txt)
    # Trap con expansión inmediata (comillas simples externas y dobles internas)
    trap "rm -f '$tmp_out'" EXIT

    (
        set +e   # Desactivamos 'errexit' para evitar abortos por errores menores
        # Cabecera
        echo "*************************************($(date +"%d/%m/%Y-%H:%M"))************************************"
        echo "  "
        echo "SERVICIO DE $SERVICE_NAME" 
        echo "***********************"

        for cdr_offset in ${CDR_OFFSETS[@]}; do
            target_string=$(date -d "$cdr_offset days" +"$DATE_FIELD_FORMAT")
            cdr_display=$(date -d "$cdr_offset days" +%d/%m/%Y)
            echo "CDRs DEL DIA $cdr_display"
            echo "--------------------------------------------"

            offset_clean="${cdr_offset#-}"
            var_name="PROC_OFFSETS_${offset_clean}"
            proc_offsets=(${!var_name})

            for proc_offset in "${proc_offsets[@]}"; do
                proc_dir="${BASE_PATH}/$(date -d "$proc_offset days" +%Y%m%d)"
                proc_display=$(date -d "$proc_offset days" +%d/%m/%Y)
                count=$(count_cdrs "$proc_dir" "$target_string")
                echo "Procesados en el dia ($proc_display): $count   "
            done
            echo "  "
        done

        echo "### REPORT COMPLETED SUCCESSFULLY ON $(date) ###"
    ) > "$tmp_out" 2>&1
    local status=$?
    if [ $status -eq 0 ]; then
        mv "$tmp_out" "$OUTPUT_FILE"
        echo "Reporte guardado en $OUTPUT_FILE"
        return 0
    else
        echo "Error al generar el reporte (codigo $status). Revise el archivo temporal $tmp_out" >&2
        return $status
    fi
}

for attempt in $(seq 1 $MAX_RETRIES); do
    echo "Intento $attempt para el servicio $SERVICE_NAME"
    if generate_report; then
        exit 0
    else
        if [ $attempt -lt $MAX_RETRIES ]; then
            echo "Intento $attempt fallo. Reintentando en $RETRY_DELAY segundos..." >&2
            sleep $RETRY_DELAY
        else
            echo "ERROR: Todos los $MAX_RETRIES intentos fallaron." >&2
            exit 1
        fi
    fi
done