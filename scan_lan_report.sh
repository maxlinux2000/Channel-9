#!/bin/bash

# ==============================================================================
# SCRIPT: scan_lan_report_v15.sh
# DESCRIPCION: Escanea la red local, reportando IP, MAC, Nombre de Host y Fabricante.
# REQUIERE: nmap, dnsutils, iproute2, curl/wget, sed.
# ==============================================================================

# Archivo de base de datos OUI (Original)
OUI_DATABASE="mac_ouis.txt"
# Archivo de base de datos OUI (NORMALIZADO TEMPORAL)
OUI_NORM_DATABASE="mac_ouis.norm.txt"
# URL de un listado OUI plano
OUI_URL="https://standards-oui.ieee.org/oui/oui.txt"

# Lista de herramientas requeridas y sus paquetes correspondientes
declare -A TOOLS
TOOLS=(
    ["nmap"]="nmap"
    ["dig"]="dnsutils"
    ["ip"]="iproute2"
    ["curl"]="curl"
    ["sed"]="sed" # Aseguramos que sed esté
)

CAN_SCAN=true

# --- TRAP: Limpieza al finalizar el script (incluso si falla) ---
# Nos aseguramos de borrar el archivo temporal normalizado
trap 'rm -f "$OUI_NORM_DATABASE"' EXIT

echo "--- Verificando y preparando dependencias ---"

# --- 1. Verificación e Instalación de Dependencias (SIN CAMBIOS) ---
for TOOL in "${!TOOLS[@]}"; do
    PACKAGE=${TOOLS[$TOOL]}
    if ! command -v "$TOOL" &> /dev/null; then
        echo "🚨 ADVERTENCIA: La herramienta '$TOOL' (paquete '$PACKAGE') no está instalada."
        
        if [[ $(id -u) -eq 0 ]]; then
            echo "Instalando $PACKAGE..."
            if apt update > /dev/null 2>&1 && apt install -y "$PACKAGE" > /dev/null 2>&1; then
                echo "✅ $TOOL instalado correctamente."
            else
                echo "❌ Falló la instalación de $TOOL. El script puede funcionar de forma limitada."
                if [ "$TOOL" == "nmap" ]; then CAN_SCAN=false; fi
            fi
        else
            echo "Por favor, instale '$PACKAGE' manualmente con 'sudo apt install $PACKAGE' para funcionalidad completa."
            if [ "$TOOL" == "nmap" ]; then CAN_SCAN=false; fi
        fi
    fi
done
echo "------------------------------------------------"

# --- 1.5. Verificación y Descarga/Normalización de Base de Datos OUI (NORMALIZACIÓN FINAL) ---
FABRICANTE_DISPONIBLE=false

# 1. Descarga el archivo original si no existe (SIN FILTRO)
if [ ! -f "$OUI_DATABASE" ]; then
    echo "⚠️ Base de datos MAC/OUI original no encontrada. Descargando..."
    if command -v curl &> /dev/null; then
        if curl -s -L "$OUI_URL" > "$OUI_DATABASE"; then
            echo "✅ Base de datos original descargada."
        else
            echo "❌ Falló la descarga de la base de datos OUI. El campo 'Fabricante' será N/A."
        fi
    else
        echo "❌ 'curl' no está disponible. No se puede descargar la base de datos OUI. El campo 'Fabricante' será N/A."
    fi
fi

# 2. Si el archivo original existe, NORMALIZARLO en el archivo temporal
if [ -f "$OUI_DATABASE" ]; then
    echo "⚙️ Creando base de datos OUI normalizada temporal: $OUI_NORM_DATABASE (Formato XXXXXX#Nombre)"
    
    # Lógica de normalización basada en la secuencia de comandos del usuario:
    # 1. Filtramos solo las líneas que contienen "base 16" (que tienen el OUI sin guiones y el nombre).
    # 2. Reemplazamos los tabuladores por #.
    # 3. Limpiamos la cadena "       (base 16)#" del medio.
    # 4. Filtramos líneas vacías y encabezados.
    if cat "$OUI_DATABASE" | grep "base 16" | tr '\t' '#' | sed 's|     (base 16)#||g' | grep -v '^\s*$' | grep -v '^OUI' > "$OUI_NORM_DATABASE.tmp"; then
        
        # Eliminar el espacio extra que queda al inicio/final si lo hubiera
        sed -i 's/^[[:space:]]*//;s/[[:space:]]*$//' "$OUI_NORM_DATABASE.tmp"
        
        mv "$OUI_NORM_DATABASE.tmp" "$OUI_NORM_DATABASE"
        echo "✅ Base de datos normalizada lista para la búsqueda."
        FABRICANTE_DISPONIBLE=true
    else
        echo "❌ Falló la normalización de la base de datos OUI. El campo 'Fabricante' será N/A."
        FABRICANTE_DISPONIBLE=false
    fi
