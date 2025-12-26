#!/bin/bash
### collect_dependencies.sh - Descarga las dependencias de los paquetes clave para el repositorio offline.

# --- Variables de Configuración ---
REPO_POOL_BASE="${HOME}/public_html/ch9/debian/pool"
DOWNLOAD_TEMP_DIR="./temp_dependencies_download"
# Detectar la arquitectura actual (ej: amd64, armhf, arm64)
ARCH="$(dpkg --print-architecture)"

# --- Detección de Plataforma ---

# Función para detectar si el sistema es Raspberry Pi OS (o basado en él)
is_raspberry_pi_os() {
    # 1. Comprobar /etc/os-release (Busca Raspbian o similares)
    if grep -q "Raspbian" /etc/os-release 2>/dev/null || grep -q "raspi" /etc/os-release 2>/dev/null; then
        return 0 # Es Raspberry Pi OS
    # 2. Comprobar si es un ARM y si hay archivos específicos de RPi (Alternativa para máquinas virtuales ARM)
    elif [[ "$ARCH" == "armhf" || "$ARCH" == "arm64" ]] && [ -d /boot/firmware/overlays ]; then
        return 0 # Es ARM y tiene estructura de RPi
    else
        return 1 # No es RPi
    fi
}

# --- Lista de Paquetes a Descargar ---
if is_raspberry_pi_os; then
    echo "INFO: Detectado entorno Raspberry Pi OS ($ARCH). Descargando un conjunto ampliado de paquetes base."
    # Lista ampliada para RPi (incluyendo elementos de escritorio y configuración comunes)
    TARGET_PACKAGES=(
        "raspberrypi-bootloader" "raspi-config" "firmware-realtek"
        "xserver-xorg" "task-xfce-desktop" "plymouth" "pi-package-archive-keyring"
        "python3-rpi.gpio" "libcamera-apps" "openssh-server"
        "apache2" "sox" "ffmpeg" "libsox-fmt-all" "python3" "python3-venv" 
        "yad" "mailutils" "libglib2.0-dev" "bind9" "postfix" "dovecot-imapd" "dovecot-pop3d"
    )
else
    echo "INFO: Detectado entorno estándar (Debian/$ARCH). Descargando solo paquetes esenciales para Channel-9."
    # Lista minimalista enfocada en Channel-9 (suficiente para la mayoría de sistemas x86/amd64/arm64)
    TARGET_PACKAGES=(
        "apache2" "sox" "ffmpeg" "libsox-fmt-all" "python3" "python3-venv" 
        "yad" "mailutils" "libglib2.0-dev" "bind9" "postfix" "dovecot-imapd" "dovecot-pop3d"
    )
fi


# --- 1. Control de Dependencias y Limpieza ---
echo "--- 1. Preparando entorno de descarga ---"

command -v apt-get >/dev/null 2>&1 || { 
    echo "🚨 Error: apt-get no está disponible. ¿Estás usando Debian/Ubuntu?"
    exit 1
}

rm -rf "$DOWNLOAD_TEMP_DIR" # Limpieza inicial
mkdir -p "$DOWNLOAD_TEMP_DIR"
mkdir -p "$REPO_POOL_BASE/$ARCH"
mkdir -p "$REPO_POOL_BASE/all"

echo "INFO: Descargando paquetes en $DOWNLOAD_TEMP_DIR. Arquitectura: $ARCH"

# --- 2. Descarga de Dependencias ---
echo "--- 2. Descargando archivos .deb (incluyendo dependencias recursivas) ---"

# Usamos 'install --reinstall --download-only' para forzar la descarga de todos,
# incluyendo dependencias, y `-o Dir::Cache::archives` para forzar la ubicación.
# Usamos DEBIAN_FRONTEND=noninteractive para evitar diálogos interactivos (ej: Postfix)
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --reinstall --download-only "${TARGET_PACKAGES[@]}" -o Dir::Cache::archives="$DOWNLOAD_TEMP_DIR"

if [ $? -ne 0 ]; then
    echo "🚨 Error: Fallo al descargar algunos paquetes. Revise la lista de paquetes y la conexión a Internet."
    rm -rf "$DOWNLOAD_TEMP_DIR"
    exit 1
fi

echo "✅ Descarga completada."

# --- 3. Clasificación y Movimiento al Repositorio ---
echo "--- 3. Clasificando y moviendo paquetes a la estructura del repositorio ---"

# Mover archivos .deb a la estructura de pool
find "$DOWNLOAD_TEMP_DIR" -maxdepth 1 -name "*.deb" -print0 | while IFS= read -r -d $'\0' DEB_FILE; do
    
    FILENAME=$(basename "$DEB_FILE")
    
    # Obtener la arquitectura del paquete del nombre de archivo (ej: 'paquete_1.0_amd64.deb' -> 'amd64')
    # Este es un método más seguro que sólo mirar '_all.deb'
    PKG_ARCH=$(echo "$FILENAME" | sed -E 's/.*_([^_]+)\.deb$/\1/')
    
    if [ "$PKG_ARCH" == "all" ]; then
        DEST_DIR="$REPO_POOL_BASE/all"
    elif [ "$PKG_ARCH" == "$ARCH" ]; then
        DEST_DIR="$REPO_POOL_BASE/$ARCH"
    else
        # Esto sucede si el paquete es para otra arquitectura que no sea la nuestra (ej: i386)
        # Por simplicidad, si no es 'all' o nuestra arquitectura, lo ignoramos.
        echo "Advertencia: Ignorando paquete con arquitectura inesperada: $FILENAME"
        continue
    fi
    
    # Mover el archivo (sustituir si existe)
    mv -f "$DEB_FILE" "$DEST_DIR/"
    echo "Movido $FILENAME a $DEST_DIR/"
done

# --- 4. Limpieza y Finalización ---
echo "--- 4. Limpieza y Finalización ---"
rm -rf "$DOWNLOAD_TEMP_DIR"

echo "=========================================================="
echo "✅ COLECCIÓN DE DEPENDENCIAS COMPLETADA."
echo "   - Paquetes .deb descargados y movidos a: ${REPO_POOL_BASE}"
echo "   - ¡Siga con la creación de sus paquetes clave y luego ejecute 'generate_local_repo.sh'!"
echo "=========================================================="

./generate_local_repo.sh
