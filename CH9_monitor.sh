#!/bin/bash
# ==============================================================================
# SCRIPT: CH9_monitor.sh - MODO 3: Monitor CB (Alerta por Transcripción)
# ==============================================================================

# ------------------------------------------------------------------------------
# SETUP DE WHISPER C++ (Necesario para la transcripción)
# ------------------------------------------------------------------------------
MODEL="small"
export WHISPER_EXECUTABLE="/opt/whisper-cpp/bin/main"
export WHISPER_MODEL_PATH="/opt/whisper-cpp/models/ggml-$MODEL.bin"
export ASR_LANGUAGE="es"
export LD_LIBRARY_PATH="/opt/whisper-cpp/bin/:$LD_LIBRARY_PATH"

# ==============================================================================
# 1. Función de Transcripción (INFO a stderr para limpiar $TRANSCRIPT)
# ==============================================================================
whisper_transcribe() {
    local audio_file="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    local transcript_filename="$RAMDISK/$USER/transcript_${timestamp}.txt"
    
    if [ -z "$audio_file" ] || [ ! -f "$audio_file" ]; then
        echo "ERROR: La función whisper_transcribe requiere una ruta de archivo válida." >&2
        return 1
    fi

    echo "INFO: Transcribiendo archivo: $audio_file" >&2 

    # Ejecuta Whisper C++ y filtra la salida para obtener solo el texto.
    TRANSCRIPT_RESULT=$(
        "$WHISPER_EXECUTABLE" -m "$WHISPER_MODEL_PATH" "$audio_file" -l "$ASR_LANGUAGE" -np -nt |\
         tail -n 1 | sed 's|^[[:space:]]*||')
    
    # Guarda la transcripción en el archivo TXT (localmente en RAMDISK)
    echo "Transcripción: $TRANSCRIPT_RESULT" > "$transcript_filename"
    echo "INFO: Transcripción guardada en: $transcript_filename" >&2 

    # Devuelve SOLO el texto transcrito (imprime a stdout)
    echo "$TRANSCRIPT_RESULT"
}
# ------------------------------------------------------------------------------

# 2. CARGA DE CONFIGURACIÓN
source $HOME/.CH9-config

# 📢 LIMPIEZA CRÍTICA DE VARIABLES DE CONFIGURACIÓN
# FIX FINAL: Convertir KEYWORDS a minúsculas, reemplazar "|" por espacios, y limpiar
KEYWORDS=$(echo "$KEYWORDS" | tr -d '\r' | sed 's/\xc2\xa0/ /g' | sed 's/|/ /g' | sed -E 's/ +/ /g; s/^ *| *$//' | tr '[:upper:]' '[:lower:]')


# 3. DEFINICIÓN DE VARIABLES INICIALES
ENABLE=1
RAMDISK=/dev/shm
USER=$(whoami)
DEBUG=0

# VARIABLE DE LOG
LOG_FILE="$HOME/ch9_monitor.log"
touch "$LOG_FILE" 

# 4. INICIALIZACIÓN DEL ENTORNO
# Se eliminó la inicialización del watchdog.

# 5. PREPARACIÓN DEL ENTORNO DE GRABACIÓN
#mkdir -p $RAMDISK/$USER/vox
#rm $RAMDISK/$USER/audio*.wav 2>/dev/null


#rm $RAMDISK/$USER/vox/vox.wav 
#if [ ! -f $RAMDISK/$USER/vox/vox.wav ]; then
#    sox -V -r $FREQ -n -b 16 -c 1 $RAMDISK/$USER/vox/vox.wav synth 0.5 sin 440 vol -10dB
#fi
#cp /usr/local/share/loro/sounds/messagereceived.wav $RAMDISK/$USER/vox/ 2>/dev/null


# 6. BUCLE PRINCIPAL DE MONITOREO (VOX Loop)

DURATION=$(echo "($MinMexDuration * 1000000)/1" | bc) #"
while true; do
    
    # 6.1. ESTADO DEL SISTEMA (Watchdog eliminado)
    # SystemStop y TotTimeDone eliminados. ENABLE siempre será 1 si el script está corriendo.

    # 6.2. MUESTRA EL ESTADO Y LOS ÚLTIMOS MENSAJES
    if [ "$DEBUG" = 0 ]; then clear; fi
    
    echo "monitoring (Modo Monitor CB/Alerta)..."
    rm *.wav 2> /dev/null

    echo "
