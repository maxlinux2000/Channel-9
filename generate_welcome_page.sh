#!/bin/bash
# ==============================================================================
# SCRIPT: generate_welcome_page.sh
# Descripción: Genera una página HTML de bienvenida en $HOME/public_html
#              con información del sistema y enlaces a repositorios locales.
# ==============================================================================

# 1. Definición de Variables y Detección de Sistema
# ------------------------------------------------------------------------------

# Directorio de salida (asume que Lighttpd está configurado para ~user/public_html)
OUTPUT_DIR="${HOME}/public_html"
OUTPUT_FILE="${OUTPUT_DIR}/index.html"

# Detectar Sistema Operativo (versión 'bonita')
if [ -f "/etc/os-release" ]; then
    OS_NAME=$(grep PRETTY_NAME /etc/os-release | cut -d'=' -f2 | tr -d '"')
else
    # Si no existe /etc/os-release (sistemas muy antiguos o mínimales)
    OS_NAME=$(uname -o) 
fi

# Detectar Arquitectura
ARCHITECTURE=$(uname -m)
SYSTEM_INFO="$OS_NAME ($ARCHITECTURE)"


# Revisar el archivo de información de la CPU en busca del identificador de hardware
if grep -q "Raspberry Pi" /proc/cpuinfo || grep -q "BCM" /proc/cpuinfo; then
    echo "¡Detección directa de Raspberry Pi!"
    RASPBERRYPI=$(cat /proc/cpuinfo | grep "Raspberry" | cut -d ':' -f2)

    echo RASPBERRYPI=$RASPBERRYPI
else
    echo "No se detectó el identificador de hardware de Raspberry Pi."
fi


# 2. Preparación del Directorio
# ------------------------------------------------------------------------------
echo "--- Generando página de bienvenida en $OUTPUT_FILE ---"
mkdir -p "$OUTPUT_DIR" || { echo "🚨 Error: No se pudo crear el directorio $OUTPUT_DIR. Verifique permisos."; exit 1; }

# 3. Generación del Contenido HTML
# ------------------------------------------------------------------------------


# Usamos un HEREDOC para escribir el HTML completo
cat << EOF_HTML > "$OUTPUT_FILE"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Bienvenido a su Servidor Channel 9 Local</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; margin: 20px; color: #333; line-height: 1.6; background-color: #f4f7f6; }
        .container { max-width: 900px; margin: auto; background: #fff; padding: 30px; border-radius: 8px; box-shadow: 0 4px 8px rgba(0, 0, 0, 0.1); }
        h1 { color: #007bff; border-bottom: 2px solid #007bff; padding-bottom: 10px; }
        h2 { color: #555; margin-top: 25px; }
        ul { list-style-type: disc; margin-left: 20px; }
        strong { font-weight: 600; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; background-color: #f9f9f9; }
        td, th { padding: 10px; text-align: left; border: 1px solid #ddd; }
        .d { background-color: #f0f0f0; }
        .n a { text-decoration: none; color: #007bff; }
        .n a:hover { text-decoration: underline; }
        .m, .s, .t { font-family: monospace; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Bienvenido a este Servidor de prueba</h1>
        <h2>Este mini ordenador se usa para el proyecto de Channel 9 y Espejos de repositorios Debian y Proxmox</h2>
        <p>Este servidor ha sido configurado como un centro de operaciones de radio autónomo, proveyendo todos los recursos de software libre necesarios para el proyecto Channel 9 (automatización, monitoreo, TTS, y más).</p>

        <h2>1) Información del Sistema</h2>
        <p>Este es un ordenador funcionando con:</p>
        <p><strong>Sistema Operativo:</strong> <code>$SYSTEM_INFO $RASPBERRYPI</code></p>

        <h2>2) Repositorios Locales Disponibles</h2>
        <p>Este sistema contiene en su interior varios repositorios para que otras máquinas de la red (o el propio servidor si trabaja sin Internet) puedan instalar paquetes de forma rápida y segura.</p>
        <ul>
            <li><strong>a) Repositorio de Channel 9:</strong> Contiene todos los paquetes `.deb` construidos localmente (Whisper.cpp, Piper TTS, etc.).</li>
            <li><strong>b) Repositorio de Debian 12 (Bookworm):</strong> Un mirror local de los paquetes principales de Debian 12.</li>
            <li><strong>c) Repositorio de Proxmox (Debian 12):</strong> Packages para instalar la virtualización de Proxmox VE.</li>
        </ul>

        <h2>3) Editores y Herramientas</h2>
        <p>Se han preinstalado los **Editores de Texto e IDEs** más comunes para facilitar la programación y el mantenimiento del código fuente del proyecto.</p>

        <h2>Acceso a Contenido Compartido</h2>
        <p>Acceda directamente a los directorios del repositorio web:</p>

        <table>
            <tbody>
                <tr class="d"><td class="n"><a href="../">..</a>/</td><td class="m">&nbsp;</td><td class="s">- &nbsp;</td><td class="t">Directory</td></tr>
                <tr class="d"><td class="n"><a href="IDE_EDITORS/">IDE_EDITORS</a>/</td><td class="m">2025-Dec-25 02:19:45</td><td class="s">- &nbsp;</td><td class="t">Directory</td></tr>
                <tr class="d"><td class="n"><a href="ch9/">ch9</a>/</td><td class="m">2025-Dec-25 07:11:00</td><td class="s">- &nbsp;</td><td class="t">Directory</td></tr>
                <tr class="d"><td class="n"><a href="mirror/">mirror</a>/</td><td class="m">2025-Dec-29 07:41:31</td><td class="s">- &nbsp;</td><td class="t">Directory</td></tr>
            </tbody>
        </table>
    </div>
</body>
</html>
EOF_HTML

echo "✅ Página de bienvenida generada en: $OUTPUT_FILE"
echo "   Puede acceder a ella visitando la IP de su servidor."

# ------------------------------------------------------------------------------
