#!/bin/bash
# ==============================================================================
# SCRIPT: install_ch9_local.sh
# Versión: 2.5 - Instalación CORE de Channel-9 (Lighttpd/BIND9 condicional)
# Descripción: Construye e instala paquetes DEB. Instala Lighttpd y BIND9/Correo
#              solo si no se detecta ISPConfig.
# ==============================================================================


# --- 9.1. controlamos si las interfaces de red usan nombres tradicionales (canonical) o no y los forzamos ---
echo "--- 9.1 comprobamos los nombres de las interfaces de red ---"
if [ -f "force_canonical_netnames.sh" ]; then
    ./force_canonical_netnames.sh || { echo "🚨 Error al comprobar los nombres de las interfaces."; }
else
    echo "🚨 Error: force_canonical_netnames.sh no encontrado."
fi


# --- Variables de Configuración ---
REPO_ROOT="${HOME}/public_html/ch9/debian"
ARCH=$(dpkg --print-architecture)
DEB_POOL="${REPO_ROOT}/pool/${ARCH}"
DEB_POOL_ALL="${REPO_ROOT}/pool/all"

# Lista de paquetes base a verificar y sus respectivos scripts de construcción
# Formato: "nombre_paquete:script_builder_base:script_builder_adicionales"
PACKAGES_TO_CHECK=(
    "libretranslate-base:build_libretranslate_deb.sh:build_libretranslate_models_deb.sh build_libretranslate_service_deb.sh"
    "whisper-cpp-cli:build_whisper_deb.sh:"
    "piper-tts:build_piper_deb.sh:build_piper_models_deb.sh" 
)

# Lista de paquetes que se instalarán al final (solo los paquetes base y el servicio LT)
CORE_PACKAGES="libretranslate-base libretranslate-service whisper-cpp-cli piper-tts"

# --- Funciones de Utilidad ---

# Función para verificar si un paquete base está instalado
is_installed() {
    dpkg -s "$1" &>/dev/null
}

# Función para verificar si un paquete .deb existe en el repositorio local (pool)
deb_exists() {
    if find "$DEB_POOL" -maxdepth 1 -name "$1_*.deb" -print -quit 2>/dev/null | grep -q .; then
        return 0 
    fi
    if find "$DEB_POOL_ALL" -maxdepth 1 -name "$1_*.deb" -print -quit 2>/dev/null | grep -q .; then
        return 0 
    fi
    return 1 
}

# --- 1. Control de Dependencias Generales y Preparación ---
echo "--- 1. Instalando dependencias básicas y FPM ---"

# eliminamos el repositorio local porqué va a ser regenerado y añadido después:
sudo rm /etc/apt/sources.list.d/channel9.list

# Instalación de todas las dependencias. AÑADIDO 'lighttpd' de nuevo.
sudo apt update
sudo apt install -y sox ffmpeg zenity mailutils multimon-ng net-tools git cmake build-essential ruby ruby-dev python3 python3-venv wget yad mutt msmtp lighttpd

command -v dpkg-scanpackages >/dev/null 2>&1 || {
    echo "⚙️ Instalando dpkg-dev (necesario para la gestión de repositorios)..."
    sudo apt install dpkg-dev -y
}

# Instalación de FPM
command -v fpm >/dev/null 2>&1 || {
    echo "⚙️ Instalando fpm (Fast Package Manager)..."
    sudo gem install fpm
}

# --- 1.1. Configuración del Servidor Web (Lighttpd/Userdir y Dirlisting) ---
echo "--- 1.1. Configuración de Infraestructura Web (Lighttpd/Userdir) ---"

# CRÍTICO: Comprobación de existencia de ISPConfig
if [ -d "/usr/local/ispconfig" ]; then
    echo "⚠️ Omisión: Detectado ISPConfig. Lighttpd no se configura para evitar conflictos."
