#!/bin/bash
### build_piper_deb.sh - Crea el paquete DEB base para Piper TTS (Binario y Venv)

# --- Variables de Configuración Global ---
# Versión por defecto para la mayoría de las arquitecturas (AMD64, etc.)
PIPER_VERSION="1.2.0" 
ARCH=$(dpkg --print-architecture)
INSTALL_PREFIX="/opt/piper" # Ruta final del sistema para el Venv
PACKAGE_NAME_BASE="piper-tts"
BUILD_DIR="piper_build_staging" # Directorio temporal de trabajo
PIPER_REPO="https://github.com/rhasspy/piper"

# --- Variables de Repositorio (NUEVAS) ---
# Ruta donde se guardará el paquete .deb final
REPO_PATH="${HOME}/public_html/ch9/debian/pool/${ARCH}" 
# Nombre del archivo DEB, siguiendo la convención: nombre_version_arch.deb
DEB_FILENAME="${PACKAGE_NAME_BASE}_${PIPER_VERSION}_${ARCH}.deb"

# DIRECTORIO TEMPORAL DE FPM (para robustez)
FPM_TMP_PATH="fpm_piper_temp_dir" 
# La ruta absoluta que EXPORTAREMOS
export ABSOLUTE_FPM_TMP_PATH="$(pwd)/$FPM_TMP_PATH" 
# CRÍTICO: Forzar el uso de la ruta de disco duro en lugar de /tmp (tmpfs)
export TMPDIR="$ABSOLUTE_FPM_TMP_PATH"
export TEMP="$ABSOLUTE_FPM_TMP_PATH"
export FPM_TEMP="$ABSOLUTE_FPM_TMP_PATH"

# --- Scripts Temporales para fpm ---
BASE_PRE_INSTALL_SCRIPT="base-pre-install.sh"

# Comandos de pre-instalación
echo "echo 'Instalando binario Piper TTS...'" > "$BASE_PRE_INSTALL_SCRIPT"
chmod +x "$BASE_PRE_INSTALL_SCRIPT"

# --- 1. Control de Dependencias ---
echo "1. Verificando e instalando dependencias (python3-venv, fpm, dependencias runtime)..."
sudo apt update
sudo apt install -y python3 python3-venv wget ruby ruby-dev build-essential
command -v fpm >/dev/null 2>&1 || { 
    echo "⚙️ Instalando fpm (Fast Package Manager)..."
    sudo gem install fpm
}

# --- 2. Preparar Entorno Temporal (Base) (MODIFICADO) ---
rm -rf "$BUILD_DIR" "$FPM_TMP_PATH"
mkdir -p "$BUILD_DIR"
mkdir -p "$FPM_TMP_PATH" # Creamos el directorio temporal para fpm
cd "$BUILD_DIR" || exit 1

# Creamos la estructura de directorios de destino DENTRO del BUILD_DIR
mkdir -p ".$INSTALL_PREFIX/venv"
mkdir -p "./usr/local/bin" 

# --- 3. Instalar Piper Base en entorno virtual local (y corregir Shebang) ---
echo "2. Instalando Piper BASE en entorno virtual..."
python3 -m venv ".$INSTALL_PREFIX/venv" 
VENV_PIP="./$INSTALL_PREFIX/venv/bin/pip" 
"$VENV_PIP" install piper-tts=="$PIPER_VERSION" || { echo "Error al instalar piper-tts."; exit 1; }


echo " -> Corrigiendo Shebang del script 'piper' dentro del Venv..."
VENV_PYTHON_SCRIPT="./$INSTALL_PREFIX/venv/bin/piper"
# Usamos una ruta absoluta al intérprete del Venv para asegurar el aislamiento
sed -i '1s|.*|#!'"$INSTALL_PREFIX"'/venv/bin/python3|' "$VENV_PYTHON_SCRIPT"


# Crear script wrapper para ejecutar Piper (Usando el módulo Python directamente para mayor limpieza)
PIPER_WRAPPER="./usr/local/bin/piper"
cat <<EOT > "$PIPER_WRAPPER"
#!/bin/bash
# Script Wrapper para ejecutar Piper (usando el modulo python del venv)
exec $INSTALL_PREFIX/venv/bin/python3 -m piper "\$@"
EOT
chmod +x "$PIPER_WRAPPER"

# --- 4. Crear el Paquete .deb BASE (piper-tts.deb) (MODIFICADO) ---
echo "3. Creando el paquete .deb BASE (${DEB_FILENAME})..."
echo "INFO: FPM usará el directorio temporal: $ABSOLUTE_FPM_TMP_PATH"
echo "INFO: El paquete se guardará en: ${REPO_PATH}/${DEB_FILENAME}"

cd .. # Volvemos al directorio raíz para FPM

# Creamos la carpeta del repositorio
mkdir -p "${REPO_PATH}"

rm -f ${PACKAGE_NAME_BASE}-${PIPER_VERSION}.deb

fpm -s dir -t deb --force \
    --before-install "$BASE_PRE_INSTALL_SCRIPT" \
    -n "$PACKAGE_NAME_BASE" \
    -v "$PIPER_VERSION" \
    -a "$ARCH" \
    --description "Piper TTS: Motor ligero de Texto-a-Voz (Binario Base)." \
    --depends "libgomp1" \
    --depends "libespeak-ng1" \
    --url "$PIPER_REPO" \
    --category "utils" \
    --maintainer "Channel9 Project <ch9@mi.atalaya>" \
    -p "${REPO_PATH}/${DEB_FILENAME}" \
    -C "$BUILD_DIR" \
    --exclude '**.pyc' \
    --exclude '**__pycache__**' \
    --exclude '**.dist-info**' \
    --exclude '**.egg-info**' \
    --exclude '**/include/**' \
    --exclude '**/man/**' \
    --exclude '**/tests/**' \
    --exclude '**/test/**' \
    opt usr || { echo "Error al crear el paquete BASE."; rm "$BASE_PRE_INSTALL_SCRIPT" 2>/dev/null; rm -rf "$FPM_TMP_PATH"; exit 1; } 
    
# --- 5. Limpieza Final (MODIFICADO) ---
rm -rf "$BUILD_DIR"
rm -rf "$FPM_TMP_PATH"
rm "$BASE_PRE_INSTALL_SCRIPT" 2>/dev/null

echo "=========================================================="
echo "✅ ¡PAQUETE BASE PIPER .DEB CREADO CON ÉXITO!"
echo "Paquete: ${REPO_PATH}/${DEB_FILENAME}"
echo "=========================================================="

