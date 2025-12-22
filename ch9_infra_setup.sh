#!/bin/bash
### ch9_infra_setup.sh - Configura DNS (bind9) y Correo (Postfix/Dovecot)

# --- Variables Globales ---
DOMAIN="mi.atalaya"
MAIL_PASS="preparandonos"
MAIL_USERS=("ch9" "yo")

# --- Detección Dinámica de IP y de Interfaz ---

# Función robusta para obtener la IP de la interfaz activa que tiene ruta a Internet
get_active_ip() {
    ip route get 8.8.8.8 2>/dev/null | awk '{
        for(i=1; i<=NF; i++) {
            if ($i == "src") {
                print $(i+1);
                exit;
            }
        }
    }'
}

# Función robusta para obtener el nombre de la interfaz activa
get_active_interface() {
    ip route get 8.8.8.8 2>/dev/null | awk '{
        for(i=1; i<=NF; i++) {
            if ($i == "dev") {
                print $(i+1);
                exit;
            }
        }
    }'
}

STATION_IP=$(get_active_ip)
NET_INTERFACE=$(get_active_interface)

if [ -z "$STATION_IP" ]; then
    echo "🚨 ERROR CRÍTICO: No se pudo detectar una IP activa ni una interfaz de red. Asegúrese de que la máquina está conectada a una red (por DHCP o IP estática)."
    exit 1
fi

echo "INFO: Interfaz activa detectada: $NET_INTERFACE con IP: $STATION_IP."

# --- 1. Verificación e Instalación de Paquetes ---
echo "--- 1. Instalando dependencias (DNS, Mail)... ---"
sudo apt update
sudo apt install -y bind9 postfix dovecot-imapd dovecot-pop3d

# --- 2. Configuración de la Interfaz de Red Local (Saltada) ---
echo "--- 2. Saltando la configuración de IP estática. Usaremos la IP detectada. ---"

# --- 3. Configuración del Servidor DNS (bind9) ---
echo "--- 3. Configurando BIND9 (DNS) para $DOMAIN ---"

# 3.1. Configuración de zona local en named.conf.local
ZONE_CONFIG="/etc/bind/named.conf.local"

# CRÍTICO 1: Eliminar definiciones anteriores antes de agregar una nueva para evitar duplicados.
sudo sed -i '/zone "mi.atalaya" {/,/};/d' "$ZONE_CONFIG"

# Usamos <<-EOT y sangría con TAB
sudo sh -c "
cat <<-EOT >> \"$ZONE_CONFIG\"
    zone \"$DOMAIN\" {
        type master;
        file \"/etc/bind/db.$DOMAIN\";
    };
EOT
"
echo "INFO: Zona $DOMAIN definida correctamente en named.conf.local (sin duplicados)."

# 3.2. Creación del archivo de zona db.mi.atalaya
DB_FILE="/etc/bind/db.$DOMAIN"
CURRENT_SERIAL=$(date +%Y%m%d%S) 
DOMAIN_FQDN="${DOMAIN}."

# CRÍTICO: Usamos echo + sudo mv para evitar problemas de espaciado/caracteres invisibles.
echo "\$TTL 604800
\$ORIGIN ${DOMAIN_FQDN}
@ IN SOA ${DOMAIN_FQDN} root.${DOMAIN_FQDN} (
    ${CURRENT_SERIAL} ; Serial 
    604800  ; Refresh
    86400   ; Retry
    2419200 ; Expire
    604800 ) ; Negative Cache TTL
@ IN NS ${DOMAIN_FQDN}
@ IN A $STATION_IP
mail IN A $STATION_IP
pop3 IN A $STATION_IP
imap IN A $STATION_IP
@ IN MX 10 mail.${DOMAIN_FQDN}
" > /tmp/DB

sudo mv /tmp/DB "$DB_FILE"

# 3.3. Arreglo de permisos y Verificación
sudo chown root:bind "$DB_FILE"
sudo chmod 644 "$DB_FILE"

# Verificamos la sintaxis del archivo de zona
echo "INFO: Verificando sintaxis del archivo de zona..."
sudo named-checkzone "$DOMAIN" "$DB_FILE" || { echo "🚨 ERROR CRÍTICO: Fallo en la sintaxis del archivo de zona. Deteniendo."; exit 1; }

