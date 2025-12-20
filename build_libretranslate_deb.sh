#!/bin/bash
### build_libretranslate_deb.sh - Crea el paquete DEB base para LibreTranslate (Binario y Venv)

# --- Variables de Configuración Global ---
LT_VERSION="1.4.0" 
INSTALL_PREFIX="/opt/libretranslate" 
PACKAGE_NAME_BASE="libretranslate-base"
BUILD_DIR="libretranslate_build_staging" 
LT_REPO="https://github.com/LibreTranslate/LibreTranslate"
GUNICORN_DEPENDENCY="gunicorn" 

# Rutas de Staging
FINAL_VENV_PATH="./opt/libretranslate/venv"
VENV_PIP="$FINAL_VENV_PATH/bin/pip"

# --- Variables de Arquitectura y Repositorio ---
ARCH=$(dpkg --print-architecture) # Detecta amd64, arm64, etc.
# Ruta donde se guardará el paquete .deb final
REPO_PATH="${HOME}/public_html/ch9/debian/pool/${ARCH}" 
# Nombre del archivo DEB, siguiendo la convención: nombre_version_arch.deb
DEB_FILENAME="${PACKAGE_NAME_BASE}_${LT_VERSION}_${ARCH}.deb"

# DIRECTORIO TEMPORAL DE FPM (¡La solución crítica!)
FPM_TMP_PATH="fpm_temp_dir" 
export ABSOLUTE_FPM_TMP_PATH="$(pwd)/$FPM_TMP_PATH" 
export TMPDIR="$ABSOLUTE_FPM_TMP_PATH"
export TEMP="$ABSOLUTE_FPM_TMP_PATH"
export FPM_TEMP="$ABSOLUTE_FPM_TMP_PATH"

# --- Scripts Temporales para fpm ---
BASE_PRE_INSTALL_SCRIPT="base-pre-install.sh"
echo "echo 'Instalando binario LibreTranslate...'" > "$BASE_PRE_INSTALL_SCRIPT"
chmod +x "$BASE_PRE_INSTALL_SCRIPT"

# --- 1. Control de Dependencias ---
echo "--- 1. Verificando e instalando dependencias (python3-venv, fpm)... ---"
sudo apt update
command -v fpm >/dev/null 2>&1 || { 
    echo "⚙️ Instalando fpm (Fast Package Manager)..."
    sudo gem install fpm
}

# --- 2. Preparar Entorno Temporal (Base) ---
echo "--- 2. Limpiando y preparando entorno de staging ($BUILD_DIR) ---"
rm -rf "$BUILD_DIR" "$FPM_TMP_PATH"
mkdir -p "$BUILD_DIR"
mkdir -p "$FPM_TMP_PATH" # Creamos el directorio temporal para fpm
cd "$BUILD_DIR" || exit 1

# Creamos la estructura de directorios de destino dentro del BUILD_DIR:
mkdir -p "./opt/libretranslate"
mkdir -p "./usr/local/bin" 

# --- 3. Instalar LibreTranslate Base en entorno virtual local (Directamente en ruta final) ---
echo "--- 3. Instalando LibreTranslate BASE y Gunicorn en Venv... ---"
python3 -m venv "${FINAL_VENV_PATH}" 
"${VENV_PIP}" install libretranslate=="$LT_VERSION" gunicorn || { echo "Error al instalar libretranslate."; exit 1; }

# --- 4. Corregir Symlinks y Limpiar (Anti-tar-failed y Reducción de Tamaño) ---
echo "--- 4. Corrigiendo symlinks y limpiando Venv para reducir tamaño... ---"

# 4.1. Eliminar symlinks rotos (Causa principal de tar failed (exit code 2) si no es espacio)
find "${FINAL_VENV_PATH}" -type l -xtype l -delete 2>/dev/null
echo "INFO: Enlaces simbólicos rotos eliminados."

