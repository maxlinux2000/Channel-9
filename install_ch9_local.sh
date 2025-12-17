#!/bin/bash
# ==============================================================================
# SCRIPT: install_ch9_local.sh
# Versión: 1.1 - Instalación local de Scripts, Iconos y Cache de Channel-9
# ==============================================================================


# Instalación de todas las dependencias
sudo apt update
sudo apt install -y sox ffmpeg zenity mailutils multimon-ng net-tools git cmake build-essential ruby ruby-dev python3 python3-venv wget yad mutt
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y msmtp

# Instalación de FPM
sudo gem install fpm


echo "🚀 Iniciando la compilación de Piper y Whisper.cpp..."

# 0 compilando e instalado Whisper y Piper
./build_piper_deb.sh
./build_piper_models_deb.sh
./build_whisper_deb.sh

mkdir debs
mv *.deb debs/
cd debs/
sudo apt install -y *.deb
cd -


echo "🚀 Iniciando instalación local de Channel-9..."

# --- 1. DEFINICIÓN DE RUTAS LOCALES ---
BIN_DIR="$HOME/.local/bin"
ICONS_DIR="$HOME/.local/share/icons/hicolor/256x256"
APPLICATIONS_DIR="$HOME/.local/share/applications"

# Lista de scripts (Asumimos que están en el directorio actual)
SCRIPTS_TO_INSTALL=(
    "CH9.sh"
    "CH9-config.sh"
    "CH9_loro.sh"
    "CH9_monitor.sh"
    "CH9_secretaria.sh"
)

# Lista de iconos (Asumimos que están en el directorio actual)
ICONS_TO_INSTALL=(
    "CH9.png"        # El icono principal
    "CH9-config.png" # El icono de configuración
)

# --- 2. CREACIÓN DE DIRECTORIOS ---
echo "Creando directorios locales necesarios..."
mkdir -p "$BIN_DIR"
mkdir -p "$ICONS_DIR"
mkdir -p "$APPLICATIONS_DIR"

# --- 3. INSTALACIÓN DE SCRIPTS ---
echo "Instalando scripts en $BIN_DIR..."
for script in "${SCRIPTS_TO_INSTALL[@]}"; do
    if [ -f "$script" ]; then
        cp "$script" "$BIN_DIR/"
        chmod +x "$BIN_DIR/$script"
        echo "   -> Instalado y hecho ejecutable: $script"
    else
        echo "   ⚠️ Advertencia: Archivo $script no encontrado. Omitiendo."
    fi
done

# --- 4. INSTALACIÓN DE ICONOS ---
echo "Instalando iconos en $ICONS_DIR..."
for icon in "${ICONS_TO_INSTALL[@]}"; do
    if [ -f "$icon" ]; then
        cp "$icon" "$ICONS_DIR/"
        echo "   -> Icono instalado: $icon"
    else
        echo "   ⚠️ Advertencia: Archivo $icon no encontrado. Omitiendo."
    fi
done

# --- 5. CREACIÓN DE LANZADORES DE ESCRITORIO (.desktop) ---
echo "Creando lanzadores de escritorio en $APPLICATIONS_DIR..."

# 5.1. Lanzador Principal: Channel-9.desktop
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

echo "   -> Lanzador Channel-9.desktop creado."

# 5.2. Lanzador Configuración: Channel-9-Config.desktop
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

echo "   -> Lanzador Channel-9-Config.desktop creado."

# --- 6. ACTUALIZACIÓN DE CACHÉS ---
echo "Actualizando la base de datos de lanzadores y la caché de iconos..."
update-desktop-database "$APPLICATIONS_DIR" 2>/dev/null
# Comando clave para forzar la visualización de iconos
gtk-update-icon-cache -f "$HOME/.local/share/icons/hicolor" 2>/dev/null

echo "✅ Instalación local de Channel-9 completada. Los lanzadores y sus iconos deberían aparecer ahora."

