#!/bin/bash

# --- PARAMETROS GLOBALES YAD ---
YAD_GEOMETRY="--width=600 --height=350 --posx=300 --posy=100"
YAD_GEOMETRY_INFO="--width=600 --height=350 --posx=300 --posy=100"
# -------------------------------

# ==============================================================================
# 0. LECTURA DE CONFIGURACIÓN PREVIA Y DEPS
# ==============================================================================

CONFIG_FILE="$HOME/.CH9-config"
# Variables de Correo
MSMTP_RC="$HOME/.msmtprc" 
MSMTP_LOG="$HOME/.log/msmtp.log" 

# --- 0.1 Cargar configuración previa si existe ---
if [ -f "$CONFIG_FILE" ]; then
    echo "INFO: Cargando configuración existente de $CONFIG_FILE..."
    source "$CONFIG_FILE"
    
    # Definimos valores previos para YAD
    PREV_MODE=$(echo "${OPERATION_MODE:-3}" | tr -d '"')
    PREV_DRIVER=$(echo "${AUDIODRIVER:-alsa}" | tr -d '"')
    PREV_AUDIODEV=$(echo "${AUDIODEV:-hw:0,0}" | tr -d '"')
    PREV_FREQ=$(echo "${FREQ:-48000}" | tr -d '"')
    
    # Valores de escala: multiplicar por 100 y CORREGIR DECIMALES con sed para forzar entero
    PREV_SILENCE_TIME=$(echo "${TIME:-1.50} * 100" | bc 2>/dev/null | sed 's/\..*//g' || echo 150)
    PREV_DURATIO_MIN=$(echo "${MinMexDuration:-2.90} * 100" | bc 2>/dev/null | sed 's/\..*//g' || echo 290)
    
    PREV_KEYWORDS=$(echo "${KEYWORDS:-ayuda, fuego, accidente, emergencia, simulacro}" | tr -d '"' | tr '|' ' ')
    PREV_EMAIL=$(echo "${EMAIL_FROM:-ch9@mi.arca}" | tr -d '"')
    PREV_LOCAL_EMAIL_TO=$(echo "${LOCAL_EMAIL_TO:-ch9_to@mi.arca}" | tr -d '"')
    PREV_RESPONSE=$(echo "${RESPONSE_MESSAGE:-}" | tr -d '"')
    
    PREV_DTMF_START=$(echo "${START:-}" | tr -d '"')
    PREV_DTMF_STOP=$(echo "${STOP:-}" | tr -d '"')
    PREV_DTMF_STARTSYSOP=$(echo "${StartSysop:-}" | tr -d '"')
    PREV_DTMF_STOPSYSOP=$(echo "${StopSysop:-}" | tr -d '"')
    PREV_ONEMSG=$(echo "${OneMsg:-0}" | tr -d '"')
    PREV_TIMETOTAL=$(echo "${TimeTotal:-0}" | tr -d '"')
    
else
    echo "INFO: Archivo de configuración no encontrado. Usando valores por defecto."
    
    # Valores por defecto si no existe el archivo
    PREV_MODE="3"
    PREV_DRIVER="alsa"
    PREV_AUDIODEV="hw:0,0"
    PREV_FREQ="48000"
    PREV_SILENCE_TIME="150"
    PREV_DURATIO_MIN="290"
    PREV_KEYWORDS="ayuda, fuego, accidente, emergencia, simulacro"
    PREV_EMAIL="ch9@mi.arca"
    PREV_LOCAL_EMAIL_TO="ch9_to@mi.arca"
    PREV_RESPONSE=""
    PREV_DTMF_START=""
    PREV_DTMF_STOP=""
    PREV_DTMF_STARTSYSOP=""
    PREV_DTMF_STOPSYSOP=""
    PREV_ONEMSG="0"
    PREV_TIMETOTAL="0"
fi


# ==============================================================================
# 1. SELECCIÓN DE MODO DE OPERACIÓN
# ==============================================================================

MODE_SELECT=$(yad --list \
    $YAD_GEOMETRY \
    --title="Selecciona el Modo de Operación" \
    --text="Elige el modo principal de funcionamiento." \
    --radiolist \
    --column "Seleccionar" \
    --column "Modo" \
    $( [ "$PREV_MODE" = "1" ] && echo TRUE || echo FALSE ) "1 - Loro/Parrot (Repetidor de voz" \
    $( [ "$PREV_MODE" = "2" ] && echo TRUE || echo FALSE ) "2 - Secretaría Telefónica (Graba y Notifica)" \
    $( [ "$PREV_MODE" = "3" ] && echo TRUE || echo FALSE ) "3 - Monitor CB (Alerta por transcripción)")

