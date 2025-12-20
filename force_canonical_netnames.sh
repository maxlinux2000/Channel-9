#!/bin/bash
### force_canonical_netnames.sh - Fuerza los nombres de interfaz canónicos (eth0/wlan0) en amd64

# --- Variables y Constantes ---
REQUIRED_GRUB_OPTS="net.ifnames=0 biosdevname=0"
GRUB_FILE="/etc/default/grub"
ARCH=$(dpkg --print-architecture)

echo "⚙️ Ejecutando chequeo de nombres de interfaz de red..."
echo "Arquitectura detectada: $ARCH"

# --- 1. Detección de Nombres de Interfaz No Canónicos ---
# Busca interfaces activas que NO sean 'lo', 'eth*', 'wlan*', o 'br*' (bridge).
# Si encuentra otros (ej. enpXsX, enoX, wlpXsX), asume que se usan nombres persistentes.
NON_CANONICAL_INTERFACES=$(ip a | awk '/^[0-9]: / {print $2}' | sed 's/://' | grep -vE '^(lo|eth|wlan|br|veth)')

if [ -z "$NON_CANONICAL_INTERFACES" ]; then
    echo "✅ Los nombres de interfaz canónicos (eth0, wlan0) parecen estar en uso o no hay interfaces activas."
    exit 0
fi

echo "⚠️ Nombres de interfaz no canónicos detectados: $NON_CANONICAL_INTERFACES"

# --- 2. Condición de Arquitectura ---
# La modificación de GRUB se aplica solo en amd64, como ha solicitado.
if [ "$ARCH" != "amd64" ]; then
    echo "ℹ️ La modificación de GRUB para forzar eth0/wlan0 se aplica solo en arquitectura amd64. Omitiendo modificación."
    exit 0
fi

# --- 3. Aplicar Modificación de GRUB (Solo AMD64) ---

echo "⚙️ Aplicando corrección para forzar nombres canónicos..."

# 3.1. Leer la línea actual de GRUB_CMDLINE_LINUX
CURRENT_GRUB_CMDLINE=$(grep '^GRUB_CMDLINE_LINUX=' "$GRUB_FILE" | head -n 1)

# 3.2. Extraer el contenido dentro de las comillas (ej. "quiet splash")
CURRENT_CONTENT=$(echo "$CURRENT_GRUB_CMDLINE" | sed 's/GRUB_CMDLINE_LINUX=//; s/^"//; s/"$//')

# 3.3. Añadir las opciones requeridas si no existen
NEW_CONTENT="$CURRENT_CONTENT"

# Añadir 'net.ifnames=0' si no está presente
if ! echo "$NEW_CONTENT" | grep -q 'net.ifnames=0'; then
    NEW_CONTENT="$NEW_CONTENT net.ifnames=0"
fi

# Añadir 'biosdevname=0' si no está presente
if ! echo "$NEW_CONTENT" | grep -q 'biosdevname=0'; then
    NEW_CONTENT="$NEW_CONTENT biosdevname=0"
fi

# Limpiar espacios en blanco al inicio/final y duplicados
NEW_CONTENT=$(echo "$NEW_CONTENT" | xargs)

# 3.4. Reemplazar la línea en el archivo utilizando sed
echo "Modificando $GRUB_FILE para incluir: '$REQUIRED_GRUB_OPTS'"
# El comando 'c\' reemplaza toda la línea coincidente.
sudo sed -i "/^GRUB_CMDLINE_LINUX=/c\GRUB_CMDLINE_LINUX=\"$NEW_CONTENT\"" "$GRUB_FILE"

# 3.5. Actualizar GRUB (sin reiniciar)
echo "Ejecutando update-grub. Los cambios se aplicarán al kernel. (No se reinicia ahora)."
sudo update-grub

echo "✅ Modificación de GRUB aplicada con éxito."
echo "Recuerde: Se necesita un reinicio (reboot) al final de la instalación para que los nombres 'eth0' y 'wlan0' sean efectivos."