fi
echo "------------------------------------------------"

# --- 2. Determinación del Rango de Red Local (SIN CAMBIOS) ---
if ! command -v ip &> /dev/null; then
    echo "❌ ERROR: 'ip' no está disponible. No se puede determinar el rango de red local. Abortando."
    exit 1
fi

LOCAL_IP=$(ip a | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -n 1)
if [ -z "$LOCAL_IP" ]; then
    echo "❌ ERROR: No se pudo determinar la dirección IP local. Verifique la conexión de red."
    exit 1
fi

NETWORK_RANGE=$(echo "$LOCAL_IP" | awk -F '.' '{print $1"."$2"."$3".0"}' | cut -d '/' -f 1)/24
echo "🌐 Rango de la red local detectado: $NETWORK_RANGE"

# --- 3. Escaneo Activo con Nmap (SIN CAMBIOS) ---
if $CAN_SCAN; then
    echo "Ejecutando escaneo Nmap (ARP Ping) para añadir hosts a la caché ARP existente..."
    nmap -sP -PR -n "$NETWORK_RANGE" > /dev/null 2>&1
else
    echo "⚠️ Nmap no está disponible. Usando solo la caché ARP existente (el reporte será limitado)."
fi

# --- FUNCION AUXILIAR: Obtener fabricante (USANDO FORMATO XXXXXX#Nombre) ---
get_manufacturer() {
    local MAC_FULL=$1
    
    # 1. Transformamos la MAC a 6 caracteres sin separadores, en mayúsculas (Formato XXXXXX)
    local OUI_KEY=$(echo "$MAC_FULL" | tr -d ':' | tr '[:lower:]' '[:upper:]' | cut -c 1-6)

    # 2. Buscamos la clave exacta en el archivo normalizado (XXXXXX#Nombre)
    local MANUFACTURER_LINE=$(cat "$OUI_NORM_DATABASE" | grep "${OUI_KEY}#")

    if [ -z "$MANUFACTURER_LINE" ]; then
        echo "Desconocido"
    else
        # 3. Usamos cut para extraer el campo 2 (el nombre del fabricante)
        # Se añade cut -c 1-20 para asegurar que el nombre no desborde la columna de la tabla.
        echo "$MANUFACTURER_LINE" | cut -d '#' -f 2 | cut -c 1-20 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
    fi
}


# --- 4. Generación del Reporte (SIN CAMBIOS) ---

echo ""
echo "=================================================================================="
echo "         INFORME DE DISPOSITIVOS CONECTADOS EN LA LAN    "
echo "=================================================================================="
printf "%-18s | %-18s | %-20s | %s\n" "IP" "MAC" "FABRICANTE" "NOMBRE DE HOST"
echo "-------------------*-------------------*----------------------*-------------------"

ARP_CLEAN_OUTPUT=$(arp -a | grep -v '<incomplete>')

echo "$ARP_CLEAN_OUTPUT" | while IFS= read -r LINE; do
    
    IP=$(echo "$LINE" | awk '{ gsub(/[()]/,"",$2); print $2 }')
    MAC=$(echo "$LINE" | awk '{ print $4 }' | tr '[:upper:]' '[:lower:]')

    if [[ "$IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && [ -n "$MAC" ]; then
        
        HOST_NAME=""
        if command -v dig &> /dev/null; then
            HOST_NAME=$(dig -x "$IP" +short | sed 's/\.$//' | tr -d '\n')
        fi
        
        if [ -z "$HOST_NAME" ]; then
             HOST_NAME=$(echo "$LINE" | awk '{ print $1 }' | sed 's/[[:space:]]*$//; s/^\?//; s/^[[:space:]]*//')
        fi
        
        if [ -z "$HOST_NAME" ]; then
            HOST_NAME="Desconocido"
        fi
        
        if $FABRICANTE_DISPONIBLE; then
            MANUFACTURER=$(get_manufacturer "$MAC")
        else
            MANUFACTURER="N/A (Sin Base OUI)"
        fi

        printf "%-18s | %-18s | %-20s | %s\n" "$IP" "$MAC" "$MANUFACTURER" "$HOST_NAME"
    fi
done

echo "=================================================================================="
echo "Fin del informe."
