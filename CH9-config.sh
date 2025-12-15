#!/bin/bash

# ==============================================================================
# 0. LECTURA DE CONFIGURACIÓN PREVIA Y DEPS
# ==============================================================================

CONFIG_FILE="$HOME/.CH9-config"

# --- 0.1 Cargar configuración previa si existe ---
if [ -f "$CONFIG_FILE" ]; then
    echo "INFO: Cargando configuración existente de $CONFIG_FILE..."
    # Cargamos el archivo para que las variables estén disponibles
    source "$CONFIG_FILE"
    
    # Limpiamos las variables exportadas y definimos valores previos para Zenity
    PREV_MODE=$(echo "${OPERATION_MODE:-3}" | tr -d '"')
    PREV_DRIVER=$(echo "${AUDIODRIVER:-alsa}" | tr -d '"')
    PREV_AUDIODEV=$(echo "${AUDIODEV:-hw:0,0}" | tr -d '"')
    PREV_FREQ=$(echo "${FREQ:-48000}" | tr -d '"')
    
    # Valores de escala: multiplicar por 100 y CORREGIR DECIMALES con sed para forzar entero
    
    # Squelch (TIME)
    # Si TIME no existe o es nulo, usa 1.50. Multiplica por 100 y elimina la parte decimal.
    PREV_SILENCE_TIME=$(echo "${TIME:-1.50} * 100" | bc 2>/dev/null | sed 's/\..*//g' || echo 150)
    
    # Duración Mínima (MinMexDuration)
    # Si MinMexDuration no existe o es nulo, usa 2.90. Multiplica por 100 y elimina la parte decimal.
    PREV_DURATIO_MIN=$(echo "${MinMexDuration:-2.90} * 100" | bc 2>/dev/null | sed 's/\..*//g' || echo 290)
    
    PREV_KEYWORDS=$(echo "${KEYWORDS:-ayuda, fuego, accidente, emergencia}" | tr -d '"' | tr '|' ' ')
    PREV_EMAIL=$(echo "${EMAIL_RECIPIENT:-tu.correo@ejemplo.com}" | tr -d '"')
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
    PREV_KEYWORDS="ayuda, fuego, accidente, emergencia"
    PREV_EMAIL="tu.correo@ejemplo.com"
    PREV_RESPONSE=""
    PREV_DTMF_START=""
    PREV_DTMF_STOP=""
    PREV_DTMF_STARTSYSOP=""
    PREV_DTMF_STOPSYSOP=""
    PREV_ONEMSG="0"
    PREV_TIMETOTAL="0"
fi


# --- 0.2 Instalación de Dependencias (Se mantiene) ---
if [ ! -f /usr/bin/sox ]; then sudo apt install sox -y; fi
if [ ! -f /usr/bin/ffmpeg ]; then sudo apt install ffmpeg -y; fi
if [ ! -f /usr/bin/zenity ]; then sudo apt install zenity -y; fi
if [ ! -f /usr/bin/multimon-ng ]; then sudo apt install multimon-ng -y; fi


# ==============================================================================
# 1. SELECCIÓN DE MODO DE OPERACIÓN (USANDO VALOR PREVIO)
# ==============================================================================

MODE_SELECT=$(zenity --list \
    --width="600" \
    --height="300" \
    --title="Selecciona el Modo de Operación" \
    --text="Elige el modo principal de funcionamiento." \
    --radiolist \
    --column "Seleccionar" \
    --column "Modo" \
    $( [ "$PREV_MODE" = "1" ] && echo TRUE || echo FALSE ) "1 - Loro/Parrot (Repetidor de voz" \
    $( [ "$PREV_MODE" = "2" ] && echo TRUE || echo FALSE ) "2 - Secretaría Telefónica (Graba y Notifica)" \
    $( [ "$PREV_MODE" = "3" ] && echo TRUE || echo FALSE ) "3 - Monitor CB (Alerta por transcripción)")

if [ $? -ne 0 ]; then exit 1; fi

OPERATION_MODE=$(echo "$MODE_SELECT" | cut -d ' ' -f1 | tr -d '\n')
# Resetear variables específicas por si el usuario cambia de modo
EMAIL_RECIPIENT=""
KEYWORDS_RAW=""
RESPONSE_MESSAGE=""
START=""
STOP=""
StartSysop=""
StopSysop=""
OneMsg=0
TimeTotal=0

# ==============================================================================
# 2. CONFIGURACIÓN ESPECÍFICA POR MODO (Lógica Condicional - USANDO VALORES PREVIOS)
# ==============================================================================