if [ $? -ne 0 ]; then exit 1; fi

OPERATION_MODE=$(echo "$MODE_SELECT" | cut -d '|' -f2 | cut -d ' ' -f1 | tr -d '\n')

EMAIL_FROM=""
LOCAL_EMAIL_TO=""
KEYWORDS_RAW=""
RESPONSE_MESSAGE=""
START=""
STOP=""
StartSysop=""
StartSysop=""
OneMsg=0
TimeTotal=0

# ==============================================================================
# 2. CONFIGURACIÓN ESPECÍFICA POR MODO
# ==============================================================================

case "$OPERATION_MODE" in
    
    1) # LORO/PARROT
        
        ENABLE=$(yad --form --title="CONFIGURACIÓN DTMF (Modo Loro)" --text="Contraseñas para Activar y Desactivar el Loro remotamente." \
            $YAD_GEOMETRY \
            --field="Activar (DTMF):" "$PREV_DTMF_START" \
            --field="Desactivar (DTMF):" "$PREV_DTMF_STOP" \
            --field="Activar (Sysop DTMF):" "$PREV_DTMF_STARTSYSOP" \
            --field="Desactivar (Sysop DTMF):" "$PREV_DTMF_STOPSYSOP" \
            --separator="|")
        
        if [ $? -ne 0 ]; then exit 1; fi
        
        START=$(echo $ENABLE | cut -d '|' -f1)
        STOP=$(echo $ENABLE | cut -d '|' -f2)
        StartSysop=$(echo $ENABLE | cut -d '|' -f3)
        StopSysop=$(echo $ENABLE | cut -d '|' -f4)

        TIMES=$(yad --form \
            --title="Tiempos de Uso (Modo Loro)" \
            --text="Establece los límites de duración de mensajes." \
            $YAD_GEOMETRY \
            --field="Duración máxima por Mensaje (segundos):" "$PREV_ONEMSG" \
            --field="Tiempo total de uso diario (segundos):" "$PREV_TIMETOTAL" \
            --separator="|")
            
        if [ $? -ne 0 ]; then exit 1; fi
            
        OneMsg=$(echo $TIMES | cut -d '|' -f1)
        TimeTotal=$(echo $TIMES | cut -d '|' -f2)
        ;;
        
    3|2) # MONITOR CB y SECRETARÍA TELEFÓNICA - Pedir Email (FROM y TO)
        
        if [ "$OPERATION_MODE" = "3" ]; then
            KEYWORDS_RAW=$(yad --entry \
                $YAD_GEOMETRY \
                --title="Configuración de Alertas (Monitor CB)" \
                --text="Introduce las PALABRAS CLAVE separadas por comas o espacios.\nEj: ayuda, fuego, accidente, emergencia" \
                --entry-text="$PREV_KEYWORDS")
                
            if [ $? -ne 0 ]; then exit 1; fi
            
            # Procesar KEYWORDS: Reemplazar comas/espacios por pipe (|)
            KEYWORDS=$(echo "$KEYWORDS_RAW" | tr ', ' ' ' | sed 's/  */|/g' | sed 's/||*/|/g' | sed 's/^|//;s/|$//')
        fi
        
        if [ "$OPERATION_MODE" = "2" ]; then
            RESPONSE_FIELDS=$(yad --form --title="Mensaje de Respuesta" \
                $YAD_GEOMETRY \
                --text="Introduce la RUTA al archivo de audio (.wav) que se reproducirá como respuesta.\nSi se deja vacío, la secretaría no contesta." \
                --field="Ruta a audio de respuesta (.wav):" "$PREV_RESPONSE" \
                --separator="|")
                
            if [ $? -ne 0 ]; then exit 1; fi
                
            RESPONSE_MESSAGE=$(echo $RESPONSE_FIELDS | cut -d '|' -f1)
        fi
        
        # --- FORMULARIO COMBINADO PARA CORREO (FROM y TO) ---
        EMAIL_FIELDS=$(yad --form \
            $YAD_GEOMETRY \
            --title="Configuración de Correo" \
            --text="Configura las direcciones de correo para el envío de alertas." \
            --field="1. Dirección de ENVÍO (FROM):" "$PREV_EMAIL" \
            --field="2. Dirección de DESTINO (TO, para alertas/DeltaChat):" "$PREV_LOCAL_EMAIL_TO" \
            --separator="|")

        if [ $? -ne 0 ]; then exit 1; fi
        
        EMAIL_FROM=$(echo $EMAIL_FIELDS | cut -d '|' -f1 | tr ' ' ',' | sed 's/,,*/,/g' | sed 's/^,//;s/,$//')
        LOCAL_EMAIL_TO=$(echo $EMAIL_FIELDS | cut -d '|' -f2 | tr ' ' ',' | sed 's/,,*/,/g' | sed 's/^,//;s/,$//')
        # ----------------------------------------------------
        
        ;;
        
