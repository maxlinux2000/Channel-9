#!/bin/bash
# ==============================================================================
# SCRIPT: CH9.sh - Conmutador Principal de Modos de Operación (Channel-9)
#
# DESCRIPCIÓN:
# Carga el modo de operación desde la configuración y lanza el script 
# especializado (Loro, Secretaría, o Monitor CB).
#
# ==============================================================================

# 1. CARGA DE CONFIGURACIÓN CRÍTICA
# Usamos el nombre de archivo de configuración que genera CH9-config.sh
CONFIG_FILE="$HOME/.CH9-config"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "🚨 ERROR: Archivo de configuración ($CONFIG_FILE) no encontrado." >&2
    echo "Ejecutando el programa de configuración..." >&2
    # El nombre real del script de configuración es CH9-config.sh (antes loro-config.sh)
    CH9-config.sh
    # Reintentar cargar la configuración después de la ejecución
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "🚨 ERROR: La configuración no pudo ser generada. Abortando." >&2
        exit 1
    fi
fi

# Cargar las variables de entorno, incluyendo OPERATION_MODE
source "$CONFIG_FILE"

# 2. LANZAMIENTO DEL MODO ESPECÍFICO

case "$OPERATION_MODE" in
    1)
        echo "INFO: Iniciando modo 1 (Loro/Parrot)..."
        exec CH9_loro.sh
        ;;
    2)
        echo "INFO: Iniciando modo 2 (Secretaría Telefónica)..."
        exec CH9_secretaria.sh
        ;;
    3)
        echo "INFO: Iniciando modo 3 (Monitor CB/Alerta)..."
        exec CH9_monitor.sh
        ;;
    *)
        echo "🚨 ERROR: Modo de operación no válido ($OPERATION_MODE). Verifica $CONFIG_FILE." >&2
        exit 1
        ;;
esac

exit 0