case "$OPERATION_MODE" in
    
    1) # LORO/PARROT - Pedir contraseñas DTMF y Tiempos
        
        ENABLE=$(zenity --forms --title="CONFIGURACIÓN DTMF (Modo Loro)" --text="Contraseñas para Activar y Desactivar el Loro remotamente." \
            --width="600" \
            --height="300" \
            --add-entry="Activar (DTMF):$PREV_DTMF_START" \
            --add-entry="Desactivar (DTMF):$PREV_DTMF_STOP" \
            --add-entry="Activar (Sysop DTMF):$PREV_DTMF_STARTSYSOP" \
            --add-entry="Desactivar (Sysop DTMF):$PREV_DTMF_STOPSYSOP")
        
        if [ $? -ne 0 ]; then exit 1; fi
        
        START=$(echo $ENABLE | cut -d '|' -f1)
        STOP=$(echo $ENABLE | cut -d '|' -f2)
        StartSysop=$(echo $ENABLE | cut -d '|' -f3)
        StopSysop=$(echo $ENABLE | cut -d '|' -f4)

        TIMES=$(zenity --forms \
            --title="Tiempos de Uso (Modo Loro)" \
            --text="Establece los límites de duración de mensajes." \
            --width="600" \
            --height="300" \
            --add-entry="Duración máxima por Mensaje (segundos):$PREV_ONEMSG" \
            --add-entry="Tiempo total de uso diario (segundos):$PREV_TIMETOTAL")
            
        if [ $? -ne 0 ]; then exit 1; fi
            
        OneMsg=$(echo $TIMES | cut -d '|' -f1)
        TimeTotal=$(echo $TIMES | cut -d '|' -f2)
        ;;

    3) # MONITOR CB (Alertas) - Pedir Palabras Clave y Email
        
        KEYWORDS_RAW=$(zenity --entry \
            --title="Configuración de Alertas (Monitor CB)" \
            --text="Introduce las PALABRAS CLAVE separadas por comas o espacios.\nEj: ayuda, fuego, accidente, emergencia" \
            --entry-text="$PREV_KEYWORDS")
            
        if [ $? -ne 0 ]; then exit 1; fi
            
        EMAIL_RECIPIENT=$(zenity --entry \
            --title="Configuración de Alertas (Monitor CB)" \
            --text="Introduce la(s) dirección(es) de correo electrónico para las alertas.\nSepara varias direcciones con comas." \
            --entry-text="$PREV_EMAIL")
            
        if [ $? -ne 0 ]; then exit 1; fi
            
        # Procesar KEYWORDS: Reemplazar comas/espacios por pipe (|)
        KEYWORDS=$(echo "$KEYWORDS_RAW" | tr ', ' ' ' | sed 's/  */|/g' | sed 's/||*/|/g' | sed 's/^|//;s/|$//')
        
        # Procesar EMAIL_RECIPIENT
        EMAIL_RECIPIENT=$(echo "$EMAIL_RECIPIENT" | tr ' ' ',' | sed 's/,,*/,/g' | sed 's/^,//;s/,$//')
        ;;
        
    2) # SECRETARÍA TELEFÓNICA - Pedir Email y Mensaje de Respuesta
        
        EMAIL_RECIPIENT=$(zenity --entry \
            --title="Configuración de Secretaría Telefónica" \
            --text="Introduce la(s) dirección(es) de correo electrónico para enviar la grabación.\nSepara varias direcciones con comas." \
            --entry-text="$PREV_EMAIL")
            
        if [ $? -ne 0 ]; then exit 1; fi
            
        RESPONSE_FIELDS=$(zenity --forms --title="Mensaje de Respuesta" \
            --text="Introduce la RUTA al archivo de audio (.wav) que se reproducirá como respuesta.\nSi se deja vacío, la secretaría no contesta." \
            --add-entry="Ruta a audio de respuesta (.wav):$PREV_RESPONSE")
            
        if [ $? -ne 0 ]; then exit 1; fi
            
        RESPONSE_MESSAGE=$(echo $RESPONSE_FIELDS | cut -d '|' -f1)
        
        # Procesar EMAIL_RECIPIENT
        EMAIL_RECIPIENT=$(echo "$EMAIL_RECIPIENT" | tr ' ' ',' | sed 's/,,*/,/g' | sed 's/^,//;s/,$//')
        ;;
        
esac

# ==============================================================================
# 3. CONFIGURACIÓN DE INTERFAZ DE AUDIO (USANDO VALORES PREVIOS)
# ==============================================================================

# Driver (usando valor previo)
DiverSelect=$(zenity --list \
    --width="600" \
    --height="300" \
    --title="Selecciona el Driver audio" \
    --radiolist \
    --column="Seleccionar" \
    --column="Driver"  \
    $( [ "$PREV_DRIVER" = "alsa" ] && echo TRUE || echo FALSE ) alsa \
    $( [ "$PREV_DRIVER" = "jack" ] && echo TRUE || echo FALSE ) jack \
    $( [ "$PREV_DRIVER" = "pulseaudio" ] && echo TRUE || echo FALSE ) pulseaudio)

if [ $? -ne 0 ]; then exit 1; fi

# Tarjeta de Audio (manteniendo el script original para la lista)
# ------------------------- NO TOCAR ESTA SECCIÓN -------------------------
AudioCardsList=$(arecord -L | grep -v "plughw" | grep -A1 "hw:" | sed 's|--||g' | sed 's|^     ||g' | grep  "." | paste -d ' ' - - | tr ' ' '_' )

