#!/bin/bash
### ch9_infra_setup.sh - Configura DNS (bind9) y Correo (Postfix/Dovecot) para Channel-9

# --- Variables Globales ---
DOMAIN="mi.atalaya"
MAIL_PASS="preparandonos"
MAIL_USERS=("ch9" "yo")

# ==============================================================================
# 1. DETECCIÓN DE RED
# ==============================================================================

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

# ==============================================================================
# 2. FUNCIONES DE INFRAESTRUCTURA
# ==============================================================================

# ------------------------------------------------------------------------------
# FUNCIÓN: configure_networkmanager_dns_local
# ------------------------------------------------------------------------------
configure_networkmanager_dns_local() {
    local SERVER_IP="$1"
    local NM_CONF="/etc/NetworkManager/NetworkManager.conf"
    local RESOLV_CONF="/etc/resolv.conf"

    echo "--- Configurando NetworkManager para DNS Local (IP: $SERVER_IP) ---"

    # 1. Modificar /etc/NetworkManager/NetworkManager.conf
    echo "Paso 1: Editando $NM_CONF para deshabilitar la gestión de DNS..."

    # Usamos sed para añadir dns=none y rc-manager=unmanaged en la sección [main]
    sudo sed -i '/^\[main\]/a dns=none\nrc-manager=unmanaged' "$NM_CONF"
    
    # Limpiar duplicados y garantizar que la configuración se aplica
    sudo sed -i '/^dns=none/!s/^dns=.*/dns=none/' "$NM_CONF"
    sudo sed -i '/^rc-manager=unmanaged/!s/^rc-manager=.*/rc-manager=unmanaged/' "$NM_CONF"
    
    # 2. Desactivar systemd-resolved (si está activo y enlazado)
    if [ -L /etc/resolv.conf ] && [ "$(readlink -f /etc/resolv.conf)" = "/run/systemd/resolve/stub-resolv.conf" ]; then
        echo "Paso 2: Deshabilitando y deteniendo systemd-resolved..."
        sudo systemctl disable systemd-resolved --now
        sudo rm "$RESOLV_CONF"
    fi

    # 3. Establecer el servidor DNS local en /etc/resolv.conf
    echo "Paso 3: Estableciendo 127.0.0.1 como nameserver principal..."
    
    echo "# Generado por Channel-9 setup (Local BIND9)" | sudo tee "$RESOLV_CONF" > /dev/null
    echo "nameserver 127.0.0.1" | sudo tee -a "$RESOLV_CONF" > /dev/null
    
    # 4. Reiniciar servicios
    echo "Paso 4: Reiniciando NetworkManager..."
    sudo systemctl restart NetworkManager

    echo "✅ Configuración de DNS local completada. El sistema consultará a BIND9 localmente (127.0.0.1)."
}

# ------------------------------------------------------------------------------
# FUNCIÓN: generate_local_ssl_cert
# ------------------------------------------------------------------------------
generate_local_ssl_cert() {
    echo "--- Generando Certificado Self-Signed para el Dominio de Correo ---"
    
    local LOCAL_DOMAIN="mail.$DOMAIN"
    local CERT_DIR="/etc/ssl/local-certs"

    if [ -f "$CERT_DIR/$LOCAL_DOMAIN.crt" ] && openssl x509 -noout -subject -in "$CERT_DIR/$LOCAL_DOMAIN.crt" | grep -q "CN=$LOCAL_DOMAIN"; then
        echo "INFO: Certificado para $LOCAL_DOMAIN ya existe y tiene el CN correcto. Omitiendo la generación."
        return 0
    fi

    sudo mkdir -p "$CERT_DIR"
    sudo chmod 700 "$CERT_DIR"

    echo "🚀 Generando clave privada y certificado self-signed (3650 días)..."
    sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$CERT_DIR/$LOCAL_DOMAIN.key" \
        -out "$CERT_DIR/$LOCAL_DOMAIN.crt" \
        -subj "/C=ES/ST=Local/L=Atalaya/O=Channel9-Project/CN=$LOCAL_DOMAIN" \
        -addext "subjectAltName = DNS:$LOCAL_DOMAIN, DNS:mail"

    if [ $? -ne 0 ]; then
        echo "🚨 ERROR: Fallo al generar el certificado con OpenSSL."
        return 1
    fi

    echo "--- Configurando Postfix y Dovecot para usar el nuevo certificado ---"
    
    # Postfix (main.cf)
    sudo postconf -e "smtpd_tls_cert_file=$CERT_DIR/$LOCAL_DOMAIN.crt"
    sudo postconf -e "smtpd_tls_key_file=$CERT_DIR/$LOCAL_DOMAIN.key"

    # Dovecot (10-ssl.conf)
    local DOVECOT_SSL_CONF="/etc/dovecot/conf.d/10-ssl.conf"
    if [ -f "$DOVECOT_SSL_CONF" ]; then
        sudo sed -i "s|^#*ssl_cert = .*|ssl_cert = <$CERT_DIR/$LOCAL_DOMAIN.crt|" $DOVECOT_SSL_CONF
        sudo sed -i "s|^#*ssl_key = .*|ssl_key = <$CERT_DIR/$LOCAL_DOMAIN.key|" $DOVECOT_SSL_CONF
    else
        echo "🚨 Advertencia: Archivo $DOVECOT_SSL_CONF no encontrado. Omisión de la configuración de Dovecot SSL."
    fi

    echo "✅ Certificado self-signed para $LOCAL_DOMAIN configurado."
}

