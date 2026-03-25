#!/bin/bash
# create_service_script.sh - Genera un script contenedor para un servicio
# Uso: create_service_script.sh <nombre_servicio> <ruta_config> [directorio_destino]
# Ejemplo: ./create_service_script.sh voice /etc/cdr_report/voice.conf /usr/local/bin

SERVICE="$1"
CONFIG="$2"

if [ -z "$SERVICE" ] || [ -z "$CONFIG" ]; then
    echo "Uso: $0 <nombre_servicio> <ruta_config> [directorio_destino]"
    exit 1
fi

SCRIPT_NAME="reporte_${SERVICE}.sh"
SCRIPT_PATH="${SCRIPT_DIR}/${SCRIPT_NAME}"

# Obtener la ruta absoluta del script principal (asumiendo que está en el mismo directorio que este script)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MAIN_SCRIPT="${SCRIPT_DIR}/reporte_cdr.sh"

if [ ! -f "$MAIN_SCRIPT" ]; then
    echo "ERROR: No se encontró el script principal en $MAIN_SCRIPT"
    exit 1
fi

cat > "$SCRIPT_PATH" <<EOF
#!/bin/bash
# Wrapper para el servicio $SERVICE
# Generado automáticamente por $0 el $(date)

exec "$MAIN_SCRIPT" "$CONFIG"
EOF

chmod +x "$SCRIPT_PATH"
echo "Creado $SCRIPT_PATH"