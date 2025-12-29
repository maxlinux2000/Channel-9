#!/bin/bash
### create_installer_run.sh - Crea el instalador auto-extraíble (.run) para Channel 9

# --- Variables de Configuración ---
INSTALLER_NAME="Channel9_Installer.run"
TEMP_DIR="installer_staging"
ARCHIVE_NAME="channel9_scripts.tar.gz"

# Lista de todos los scripts y archivos necesarios para la instalación offline
# (Esto incluye builders, generadores, instaladores y los scripts de la aplicación)
FILES_TO_INCLUDE=(
    # Builders de Dependencias
    "build_libretranslate_deb.sh"
    "build_libretranslate_models_deb.sh"
    "build_libretranslate_service_deb.sh"
    "build_piper_deb.sh"
    "build_piper_models_deb.sh"
    "build_whisper_deb.sh"
    
    # Scripts de Infraestructura y Repositorio
    "ch9_ap_bypass.sh"
    "ch9_infra_setup.sh"
    "generate_local_repo.sh"
    "create_homepage.sh"

    # Script de Instalación Principal
    "1_install_ch9_local.sh"

    # Scripts de la Aplicación (Core)
    "CH9.sh"
    "CH9-config.sh"
    "CH9_loro.sh"
    "CH9_monitor.sh"
    "CH9_secretaria.sh"

    # Iconos y otros archivos estáticos
    "CH9.png"
    "CH9-config.png"
    
    # Script para corregir problemas de red (si es necesario)
    "force_canonical_netnames.sh"
)

# --- 1. Preparación del Entorno ---
echo "--- 1. Preparando entorno de staging y verificando archivos ---"
rm -rf "$TEMP_DIR" "$INSTALLER_NAME"
mkdir -p "$TEMP_DIR"

# Copiar archivos al staging y verificar que existen
MISSING_FILE=false
for FILE in "${FILES_TO_INCLUDE[@]}"; do
    if [ -f "$FILE" ]; then
        cp "$FILE" "$TEMP_DIR/"
    else
        echo "🚨 ERROR: Archivo requerido no encontrado: $FILE"
        MISSING_FILE=true
    fi
done

if $MISSING_FILE; then
    echo "🚨 Abortando: Faltan archivos cruciales para crear el instalador."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# --- 2. Creación del Archivo Comprimido (.tar.gz) ---
echo "--- 2. Creando el archivo comprimido ($ARCHIVE_NAME) ---"
tar -czf "$ARCHIVE_NAME" -C "$TEMP_DIR" .
rm -rf "$TEMP_DIR" # Limpiamos el staging


# --- 3. Generación del Script Auto-Extraíble (.run) ---
echo "--- 3. Generando el instalador final ($INSTALLER_NAME) ---"

# Escribimos la cabecera del script auto-extraíble
cat <<EOF > "$INSTALLER_NAME"
#!/bin/bash
# ==============================================================================
# Channel9_Installer.run - Instalador Auto-Extraíble del Proyecto Channel 9
# ==============================================================================
# Este script auto-extraíble contiene el código de instalación y todos los
# scripts binarios y modelos necesarios.

INSTALL_PATH="\$HOME/ch9_install_\$(date +%Y%m%d%H%M%S)"
ARCHIVE_START_LINE=\$(awk '/^__ARCHIVE_FOLLOWS__/ {print NR + 1; exit 0;}' "\$0")
ARCHIVE_FILE="$ARCHIVE_NAME"

# --- 1. Control de Permisos y Dependencias Básicas ---
if [ "\$(id -u)" = 0 ]; then
    echo "🚨 ERROR: Por favor, no ejecute el instalador como root (sudo). Ejecútelo como un usuario normal."
    exit 1
fi

command -v tail >/dev/null 2>&1 || {
    echo "🚨 ERROR: La herramienta 'tail' no está instalada. No se puede continuar."
    exit 1
}

# --- 2. Extracción del Archivo ---
echo "--- 1. Extrayendo archivos de instalación a \$INSTALL_PATH ---"
mkdir -p "\$INSTALL_PATH"
if ! tail -n +\$ARCHIVE_START_LINE "\$0" | base64 -d | tar -xzf - -C "\$INSTALL_PATH"; then
    echo "🚨 ERROR: Fallo en la extracción del archivo. Verifique la integridad del archivo."
    rm -rf "\$INSTALL_PATH"
    exit 1
fi

# --- 3. Lanzamiento del Instalador Principal ---
echo "--- 2. Lanzando el instalador principal (1_install_ch9_local.sh) ---"
cd "\$INSTALL_PATH" || exit 1

# Asegurarse de que el instalador principal sea ejecutable
chmod +x 1_install_ch9_local.sh

./1_install_ch9_local.sh

INSTALLER_STATUS=\$?

# --- 4. Limpieza ---
if [ \$INSTALLER_STATUS -eq 0 ]; then
    echo "✅ Instalación de Channel 9 completada con éxito. Limpiando archivos temporales."
    # Mantenemos la carpeta por defecto para depuración, pero si todo va bien, se puede eliminar.
    # rm -rf "\$INSTALL_PATH" 
    echo "La carpeta de instalación temporal es: \$INSTALL_PATH"
else
    echo "🚨 La instalación de Channel 9 FUE INTERRUMPIDA o FALLÓ. Revise los errores."
    echo "Manteniendo archivos temporales para depuración en: \$INSTALL_PATH"
fi

exit \$INSTALLER_STATUS

__ARCHIVE_FOLLOWS__
EOF

# Añadir el contenido del archivo comprimido codificado en Base64
base64 "$ARCHIVE_NAME" >> "$INSTALLER_NAME"

# Hacer el instalador ejecutable
chmod +x "$INSTALLER_NAME"

# --- 4. Limpieza y Mensaje Final ---
rm "$ARCHIVE_NAME"
echo "================================================================"
echo "✅ Instalador Auto-Extraíble CREADO: $INSTALLER_NAME"
echo "================================================================"
echo "Instrucciones de uso:"
echo "1. Asegúrese de tener 'base64' y 'tar' instalados."
echo "2. Ejecute: ./$INSTALLER_NAME"
echo ""

