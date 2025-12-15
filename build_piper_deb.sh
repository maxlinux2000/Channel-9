#!/bin/bash
### build_piper_deb.sh - Crea el paquete DEB base para Piper TTS (Binario y Venv)

# --- Variables de Configuración Global ---
PIPER_VERSION="1.2.0"
INSTALL_PREFIX="/opt/piper" # Ruta final del sistema para el Venv
PACKAGE_NAME_BASE="piper-tts"
BUILD_DIR="piper_build_staging" # Directorio temporal de trabajo
PIPER_REPO="https://github.com/rhasspy/piper"

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

# --- 2. Preparar Entorno Temporal (Base) ---
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
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

# --- 4. Crear el Paquete .deb BASE (piper-tts.deb) ---
echo "3. Creando el paquete .deb BASE (piper-tts.deb)..."
cd .. # Volvemos al directorio raíz para FPM

rm -f ${PACKAGE_NAME_BASE}-${PIPER_VERSION}.deb

fpm -s dir -t deb --force \
    --before-install "$BASE_PRE_INSTALL_SCRIPT" \
    -n "$PACKAGE_NAME_BASE" \
    -v "$PIPER_VERSION" \
    -a "$(dpkg --print-architecture)" \
    --description "Piper TTS: Motor ligero de Texto-a-Voz (Binario Base)." \
    --depends "libgomp1" \
    --depends "libespeak-ng1" \
    --url "$PIPER_REPO" \
    --category "utils" \
    --maintainer "Max <max@example.com>" \
    -p "${PACKAGE_NAME_BASE}-${PIPER_VERSION}.deb" \
    -C "$BUILD_DIR" \
    --exclude '**.pyc' \
    --exclude '**__pycache__**' \
    --exclude '**.dist-info**' \
    --exclude '**.egg-info**' \
    --exclude '**/include/**' \
    --exclude '**/man/**' \
    --exclude '**/tests/**' \
    --exclude '**/test/**' \
    opt usr || { echo "Error al crear el paquete BASE."; rm "$BASE_PRE_INSTALL_SCRIPT" 2>/dev/null; exit 1; } 
    
# --- 5. Limpieza Final ---
rm -rf "$BUILD_DIR"
rm "$BASE_PRE_INSTALL_SCRIPT" 2>/dev/null

echo "=========================================================="
echo "✅ ¡PAQUETE BASE PIPER .DEB CREADO CON ÉXITO!"
echo "Paquete: ${PACKAGE_NAME_BASE}-${PIPER_VERSION}.deb"
echo "=========================================================="
