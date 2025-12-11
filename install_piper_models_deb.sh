#!/bin/bash
### install_piper_models_deb.sh - Descarga modelos de Piper de forma masiva y los empaqueta por idioma

# --- Variables de Configuración Global ---
PIPER_VERSION="1.2.0"
PACKAGE_NAME_BASE="piper-tts"
DOWNLOAD_DIR="piper_download_temp"
BUILD_DIR="piper_models_staging"
VOICES_URL="https://raw.githubusercontent.com/rhasspy/piper/refs/heads/master/VOICES.md"
VOICES_FILE="VOICES.md"
URL_LIST="model_urls.list"

# Ruta estándar para los modelos: /usr/share/piper-tts/models
MODEL_INSTALL_PATH="/usr/share/$PACKAGE_NAME_BASE/models" 

# --- 1. Preparación y Descarga de URLs Limpias ---
echo "1. Descargando lista de modelos y extrayendo URLs limpias..."
command -v wget >/dev/null 2>&1 || { 
    echo "Instalando wget..."
    sudo apt update && sudo apt install -y wget
}

# Preparamos directorios
mkdir -p "$DOWNLOAD_DIR"
rm -f piper-tts-model-*.deb # Limpiamos .deb anteriores

# Descargar el archivo VOICES.md
wget -c "$VOICES_URL" -O "$VOICES_FILE" || { echo "Error al descargar VOICES.md."; exit 1; }

# Obtención y limpieza de URLs (Generación de la lista maestra)
cat "$VOICES_FILE" | tr '(' '\n' | tr ')' '\n' | grep "https" | tr '?' '\n' | grep "http" > "$URL_LIST.temp"
grep '\.onnx$' "$URL_LIST.temp" > "$URL_LIST.onnx"
cp "$URL_LIST.onnx" "$URL_LIST.json"
sed -i 's/\.onnx$/.onnx.json/g' "$URL_LIST.json"
cat "$URL_LIST.onnx" "$URL_LIST.json" > "$URL_LIST.final"
rm "$URL_LIST.temp" "$URL_LIST.onnx" "$URL_LIST.json"

# --- 2. Descarga Masiva de Todos los Archivos ---
echo "2. Descargando masivamente todos los modelos y archivos de configuración..."
cd "$DOWNLOAD_DIR" || exit 1 
cat "../$URL_LIST.final" | xargs -n 1 wget -c --no-clobber
cd .. 

# --- 3. Agrupar Archivos Descargados por Idioma y Preparar Data ---
echo "3. Agrupando archivos descargados por idioma y preparando el staging..."

mkdir -p "$BUILD_DIR"
declare -A files_by_lang

# Obtener la lista única y robusta de códigos de idioma (ar, es, fr, etc.)
cd "$DOWNLOAD_DIR" || exit 1 
readarray -t LANG_CODES < <(ls | cut -d '_' -f1 | sort | uniq)
cd ..

# Llenar el array asociativo files_by_lang
for LANG_CODE in "${LANG_CODES[@]}"; do
    for FILE_PATH in $(find "$DOWNLOAD_DIR" -maxdepth 1 -type f -name "${LANG_CODE}_*"); do
        FILENAME=$(basename "$FILE_PATH")
        files_by_lang[$LANG_CODE]+="$FILENAME "
    done
done

echo "✅ Idiomas detectados para empaquetar: ${!files_by_lang[@]}"
echo "Iniciando empaquetado por idioma..."



# --- 4. Creación de Paquetes .deb por Idioma (CORRECCIÓN FINAL) ---

for LANG_CODE in "${!files_by_lang[@]}"; do
    MODELS_LIST="${files_by_lang[$LANG_CODE]}"
    if [ -z "$MODELS_LIST" ]; then 
        echo "Advertencia: No se encontraron archivos para el código $LANG_CODE. Omitiendo."
        continue 
    fi
    
    echo "========================================================"
    echo "📦 Procesando idioma: $LANG_CODE"

    # --- 4.1 Preparación del Staging Específico ---
    # Usamos un directorio de staging temporal y único para este idioma
    LANG_STAGING_DIR="$BUILD_DIR/$LANG_CODE" 
    rm -rf "$LANG_STAGING_DIR" # Limpiamos por si acaso
    mkdir -p "$LANG_STAGING_DIR"
    
    # Directorio de instalación FINAL dentro del STAGING
    # FINAL_DEST: [LANG_STAGING_DIR]/usr/share/piper-tts/models/
    FINAL_DEST_DIR="$LANG_STAGING_DIR/$MODEL_INSTALL_PATH" 
    mkdir -p "$FINAL_DEST_DIR" 
    
    echo " -> Moviendo modelos descargados a: $FINAL_DEST_DIR"

    # --- 4.2 Mover y Aplanar la Estructura (Sin Subdirectorios) ---
    for FILENAME in $MODELS_LIST; do
        # Movemos el archivo descargado directamente a la carpeta base /models/
        cp "$DOWNLOAD_DIR/$FILENAME" "$FINAL_DEST_DIR/"
    done

    # --- 4.3 Creación del Paquete .deb (El directorio base del .deb es LANG_STAGING_DIR) ---
    echo "  -> Empaquetando $LANG_CODE en .deb..."

    MODEL_PRE_INSTALL_SCRIPT="${LANG_CODE}-pre-install.sh"
    echo "echo 'Instalando modelos de idioma ($LANG_CODE) para Piper...'" > "$MODEL_PRE_INSTALL_SCRIPT"
    chmod +x "$MODEL_PRE_INSTALL_SCRIPT"

    fpm -s dir -t deb --force \
        --before-install "$MODEL_PRE_INSTALL_SCRIPT" \
        -n "${PACKAGE_NAME_BASE}-model-$LANG_CODE" \
        -v "$PIPER_VERSION" \
        -a "$(dpkg --print-architecture)" \
        --depends "$PACKAGE_NAME_BASE = $PIPER_VERSION" \
        --description "Modelos de idioma ($LANG_CODE) para Piper TTS." \
        -p "${PACKAGE_NAME_BASE}-model-${LANG_CODE}-${PIPER_VERSION}.deb" \
        -C "$LANG_STAGING_DIR" \
        usr || { echo "Error al crear el paquete $LANG_CODE."; } 
        
    rm "$MODEL_PRE_INSTALL_SCRIPT"
    echo "  -> Paquete creado: ${PACKAGE_NAME_BASE}-model-${LANG_CODE}-${PIPER_VERSION}.deb"
done


# --- 5. Limpieza Final ---
rm -rf "$DOWNLOAD_DIR"
rm -rf "$BUILD_DIR"
rm "$VOICES_FILE" "$URL_LIST.final"

echo "=========================================================="
echo "✅ Generación de paquetes de modelos Piper por idioma finalizada."
echo "=========================================================="