# --- 3.4. Configurar Reenvío (Forwarding) de BIND9 (NUEVA SECCIÓN) ---
echo "--- 3.4. Configurando BIND9 como servidor de reenvío (Forwarder) ---"
OPTIONS_FILE="/etc/bind/named.conf.options"
FORWARDERS_BLOCK='forwarders { 1.1.1.1; 8.8.8.8; };'

# CRÍTICO: Limpiar cualquier configuración de forwarders previa.
sudo sed -i '/forwarders {/,/};/d' "$OPTIONS_FILE"

# Insertar el bloque de forwarders dentro del bloque 'options { ... }'
sudo awk -i inplace '/options {/ {print; print "    '"$FORWARDERS_BLOCK"'"} !/options {/ {print}' "$OPTIONS_FILE"

echo "INFO: Añadido reenvío DNS (1.1.1.1 y 8.8.8.8) a named.conf.options."


# 3.5. Reiniciar BIND9 (Movido aquí para cargar la nueva configuración de forwarders)
sudo systemctl restart bind9 || { echo "🚨 ERROR: Fallo al reiniciar named.service (BIND9). Revise los logs (journalctl -xeu named.service). Deteniendo."; exit 1; }
echo "INFO: DNS configurado para $DOMAIN. A records apuntan a $STATION_IP. Ahora reenvía peticiones externas."


# --- 4. Configuración del Servidor de Correo (Postfix y Dovecot) ---
echo "--- 4. Configurando Correo Local (Postfix/Dovecot) para $DOMAIN ---"

# 4.1. Postfix: Configurar para recibir correo localmente para el dominio
POSTFIX_CONF="/etc/postfix/main.cf"
sudo postconf -e "mydestination = localhost, $DOMAIN, $STATION_IP"
sudo postconf -e "mydomain = $DOMAIN"
sudo postconf -e "myhostname = mail.$DOMAIN"
sudo postconf -e "virtual_alias_maps = hash:/etc/postfix/virtual"
# Usamos Maildir para compatibilidad con Dovecot
sudo postconf -e "home_mailbox = Maildir/"

# 4.2. Crear el archivo de aliases virtuales
VIRTUAL_FILE="/etc/postfix/virtual"
sudo sh -c "
echo \"ch9@$DOMAIN ${MAIL_USERS[0]}\" > \"$VIRTUAL_FILE\"
echo \"yo@$DOMAIN ${MAIL_USERS[1]}\" >> \"$VIRTUAL_FILE\"
"
sudo postmap "$VIRTUAL_FILE"
sudo systemctl restart postfix
echo "INFO: Postfix configurado."

# 4.3. Crear los usuarios del sistema para los buzones y establecer contraseña por defecto
for user in "${MAIL_USERS[@]}"; do
    if ! id -u "$user" >/dev/null 2>&1; then
        echo "INFO: Creando usuario de sistema '$user' para buzón..."
        sudo useradd -m -s /bin/bash "$user"
    fi
    echo "$user:$MAIL_PASS" | sudo chpasswd
done

# 4.4. Dovecot: Configurar Maildir y protocolo IMAP/POP3
echo "INFO: Configurando Maildir para Dovecot..."
DOVECOT_CONF="/etc/dovecot/conf.d/10-mail.conf"
# Uso de '|' como delimitador de sed para evitar el error de sintaxis con '/'.
sudo sed -i 's|^#mail_location = maildir:~/Maildir|mail_location = maildir:~/Maildir|' "$DOVECOT_CONF"

# 4.5. Dovecot: Configuración de escucha
echo "INFO: Omitiendo la configuración de IP de escucha, el valor por defecto (*) es adecuado para un entorno de IP dinámica."

# 4.6. Reiniciar Dovecot
sudo systemctl restart dovecot
echo "INFO: Dovecot (IMAP/POP3) configurado. Cuentas: ch9@$DOMAIN, yo@$DOMAIN. Contraseña: $MAIL_PASS"

echo "=========================================================="
echo "✅ CONFIGURACIÓN DE INFRAESTRUCTURA LOCAL COMPLETADA."
echo "   - Interfaz Detectada: $NET_INTERFACE"
echo "   - IP de la Estación: $STATION_IP (Usando IP asignada por la red externa)."
echo "   - Dominio Local: $DOMAIN"
echo "   - CRÍTICO: Los clientes DEBEN usar la IP de la estación ($STATION_IP) como servidor DNS para resolver $DOMAIN y el resto de dominios."
echo "=========================================================="

