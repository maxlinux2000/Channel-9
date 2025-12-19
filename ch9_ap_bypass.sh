#!/bin/bash
### ch9_ap_bypass.sh - Configura DNS y Webserver para engañar al Captive Portal de Android.

# --- Variables Globales ---
STATION_IP="192.168.1.2"
CHECK_PATH="/generate_204"

# Lista de dominios que Android y Google usan para el chequeo de conectividad
CHECK_DOMAINS=(
    "connectivitycheck.gstatic.com"
    "www.gstatic.com"
    "clients3.google.com"
)

# --- 1. Instalación del Servidor Web (Lighttpd) ---
echo "--- 1. Instalando Lighttpd (Servidor Web Ligero)... ---"
sudo apt update
sudo apt install -y lighttpd

# --- 2. Configuración del Servidor DNS (BIND9) ---
echo "--- 2. Configurando BIND9 para resolver los dominios de chequeo a $STATION_IP ---"

DB_FILE="/etc/bind/db.mi.atalaya"
ENTRY_COUNT=0

for DOMAIN in "${CHECK_DOMAINS[@]}"; do
    if ! sudo grep -q "$DOMAIN" "$DB_FILE"; then
        # Aseguramos que solo se añade si no existe.
        echo "INFO: Añadiendo entrada A para $DOMAIN en $DB_FILE."
        # Usamos sh -c para escribir con sudo al final del archivo de zona
        sudo sh -c "echo \"$DOMAIN. IN A $STATION_IP\" >> \"$DB_FILE\""
        ENTRY_COUNT=$((ENTRY_COUNT + 1))
    else
        echo "INFO: Entrada DNS para $DOMAIN ya existe."
    fi
done

if [ "$ENTRY_COUNT" -gt 0 ]; then
    # Reiniciar BIND9 solo si se hicieron cambios
    sudo systemctl restart bind9
    echo "INFO: DNS BIND9 recargado."
fi

# --- 3. Configuración del Servidor Web (Lighttpd) ---

# 3.1. Habilitar módulo 'setenv' para forzar la respuesta 204
echo "--- 3. Habilitando módulo 'setenv' de Lighttpd... ---"
sudo lighty-enable-mod setenv 2>/dev/null

# 3.2. Crear el archivo de configuración para interceptar la ruta /generate_204
LIGHTTPD_CONF="/etc/lighttpd/conf-available/99-captive-bypass.conf"

echo "--- 3.3. Creando la configuración de bypass para Lighttpd ---"

# Este bloque fuerza una respuesta '204 No Content' para la ruta de chequeo.
sudo sh -c "
cat <<EOF > \"$LIGHTTPD_CONF\"
\$HTTP[\"url\"] =~ \"^$CHECK_PATH\" {
    # CRÍTICO: Forzar el código de estado 204 (el que indica éxito sin contenido)
    # Usamos setenv.add-response-header para añadir el código Status 204.
    # NOTA: En Lighttpd, la forma más limpia y robusta de devolver 204
    # es usar mod_magnet/LUA o forzar el encabezado en un bloque condicional.
    # Aquí, usamos el método 'setenv' que funciona en muchas instalaciones.
    setenv.add-response-header = ( \"Status\" => \"204 No Content\" )
    # Apuntamos a un archivo vacío o inexistente para no enviar contenido.
    server.document-root = \"/var/www/html\"
    server.error-handler-404 = \"/dev/null\"
}
EOF
"

# --- 3.4. Habilitar el archivo de configuración y reiniciar Lighttpd ---
sudo lighty-enable-mod 99-captive-bypass 2>/dev/null
sudo systemctl restart lighttpd
echo "INFO: Lighttpd configurado para responder 204 a los chequeos de conectividad."

echo "=========================================================="
echo "✅ BYPASS DE CONECTIVIDAD PARA ANDROID CONFIGURADO."
echo "   - Ahora cubrimos los 3 dominios principales de chequeo de Google."
echo "=========================================================="