else
    echo "🚀 Configurando Lighttpd para servir el repositorio local..."

    # 1. Habilitar mod_userdir (para ~user/public_html)
    sudo lighty-enable-mod userdir 2>/dev/null

    # 2. Habilitar mod_dirlisting para que se vean los paquetes .deb
    sudo lighty-enable-mod dirlisting 2>/dev/null

    # 3. Crear el directorio public_html si no existe
    mkdir -p "$HOME/public_html"

    # 4. Ajustar permisos
    chmod 755 "$HOME/public_html"

    # 5. Reiniciar Lighttpd para aplicar cambios
    sudo systemctl restart lighttpd || { echo "🚨 Error al reiniciar Lighttpd. Continuación no garantizada."; }
    echo "INFO: Lighttpd configurado con Userdir y Dirlisting."
fi


# --- 2. Lógica de Construcción Condicional ---

NEEDS_BUILD_FLAG=false
BUILD_SCRIPTS=()

echo "--- 2. Verificación de Componentes Base (Piper, Whisper, LibreTranslate) ---"

# Asegurar la existencia de las carpetas pool antes de los builders
mkdir -p "$DEB_POOL" "$DEB_POOL_ALL"

for item in "${PACKAGES_TO_CHECK[@]}"; do
    # Separar campos
    IFS=':' read -r PACKAGE_NAME BUILD_SCRIPT BUILD_MODELS_SCRIPTS <<< "$item"
    
    echo "-> Componente: ${PACKAGE_NAME}..."

    if is_installed "$PACKAGE_NAME"; then
        echo "   [OK] Ya instalado. (Saltando construcción)"
    elif deb_exists "$PACKAGE_NAME"; then
        echo "   [DEB OK] .deb encontrado en el repositorio. (Saltando construcción)"
    else
        echo "   [FALTA] Ni instalado, ni .deb encontrado. Necesita construcción."
        NEEDS_BUILD_FLAG=true
        BUILD_SCRIPTS+=("./$BUILD_SCRIPT") # Añadir script base
        
        # Añadir scripts de modelos/servicios asociados
        for model_script in $BUILD_MODELS_SCRIPTS; do
            BUILD_SCRIPTS+=("./$model_script")
        done
    fi
done

# --- 3. Ejecución de Builders si es necesario ---

if $NEEDS_BUILD_FLAG; then
    echo "--- 3. Ejecutando scripts de construcción necesarios ---"
    
    for SCRIPT in "${BUILD_SCRIPTS[@]}"; do
        if [ -f "$SCRIPT" ]; then
            echo "🚀 Ejecutando: $SCRIPT..."
            "$SCRIPT" || { echo "🚨 Error crítico al construir ${SCRIPT}. Abortando instalación."; exit 1; }
        else
            echo "⚠️ Advertencia: Script de construcción $SCRIPT no encontrado. Saltando."
        fi
    done
else
    echo "--- 3. No se requiere construcción. Continuar a la instalación. ---"
fi


# --- 4. Actualización del Repositorio Local y Configuración de APT ---

echo "--- 4. Actualizando el índice del repositorio local (generate_local_repo.sh) ---"
if [ -f "generate_local_repo.sh" ]; then
    ./generate_local_repo.sh
else
    echo "🚨 Error: generate_local_repo.sh no encontrado. No se puede generar el índice."
    exit 1
fi

echo "--- 5. Configurando APT para usar el repositorio local (Loopback) ---"

# Usamos el formato Userdir: http://127.0.0.1/~<usuario>/ (asumiendo que el Mirror lo sirve)
USER_NAME=$(whoami)
# CRÍTICO: Añadir [trusted=yes] para evitar el error de firma GPG en repositorios locales.
REPO_WEB_PATH="deb [trusted=yes] http://127.0.0.1/~${USER_NAME}/ch9/debian stable main"

# 1. Eliminar cualquier fuente anterior del proyecto Channel9
sudo rm -f /etc/apt/sources.list.d/channel9.list

# 2. Añadir la fuente del repositorio
echo "Añadiendo línea de repositorio: ${REPO_WEB_PATH}"

sudo sh -c "echo \"${REPO_WEB_PATH}\" > /etc/apt/sources.list.d/channel9.list"