AudioSelect=$(zenity --list \
    --width="600" \
    --height="300" \
    --title="Selecciona la tarjeta audio" \
    --column="tarjeta"  \
    $AudioCardsList)
AudioCard=$(echo $AudioSelect | cut -d '_' -f1)
# ------------------------------------------------------------------------

# Squelch (usando valor previo, que ahora es un entero)
SilenceTime=$(zenity --scale --text="Duracción del silencio en segundos/100 (Squelch)" --value="$PREV_SILENCE_TIME" --min-value="1" --max-value="500" --step="1")

if [ $? -ne 0 ]; then exit 1; fi

SilenceTime=$(echo "scale=2 ; $SilenceTime/100" | bc)

# Duración Mínima (usando valor previo, que ahora es un entero)
DuratioMin=$(zenity --scale --text="Duracción mínima de un mensaje en segundos/100" --value="$PREV_DURATIO_MIN" --min-value="10" --max-value="500" --step="1")

if [ $? -ne 0 ]; then exit 1; fi

DuratioMin=$(echo "scale=2 ; $DuratioMin/100" | bc)

# Frecuencia (usando valor previo)
FreqSelect=$(zenity --list \
    --width="600" \
    --height="300" \
    --title="Selecciona la frecuencia de muestreo audio" \
    --radiolist \
    --column="Seleccionar" \
    --column="Freq"  \
    $( [ "$PREV_FREQ" = "48000" ] && echo TRUE || echo FALSE ) 48000 \
    $( [ "$PREV_FREQ" = "44100" ] && echo TRUE || echo FALSE ) 44100 \
    $( [ "$PREV_FREQ" = "22050" ] && echo TRUE || echo FALSE ) 22050 \
    $( [ "$PREV_FREQ" = "8000" ] && echo TRUE || echo FALSE ) 8000)

if [ $? -ne 0 ]; then exit 1; fi


# ==============================================================================
# 4. ESCRITURA DEL ARCHIVO DE CONFIGURACIÓN
# ==============================================================================

{
# Encabezado con información crítica
echo "# =========================================================="
echo "# CONFIGURACIÓN GENERADA POR $0"
echo "# Creado el: $(date)"
echo "# =========================================================="
echo ""

# Variables del MODO DE OPERACIÓN
echo "# MODOS DE OPERACIÓN: 1=LORO, 2=SECRETARIA, 3=MONITOR CB"
echo "export OPERATION_MODE=\"$OPERATION_MODE\""
echo ""

# Variables de INTERFAZ DE AUDIO
echo "# Variables de Interfaz de Audio y Tiempos de Squelch"
echo "export AUDIODRIVER=\"$DiverSelect\""
echo "export AUDIODEV=\"$AudioCard\""
echo "export TIME=\"$SilenceTime\""
echo "export MinMexDuration=\"$DuratioMin\""
echo "export FREQ=\"$FreqSelect\""
echo ""

# Variables condicionales de DTMF y Tiempos de Uso
if [ "$OPERATION_MODE" = "1" ]; then
    echo "# Variables de Control DTMF (Solo Modo Loro)"
    echo "export STOP=\"$STOP\""
    echo "export START=\"$START\""
    echo "export StopSysop=\"$StopSysop\""
    echo "export StartSysop=\"$StartSysop\""
    echo "export OneMsg=\"$OneMsg\""
    echo "export TimeTotal=\"$TimeTotal\""
elif [ "$OPERATION_MODE" = "2" ] || [ "$OPERATION_MODE" = "3" ]; then
    # Usamos los valores previos si el usuario no tocó DTMF/Loro, para que los scripts principales tengan variables definidas
    echo "# Variables de Tiempo (Modos no Loro - Usando valores por defecto o previos)"
    echo "export OneMsg=\"$PREV_ONEMSG\"" 
    echo "export TimeTotal=\"$PREV_TIMETOTAL\""
fi
echo ""

# Variables específicas del modo (Email, Keywords, Respuesta)
if [ "$OPERATION_MODE" = "3" ] || [ "$OPERATION_MODE" = "2" ]; then
    echo "# Variables de Alerta/Notificación (Modo 2 y 3)"
    echo "export EMAIL_RECIPIENT=\"$EMAIL_RECIPIENT\""
fi

if [ "$OPERATION_MODE" = "3" ]; then
    echo "# Variables de Monitor CB"
    echo "export KEYWORDS=\"$KEYWORDS\""
    echo "export ALERT_DIR=\"$HOME/lorocb_alert_log\""
fi

if [ "$OPERATION_MODE" = "2" ]; then
    echo "# Variables de Secretaría Telefónica"
    echo "export RESPONSE_MESSAGE=\"$RESPONSE_MESSAGE\""
fi

} > "$HOME/.CH9-config"

echo "========================================================"
echo "✅ Archivo de configuración guardado en: $HOME/.CH9-config"
echo "Modo seleccionado: $MODE_SELECT"
echo "========================================================"

