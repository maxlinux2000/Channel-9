#!/bin/bash
### build_whisper_deb.sh - Compila whisper.cpp y crea paquete .deb

# --- Variables de Configuración ---
WHISPER_VERSION="1.4.0" 
PACKAGE_NAME="whisper-cpp-cli"
INSTALL_PREFIX="/opt/whisper-cpp"
BUILD_DIR="whisper.cpp_build"
MODEL=small  # modelo linguistico
FPM_ARCH="$(dpkg --print-architecture)"

# --- Variables de Arquitectura y Repositorio ---
ARCH=$(dpkg --print-architecture)
# Ruta donde se guardará el paquete .deb final
REPO_PATH="${HOME}/public_html/ch9/debian/pool/${ARCH}" 
# Nombre del archivo DEB, siguiendo la convención: nombre_version-modelo_arch.deb
DEB_FILENAME="${PACKAGE_NAME}_${WHISPER_VERSION}-${MODEL}_${ARCH}.deb"

# DIRECTORIO TEMPORAL DE FPM (para robustez)
FPM_TMP_BASE="fpm_whisper_temp"
export ABSOLUTE_FPM_TMP_PATH="$(pwd)/${FPM_TMP_BASE}" 
export TMPDIR="$ABSOLUTE_FPM_TMP_PATH"
export TEMP="$ABSOLUTE_FPM_TMP_PATH"
export FPM_TEMP="$ABSOLUTE_FPM_TMP_PATH"

# --- 1. Control de Dependencias ---

echo "1. Verificando dependencias necesarias (git, cmake, make, ruby, fpm)..."

command -v git >/dev/null 2>&1 || {
    echo "⚙️ Instalando git..."
    sudo apt install git -y
}
command -v cmake >/dev/null 2>&1 || {
    echo "⚙️ Instalando cmake..."
    sudo apt install cmake -y
}
command -v make >/dev/null 2>&1 || {
    echo "⚙️ Instalando make..."
    sudo apt install make -y
}

# Instalar Ruby y fpm si no están presentes
command -v ruby >/dev/null 2>&1 || {
    echo "⚙️ Instalando Ruby y Ruby-Dev (necesario para fpm)..."
    sudo apt install ruby ruby-dev -y
}
command -v fpm >/dev/null 2>&1 || {
    echo "⚙️ Instalando fpm (Fast Package Manager)..."
    sudo gem install fpm
}

echo "Dependencias verificadas. Continuando con la compilación..."

# --- 2. Preparar Entorno ---
rm -rf "$BUILD_DIR" "$FPM_TMP_BASE"
mkdir -p "$BUILD_DIR" "$FPM_TMP_BASE"
cd "$BUILD_DIR" || exit 1

# --- 3. Descargar y Compilar whisper.cpp ---
echo "2. Descargando y compilando whisper.cpp..."
git clone https://github.com/ggerganov/whisper.cpp.git .
make clean
# Compilamos, el binario 'whisper-cli' se crea en build/bin/
make || { echo "Error en la compilación de whisper.cpp."; exit 1; }

# --- 4. Descargar el Modelo  ---
echo "3. Descargando el modelo ggml-$MODEL.bin..."
bash ./models/download-ggml-model.sh "$MODEL" || { echo "Error al descargar el modelo."; exit 1; }

# --- 5. Preparar la Estructura de Instalación Temporal ---
echo "4. Creando la estructura temporal en staging..."
STAGING_DIR="../whisper_staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR/$INSTALL_PREFIX/bin"
mkdir -p "$STAGING_DIR/$INSTALL_PREFIX/models"

# 5.1. Mover el ejecutable principal al staging
EXECUTABLE_NAME="whisper-cli"
cp "./build/bin/${EXECUTABLE_NAME}" "$STAGING_DIR/$INSTALL_PREFIX/bin/main" # Renombrado a 'main'
chmod +x "$STAGING_DIR/$INSTALL_PREFIX/bin/main"

# 5.2. Mover librerías compartidas (libwhisper y libggml)
echo "INFO: Copiando librerías compartidas .so a la carpeta bin..."
# Se asume que libwhisper.so y libggml.so están en build/src o build/ggml/src
find ./build -name "*.so*" -exec cp {} "$STAGING_DIR/$INSTALL_PREFIX/bin/" \;

# 5.3. Mover el modelo al staging
cp "./models/ggml-${MODEL}.bin" "$STAGING_DIR/$INSTALL_PREFIX/models/"

# --- 6. Crear el Paquete .deb con fpm y moverlo al Repositorio ---
echo "5. Creando el paquete .deb (${DEB_FILENAME})..."
echo "INFO: El paquete se guardará en: ${REPO_PATH}"

cd "$STAGING_DIR" || exit 1
mkdir -p "${REPO_PATH}" # Crear la estructura de directorios del repositorio (si no existe)

# CRÍTICO: Usamos las variables de arquitectura y repositorio en -p
fpm -s dir -t deb --force \
    -n "$PACKAGE_NAME" \
    -v "$WHISPER_VERSION" \
    -a "$ARCH" \
    --description "Lightweight C++ port of OpenAI's Whisper for transcription (Modelo: ${MODEL})." \
    --depends "libopenblas0" \
    --depends "libgomp1" \
    --url "https://github.com/ggerganov/whisper.cpp" \
    --category "sound" \
    --maintainer "Channel9 Project <ch9@mi.atalaya>" \
    -p "${REPO_PATH}/${DEB_FILENAME}" \
    --prefix / \
    . || { echo "Error al crear el paquete .DEB."; exit 1; }

# --- 7. Limpieza ---
cd ..
rm -rf "$BUILD_DIR" 
rm -rf "$STAGING_DIR"
rm -rf "$FPM_TMP_BASE"

echo "=========================================================="
echo "✅ ¡PAQUETE WHISPER .DEB CREADO CON ÉXITO!"
echo "Paquete: ${REPO_PATH}/${DEB_FILENAME}"
echo "El ejecutable se instala en: ${INSTALL_PREFIX}/bin/main"
echo "=========================================================="