esac

# ==============================================================================
# 3. CONFIGURACIÓN DE INTERFAZ DE AUDIO
# ==============================================================================

DiverSelect=$(yad --list \
    $YAD_GEOMETRY \
    --title="Selecciona el Driver audio" \
    --radiolist \
    --column="Seleccionar" \
    --column="Driver"  \
    $( [ "$PREV_DRIVER" = "alsa" ] && echo TRUE || echo FALSE ) alsa \
    $( [ "$PREV_DRIVER" = "jack" ] && echo TRUE || echo FALSE ) jack \
    $( [ "$PREV_DRIVER" = "pulseaudio" ] && echo TRUE || echo FALSE ) pulseaudio)

if [ $? -ne 0 ]; then exit 1; fi

DiverSelect=$(echo "$DiverSelect" | cut -d '|' -f2 | tr -d '\n')

# Tarjeta de Audio
AudioCardsList=$(arecord -L 2>/dev/null | grep -v "plughw" | grep -A1 "hw:" | sed 's|--||g' | sed 's|^     ||g' | grep  "." | paste -d ' ' - - | tr ' ' '_' )

AudioSelect=$(yad --list \
    $YAD_GEOMETRY \
    --title="Selecciona la tarjeta audio" \
    --column="tarjeta"  \
    $AudioCardsList)
AudioCard=$(echo $AudioSelect | cut -d '_' -f1)

# Squelch
SilenceTime=$(yad $YAD_GEOMETRY --scale --text="Duracción del silencio en segundos/100 (Squelch)" --value="$PREV_SILENCE_TIME" --min-value="1" --max-value="500" --step="1")

if [ $? -ne 0 ]; then exit 1; fi

SilenceTime=$(echo "scale=2 ; $SilenceTime/100" | bc)

# Duración Mínima
DuratioMin=$(yad $YAD_GEOMETRY --scale --text="Duracción mínima de un mensaje en segundos/100" --value="$PREV_DURATIO_MIN" --min-value="10" --max-value="500" --step="1")

if [ $? -ne 0 ]; then exit 1; fi

DuratioMin=$(echo "scale=2 ; $DuratioMin/100" | bc)

# Frecuencia
FreqSelect=$(yad --list \
    $YAD_GEOMETRY \
    --title="Selecciona la frecuencia de muestreo audio" \
    --radiolist \
    --column="Seleccionar" \
    --column="Freq"  \
    $( [ "$PREV_FREQ" = "48000" ] && echo TRUE || echo FALSE ) 48000 \
    $( [ "$PREV_FREQ" = "44100" ] && echo TRUE || echo FALSE ) 44100 \
    $( [ "$PREV_FREQ" = "22050" ] && echo TRUE || echo FALSE ) 22050 \
    $( [ "$PREV_FREQ" = "8000" ] && echo TRUE || echo FALSE ) 8000)

if [ $? -ne 0 ]; then exit 1; fi

FreqSelect=$(echo "$FreqSelect" | cut -d '|' -f2 | tr -d '\n')


# ==============================================================================
# 4. ESCRITURA DEL ARCHIVO DE CONFIGURACIÓN PRINCIPAL (.CH9-config)
# ==============================================================================

