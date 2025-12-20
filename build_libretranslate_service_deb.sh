#!/bin/bash
### build_libretranslate_service_deb.sh - Crea el paquete DEB para el servicio systemd de LibreTranslate

# --- Variables de Configuración Global ---
LT_VERSION="1.4.0" 
PACKAGE_NAME="libretranslate-service"
PACKAGE_BASE="libretranslate"
ARCH="all" # ¡CRÍTICO! Este paquete es independiente de la arquitectura
BUILD_DIR="libretranslate_service_staging"

# --- Nuevas Variables de Repositorio ---
# Ruta donde se guardará el paquete .deb final (arquitectura 'all')
REPO_PATH="${HOME}/public_html/ch9/debian/pool/${ARCH}" 
# Nombre del archivo DEB, siguiendo la convención: nombre_version_arch.deb
DEB_FILENAME="${PACKAGE_NAME}_${LT_VERSION}_${ARCH}.deb"

# DIRECTORIO TEMPORAL DE FPM (¡Asegurando la robustez como en el script base!)
FPM_TMP_PATH="fpm_service_temp_dir" 
# La ruta absoluta que EXPORTAREMOS
export ABSOLUTE_FPM_TMP_PATH="$(pwd)/$FPM_TMP_PATH" 
# CRÍTICO: Forzar el uso de la ruta de disco duro en lugar de /tmp (tmpfs)
export TMPDIR="$ABSOLUTE_FPM_TMP_PATH"
export TEMP="$ABSOLUTE_FPM_TMP_PATH"
export FPM_TEMP="$ABSOLUTE_FPM_TMP_PATH"

# Rutas de instalación en el sistema
SYSTEMD_PATH="./lib/systemd/system"
USER_NAME="libretranslate"
GROUP_NAME="libretranslate"

# --- 1. Control de Dependencias y Preparación ---
echo "--- 1. Preparando entorno de staging ($BUILD_DIR) ---"

command -v fpm >/dev/null 2>&1 || { 
    echo "⚙️ Error: fpm no está instalado. Por favor, instálalo con 'sudo gem install fpm'."
    exit 1
}

rm -rf "$BUILD_DIR" "$FPM_TMP_PATH" # Limpieza inicial
mkdir -p "$BUILD_DIR"
mkdir -p "$BUILD_DIR/$SYSTEMD_PATH"
mkdir -p "$FPM_TMP_PATH" # Creamos el directorio temporal para fpm

# --- 2. Crear Archivo de Servicio Systemd ---
echo "--- 2. Creando el archivo de servicio libretranslate.service ---"

SERVICE_FILE="$BUILD_DIR/$SYSTEMD_PATH/libretranslate.service"

# Utilizamos la sintaxis robusta de ${VARIABLE} para mayor claridad
cat <<EOT > "${SERVICE_FILE}"
[Unit]
Description=Servidor de Traducción LibreTranslate (Canal 9)
After=network.target

[Service]
# Ejecutado como usuario de sistema de baja prioridad
User=${USER_NAME}
Group=${GROUP_NAME}

# El binario wrapper está en /usr/local/bin (instalado por libretranslate-base.deb)
ExecStart=/usr/local/bin/libretranslate
# Reiniciar si falla
Restart=always

# Crear un directorio temporal para Gunicorn/LibreTranslate
# CRÍTICO: Aseguramos que la aplicación tiene su propio temp y no usa /tmp global.
PrivateTmp=true

[Install]
# Habilitar en el arranque del sistema
WantedBy=multi-user.target
EOT

echo "INFO: Archivo ${SERVICE_FILE} creado."

# --- 3. Scripts de Mantenimiento (Pre/Post Instalación) ---

# Este script se ejecuta ANTES de que el paquete se instale
PRE_INSTALL_SCRIPT="pre-install.sh"
cat <<EOT > "${PRE_INSTALL_SCRIPT}"
#!/bin/bash
# 1. Detener el servicio si está corriendo
if systemctl is-active --quiet libretranslate.service; then
    systemctl stop libretranslate.service