########################################################
# MODO MONITOR CB - ENABLE=$ENABLE
########################################################"

    echo "--- Últimos 5 Mensajes Registrados ---"
    tail -n 5 "$LOG_FILE"
    echo "--------------------------------------"

    # 6.3. COMANDO CRÍTICO DE SQUELCH (TRIPLE PIPE)
    AUDIODRIVER=$AUDIODRIVER AUDIODEV=$AUDIODEV rec -V0 -r $FREQ -e signed-integer -b 16 -c 1 --endian little    -p  | sox -p -p silence 0 1 0:$TIME 10% | sox -p -r $FREQ -e signed-integer -b 16 -c 1 --endian little $RAMDISK/$USER/audio.wav compand 0.3,1 6:-70,-60,-20 -5 -90 0.2  silence 0 1 0:02 10% : newfile

    # 6.4. PROCESAMIENTO POST-GRABACIÓN
    ls $RAMDISK/$USER/*.wav > $RAMDISK/$USER/list.log
    du $RAMDISK/$USER/*.wav >> $RAMDISK/$USER/size.log

    for audio in $(cat $RAMDISK/$USER/list.log); do
        size=$(cat $audio | wc -l)
        
        if [ $size == "0" ]; then
            echo "$audio file empty"
            rm $audio
        else
            size2=$(ffprobe -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $audio 2>/dev/null | tr -d '.')
            
            if [ $size2 -lt "$DURATION" ]; then
                echo "$audio file too short"
                rm -f $audio
            else
                # 6.5. LÓGICA ESPECÍFICA DEL MODO MONITOR CB
                if [ $ENABLE = 1 ]; then
                    MexDuration=$(echo "( $size2 / 1000000 )*1" | bc) #"
                    
                    # Se eliminó la acumulación de tiempo en watchdog.log

                    # 1. Transcribir el audio (Captura el texto crudo)
                    TRANSCRIPT_RAW=$(whisper_transcribe "$audio")
                    
                    # 📢 FILTRO DE LIMPIEZA DE TRANSCRIPCIÓN (VERSION ROBUSTA)
                    TRANSCRIPT=$(echo "$TRANSCRIPT_RAW" | \
                        sed 's/\xc2\xa0/ /g' | \
                        sed -E 's/[^[:alnum:] ]/ /g' | \
                        sed -E 's/ +/ /g; s/^ *| *$//' | tr '[:upper:]' '[:lower:]')

                    # 📢 Añadir espacios de relleno para la búsqueda nativa de Bash (Word Boundary Check)
                    PADDED_TRANSCRIPT=" $TRANSCRIPT "

                    # Inicializar STATUS a 1 (No Alerta)
                    STATUS=1 
                    DETECTED_WORD=""

                    echo "DEBUG TRANSCRIPT (Padded): [$PADDED_TRANSCRIPT]"
                    echo "DEBUG KEYWORDS (Minúsculas y separadas por espacio): [$KEYWORDS]"

                    # 2. BÚSQUEDA ROBUSTA DE PALABRAS CLAVE (Iteración por palabra y BASH Nativo)
                    if [ ! -z "$KEYWORDS" ]; then

                        # Dividir $KEYWORDS por espacios para iterar
                        for word in $KEYWORDS; do

                            # 📢 CREAMOS EL PATRÓN A BUSCAR con relleno de espacios
                            PADDED_WORD=" $word "

                            # Usamos la coincidencia de patrón nativa de Bash (altamente fiable)
                            if [[ "$PADDED_TRANSCRIPT" == *"$PADDED_WORD"* ]]; then
                                STATUS=0 # Palabra clave encontrada
                                DETECTED_WORD="$word"
                                break    # Salir del bucle tan pronto como se encuentre una
                            fi
                        done
                    fi

                    
                    # 3. USO DEL STATUS EXPLICITO
                    if [ "$STATUS" = 0 ]; then
                        
                        echo "🚨 ALERTA DETECTADA: Palabra clave encontrada: [$DETECTED_WORD]" 
                        
                        # REGISTRO DE ALERTA: Texto limpio + Etiqueta
                        LOG_ENTRY="$(date '+%Y-%m-%d %H:%M:%S') - ALERTA!! - $TRANSCRIPT"
                        echo "$LOG_ENTRY" >> "$LOG_FILE"
                        
                        # ----------------------------------------------------------------
                        # PASO 4.1: CONVERSIÓN A OGG PARA COMPATIBILIDAD CON DELTACHAT
                        # ----------------------------------------------------------------
                        # Creamos la ruta para el archivo OGG en el mismo directorio (RAMDISK)
                        OGG_AUDIO="${audio%.wav}.ogg"
                        echo "INFO: Convirtiendo $audio a formato OGG ($OGG_AUDIO) para adjuntar..." >&2
                        
                        # Usamos ffmpeg para la conversión (codec libvorbis, calidad 5).
                        ffmpeg -i "$audio" -c:a libvorbis -qscale:a 5 "$OGG_AUDIO" -y > /dev/null 2>&1
                        
                        if [ $? -ne 0 ] || [ ! -f "$OGG_AUDIO" ]; then
                            echo "ERROR: Falló la conversión a OGG. Adjuntando WAV original." >&2
                            FILE_TO_ATTACH="$audio"
                            ATTACHMENT_INFO="WAV original"
                        else
                            FILE_TO_ATTACH="$OGG_AUDIO"
                            ATTACHMENT_INFO="OGG para Deltachat"
                            echo "INFO: Conversión a OGG exitosa. Adjuntando $FILE_TO_ATTACH." >&2
                        fi
                        
                        # 4.2. Enviar Correo de Alerta
                        EMAIL_SUBJECT="[Channel-9] 🚨 ALERTA DE EMERGENCIA POR RADIO 🚨"
                        EMAIL_BODY="
==============================================
¡ALERTA DE EMERGENCIA DETECTADA!
==============================================
Modo: Monitor CB (Alerta)
Palabra clave detectada: $DETECTED_WORD
Lista de palabras clave: $(echo $KEYWORDS | tr ' ' '|')
Fecha y Hora: $(date '+%Y-%m-%d %H:%M:%S')
Duración: $MexDuration segundos

--- Transcripción ---
$TRANSCRIPT
--- Fin de Transcripción ---

Se adjunta el archivo de audio ($ATTACHMENT_INFO) para su revisión.
"
                        # USANDO mutt -a PARA ADJUNTAR EL ARCHIVO CONVERTIDO (OGG o WAV)
                        echo "$EMAIL_BODY" | mutt -s "$EMAIL_SUBJECT" -a "$FILE_TO_ATTACH" -- "$EMAIL_RECIPIENT"
                        echo "✅ Correo de alerta de emergencia enviado a $EMAIL_RECIPIENT."

                        cp "$audio" . # Mantenemos esta línea para debug, copiando el WAV original antes de borrar

                        # 4.3. Limpieza de archivos de audio
                        rm -f "$audio" "$OGG_AUDIO" 2>/dev/null

                    else
                        # REGISTRO DE MENSAJE NORMAL: Texto limpio sin etiqueta
                        LOG_ENTRY="$(date '+%Y-%m-%d %H:%M:%S') - $TRANSCRIPT"
                        echo "$LOG_ENTRY" >> "$LOG_FILE"
                        
                        echo "INFO: Modo Monitor CB: No se detectaron palabras clave. Omitiendo alerta."
                        # Limpiar el archivo WAV en caso de no alerta
                        rm -f "$audio" 2>/dev/null 
                    fi
                fi
            fi
        fi
        # Se eliminó la limpieza final al final del 'for' loop
    done
    
    # 6.6. LIMPIEZA Y PAUSA DEL BUCLE
    sleep 0.3
    :> $RAMDISK/$USER/size.log
    
    # 6.7. RESET DIARIO (Eliminado)
    # Se eliminó la lógica de reset diario del watchdog.
done
exit 0
