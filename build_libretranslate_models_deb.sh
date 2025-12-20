#!/bin/bash
### build_libretranslate_models_deb.sh - Descarga modelos de LibreTranslate y los empaqueta por idioma

# --- Variables de Configuración Global ---
LT_VERSION="1.4.0" # Debe coincidir con la versión de libretranslate-base
PACKAGE_NAME_BASE="libretranslate"
ARCH="all" # ¡CRÍTICO! Los modelos son datos, no binarios.
MODEL_INDEX_URL="https://raw.githubusercontent.com/argosopentech/argospm-index/refs/heads/main/index.json"
MODEL_INDEX_FILE="models.json"
DOWNLOAD_DIR="lt_models_download_temp"
BUILD_DIR="lt_models_staging"

# Ruta donde LibreTranslate espera encontrar los modelos: /usr/share/libretranslate/models
MODEL_INSTALL_PATH="/usr/share/${PACKAGE_NAME_BASE}/models" 

# --- Variables de Repositorio Local ---
# Ruta donde se guardarán los paquetes DEB de arquitectura 'all'
REPO_PATH="${HOME}/public_html/ch9/debian/pool/${ARCH}"

# --- Variables de Directorio Temporal de FPM (para robustez) ---
FPM_TMP_BASE="fpm_model_temp"
export ABSOLUTE_FPM_TMP_PATH="$(pwd)/${FPM_TMP_BASE}" 
# CRÍTICO: Forzar el uso de la ruta de disco duro en lugar de /tmp (tmpfs)
export TMPDIR="$ABSOLUTE_FPM_TMP_PATH"
export TEMP="$ABSOLUTE_FPM_TMP_PATH"
export FPM_TEMP="$ABSOLUTE_FPM_TMP_PATH"


# --- 1. Preparación y Descarga de Índice de Modelos ---
echo "--- 1. Preparación y Descarga de Índice de Modelos ---"

# Control de dependencias (se asume que jq y wget están instalados o se instalarán)
command -v wget >/dev/null 2>&1 || { 
    echo "Instalando wget..."
    sudo apt update && sudo apt install -y wget
}
command -v jq >/dev/null 2>&1 || { 
    echo "Instalando jq (necesario para procesar JSON)..."
    sudo apt update && sudo apt install -y jq
}

# Preparamos directorios
rm -rf "$DOWNLOAD_DIR" "$BUILD_DIR"-* "$FPM_TMP_BASE"
mkdir -p "$DOWNLOAD_DIR"
mkdir -p "$FPM_TMP_BASE" # Creamos el directorio temporal para fpm

# Descargar el archivo índice
echo "-> Intentando descargar el índice de modelos desde: ${MODEL_INDEX_URL}"
wget -c "${MODEL_INDEX_URL}" -O "$MODEL_INDEX_FILE" || { echo "Error al descargar $MODEL_INDEX_FILE."; exit 1; }

# --- 2. Procesar JSON y Descargar Modelos ---
echo "--- 2. Procesando el índice para obtener URLs y códigos de modelos ---"

MODEL_LIST=$(jq -r '.[] | select(.links[0] | endswith(".argosmodel")) | "\(.links[0]) \(.code)"' "$MODEL_INDEX_FILE")

if [ -z "$MODEL_LIST" ]; then
    echo "Error: No se encontraron modelos válidos (.argosmodel) en el índice JSON. Comprueba la estructura del archivo."
    exit 1
fi

# Descargar cada modelo
echo "--- 3. Descargando modelos de LibreTranslate (.argosmodel) ---"
while read -r MODEL_URL MODEL_CODE_PAIR; do
    FILENAME=$(basename "$MODEL_URL")
    echo "-> Descargando $FILENAME (Código: $MODEL_CODE_PAIR)..."
    wget -c "$MODEL_URL" -O "$DOWNLOAD_DIR/$FILENAME" || { echo "Advertencia: Error al descargar $FILENAME. Continuando..."; }
done <<< "$MODEL_LIST"

