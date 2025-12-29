#!/bin/bash
# ==============================================================================
# SCRIPT: CH9_whisper.sh - PROCESO ASÍNCRONO DE TRANSCRIPCIÓN Y ALERTA (SERVICIO SYSTEMD)
# ==============================================================================

# ELIMINAMOS: PARENT_PID ya no es necesario.

# ------------------------------------------------------------------------------
# SETUP DE WHISPER C++ (Necesario para la transcripción)
# ------------------------------------------------------------------------------
MODEL="small"
export WHISPER_EXECUTABLE="/opt/whisper-cpp/bin/main"
export WHISPER_MODEL_PATH="/opt/whisper-cpp/models/ggml-$MODEL.bin"
export LD_LIBRARY_PATH="/opt/whisper-cpp/bin/:$LD_LIBRARY_PATH"
# ------------------------------------------------------------------------------

# 1. CARGA DE CONFIGURACIÓN y VARIABLES
source $HOME/.CH9-config

# 📢 LIMPIEZA CRÍTICA DE VARIABLES DE CONFIGURACIÓN
KEYWORDS=$(echo "$KEYWORDS" | tr -d '\r' | sed 's/\xc2\xa0/ /g' | sed 's/|/ /g' | sed -E 's/ +/ /g; s/^ *| *$//' | tr '[:upper:]' '[:lower:]')

RAMDISK=/dev/shm
USER=$(whoami)
AUDIO_DIR="$RAMDISK/$USER/vox"
LOG_FILE="$HOME/ch9_monitor.log" 
MSMTP_RC="$HOME/.msmtprc"
MSMTP_LOG="$HOME/.log/msmtp.log"
SLEEP_TIME=10 # Comprobación cada 10 segundos

# ------------------------------------------------------------------------------
# 2. Función de Transcripción (Sin cambios)
# ------------------------------------------------------------------------------
whisper_transcribe() {
    local audio_file="$1"
    local timestamp=$(basename "$audio_file" .wav)
    
    local transcript_filename="$RAMDISK/$USER/transcript_${timestamp}.txt"
    
    if [ -z "$audio_file" ] || [ ! -f "$audio_file" ]; then
        echo "ERROR: La función whisper_transcribe requiere una ruta de archivo válida." >&2
        return 1
    fi

    echo "INFO: Transcribiendo archivo: $audio_file (Idioma: $WHISPER_LANG)" >&2 

    TRANSCRIPT_RESULT=$(
        "$WHISPER_EXECUTABLE" -m "$WHISPER_MODEL_PATH" "$audio_file" -l "$WHISPER_LANG" -np -nt |\
         tail -n 1 | sed 's|^[[:space:]]*||')
    
    echo "Transcripción: $TRANSCRIPT_RESULT" > "$transcript_filename"
    echo "INFO: Transcripción guardada en: $transcript_filename" >&2 

    echo "$TRANSCRIPT_RESULT"
}
# ------------------------------------------------------------------------------


# 3. BUCLE PRINCIPAL DE PROCESAMIENTO
echo "INFO: CH9_whisper.sh iniciado como servicio persistente. Monitoreando cola en $AUDIO_DIR"