# ------------------------------------------------------------------------------
# FUNCIÓN: enable_postfix_submission
# ------------------------------------------------------------------------------
enable_postfix_submission() {
    echo "--- Activando el servicio 'submission' (puerto 587) en Postfix ---"
    local MASTER_CF="/etc/postfix/master.cf"
    
    if [ ! -f "$MASTER_CF" ]; then
        echo "🚨 ERROR: Archivo $MASTER_CF no encontrado. Postfix no está instalado o la ruta es incorrecta."
        return 1
    fi
    
    # 1. Descomentar la línea principal de 'submission'
    sudo sed -i '/^#submission\s\+inet/s/^#//' "$MASTER_CF"
    
    # 2. Descomentar las opciones clave para seguridad y autenticación (MSA)
    sudo sed -i '/^submission\s\+inet\s\+n/ {
        n; s/^#\s\+-o syslog_name=postfix\/submission/\t-o syslog_name=postfix\/submission/
        n; s/^#\s\+-o smtpd_tls_security_level=encrypt/\t-o smtpd_tls_security_level=encrypt/
        n; s/^#\s\+-o smtpd_sasl_auth_enable=yes/\t-o smtpd_sasl_auth_enable=yes/
        n; s/^#\s\+-o smtpd_tls_auth_only=yes/\t-o smtpd_tls_auth_only=yes/
    }' "$MASTER_CF"
    
    echo "Paso 2: Opciones de TLS/Autenticación descomentadas."

    # 3. Reiniciar Postfix (será reiniciado de nuevo al final, pero lo hacemos ahora para el puerto)
    echo "Paso 3: Reiniciando el servicio Postfix..."
    sudo systemctl restart postfix
    
    if [ $? -eq 0 ]; then
        echo "✅ Postfix reiniciado. El puerto 587 ahora debería estar activo."
    else
        echo "🚨 ERROR: Fallo al reiniciar Postfix."
        return 1
    fi
}

# ==============================================================================
# 3. INSTALACIÓN Y CONFIGURACIÓN CORE
# ==============================================================================

# --- 3.0. Instalación de Paquetes ---
echo "--- 3.0. Instalando dependencias (DNS, Mail, SSL)... ---"
sudo apt update
sudo apt install -y bind9 postfix dovecot-imapd dovecot-pop3d openssl net-tools

# --- 3.1. Configuración del Servidor DNS (bind9) ---
echo "--- 3.1. Configurando BIND9 (DNS) para $DOMAIN ---"
ZONE_CONFIG="/etc/bind/named.conf.local"
DB_FILE="/etc/bind/db.$DOMAIN"

# 3.1.1. Definición de zona en named.conf.local
sudo sed -i '/zone "mi.atalaya" {/,/};/d' "$ZONE_CONFIG"
sudo sh -c "
cat <<-EOT >> \"$ZONE_CONFIG\"
    zone \"$DOMAIN\" {
        type master;
        file \"/etc/bind/db.$DOMAIN\";
    };
EOT
"