# --- 4. Empaquetar Modelos (.deb) por separado ---
echo "--- 4. Creando paquetes .deb para cada modelo descargado ---"
echo "INFO: Los paquetes se guardarán en: ${REPO_PATH}"

# Crear la estructura de directorios del repositorio (si no existe)
mkdir -p "${REPO_PATH}"

# Itera sobre los archivos .argosmodel descargados
for MODEL_FILE in "$DOWNLOAD_DIR"/*.argosmodel; do
    if [ ! -f "$MODEL_FILE" ]; then
        continue 
    fi
    
    FILENAME=$(basename "$MODEL_FILE")
    
    # Extraemos el par de idiomas (ej: sq_en) del nombre del archivo
    LANG_PAIR=$(echo "$FILENAME" | sed -E 's/translate-([a-z]{2}_[a-z]{2}).*/\1/') 
    
    if [ -z "$LANG_PAIR" ]; then
        echo "Advertencia: No se pudo extraer el par de idiomas (LANG_PAIR) del archivo $FILENAME. Saltando."
        continue
    fi
    
    PACKAGE_FULL_NAME="${PACKAGE_NAME_BASE}-model-${LANG_PAIR}"
    
    # Directorio de Staging para este paquete: ./lt_models_staging-es_en/...
    LANG_STAGING_DIR="$BUILD_DIR-$LANG_PAIR"
    FINAL_DEST_DIR="$LANG_STAGING_DIR/$MODEL_INSTALL_PATH"
    
    rm -rf "$LANG_STAGING_DIR"
    mkdir -p "$FINAL_DEST_DIR"
    
    echo "-> Empaquetando modelo: $FILENAME (Paquete: ${PACKAGE_FULL_NAME}) [${ARCH}]..."

    # Copiar el archivo .argosmodel descargado al directorio de destino final
    cp "$MODEL_FILE" "$FINAL_DEST_DIR/"

    # --- 4.1 Creación del Paquete .deb ---
    MODEL_PRE_INSTALL_SCRIPT="${LANG_PAIR}-pre-install.sh"
    echo "echo 'Instalando modelo ($FILENAME) para LibreTranslate...' y creando directorio de destino." > "$MODEL_PRE_INSTALL_SCRIPT"
    echo "mkdir -p ${MODEL_INSTALL_PATH}" >> "$MODEL_PRE_INSTALL_SCRIPT"
    chmod +x "$MODEL_PRE_INSTALL_SCRIPT"

    # Nombre final del DEB: nombre_version_all.deb
    DEB_MODEL_FILENAME="${PACKAGE_FULL_NAME}_${LT_VERSION}_${ARCH}.deb"

    fpm -s dir -t deb --force \
        --before-install "$MODEL_PRE_INSTALL_SCRIPT" \
        -n "$PACKAGE_FULL_NAME" \
        -v "$LT_VERSION" \
        -a "$ARCH" \
        --depends "$PACKAGE_NAME_BASE = $LT_VERSION" \
        --description "Modelo de idioma ($LANG_PAIR) para LibreTranslate. Archivo: $FILENAME" \
        --maintainer "Channel9 Project <ch9@mi.atalaya>" \
        -p "${REPO_PATH}/${DEB_MODEL_FILENAME}" \
        -C "$LANG_STAGING_DIR" \
        usr || { echo "Error al crear el paquete $PACKAGE_FULL_NAME."; } 
        
    rm "$MODEL_PRE_INSTALL_SCRIPT" 2>/dev/null
    rm -rf "$LANG_STAGING_DIR" # Limpieza del staging de este modelo
    # El temporal de FPM se limpia al final (Paso 5)

done

# --- 5. Limpieza Final...
echo "--- 5. Limpieza Final ---"
rm -rf "$DOWNLOAD_DIR"
rm -f "$MODEL_INDEX_FILE"
rm -rf "$FPM_TMP_BASE" # Limpieza del directorio temporal de FPM

echo "=========================================================="
echo "✅ CREACIÓN DE PAQUETES DE MODELOS FINALIZADA."
echo "Los paquetes se encuentran en: ${REPO_PATH}"
echo "=========================================================="