# El bucle es 'while true' y solo sale si el servicio systemd lo detiene.
while true; do
    
    # 3.1. Búsqueda de nuevos archivos para transcribir
    NEW_AUDIOS=($(find "$AUDIO_DIR" -maxdepth 1 -name "*.wav" -print | sort))
    NUM_AUDIOS=${#NEW_AUDIOS[@]}

    
    if [ $NUM_AUDIOS -gt 0 ]; then
        echo "INFO: ${NUM_AUDIOS} archivo(s) de audio encontrado(s) para transcripción."
        
        for audio in "${NEW_AUDIOS[@]}"; do
            
            # --- Lógica de Transcripción y Correo (Mantenida) ---
            
            # 1. Transcribir el audio
            TRANSCRIPT_RAW=$(whisper_transcribe "$audio")
            
            # 📢 FILTRO DE LIMPIEZA DE TRANSCRIPCIÓN
            TRANSCRIPT=$(echo "$TRANSCRIPT_RAW" | \
                sed 's/\xc2\xa0/ /g' | \
                sed -E 's/[^[:alnum:] ]/ /g' | \
                sed -E 's/ +/ /g; s/^ *| *$//' | tr '[:upper:]' '[:lower:]')

            PADDED_TRANSCRIPT=" $TRANSCRIPT "

            STATUS=1 
            DETECTED_WORD=""

            # 2. BÚSQUEDA ROBUSTA DE PALABRAS CLAVE
            if [ ! -z "$KEYWORDS" ]; then
                for word in $KEYWORDS; do
                    PADDED_WORD=" $word "
                    if [[ "$PADDED_TRANSCRIPT" == *"$PADDED_WORD"* ]]; then
                        STATUS=0 
                        DETECTED_WORD="$word"
                        break    
                    fi
                done
            fi

            
            # 3. USO DEL STATUS EXPLICITO
            if [ "$STATUS" = 0 ]; then
                
                echo "🚨 ALERTA DETECTADA: Palabra clave encontrada: [$DETECTED_WORD] en $audio" 
                
                LOG_ENTRY="$(date '+%Y-%m-%d %H:%M:%S') - ALERTA!! - $TRANSCRIPT"
                echo "$LOG_ENTRY" >> "$LOG_FILE"
                
                # Conversión a OGG y Envío de Correo
                MexDuration=$(ffprobe -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$audio" 2>/dev/null | tr -d '.' | awk '{print int($1/1000000)}')
                
#'
                OGG_AUDIO="${audio%.wav}.ogg"
                ffmpeg -i "$audio" -c:a libvorbis -qscale:a 5 "$OGG_AUDIO" -y > /dev/null 2>&1
                
                if [ $? -ne 0 ] || [ ! -f "$OGG_AUDIO" ]; then
                    FILE_TO_ATTACH="$audio"
                    ATTACHMENT_INFO="WAV original"
                else
                    FILE_TO_ATTACH="$OGG_AUDIO"
                    ATTACHMENT_INFO="OGG para Deltachat"
                fi
                
                EMAIL_SUBJECT="[Channel-9] 🚨 ALERTA DE EMERGENCIA POR RADIO 🚨"
                EMAIL_BODY="
==============================================
¡ALERTA DE EMERGENCIA DETECTADA!
==============================================
Modo: Monitor CB (Asíncrono)
Palabra clave detectada: $DETECTED_WORD
Fecha y Hora: $(date '+%Y-%m-%d %H:%M:%S')
Duración: $MexDuration segundos

--- Transcripción ---
$TRANSCRIPT
--- Fin de Transcripción ---

Se adjunta el archivo de audio ($ATTACHMENT_INFO) para su revisión.
"
                # Envío de correo con mutt
                TEMP_MUTTRC="$RAMDISK/$USER/temp_muttrc_ch9_whisper_$$"
                mkdir -p "$(dirname "$TEMP_MUTTRC")"
                echo "set sendmail=\"/usr/bin/msmtp -C $MSMTP_RC --account=local\"" > "$TEMP_MUTTRC"
                echo "set use_envelope_from=yes" >> "$TEMP_MUTTRC" 
                
                echo "$EMAIL_BODY" | /usr/bin/mutt -F "$TEMP_MUTTRC" -s "$EMAIL_SUBJECT" -a "$FILE_TO_ATTACH" -- "$LOCAL_EMAIL_TO"
                
                if [ $? -eq 0 ]; then
                    echo "✅ Correo de alerta enviado a $LOCAL_EMAIL_TO."
                else
                    echo "❌ ERROR al enviar correo. Revise $MSMTP_LOG"
                fi
                rm -f "$TEMP_MUTTRC"
                
                # Limpieza de archivos de audio procesados
                rm -f "$audio" "$OGG_AUDIO" 2>/dev/null


            else
                # REGISTRO DE MENSAJE NORMAL
                LOG_ENTRY="$(date '+%Y-%m-%d %H:%M:%S') - $TRANSCRIPT"
                echo "$LOG_ENTRY" >> "$LOG_FILE"
                
                echo "INFO: No se detectaron palabras clave en $audio. Omitiendo alerta."
                # Limpiar el archivo WAV no alertado
                rm -f "$audio" 2>/dev/null 
            fi
            
            echo "--- Procesamiento completado para $audio ---"

        done
    else
        echo "INFO: Cola de audios vacía. Esperando $SLEEP_TIME segundos..."
    fi

    # Pausa antes del próximo chequeo
    sleep $SLEEP_TIME 
done

exit