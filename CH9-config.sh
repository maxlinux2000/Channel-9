#!/bin/bash

# ==============================================================================
# 0. Instalación de Dependencias (Se mantiene)
# ==============================================================================

if [ ! -f /usr/bin/sox ]; then
    sudo apt install sox -y
fi
if [ ! -f /usr/bin/ffmpeg ]; then
    sudo apt install ffmpeg -y
fi

if [ ! -f /usr/bin/zenity ]; then
    sudo apt install zenity -y
fi

if [ ! -f /usr/bin/multimon-ng ]; then
    sudo apt install multimon-ng -y
fi

# ==============================================================================
# 1. SELECCIÓN DE MODO DE OPERACIÓN (NUEVO ORDEN - PRIMERO)
# ==============================================================================

MODE_SELECT=$(zenity --list \
    --width="600" \
    --height="300" \
    --title="Selecciona el Modo de Operación" \
    --text="Elige el modo principal de funcionamiento." \
    --radiolist \
    --column "Seleccionar" \
    --column "Modo" \
    FALSE "1 - Loro/Parrot (Repetidor de voz)" \
    FALSE "2 - Secretaría Telefónica (Graba y Notifica)" \
    TRUE "3 - Monitor CB (Alerta por transcripción)")

OPERATION_MODE=$(echo "$MODE_SELECT" | cut -d ' ' -f1 | tr -d '\n')
EMAIL_RECIPIENT=""
KEYWORDS_RAW=""
RESPONSE_MESSAGE=""

# Inicializar DTMF/Tiempos por defecto (vacío/cero)
START=""
STOP=""
StartSysop=""
StopSysop=""
OneMsg=0
TimeTotal=0

# ==============================================================================
# 2. CONFIGURACIÓN ESPECÍFICA POR MODO (Lógica Condicional)
# ==============================================================================

case "$OPERATION_MODE" in
    
    1) # LORO/PARROT - Pedir contraseñas DTMF y Tiempos
        
        ENABLE=$(zenity --forms --title="CONFIGURACIÓN DTMF (Modo Loro)" --text="Contraseñas para Activar y Desactivar el Loro remotamente." \
            --width="600" \
            --height="300" \
            --add-entry="Activar (DTMF)" \
            --add-entry="Desactivar (DTMF)" \
            --add-entry="Activar (Sysop DTMF)" \
            --add-entry="Desactivar (Sysop DTMF)")
        
        START=$(echo $ENABLE | cut -d '|' -f1)
        STOP=$(echo $ENABLE | cut -d '|' -f2)
        StartSysop=$(echo $ENABLE | cut -d '|' -f3)
        StopSysop=$(echo $ENABLE | cut -d '|' -f4)

        TIMES=$(zenity --forms \
            --title="Tiempos de Uso (Modo Loro)" \
            --text="Establece los límites de duración de mensajes." \
            --width="600" \
            --height="300" \
            --add-entry="Duración máxima por Mensaje (segundos)" \
            --add-entry="Tiempo total de uso diario (segundos)")
            
        OneMsg=$(echo $TIMES | cut -d '|' -f1)
        TimeTotal=$(echo $TIMES | cut -d '|' -f2)
        ;;

    3) # MONITOR CB (Alertas) - Pedir Palabras Clave y Email
        
        KEYWORDS_RAW=$(zenity --entry \
            --title="Configuración de Alertas (Monitor CB)" \
            --text="Introduce las PALABRAS CLAVE separadas por comas o espacios.\nEj: ayuda, fuego, accidente, emergencia" \
            --entry-text="ayuda, fuego, accidente, emergencia")
            
        EMAIL_RECIPIENT=$(zenity --entry \
            --title="Configuración de Alertas (Monitor CB)" \
            --text="Introduce la(s) dirección(es) de correo electrónico para las alertas.\nSepara varias direcciones con comas." \
            --entry-text="tu.correo@ejemplo.com")
            
        # Procesar KEYWORDS: Reemplazar comas/espacios por pipe (|)
        KEYWORDS=$(echo "$KEYWORDS_RAW" | tr ', ' ' ' | sed 's/  */|/g' | sed 's/||*/|/g' | sed 's/^|//;s/|$//')
        
        # Procesar EMAIL_RECIPIENT
        EMAIL_RECIPIENT=$(echo "$EMAIL_RECIPIENT" | tr ' ' ',' | sed 's/,,*/,/g' | sed 's/^,//;s/,$//')
        ;;
        
    2) # SECRETARÍA TELEFÓNICA - Pedir Email y Mensaje de Respuesta
        
        EMAIL_RECIPIENT=$(zenity --entry \
            --title="Configuración de Secretaría Telefónica" \
            --text="Introduce la(s) dirección(es) de correo electrónico para enviar la grabación.\nSepara varias direcciones con comas." \
            --entry-text="tu.correo@ejemplo.com")
            
        RESPONSE_FIELDS=$(zenity --forms --title="Mensaje de Respuesta" \
            --text="Introduce la RUTA al archivo de audio (.wav) que se reproducirá como respuesta.\nSi se deja vacío, la secretaría no contesta." \
            --add-entry="Ruta a audio de respuesta (.wav)")
            
        RESPONSE_MESSAGE=$(echo $RESPONSE_FIELDS | cut -d '|' -f1)
        
        # Procesar EMAIL_RECIPIENT
        EMAIL_RECIPIENT=$(echo "$EMAIL_RECIPIENT" | tr ' ' ',' | sed 's/,,*/,/g' | sed 's/^,//;s/,$//')
        ;;
        
esac

# ==============================================================================
# 3. CONFIGURACIÓN DE INTERFAZ DE AUDIO (NUEVO ORDEN - AL FINAL)
# ==============================================================================

DiverSelect=$(zenity --list \
    --width="600" \
    --height="300" \
    --title="Selecciona el Driver audio" \
    --column="Driver"  \
    alsa jack pulseaudio)

AudioCardsList=$(arecord -L | grep -v "plughw" | grep -A1 "hw:" | sed 's|--||g' | sed 's|^     ||g' | grep  "." | paste -d ' ' - - | tr ' ' '_' )

AudioSelect=$(zenity --list \
    --width="600" \
    --height="300" \
    --title="Selecciona la tarjeta audio" \
    --column="tarjeta"  \
    $AudioCardsList)
AudioCard=$(echo $AudioSelect | cut -d '_' -f1)

SilenceTime=$(zenity --scale --text="Duracción del silencio en segundos/100 (Squelch)" --value="150" --min-value="1" --max-value="500" --step="1")
SilenceTime=$(echo "scale=2 ; $SilenceTime/100" | bc)

DuratioMin=$(zenity --scale --text="Duracción mínima de un mensaje en segundos/100" --value="290" --min-value="10" --max-value="500" --step="1")
DuratioMin=$(echo "scale=2 ; $DuratioMin/100" | bc)

FreqSelect=$(zenity --list \
    --width="600" \
    --height="300" \
    --title="Selecciona la frecuencia de muestreo audio" \
    --column="Freq"  \
    48000 44100 22050 8000)


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
echo "export OPERATION_MODE=$OPERATION_MODE"
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
    # Añadimos variables de tiempo para que el script principal no falle, aunque sean 0
    echo "# Variables de Tiempo (Modos no Loro)"
    echo "export OneMsg=60" 
    echo "export TimeTotal=3600"
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
