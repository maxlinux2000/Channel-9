#!/bin/bash
### generate_local_repo.sh - Genera los archivos de índice (Packages, Release) para el repositorio Debian local

# --- Variables de Configuración ---
REPO_ROOT="${HOME}/public_html/ch9/debian"
DISTRIBUTION="stable"
COMPONENT="main"

# Arquitecturas que manejamos (deben coincidir con las carpetas en pool/)
ARCHITECTURES=("all" "amd64" "arm64") 

# --- 1. Control de Dependencias ---
echo "--- 1. Verificando dependencias necesarias (dpkg-dev, gzip)... ---"

command -v dpkg-scanpackages >/dev/null 2>&1 || {
    echo "⚙️ Instalando dpkg-dev (necesario para dpkg-scanpackages)..."
    sudo apt update && sudo apt install dpkg-dev -y
}
command -v gzip >/dev/null 2>&1 || {
    echo "⚙️ Instalando gzip..."
    sudo apt install gzip -y
}

# --- 2. Detección de IP y Configuración de URL (CORREGIDO) ---
echo "--- 2. Detectando IPs de red y configurando ruta web con ~usuario ---"

# Función robusta para obtener la IP de una interfaz
get_ip() {
    ip addr show "$1" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1
}

ETH0_IP=$(get_ip "eth0")
WLAN0_IP=$(get_ip "wlan0")

# NUEVAS VARIABLES CRÍTICAS PARA public_html
LINUX_USER="$(whoami)"
REPO_WEB_PATH="~${LINUX_USER}/ch9/debian" # Incluye la parte ~usuario/

SERVER_IP_LINES=""

if [ -n "$ETH0_IP" ]; then
    SERVER_IP_LINES+="<p><strong>URL Sugerida (eth0):</strong> <code>http://${ETH0_IP}/${REPO_WEB_PATH}</code></p>"
fi

if [ -n "$WLAN0_IP" ]; then
    SERVER_IP_LINES+="<p><strong>URL Sugerida (wlan0):</strong> <code>http://${WLAN0_IP}/${REPO_WEB_PATH}</code></p>"
fi

# Fallback si no se encuentra ninguna IP
if [ -z "$SERVER_IP_LINES" ]; then
    SERVER_IP_LINES="<p><strong>URL base (Reemplazar):</strong> <code>http://[IP-DEL-SERVIDOR]/${REPO_WEB_PATH}</code></p>"
fi

echo "Direcciones detectadas: $(echo "$SERVER_IP_LINES" | sed 's/<[^>]*>//g' | tr '\n' ' ')"

# --- 3. Preparación de Estructura de Directorios ---
echo "--- 3. Creando la estructura de carpetas del repositorio en ${REPO_ROOT} ---"
mkdir -p "$REPO_ROOT/dists/$DISTRIBUTION"

# --- 4. Generación de los archivos Packages para cada arquitectura ---
echo "--- 4. Escaneando paquetes y generando archivos Packages ---"

# CRÍTICO: Entrar en el directorio raíz del repositorio antes de dpkg-scanpackages
# Esto asegura que las rutas en el campo 'Filename' de Packages.gz sean RELATIVAS
pushd "$REPO_ROOT" > /dev/null

for ARCH in "${ARCHITECTURES[@]}"; do
    # Las rutas usadas aquí son relativas a $REPO_ROOT (el nuevo CWD)
    POOL_DIR="pool/${ARCH}"
    INDEX_DIR="dists/${DISTRIBUTION}/${COMPONENT}/binary-${ARCH}"
    
    if [ ! -d "$POOL_DIR" ] || [ -z "$(ls -A "$POOL_DIR" 2>/dev/null)" ]; then
        echo "Advertencia: La carpeta de paquetes para ${ARCH} no existe o está vacía: ${POOL_DIR}. Saltando."
        continue
    fi
    
    echo "-> Procesando arquitectura: ${ARCH}"
    mkdir -p "$INDEX_DIR"
    
    # 4.1. Generar el archivo Packages (AHORA DESCOMENTADO y usando rutas relativas)
    dpkg-scanpackages --arch "$ARCH" "$POOL_DIR" /dev/null > "${INDEX_DIR}/Packages"
    
    # 4.2. Generar el archivo Packages.gz (AHORA DESCOMENTADO y usando rutas relativas)
    echo "-> Comprimiendo Packages.gz..."
    gzip -9c "${INDEX_DIR}/Packages" > "${INDEX_DIR}/Packages.gz"
    
    echo "✅ Índices Packages para ${ARCH} generados en ${INDEX_DIR}"