{
echo "# =========================================================="
echo "# CONFIGURACIÓN GENERADA POR $0"
echo "# Creado el: $(date)"
echo "# =========================================================="
echo ""

# Variables del MODO DE OPERACIÓN
echo "export OPERATION_MODE=\"$OPERATION_MODE\""
echo ""

# Variables de INTERFAZ DE AUDIO
echo "export AUDIODRIVER=\"$DiverSelect\""
echo "export AUDIODEV=\"$AudioCard\""
echo "export TIME=\"$SilenceTime\""
echo "export MinMexDuration=\"$DuratioMin\""
echo "export FREQ=\"$FreqSelect\""
echo ""

# Variables condicionales de DTMF y Tiempos de Uso
if [ "$OPERATION_MODE" = "1" ]; then
    echo "export STOP=\"$STOP\""
    echo "export START=\"$START\""
    echo "export StopSysop=\"$StopSysop\""
    echo "export StartSysop=\"$StartSysop\""
    echo "export OneMsg=\"$OneMsg\""
    echo "export TimeTotal=\"$TimeTotal\""
elif [ "$OPERATION_MODE" = "2" ] || [ "$OPERATION_MODE" = "3" ]; then
    echo "export OneMsg=\"$PREV_ONEMSG\"" 
    echo "export TimeTotal=\"$PREV_TIMETOTAL\""
fi
echo ""

# Variables específicas del modo (Email, Keywords, Respuesta)
if [ "$OPERATION_MODE" = "3" ] || [ "$OPERATION_MODE" = "2" ]; then
    echo "export EMAIL_FROM=\"$EMAIL_FROM\""
    echo "export LOCAL_EMAIL_TO=\"$LOCAL_EMAIL_TO\""
fi

if [ "$OPERATION_MODE" = "3" ]; then
    echo "export KEYWORDS=\"$KEYWORDS\""
    echo "export ALERT_DIR=\"$HOME/lorocb_alert_log\""
fi

if [ "$OPERATION_MODE" = "2" ]; then
    echo "export RESPONSE_MESSAGE=\"$RESPONSE_MESSAGE\""
fi

} > "$CONFIG_FILE"

echo "========================================================"
echo "✅ Archivo de configuración principal guardado en: $CONFIG_FILE"
echo "Modo seleccionado: $OPERATION_MODE"
echo "========================================================"


# ==============================================================================
# 5. CONFIGURACIÓN DE CORREO LOCAL (UNIFICADA - Solo si es Modo 2 o 3)
# ==============================================================================

