#!/bin/bash
# Script de configuración de msmtp y mutt para Channel-9 (CH9)

# -----------------------------------------------------
# PARÁMETROS DE CONFIGURACIÓN DEL SERVIDOR DE CORREO
# -----------------------------------------------------
SERVER_ADDRESS="mi.arca"
SMTP_PORT="587"
# Usaremos la cuenta ch9@mi.arca para autenticar y para el campo "From"
SMTP_USER="ch9@mi.arca"
SMTP_PASSWORD="preparandonos" # <--- ¡IMPORTANTE! ¡CÁMBIALO!
FROM_ADDRESS="Channel-9 <ch9@mi.arca>" 
TEST_TO_ADDRESS="yo@mi.arca"

# Definimos el nombre de la cuenta msmtp para referencia
MSMTP_ACCOUNT_NAME="ch9" 
# Definimos la ruta completa del script wrapper (usando .local/bin)
WRAPPER_SCRIPT="$HOME/.local/bin/mutt-msmtp.sh"

# -----------------------------------------------------
# VERIFICACIÓN DE USUARIO
# -----------------------------------------------------

# Comprobar si el usuario actual es root.
if [ "$(id -u)" -eq 0 ]; then
   echo "ERROR: ¡No ejecutes este script como root! Ejecútalo con el usuario normal (ej. 'max')."
   echo "El script pedirá la contraseña de sudo cuando sea necesario."
   exit 1
fi

echo "Actualizando listas de paquetes e instalando mutt y msmtp..."
sudo apt update
sudo apt install -y mutt msmtp

# -----------------------------------------------------
# CREACIÓN DEL ARCHIVO DE CONFIGURACIÓN GLOBAL /etc/msmtprc
# -----------------------------------------------------

echo "Creando el archivo de configuración global /etc/msmtprc..."

# Usamos /tmp para escribir el archivo y luego moverlo con sudo
cat <<EOF > /tmp/msmtprc
# Configuración global para msmtp (Channel-9)

defaults
auth           on
tls            on
tls_starttls   on
tls_certcheck  off
account        $MSMTP_ACCOUNT_NAME
host           $SERVER_ADDRESS
port           $SMTP_PORT
user           $SMTP_USER
password       $SMTP_PASSWORD
from           $FROM_ADDRESS
logfile        /var/log/msmtp.log
EOF

sudo mv /tmp/msmtprc  /etc/msmtprc

# Permisos de seguridad
sudo chmod 600 /etc/msmtprc

# FIX: Corregir permisos del archivo de registro
LOG_FILE="/var/log/msmtp.log"
echo "Asegurando permisos de escritura para el archivo de registro: $LOG_FILE"
# 1. Crear el archivo de log si no existe (con sudo)
sudo touch "$LOG_FILE"
# 2. Cambiar el propietario del archivo de log al usuario actual ($USER)
sudo chown $USER:$USER "$LOG_FILE"

# -----------------------------------------------------
# CREACIÓN DEL WRAPPER SCRIPT
# -----------------------------------------------------

echo "Creando carpeta de binarios local $HOME/.local/bin y script wrapper..."
mkdir -p "$HOME/.local/bin"

# El script wrapper llama a msmtp y fuerza el uso de la cuenta 'ch9'
cat <<EOF > "$WRAPPER_SCRIPT"
#!/bin/bash
# Wrapper para que mutt use la cuenta '$MSMTP_ACCOUNT_NAME'
exec /usr/bin/msmtp -a $MSMTP_ACCOUNT_NAME "\$@"
EOF

# Dar permisos de ejecución
chmod +x "$WRAPPER_SCRIPT"

# -----------------------------------------------------
# CREACIÓN DEL ARCHIVO DE CONFIGURACIÓN LOCAL $HOME/.muttrc
# -----------------------------------------------------

echo "Creando el archivo de configuración local de mutt ($HOME/.muttrc)..."

cat <<EOF > "$HOME/.muttrc"
# Configuración de Mutt para Channel-9 (FIXED con Wrapper)

# Especifica el script wrapper que fuerza la cuenta 'ch9' en msmtp.
set sendmail="$WRAPPER_SCRIPT"
set realname="$FROM_ADDRESS"
set from="$SMTP_USER"
EOF

# Permisos de muttrc
chmod 644 "$HOME/.muttrc"

# -----------------------------------------------------
# ENLACE SIMBÓLICO PARA COMPATIBILIDAD CON COMANDOS LEGACY (mail)
# -----------------------------------------------------

# Asegurar que 'sendmail' apunte a 'msmtp'
if [ ! -L /usr/sbin/sendmail ] || [ "$(readlink /usr/sbin/sendmail)" != "/usr/bin/msmtp" ]; then
    echo "Creando enlace simbólico de sendmail a msmtp..."
    sudo ln -sf /usr/bin/msmtp /usr/sbin/sendmail
fi


echo "---"
echo "✅ Configuración de msmtp y mutt completada. ¡Wrapper instalado!"
echo "Servidor SMTP: $SERVER_ADDRESS:$SMTP_PORT"
echo "Usuario de autenticación: $SMTP_USER"
echo "Ruta del Wrapper: $WRAPPER_SCRIPT"
echo "---"

# -----------------------------------------------------
# PRUEBA DE ENVÍO
# -----------------------------------------------------

echo "⚠️ Antes de la prueba, ASEGÚRATE de haber creado la cuenta $SMTP_USER en 'mi.arca'."
read -r -p "¿Deseas realizar una prueba de envío AHORA usando mutt? (s/N): " response

if [[ "$response" =~ ^([sS][iI]|[sS])$ ]]
then
    echo "Realizando prueba de envío con mutt..."
    # Usamos mutt para enviar, leyendo de stdin.
    echo "Este es el cuerpo de la prueba de mutt." | mutt -s "[CH9] PRUEBA MUTT EXITOSA" -- "$TEST_TO_ADDRESS"
    
    if [ $? -eq 0 ]; then
        echo "✅ PRUEBA EXITOSA: Correo enviado a $TEST_TO_ADDRESS."
        echo "Revisa la bandeja de entrada y el archivo de log /var/log/msmtp.log"
    else
        echo "❌ ERROR EN LA PRUEBA. Código de salida: $?."
        echo "Revisa /var/log/msmtp.log y los permisos de los archivos de configuración. Asegúrate de que $HOME/.local/bin esté en tu PATH."
    fi
else
    echo "Prueba omitida."
fi