# 3.1.2. Creación del archivo de zona db.mi.atalaya
CURRENT_SERIAL=$(date +%Y%m%d%S)
DOMAIN_FQDN="${DOMAIN}."

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

# 3.1.3. Arreglo de permisos y Reiniciar BIND9
sudo chown root:bind "$DB_FILE"
sudo chmod 644 "$DB_FILE"

sudo named-checkzone "$DOMAIN" "$DB_FILE" || { echo "🚨 ERROR CRÍTICO: Fallo en la sintaxis del archivo de zona. Deteniendo."; exit 1; }
sudo systemctl restart bind9 || { echo "🚨 ERROR: Fallo al reiniciar named.service (BIND9). Deteniendo."; exit 1; }

echo "INFO: DNS configurado para $DOMAIN. A records apuntan a $STATION_IP."

# --- 3.2. Configuración del DNS del Cliente Local (CH9) ---
echo "--- 3.2. Asegurando que el sistema CH9 use su propio BIND9 ---"
configure_networkmanager_dns_local "127.0.0.1" # Usamos loopback (127.0.0.1) ya que BIND está en la misma máquina.


# --- 4. Configuración del Servidor de Correo (Postfix y Dovecot) ---
echo "--- 4. Configurando Correo Local (Postfix/Dovecot) para $DOMAIN ---"

# 4.1. Postfix: Configuración principal
POSTFIX_CONF="/etc/postfix/main.cf"
sudo postconf -e "mydestination = localhost, $DOMAIN, $STATION_IP"
sudo postconf -e "mydomain = $DOMAIN"
sudo postconf -e "myhostname = mail.$DOMAIN"
sudo postconf -e "virtual_alias_maps = hash:/etc/postfix/virtual"
sudo postconf -e "home_mailbox = Maildir/"

# 4.2. Crear el archivo de aliases virtuales y postmap
VIRTUAL_FILE="/etc/postfix/virtual"
sudo sh -c "
echo \"ch9@$DOMAIN ${MAIL_USERS[0]}\" > \"$VIRTUAL_FILE\"
echo \"yo@$DOMAIN ${MAIL_USERS[1]}\" >> \"$VIRTUAL_FILE\"
"
sudo postmap "$VIRTUAL_FILE"

# 4.3. Activar Servicio SMTP/MSA (Puerto 587)
enable_postfix_submission

# 4.4. Generar y Configurar Certificado SSL Local
generate_local_ssl_cert

# 4.5. Crear usuarios de sistema y establecer contraseña
for user in "${MAIL_USERS[@]}"; do
    if ! id -u "$user" >/dev/null 2>&1; then
        echo "INFO: Creando usuario de sistema '$user' para buzón..."
        sudo useradd -m -s /bin/bash "$user"
    fi
    echo "$user:$MAIL_PASS" | sudo chpasswd
done

# 4.6. Dovecot: Configurar Maildir y protocolo IMAP/POP3
echo "INFO: Configurando Maildir para Dovecot..."
DOVECOT_CONF="/etc/dovecot/conf.d/10-mail.conf"
# Uso de un delimitador distinto al '/'
sudo sed -i 's|^#mail_location = maildir:~/Maildir|mail_location = maildir:~/Maildir|' "$DOVECOT_CONF"

# 4.7. Reiniciar Servicios Finales
echo "--- 5. Reinicio Final de Servicios Clave ---"
sudo systemctl restart bind9
sudo systemctl restart postfix
sudo systemctl restart dovecot
echo "INFO: Dovecot (IMAP/POP3) configurado. Cuentas: ch9@$DOMAIN, yo@$DOMAIN. Contraseña: $MAIL_PASS"

echo "=========================================================="
echo "✅ CONFIGURACIÓN DE INFRAESTRUCTURA LOCAL COMPLETADA."
echo "   - Interfaz Detectada: $NET_INTERFACE"
echo "   - IP de la Estación: $STATION_IP"
echo "   - Dominio Local: $DOMAIN (Resuelto por BIND9 en 127.0.0.1)"
echo "   - Cuentas de Correo Creadas: ch9@$DOMAIN y yo@$DOMAIN (Pass: $MAIL_PASS)"
echo "   - PRUEBA: Usa 'dig mi.atalaya' en el servidor CH9 para verificar la resolución."
echo "=========================================================="