# 3. Actualizar el índice de paquetes
sudo apt update || { echo "🚨 Error al actualizar APT. Compruebe que el proyecto Mirror esté sirviendo la carpeta $HOME/public_html."; exit 1; }

# --- 6. Instalación de Paquetes ---
echo "--- 6. Instalando paquetes base y modelos mediante APT ---"

# 6.1. Recopilar nombres de paquetes de modelos generados automáticamente
MODEL_PATTERNS="libretranslate-model-|piper-tts-model-"

MODEL_PACKAGES=$(
    grep -h "Package: " ${REPO_ROOT}/dists/stable/main/binary-${ARCH}/Packages 2>/dev/null | \
    awk '{print $2}' | \
    grep -E "$MODEL_PATTERNS" | \
    sort -u | tr '\n' ' '
)

if [ -n "$MODEL_PACKAGES" ]; then
    echo "-> Paquetes de modelos a instalar (automático): ${MODEL_PACKAGES}"
fi

# Lista final de todos los paquetes a instalar
INSTALL_LIST="${CORE_PACKAGES} ${MODEL_PACKAGES}"

echo "🚀 Iniciando instalación de: ${INSTALL_LIST}"
sudo apt install -y ${INSTALL_LIST} || { 
    echo "🚨 Error al instalar paquetes APT. La instalación falló. Abortando."
    exit 1 
}

# --- 7. Generación de Páginas Web (Paso Mantenido, NO Condicional) ---
echo "--- 7. Generando las páginas Home y de Repositorio ---"
if [ -f "create_homepage.sh" ]; then
    ./create_homepage.sh
else
    echo "⚠️ Advertencia: create_homepage.sh no encontrado. No se generará la página de inicio."
fi

# --- 8. Instalación Local de Scripts y Launchers ---
echo "--- 8. Instalación local de Channel-9 scripts y lanzadores ---"

BIN_DIR="$HOME/.local/bin"
ICONS_DIR="$HOME/.local/share/icons/hicolor/256x256"
APPLICATIONS_DIR="$HOME/.local/share/applications"

# Lista de scripts
SCRIPTS_TO_INSTALL=(
    "CH9.sh"
    "CH9-config.sh"
    "CH9_loro.sh"
    "CH9_monitor.sh"
    "CH9_secretaria.sh"
    "CH9_whisper.sh"
)

# Lista de iconos
ICONS_TO_INSTALL=(
    "CH9.png"        
    "CH9-config.png" 
)

# CREACIÓN DE DIRECTORIOS
mkdir -p "$BIN_DIR" "$ICONS_DIR" "$APPLICATIONS_DIR"

# INSTALACIÓN DE SCRIPTS
echo "Instalando scripts en $BIN_DIR..."
for script in "${SCRIPTS_TO_INSTALL[@]}"; do
    if [ -f "$script" ]; then
        cp "$script" "$BIN_DIR/"
        chmod +x "$BIN_DIR/$script"
    fi
done

# INSTALACIÓN DE ICONOS
echo "Instalando iconos en $ICONS_DIR..."
for icon in "${ICONS_TO_INSTALL[@]}"; do
    if [ -f "$icon" ]; then
        cp "$icon" "$ICONS_DIR/"
    fi
done

# CREACIÓN DE LANZADORES DE ESCRITORIO (.desktop)
echo "Creando lanzadores de escritorio en $APPLICATIONS_DIR..."
# Lanzador Principal: Channel-9.desktop
cat <<EOF > "$APPLICATIONS_DIR/Channel-9.desktop"
[Desktop Entry]
Name=Channel 9
Comment=Sistema de automatización y monitoreo de emergencias de radio.
Exec=$HOME/.local/bin/CH9.sh
Icon=$HOME/.local/share/icons/hicolor/256x256/CH9.png
Terminal=true
Type=Application
Categories=Utility;Science;
StartupNotify=false
EOF
# Lanzador Configuración: Channel-9-Config.desktop
cat <<EOF > "$APPLICATIONS_DIR/Channel-9-Config.desktop"
[Desktop Entry]
Name=Configuración Channel 9
Comment=Configura los modos de operación, palabras clave y cuenta de correo.
Exec=$HOME/.local/bin/CH9-config.sh
Icon=$HOME/.local/share/icons/hicolor/256x256/CH9-config.png
Terminal=true
Type=Application
Categories=Settings;Utility;
StartupNotify=true
EOF