fi
EOT
chmod +x "${PRE_INSTALL_SCRIPT}"

# Este script se ejecuta DESPUÉS de que el paquete se instale
POST_INSTALL_SCRIPT="post-install.sh"
cat <<EOT > "${POST_INSTALL_SCRIPT}"
#!/bin/bash
# 1. Crear el usuario de sistema y grupo si no existen
if ! id -u ${USER_NAME} >/dev/null 2>&1; then
    echo "Creando usuario de sistema '${USER_NAME}'..."
    # --system: usuario de sistema; --no-create-home: no necesita home
    adduser --system --no-create-home --group ${USER_NAME} 
fi

# 2. Recargar systemd y habilitar el servicio
echo "Recargando configuraciones de systemd y habilitando el servicio..."
systemctl daemon-reload
systemctl enable libretranslate.service
systemctl start libretranslate.service || echo "Advertencia: Fallo al iniciar el servicio (posiblemente libretranslate-base no está instalado aún)."
EOT
chmod +x "${POST_INSTALL_SCRIPT}"

# Este script se ejecuta ANTES de que el paquete se DESINSTALE
PRE_REMOVE_SCRIPT="pre-remove.sh"
cat <<EOT > "${PRE_REMOVE_SCRIPT}"
#!/bin/bash
# Detener y deshabilitar el servicio antes de desinstalar
systemctl stop libretranslate.service
systemctl disable libretranslate.service
EOT
chmod +x "${PRE_REMOVE_SCRIPT}"


# --- 4. Crear el Paquete .deb de Servicio y guardarlo en el Repositorio ---
echo "--- 4. Creando el paquete .deb de Servicio (${DEB_FILENAME}) ---"
echo "INFO: FPM usará el directorio temporal: $ABSOLUTE_FPM_TMP_PATH"
echo "INFO: El paquete se guardará en: ${REPO_PATH}/${DEB_FILENAME}"

# Aseguramos la existencia de la carpeta de destino en el repositorio
mkdir -p "${REPO_PATH}"

rm -f "${PACKAGE_NAME}_${LT_VERSION}_${ARCH}.deb"

fpm -s dir -t deb --force \
    --before-install "${PRE_INSTALL_SCRIPT}" \
    --after-install "${POST_INSTALL_SCRIPT}" \
    --before-remove "${PRE_REMOVE_SCRIPT}" \
    -n "${PACKAGE_NAME}" \
    -v "${LT_VERSION}" \
    -a "${ARCH}" \
    --description "Servicio systemd para el servidor LibreTranslate (Proyecto Channel 9)." \
    --depends "${PACKAGE_BASE} = ${LT_VERSION}" \
    --maintainer "Channel9 Project <ch9@mi.atalaya>" \
    -p "${REPO_PATH}/${DEB_FILENAME}" \
    -C "$BUILD_DIR" \
    lib || { echo "Error al crear el paquete de servicio."; rm "${PRE_INSTALL_SCRIPT}" "${POST_INSTALL_SCRIPT}" "${PRE_REMOVE_SCRIPT}" 2>/dev/null; rm -rf "$FPM_TMP_PATH"; exit 1; }
    
# --- 5. Limpieza Final ---
echo "--- 5. Limpieza y Finalización ---"
rm -rf "$BUILD_DIR"
rm -rf "$FPM_TMP_PATH" # Eliminamos la carpeta temporal de FPM
rm "${PRE_INSTALL_SCRIPT}" "${POST_INSTALL_SCRIPT}" "${PRE_REMOVE_SCRIPT}" 2>/dev/null

echo "=========================================================="
echo "✅ PAQUETE DE SERVICIO LIBRETRANSLATE CREADO CON ÉXITO!"
echo "Paquete: ${REPO_PATH}/${DEB_FILENAME}"
echo "=========================================================="
