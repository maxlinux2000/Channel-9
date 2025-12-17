#!/bin/bash
### build_whisper_deb.sh - Compila whisper.cpp y crea paquete .deb

# --- Variables de Configuración ---
WHISPER_VERSION="1.4.0" 
PACKAGE_NAME="whisper-cpp-cli"
INSTALL_PREFIX="/opt/whisper-cpp"
BUILD_DIR="whisper.cpp_build"
MODEL=small  # modelo linguistico

# --- 1. Control de Dependencias ---

echo "1. Verificando dependencias necesarias (git, cmake, make, ruby, fpm)..."
# Instalar herramientas básicas de compilación si faltan
#command -v git >/dev/null 2>&1 || { echo >&2 "🚨 ALERTA: git no está instalado. Ejecute 'sudo apt install git'."; exit 1; }
#command -v cmake >/dev/null 2>&1 || { echo >&2 "🚨 ALERTA: cmake no está instalado. Ejecute 'sudo apt install cmake'."; exit 1; }
#command -v make >/dev/null 2>&1 || { echo >&2 "🚨 ALERTA: make no está instalado. Ejecute 'sudo apt install build-essential'."; exit 1; }

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



# Instalar Ruby si no está presente (necesario para fpm)
command -v ruby >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "⚙️ Instalando Ruby y Ruby-Dev (necesario para fpm)..."
    # El usuario debe ejecutar esto con sudo
#    echo "Por favor, ejecute: sudo apt install ruby ruby-dev"
    sudo apt install ruby ruby-dev -y
#    exit 1
fi

# Instalar fpm si no está presente
command -v fpm >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "⚙️ Instalando fpm (Fast Package Manager)..."
    # El usuario debe ejecutar esto
#    echo "Por favor, ejecute: sudo gem install fpm"
#    exit 1
    sudo gem install fpm
fi

echo "Dependencias verificadas. Continuando con la compilación..."

# --- 2. Preparar Entorno ---
# Eliminamos el directorio de build anterior y lo recreamos
rm -rf "$BUILD_DIR"
mkdir "$BUILD_DIR"
cd "$BUILD_DIR" || exit 1

# --- 3. Descargar y Compilar whisper.cpp ---
echo "2. Descargando y compilando whisper.cpp..."
git clone https://github.com/ggerganov/whisper.cpp.git .
make clean
# Compilamos, el binario 'main' se crea en la raíz de la compilación.
make || { echo "Error en la compilación de whisper.cpp."; exit 1; }

# --- 4. Descargar el Modelo  ---
echo "3. Descargando el modelo ggml-$MODEL.bin..."
# Este comando descarga la versión multilingual.
bash ./models/download-ggml-model.sh $MODEL || { echo "Error al descargar el modelo."; exit 1; }

# --- 5. Preparar la Estructura de Instalación Temporal ---
echo "4. Creando la estructura temporal en staging..."
STAGING_DIR="../whisper_staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR/$INSTALL_PREFIX/bin"
mkdir -p "$STAGING_DIR/$INSTALL_PREFIX/models"

# Mover el ejecutable y el modelo al staging
# 🚨 CORRECCIÓN 1: El ejecutable 'main' está en la raíz del directorio de compilación.
cp ./build/bin/whisper-cli "$STAGING_DIR/$INSTALL_PREFIX/bin/main"

# 🚨 CORRECCIÓN FINAL 1: Copiar la librería compartida (libwhisper.so.1) desde la ruta correcta.
# 🚨 CORRECCIÓN FINAL 2: Copiar todas la librerías compartida.
cp ./build/src/libwhisper.so.1 "$STAGING_DIR/$INSTALL_PREFIX/bin/"

# 📢 NUEVA CORRECCIÓN: Copiar la dependencia faltante libggml.so.0 desde la ruta de compilación
# Esta librería causó el error "cannot open shared object file"
#cp ./build/ggml/src/libggml.so.0 "$STAGING_DIR/$INSTALL_PREFIX/bin/"

# 🚨 CORRECCIÓN FINAL 2: Copiar todas la librerías compartida.
cp ./build/ggml/src/*libggml* "$STAGING_DIR/$INSTALL_PREFIX/bin/"

# 🚨 CORRECCIÓN 2: El modelo descargado se llama ggml-$MODEL.bin.
cp ./models/ggml-$MODEL.bin "$STAGING_DIR/$INSTALL_PREFIX/models/"

# --- 6. Crear el Paquete .deb con fpm ---
echo "5. Creando el paquete .deb..."
cd "$STAGING_DIR" || exit 1

# 🚨 CORRECCIÓN 3: Se añade --force para sobrescribir el paquete anterior.
fpm -s dir -t deb --force \
    -n "$PACKAGE_NAME" \
    -v "$WHISPER_VERSION" \
    -a "$(dpkg --print-architecture)" \
    --description "Lightweight C++ port of OpenAI's Whisper for transcription." \
    --url "https://github.com/ggerganov/whisper.cpp" \
    --category "utils" \
    --maintainer "Tu Nombre <tu@email.com>" \
    -p "../${PACKAGE_NAME}-${WHISPER_VERSION}_$MODEL.deb" \
    --prefix / \
    .

# --- 7. Limpieza ---
cd ..
rm -rf "$BUILD_DIR" "$STAGING_DIR"

echo "=========================================================="
echo "✅ ¡PAQUETE .DEB CREADO CON ÉXITO!"
echo "Para instalar: sudo dpkg -i ${PACKAGE_NAME}-${WHISPER_VERSION}.deb"
echo "El ejecutable se instala en: ${INSTALL_PREFIX}/bin/main"
echo "=========================================================="