# --- 9. Configuración de Infraestructura de Red (BIND9 y Correo) (MODIFICADO) ---
echo "--- 9. Configurando Infraestructura de Red y Correo (ch9_infra_setup.sh) ---"

# CRÍTICO: Comprobación de existencia de ISPConfig
if [ -d "/usr/local/ispconfig" ]; then
    echo "⚠️ Omisión: Detectado ISPConfig (/usr/local/ispconfig)."
    echo "   El paso 9 (configuración de BIND9/Correo) se omite para evitar conflictos."
else
    # Si ISPConfig NO está instalado, ejecutamos la configuración de infraestructura.
    if [ -f "ch9_infra_setup.sh" ]; then
        echo "🚀 Ejecutando ch9_infra_setup.sh..."
        ./ch9_infra_setup.sh || { echo "🚨 Error al configurar la infraestructura de red/correo. Continuación no garantizada."; }
    else
        echo "🚨 Error: ch9_infra_setup.sh no encontrado. No se configurará BIND9/Dominio/Cuentas de Correo."
    fi
fi



# --- 10. SERVICIO DE WHISPER (ASÍNCRONO) ---
echo "--- 10. Configurando y Lanzando Servicio Asíncrono de Whisper (systemd user) ---"

# 1. Crear el directorio de configuración de systemd para el usuario si no existe
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_USER_DIR"
WHISPER_SERVICE_FILE="$SYSTEMD_USER_DIR/ch9-whisper.service"

# 2. Escribir el archivo de la unidad de servicio
cat <<EOF > "$WHISPER_SERVICE_FILE"
[Unit]
Description=Channel 9 Whisper Transcriber Service
Documentation=https://ch9.mi.atalaya/docs
After=network-online.target graphical.target

[Service]
Type=simple
Restart=always
# Usamos %h como alias de $HOME para robustez en systemd
ExecStart=%h/.local/bin/CH9_whisper.sh
# Comando para detener el servicio de forma limpia
ExecStop=/usr/bin/kill -s SIGINT \$MAINPID
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

# 3. Recargar la configuración de systemd del usuario
echo "INFO: Recargando demonio systemd del usuario..."
systemctl --user daemon-reload || echo "⚠️ Advertencia: No se pudo recargar systemd daemon (puede que no haya iniciado la sesión gráfica/systemd user)."

# 4. Activar el servicio para que inicie automáticamente
echo "INFO: Activando servicio 'ch9-whisper.service' para el inicio de sesión..."
systemctl --user enable ch9-whisper.service || echo "⚠️ Advertencia: No se pudo habilitar el servicio."

# 5. Iniciar el servicio inmediatamente
echo "INFO: Iniciando servicio 'ch9-whisper.service'..."
systemctl --user start ch9-whisper.service || echo "🚨 Error: Fallo al iniciar el servicio 'ch9-whisper.service'. Compruebe el log con 'journalctl --user -u ch9-whisper.service'"


# --- 11. FINALIZACIÓN (Antiguo 10. FINALIZACIÓN) ---
echo "--- 11. Finalización ---"
echo "Actualizando la base de datos de lanzadores y la caché de iconos..."
update-desktop-database "$APPLICATIONS_DIR" 2>/dev/null
gtk-update-icon-cache -f "$HOME/.local/share/icons/hicolor" 2>/dev/null

echo "======================================================================="
echo "✅ INSTALACIÓN BASE COMPLETA DEL PROYECTO CHANNEL-9."
echo "   El servicio de transcripción asíncrona (ch9-whisper.service) ha sido lanzado."
echo "======================================================================="