if [ "$OPERATION_MODE" = "2" ] || [ "$OPERATION_MODE" = "3" ]; then
    
    echo "INFO: El modo seleccionado requiere correo. Iniciando configuración de msmtp..."

    # --- Valores por defecto fijos ---
    DEFAULT_LOCAL_FROM="ch9@mi.arca"
    DEFAULT_LOCAL_HOST="mi.arca"
    DEFAULT_LOCAL_PORT="587"
    DEFAULT_LOCAL_USER="ch9@mi.arca"
    DEFAULT_LOCAL_PASS="preparandonos" # Contraseña por defecto

    LOCAL_DATA=$(yad --form --title="Configuración de Correo Local" \
        $YAD_GEOMETRY \
        --text="Configura la cuenta de envío local." \
        --field="Dirección de ENVÍO (From):" "$DEFAULT_LOCAL_FROM" \
        --field="Servidor SMTP Local (host):" "$DEFAULT_LOCAL_HOST" \
        --field="Puerto SMTP (port):" "$DEFAULT_LOCAL_PORT" \
        --field="Usuario (user):" "$DEFAULT_LOCAL_USER" \
        --field="Contraseña (password)::H" "$DEFAULT_LOCAL_PASS" \
        --separator="|")
        
    if [ $? -ne 0 ]; then 
        echo "Advertencia: Configuración de correo cancelada por el usuario."
    else

        LOCAL_FROM=$(echo $LOCAL_DATA | cut -d '|' -f1)
        LOCAL_HOST=$(echo $LOCAL_DATA | cut -d '|' -f2)
        LOCAL_PORT=$(echo $LOCAL_DATA | cut -d '|' -f3)
        LOCAL_USER=$(echo $LOCAL_DATA | cut -d '|' -f4)
        LOCAL_PASS=$(echo $LOCAL_DATA | cut -d '|' -f5)
        
        # Si el usuario NO introduce Usuario y Contraseña, asumimos que no requiere AUTH
        if [ -z "$LOCAL_USER" ] && [ -z "$LOCAL_PASS" ]; then
            AUTH_LOCAL_REQUIRED="FALSE"
        else
            AUTH_LOCAL_REQUIRED="TRUE"
        fi

        # -----------------------------------------------------
        # 5.1 CREACIÓN DEL ARCHIVO .msmtprc (SOLO CUENTA LOCAL)
        # -----------------------------------------------------

        echo "Creando archivo de configuración msmtp en $MSMTP_RC..."

        {
        echo "# Configuración msmtp Channel-9"
        echo "defaults"
        echo "auth off"
        echo "tls off"
        echo "tls_starttls off"
        echo "tls_certcheck off"
        echo "logfile $MSMTP_LOG"
        echo ""

        echo "# --- CUENTA LOCAL ---"
        echo "account local"
        echo "host $LOCAL_HOST"
        if [ "$LOCAL_PORT" != "587" ] && [ ! -z "$LOCAL_PORT" ]; then
            echo "port $LOCAL_PORT"
        fi
        echo "from $LOCAL_FROM"

        if [ "$AUTH_LOCAL_REQUIRED" = "TRUE" ]; then
            echo "auth plain"
            echo "user $LOCAL_USER"
            echo "password \"$LOCAL_PASS\""
        fi
        echo ""

        echo "account default : local"
        } > "$MSMTP_RC"

        # Establecer permisos seguros
        chmod 600 "$MSMTP_RC"

        # Creación de la carpeta y archivo de log
        mkdir -p "$(dirname "$MSMTP_LOG")"
        touch "$MSMTP_LOG"

        # -----------------------------------------------------
        # 5.2 ENLACE SIMBÓLICO Y RESUMEN
        # -----------------------------------------------------

        if [ ! -L /usr/sbin/sendmail ] || [ "$(readlink /usr/sbin/sendmail)" != "/usr/bin/msmtp" ]; then
            echo "Creando enlace simbólico de sendmail a msmtp..."
            sudo ln -sf /usr/bin/msmtp /usr/sbin/sendmail
        fi

        yad --info $YAD_GEOMETRY_INFO --title="Configuración de Correo Completada" \
            --text="✅ La configuración de envío de correo LOCAL se ha completado exitosamente.\n\nCuenta FROM: $LOCAL_FROM\nServidor: $LOCAL_HOST:$LOCAL_PORT\nDestinatario(s) de Alerta (Configurado): $LOCAL_EMAIL_TO\n\nEl archivo de log se guardará en: $MSMTP_LOG"

        echo "✅ Configuración de msmtp completada."


        # -----------------------------------------------------
        # 6 PRUEBA DE ENVÍO (Opcional - con YAD)
        # -----------------------------------------------------
        
        # Preguntar con YAD si quiere realizar la prueba.
        yad --question \
            $YAD_GEOMETRY_INFO \
            --title="Prueba de Envío de Correo" \
            --text="¿Deseas realizar una prueba de envío AHORA a \n\n<span color='blue'><b>$LOCAL_EMAIL_TO</b></span>\n\n(usando la cuenta LOCAL: <span color='red'>$LOCAL_FROM</span>)?" \
            --button="Enviar (Sí):0" \
            --button="Omitir (No):1"
            
        TEST_CONFIRMATION=$?

        # Si el usuario presiona "Enviar" (código de salida 0):
        if [ $TEST_CONFIRMATION -eq 0 ]
        then
            echo "Realizando prueba de envío directa con msmtp a $LOCAL_EMAIL_TO..."
            
            # Comando de envío usando msmtp directo
            (
            printf "Subject: [CH9] Prueba de Correo Local\\n"
            printf "\\n"
            printf "Este es un mensaje de prueba enviado desde Channel-9, usando la cuenta local 'local' en el archivo %s.\\n" "$MSMTP_RC"
            ) | /usr/bin/msmtp -C "$MSMTP_RC" --account=local "$LOCAL_EMAIL_TO"
            
            # Si el comando msmtp tuvo éxito (código de salida 0):
            if [ $? -eq 0 ]; then
                # Notificación de éxito con YAD
                yad --info $YAD_GEOMETRY_INFO --title="Prueba Exitosa" --text="✅ Correo de prueba enviado exitosamente a $LOCAL_EMAIL_TO.\n\nRevisa tu bandeja de entrada y el archivo de log $MSMTP_LOG."
                echo "✅ Correo de prueba enviado exitosamente a $LOCAL_EMAIL_TO."
            else
                # Notificación de error con YAD
                yad --error $YAD_GEOMETRY_INFO --title="Error de Envío" --text="❌ Error al enviar el correo de prueba. El código de salida no fue 0.\n\nRevisa el log $MSMTP_LOG para más detalles."
                echo "❌ Error al enviar el correo de prueba. Revisa el log $MSMTP_LOG para más detalles."
            fi
            
        else
            echo "Prueba de envío omitida."
        fi

    fi
fi

echo "========================================================"
echo "Configuración de Channel-9 finalizada."

