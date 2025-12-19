#!/bin/bash
### ch9_infra_setup.sh - Configura DNS (bind9) y Correo (Postfix/Dovecot)

# --- Variables Globales ---
DOMAIN="mi.atalaya"
STATION_IP="192.168.1.2"
# Asume que esta es la interfaz local (ej. la tarjeta Wi-Fi)
# NOTA: La interfaz física ahora debe ser configurada con la IP 192.168.1.1 
# Y debe estar conectada al router externo que proporciona DHCP/AP.
NET_INTERFACE="wlan0" 
NETMASK="255.255.255.0"
MAIL_PASS="preparandonos"

# Cuentas de correo (son usuarios del sistema para simplificar Postfix/Dovecot)
MAIL_USERS=("ch9" "yo")

# --- 1. Verificación e Instalación de Paquetes ---
echo "--- 1. Instalando dependencias (DNS, Mail)... ---"
sudo apt update
# Eliminamos 'isc-dhcp-server' de la instalación
sudo apt install -y bind9 postfix dovecot-imapd dovecot-pop3d

# --- 2. Configuración de la Interfaz de Red Local (IP Estática) ---
echo "--- 2. Configurando IP estática para $NET_INTERFACE ($STATION_IP) ---"

# Usamos 'ip' para asignar temporalmente y 'echo' para mostrar la acción
# NOTA: En un entorno de producción, asegúrate de que NET_INTERFACE 
# no está siendo gestionada por NetworkManager o dhcpcd.
sudo ip addr flush dev "$NET_INTERFACE" 2>/dev/null
sudo ip addr add "$STATION_IP/$NETMASK" dev "$NET_INTERFACE"
echo "INFO: Configuración de la IP estática $STATION_IP en $NET_INTERFACE."

# --- 3. Configuración del Servidor DNS (bind9) ---
echo "--- 3. Configurando BIND9 (DNS) para $DOMAIN ---"

# 3.1. Configuración de zona local en named.conf.local
ZONE_CONFIG="/etc/bind/named.conf.local"
sudo sh -c "
echo 'zone \"$DOMAIN\" {
    type master;
    file \"/etc/bind/db.$DOMAIN\";
};' >> \"$ZONE_CONFIG\"
"

# 3.2. Creación del archivo de zona db.mi.atalaya
DB_FILE="/etc/bind/db.$DOMAIN"
# Extraemos el primer octeto de la IP para el campo SOA (Serial)
IP_OCTET=$(echo "$STATION_IP" | cut -d '.' -f1) 

sudo sh -c "
cat <<EOF > \"$DB_FILE\"
\$TTL 604800
@ IN SOA $DOMAIN. root.$DOMAIN. (
    $IP_OCTET ; Serial
    604800  ; Refresh
    86400   ; Retry
    2419200 ; Expire
    604800 ) ; Negative Cache TTL
@ IN NS $DOMAIN.
@ IN A $STATION_IP
mail IN A $STATION_IP
pop3 IN A $STATION_IP
imap IN A $STATION_IP
@ IN MX 10 mail.$DOMAIN.
EOF
"
# 3.3. Reiniciar BIND9
sudo systemctl restart bind9
echo "INFO: DNS configurado para $DOMAIN."

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

# 4.2. Crear el archivo de aliases virtuales (necesario para las cuentas de DeltaChat)
VIRTUAL_FILE="/etc/postfix/virtual"
sudo sh -c "
echo \"ch9@$DOMAIN $MAIL_USERS[0]\" > \"$VIRTUAL_FILE\"
echo \"yo@$DOMAIN $MAIL_USERS[1]\" >> \"$VIRTUAL_FILE\"
"
sudo postmap "$VIRTUAL_FILE"
sudo systemctl restart postfix
echo "INFO: Postfix configurado."

# 4.3. Crear los usuarios del sistema para los buzones (si no existen) y establecer contraseña por defecto
for user in "${MAIL_USERS[@]}"; do
    if ! id -u "$user" >/dev/null 2>&1; then
        echo "INFO: Creando usuario de sistema '$user' para buzón..."
        # El usuario será sin login shell y sin directorio home
        sudo useradd -m -s /bin/bash "$user"
    fi
    # Establecer la contraseña por defecto (debe hacerse con un pipe seguro)
    echo "$user:$MAIL_PASS" | sudo chpasswd
done

# 4.4. Dovecot: Configurar Maildir y protocolo IMAP/POP3
DOVECOT_CONF="/etc/dovecot/conf.d/10-mail.conf"
sudo sed -i "s/^#mail_location = maildir:~/Maildir/mail_location = maildir:~/Maildir/" "$DOVECOT_CONF"

# 4.5. Dovecot: Forzar que solo escuche en la IP local de la estación
PROTOCOL_CONF="/etc/dovecot/conf.d/10-listen.conf"
# Permitir escuchar en todas las interfaces por defecto (más seguro en entornos locales)
# Si queremos forzar solo 192.168.1.1, descomentar la siguiente línea:
# sudo sed -i 's/^#listen = \*/listen = 192.168.1.1/' "$PROTOCOL_CONF"

# 4.6. Reiniciar Dovecot
sudo systemctl restart dovecot
echo "INFO: Dovecot (IMAP/POP3) configurado. Cuentas: ch9@$DOMAIN, yo@$DOMAIN. Contraseña: $MAIL_PASS"

echo "=========================================================="
echo "✅ CONFIGURACIÓN DE INFRAESTRUCTURA LOCAL COMPLETADA."
echo "   - Interfaz Local: $NET_INTERFACE ($STATION_IP)"
echo "   - Dominio Local: $DOMAIN"
echo "   - Clientes DEBEN usar la IP de la estación ($STATION_IP) como DNS Server."
echo "   - La función AP/DHCP la proporciona un router externo."
echo "=========================================================="

