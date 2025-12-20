#!/bin/bash
### create_homepage.sh - Crea la página de inicio (Home) del Proyecto Channel 9

# --- Variables de Configuración ---
PUBLIC_HTML_DIR="${HOME}/public_html"
INDEX_FILE="${PUBLIC_HTML_DIR}/index.html"
REPO_PATH="/~$(whoami)/ch9/debian" # Ruta relativa para el repositorio local (ya existe el index.html en /ch9/debian)
LIBRETRANSLATE_PORT="5000" # Puerto por defecto para LibreTranslate (servido por Gunicorn)

# --- Detección de IP de Referencia ---
# Usamos una función robusta para obtener la IP de eth0 como referencia principal
get_ip() {
    ip addr show "$1" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1
}

SERVER_IP=$(get_ip "eth0")
if [ -z "$SERVER_IP" ]; then
    SERVER_IP="[IP-DEL-SERVIDOR-WEB]" # Placeholder si eth0 no tiene IP
fi

# --- 1. Control de Directorio ---
echo "--- 1. Verificando y creando directorio ${PUBLIC_HTML_DIR} ---"
if [ ! -d "$PUBLIC_HTML_DIR" ]; then
    echo "⚙️ Creando directorio ${PUBLIC_HTML_DIR}..."
    mkdir -p "$PUBLIC_HTML_DIR"
    # CRÍTICO: Asegurar permisos correctos para que el servidor web pueda leerlo
    chmod 755 "$PUBLIC_HTML_DIR"
    echo "Advertencia: Asegúrese de que 'mod_userdir' (o equivalente) esté activo en el servidor web."
fi

# --- 2. Generación del archivo index.html ---
echo "--- 2. Generando el archivo index.html en ${INDEX_FILE} ---"

cat <<EOT > "${INDEX_FILE}"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Channel 9 - Consola de Operación</title>
    <style>
        body { font-family: sans-serif; line-height: 1.6; max-width: 900px; margin: 0 auto; padding: 20px; background-color: #f4f4f4; }
        .container { background-color: #ffffff; padding: 30px; border-radius: 8px; box-shadow: 0 4px 8px rgba(0,0,0,0.1); }
        h1 { color: #007bff; border-bottom: 3px solid #007bff; padding-bottom: 10px; margin-bottom: 20px; }
        h2 { color: #333; margin-top: 30px; }
        .links a {
            display: block;
            margin: 15px 0;
            padding: 15px;
            background-color: #e9ecef;
            color: #007bff;
            text-decoration: none;
            border-radius: 5px;
            font-size: 1.2em;
            transition: background-color 0.3s;
            border: 1px solid #ced4da;
        }
        .links a:hover {
            background-color: #cfe2ff;
            color: #0056b3;
        }
        .icon { margin-right: 10px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>📻 Proyecto Channel 9 - Consola de Operación</h1>

        <h2>Introducción al Sistema</h2>
        <p>El proyecto Channel 9 es una solución de software libre diseñada para la **automatización de estaciones de radio**, con un enfoque principal en el **monitoreo de emergencias** y la eficiencia del operador.</p>
        <p>Su objetivo central es permitir que el operador de radio delegue la vigilancia constante de un canal al sistema. El sistema realiza las siguientes funciones clave:</p>
        <ul>
            <li>**Grabación y Transcripción:** Graba el audio del canal y lo transcribe en tiempo real usando **Whisper.cpp**.</li>
            <li>**Alerta Inteligente:** Si detecta palabras clave de emergencia predefinidas (configuradas en el programa CH9-Config), envía inmediatamente un correo electrónico al operador con la transcripción y el archivo de audio.</li>
            <li>**Funcionalidades Adicionales:** Soporta modos como "Secretaría Telefónica" (envía todos los mensajes) y "Repetidor Loro/Parrot" (repite el último mensaje, activado por DTMF).</li>
        </ul>
        <p><strong>Tecnologías Clave:</strong> SOX, FFmpeg, **Whisper.cpp**, **Piper TTS** y **LibreTranslate**.</p>
        <p>El sistema está diseñado para una instalación <strong>sin internet</strong> en Debian 12 (Raspberry Pi compatible).</p>

        <h2>Enlaces de Acceso y Gestión</h2>

        <div class="links">
            <a href="http://${SERVER_IP}:${LIBRETRANSLATE_PORT}" target="_blank">
                <span class="icon">🌐</span> Acceso Directo a LibreTranslate (Traductor Web)
            </a>
            <p style="font-size: 0.9em; margin-top: -10px; margin-bottom: 20px; color: #6c757d;">*(Si el servicio LibreTranslate está activo)*</p>

            <a href="${REPO_PATH}" target="_blank">
                <span class="icon">📦</span> Repositorio Local de Paquetes Debian
            </a>
            <p style="font-size: 0.9em; margin-top: -10px; margin-bottom: 20px; color: #6c757d;">*(Contiene los paquetes .deb necesarios para la instalación offline en estaciones cliente.)*</p>
        </div>

        <p style="font-size: 0.8em; text-align: center; color: #999; margin-top: 40px;">Ruta de acceso web: <code>http://${SERVER_IP}/~$(whoami)/ch9/</code></p>
    </div>
</body>
</html>
EOT

echo "✅ Página de inicio generada con éxito en ${INDEX_FILE}"
echo "La página es accesible en: http://${SERVER_IP}/~$(whoami)/"