# 4.2. Limpiar cache de pip, scripts de activación y otros archivos grandes/innecesarios
find "${FINAL_VENV_PATH}" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null
rm -rf "${FINAL_VENV_PATH}/lib/python3*/site-packages/*.dist-info" 2>/dev/null
rm -rf "${FINAL_VENV_PATH}/lib/python3*/site-packages/*.egg-info" 2>/dev/null
rm -f "${FINAL_VENV_PATH}/bin/pip" 2>/dev/null
rm -f "${FINAL_VENV_PATH}/bin/pip3" 2>/dev/null
rm -f "${FINAL_VENV_PATH}/bin/activate" "${FINAL_VENV_PATH}/bin/activate.csh" "${FINAL_VENV_PATH}/bin/activate.fish" 2>/dev/null
echo "INFO: Archivos innecesarios y cache eliminados."


# --- 5. Crear script wrapper ---
echo "--- 5. Creando script wrapper para Gunicorn... ---"
WRAPPER_SCRIPT="./usr/local/bin/libretranslate"
cat <<EOT > "${WRAPPER_SCRIPT}"
#!/bin/bash
# Script Wrapper para ejecutar LibreTranslate con Gunicorn
exec ${INSTALL_PREFIX}/venv/bin/gunicorn --bind 0.0.0.0:5000 'libretranslate:app(\$@)'
EOT
chmod +x "${WRAPPER_SCRIPT}"

# --- 6. Preparación Final del Staging y Chequeo de Permisos ---
echo "--- 6. Verificaciones de Staging antes de FPM ---"

# Asegurar permisos correctos en directorios clave (recursivo)
echo "INFO: Aplicando permisos 755 a directorios clave..."
sudo chmod -R 755 ./opt/
sudo chmod -R 755 ./usr/

# Limpiar archivos ocultos (por si acaso)
find . -type f -name ".*" -delete 2>/dev/null
find . -type d -name ".*" -exec rm -rf {} + 2>/dev/null

# --- 7. Creando el Paquete .deb BASE y moviéndolo al Repositorio ---
echo "--- 7. Creando el paquete .deb BASE (${DEB_FILENAME}) ---"
echo "INFO: FPM usará el directorio temporal: ${ABSOLUTE_FPM_TMP_PATH}"
echo "INFO: El paquete se guardará en: ${REPO_PATH}"

cd .. # Volvemos al directorio raíz para FPM

# Crear la estructura de directorios del repositorio (si no existe)
mkdir -p "${REPO_PATH}"

# FPM_PRESERVE_PKGDIR=1 para debug si falla
FPM_PRESERVE_PKGDIR=1 fpm -s dir -t deb --force \
    --before-install "${BASE_PRE_INSTALL_SCRIPT}" \
    -n "${PACKAGE_NAME_BASE}" \
    -v "${LT_VERSION}" \
    -a "${ARCH}" \
    --description "LibreTranslate: Servidor de Traducción Automática (Binario Base con Gunicorn)." \
    --depends "python3-venv" \
    --depends "libopenblas-base" \
    --depends "libgomp1" \
    --url "$LT_REPO" \
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
    --exclude '**/__pycache__' \
    opt usr || { echo "Error al crear el paquete BASE."; rm "${BASE_PRE_INSTALL_SCRIPT}" 2>/dev/null; rm -rf "$FPM_TMP_PATH"; exit 1; } 
    
# --- 8. Limpieza Final ---
echo "--- 8. Limpieza y Finalización ---"
rm -rf "$BUILD_DIR"
rm -rf "$FPM_TMP_PATH"
rm "${BASE_PRE_INSTALL_SCRIPT}" 2>/dev/null

echo "=========================================================="
echo "✅ ¡PAQUETE BASE LIBRETRANSLATE .DEB CREADO CON ÉXITO!"
echo "Paquete: ${REPO_PATH}/${DEB_FILENAME}"
echo "=========================================================="