done

# CRÍTICO: Regresar al directorio original
popd > /dev/null

# --- 5. Generación del archivo Release ---
echo "--- 5. Generando el archivo Release principal ---"

RELEASE_FILE="${REPO_ROOT}/dists/${DISTRIBUTION}/Release"
TEMP_RELEASE_FILE="${REPO_ROOT}/dists/${DISTRIBUTION}/Release.temp"

# Generar el archivo Release
cat <<EOT > "${TEMP_RELEASE_FILE}"
Origin: Channel9 Project Repository
Label: Channel9 Project
Suite: ${DISTRIBUTION}
Codename: ${DISTRIBUTION}
Version: 1.0
Date: $(LC_TIME=C date -R)
Architectures: $(echo ${ARCHITECTURES[@]})
Components: ${COMPONENT}
Description: Repositorio local de paquetes .deb para el Proyecto Channel9 (Instalacion Offline)
EOT

# Añadir el SHA256 (hashes de los archivos de índice)
echo "Generando sumas de verificación (Hashes SHA256)..."

# Lista los archivos de índice y calcula sus hashes
{
    echo "MD5Sum:"
    find "${REPO_ROOT}/dists/${DISTRIBUTION}/${COMPONENT}" -type f -exec md5sum {} + | sed "s|${REPO_ROOT}/dists/${DISTRIBUTION}/||" | awk '{printf " %s %10d %s\n", $1, $2, $3}'
    echo "SHA1:"
    find "${REPO_ROOT}/dists/${DISTRIBUTION}/${COMPONENT}" -type f -exec sha1sum {} + | sed "s|${REPO_ROOT}/dists/${DISTRIBUTION}/||" | awk '{printf " %s %10d %s\n", $1, $2, $3}'
    echo "SHA256:"
    find "${REPO_ROOT}/dists/${DISTRIBUTION}/${COMPONENT}" -type f -exec sha256sum {} + | sed "s|${REPO_ROOT}/dists/${DISTRIBUTION}/||" | awk '{printf " %s %10d %s\n", $1, $2, $3}'
} >> "${TEMP_RELEASE_FILE}"

# Mover el archivo temporal al archivo Release final
mv "${TEMP_RELEASE_FILE}" "${RELEASE_FILE}"

echo "✅ Archivo Release generado en ${RELEASE_FILE}"


# --- 6. Generación del archivo index.html con instrucciones (CORREGIDO) ---
echo "--- 6. Generando el archivo index.html con instrucciones de uso ---"

INDEX_FILE="${REPO_ROOT}/index.html"

# Construir dinámicamente las líneas de código para el sources.list
SOURCE_LIST_CODE="# 1. Añadir la fuente del repositorio (ejemplo usando la IP de eth0 o wlan0)\n"

# Asegurar que la IP de eth0 y wlan0, si existen, se usen para las instrucciones en el HTML
if [ -n "$ETH0_IP" ]; then
    SOURCE_LIST_CODE+="sudo sh -c 'echo \"deb http://${ETH0_IP}/${REPO_WEB_PATH} ${DISTRIBUTION} ${COMPONENT}\" > /etc/apt/sources.list.d/channel9.list'\n"
fi
if [ -n "$WLAN0_IP" ]; then
    SOURCE_LIST_CODE+="sudo sh -c 'echo \"deb http://${WLAN0_IP}/${REPO_WEB_PATH} ${DISTRIBUTION} ${COMPONENT}\" > /etc/apt/sources.list.d/channel9.list'\n"
fi
# Si no hay IPs, usamos el placeholder
if [ -z "$ETH0_IP" ] && [ -z "$WLAN0_IP" ]; then
    SOURCE_LIST_CODE+="sudo sh -c 'echo \"deb http://[IP-DEL-SERVIDOR]/${REPO_WEB_PATH} ${DISTRIBUTION} ${COMPONENT}\" > /etc/apt/sources.list.d/channel9.list'\n"
fi
# Eliminar la última nueva línea
SOURCE_LIST_CODE=$(echo -e "$SOURCE_LIST_CODE" | sed '$d')


cat <<EOT > "${INDEX_FILE}"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Repositorio Local Channel 9 - Debian</title>
    <style>
        body { font-family: sans-serif; line-height: 1.6; max-width: 800px; margin: 0 auto; padding: 20px; }
        code { background-color: #eee; padding: 2px 4px; border-radius: 3px; }
        pre code { display: block; background-color: #f4f4f4; padding: 10px; border: 1px solid #ddd; overflow-x: auto; }
        h1, h2 { border-bottom: 2px solid #ccc; padding-bottom: 5px; }
    </style>
</head>
<body>
    <h1>Repositorio Local de Paquetes Channel 9</h1>
    
    <p><a href="./pool/"><span style="font-size: 1.2em;">📁</span> **Navegar al Directorio de Paquetes (/pool/)**</a></p>

    <h2>Contenido del Repositorio</h2>
    <p>Este repositorio local contiene los paquetes <code>.deb</code> esenciales para el proyecto Channel 9 (automatización de radio con monitoreo de emergencias), diseñados para su instalación en entornos **sin conexión a Internet** basado en Debian 12 BookWorm (compatible con Raspberry Pi).</p>
    <p>Los paquetes clave incluyen:</p>
    <ul>
        <li><code>libretranslate-base</code> y sus modelos (e.g., <code>libretranslate-model-es_en</code>).</li>
        <li><code>libretranslate-service</code> (Servicio Systemd).</li>
        <li><code>whisper-cpp-cli</code> (Binario de transcripción).</li>
        <li><code>piper-tts</code> (Motor de Texto-a-Voz).</li>
    </ul>

    <p><strong>Ruta de Servidor Web (Web Path):</strong> <code>/${REPO_WEB_PATH}</code></p>
    <p><strong>Distribución:</strong> <code>${DISTRIBUTION}</code></p>
    <p><strong>Componente:</strong> <code>${COMPONENT}</code></p>


    <h2>Instrucciones de Uso (Estación Cliente)</h2>
    
    <p>Para añadir este repositorio a otra máquina Debian:</p>

    <pre><code>${SOURCE_LIST_CODE}

# 2. Actualizar el índice de paquetes
sudo apt update

# 3. Instalar los paquetes necesarios (ejemplo de instalación completa)
sudo apt install libretranslate-base libretranslate-service libretranslate-model-es-en whisper-cpp-cli piper-tts
</code></pre>

</body>
</html>
EOT

echo "✅ Archivo index.html generado en ${INDEX_FILE}"

# --- 7. Instrucciones para el usuario ---
echo "=========================================================="
echo "✅ REPOSITORIO DEBIAN LOCAL GENERADO CON ÉXITO!"
echo "=========================================================="
echo "Para usar este repositorio en otra maquina (o en la misma):"
echo ""
echo "1. Configura el servidor web local para servir la carpeta '${REPO_ROOT}'."
echo "2. Abre el archivo: ${REPO_ROOT}/index.html para ver las instrucciones completas y las IPs detectadas."
echo "3. En la maquina cliente, añade la fuente a APT, por ejemplo, usando la IP detectada para eth0:"
if [ -n "$ETH0_IP" ]; then
    echo "   sudo sh -c 'echo \"deb http://${ETH0_IP}/${REPO_WEB_PATH} ${DISTRIBUTION} ${COMPONENT}\" > /etc/apt/sources.list.d/channel9.list'"
fi
if [ -n "$WLAN0_IP" ]; then
    echo "   sudo sh -c 'echo \"deb http://${WLAN0_IP}/${REPO_WEB_PATH} ${DISTRIBUTION} ${COMPONENT}\" > /etc/apt/sources.list.d/channel9.list'"
fi
echo "4. Ejecuta:"
echo "   sudo apt update"
echo "   sudo apt install libretranslate-base libretranslate-service libretranslate-model-* whisper-cpp-cli piper-tts"
echo ""

