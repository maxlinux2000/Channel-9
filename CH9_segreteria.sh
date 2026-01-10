#!/bin/bash
# ==============================================================================
# SCRIPT: CH9_segreteria.sh - MODO 4: Secretaría Telefónica (ENRUTAMIENTO INTELIGENTE)
# ==============================================================================

# ------------------------------------------------------------------------------
# SETUP DE WHISPER C++ (Necesario para la transcripción del primer minuto)
# ------------------------------------------------------------------------------
MODEL="small"
export WHISPER_EXECUTABLE="/opt/whisper-cpp/bin/main"
export WHISPER_MODEL_PATH="/opt/whisper-cpp/models/ggml-$MODEL.bin"
export LD_LIBRARY_PATH="/opt/whisper-cpp/bin/:$LD_LIBRARY_PATH"
# ------------------------------------------------------------------------------

# 2. CARGA DE CONFIGURACIÓN
source $HOME/.CH9-config

# 📢 LIMPIEZA CRÍTICA DE VARIABLES DE CONFIGURACIÓN
# Se asume que ARCHIVE_EMAIL_TO y DOMAIN_ATALAYA están definidos en $HOME/.CH9-config
ARCHIVE_EMAIL_TO="${ARCHIVE_EMAIL_TO:-archive@mi.atalaya}"
DOMAIN_ATALAYA="${DOMAIN_ATALAYA:-mi.atalaya}"

# 3. DEFINICIÓN DE VARIABLES INICIALES
ENABLE=1
RAMDISK=/dev/shm
USER=$(whoami)
DEBUG=0
DEFAULT_TARGET_EMAIL="$ARCHIVE_EMAIL_TO" # Correo por defecto (Almacenamiento)
ACTIVATION_PHRASE="mensaje para"

# 4. VARIABLE DE LOG
LOG_FILE="$HOME/ch9_segreteria.log"
touch "$LOG_FILE"

# 5. PREPARACIÓN DEL ENTORNO DE GRABACIÓN
# NO se usa el directorio 'vox', ya que el procesamiento es síncrono.
mkdir -p $RAMDISK/$USER/segreteria
rm $RAMDISK/$USER/audio*.wav 2>/dev/null

# ------------------------------------------------------------------------------
# 📢 MODO SECRETARÍA - NO USA SERVICIO ASÍNCRONO
# ------------------------------------------------------------------------------
echo "--- Modo Secretaría: El procesamiento de transcripción es síncrono. ---"
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# Función de Transcripción (LIMITADA A LOS PRIMEROS 10 SEGUNDOS)
# ------------------------------------------------------------------------------
whisper_transcribe_intro() {
    local audio_file="$1"
    local timestamp=$(basename "$audio_file" .wav)
    local TEMP_AUDIO="$RAMDISK/$USER/segreteria/temp_${timestamp}.wav"
    
    if [ -z "$audio_file" ] || [ ! -f "$audio_file" ]; then
        echo "ERROR: La función whisper_transcribe requiere una ruta de archivo válida." >&2
        return 1
    fi
    
    # CRÍTICO: Limitar la transcripción a los primeros 10 segundos usando ffmpeg.
    ffmpeg -i "$audio_file" -ss 00:00:00 -to 00:00:10 -c copy "$TEMP_AUDIO" -y > /dev/null 2>&1
    
    echo "INFO: Transcribiendo primeros 10 segundos de: $audio_file (Idioma: $WHISPER_LANG)" >&2 

    # -nt: no timestamp, -s: supress printing (para obtener solo el texto)
    TRANSCRIPT_RESULT=$(
        "$WHISPER_EXECUTABLE" -m "$WHISPER_MODEL_PATH" "$TEMP_AUDIO" -l "$WHISPER_LANG" -nt -s 2>/dev/null |\
         tail -n 1 | sed 's|^[[:space:]]*||')
    
    rm -f "$TEMP_AUDIO"
    
    echo "$TRANSCRIPT_RESULT"
}
# ------------------------------------------------------------------------------


# 6. BUCLE PRINCIPAL DE MONITOREO (VOX Loop)

DURATION=$(echo "($MinMexDuration * 1000000)/1" | bc) #"
while true; do
    
    # 6.1. ESTADO DEL SISTEMA
    if [ "$DEBUG" = 0 ]; then clear; fi
    
    echo "monitoring (Modo Secretaría Telefónica)... PID de Monitor: $$"
    
    echo "
########################################################
# MODO SECRETARÍA TELEFÓNICA - ENABLE=$ENABLE
########################################################"

    echo "--- Últimos 5 Mensajes Registrados ---"
    tail -n 5 "$LOG_FILE"
    echo "--------------------------------------"

    # 6.2. COMANDO CRÍTICO DE SQUELCH (TRIPLE PIPE)
    AUDIODRIVER=$AUDIODRIVER AUDIODEV=$AUDIODEV rec -V0 -r $FREQ -e signed-integer -b 16 -c 1 --endian little    -p  | sox -p -p silence 0 1 0:$TIME 10% | sox -p -r $FREQ -e signed-integer -b 16 -c 1 --endian little $RAMDISK/$USER/audio.wav compand 0.3,1 6:-70,-60,-20 -5 -90 0.2  silence 0 1 0:02 10% : newfile

    # 6.3. PROCESAMIENTO POST-GRABACIÓN
    ls $RAMDISK/$USER/*.wav > $RAMDISK/$USER/list.log
    du $RAMDISK/$USER/*.wav >> $RAMDISK/$USER/size.log

    for audio in $(cat $RAMDISK/$USER/list.log); do
        size=$(cat "$audio" | wc -l) 
        
        if [ "$size" == "0" ]; then 
            echo "$audio file empty"
            rm "$audio"
        else
            size2=$(ffprobe -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$audio" 2>/dev/null | tr -d '.')
            
            if [ "$size2" -lt "$DURATION" ]; then
                echo "$audio file too short"
                rm -f "$audio"
            else
                # 6.4. LÓGICA DE GRABACIÓN Y PROCESAMIENTO
                if [ "$ENABLE" = 1 ]; then
                    
                    # 1. Renombrar y mover para procesamiento síncrono
                    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
                    PROCESSED_AUDIO="$RAMDISK/$USER/segreteria/${TIMESTAMP}.wav"
                    
                    echo "INFO: Audio grabado ($audio). Moviendo a $PROCESSED_AUDIO para proceso síncrono."
                    mv "$audio" "$PROCESSED_AUDIO" || { echo "ERROR: No se pudo mover/renombrar el archivo de audio. Se queda en $audio."; continue; }

                    MexDuration=$(echo "( $size2 / 1000000 )*1" | bc) #"
                    
                    # 2. Transcribir el primer minuto para detectar la frase clave
                    TRANSCRIPT_RAW=$(whisper_transcribe_intro "$PROCESSED_AUDIO")
                    
                    # Limpieza de la transcripción para la búsqueda
                    TRANSCRIPT=$(echo "$TRANSCRIPT_RAW" | \
                        sed 's/\xc2\xa0/ /g' | \
                        sed -E 's/[^[:alnum:] ]/ /g' | \
                        sed -E 's/ +/ /g; s/^ *| *$//' | tr '[:upper:]' '[:lower:]')

                    PADDED_TRANSCRIPT=" $TRANSCRIPT "
                    
                    TARGET_EMAIL="$DEFAULT_TARGET_EMAIL"
                    DETECTED_USER=""
                    
                    # --- LÓGICA DE DOBLE DETECCIÓN ---
                    
                    # Paso A: Búsqueda de la Frase de Activación
                    if [[ "$PADDED_TRANSCRIPT" == *"$ACTIVATION_PHRASE"* ]]; then
                        echo "INFO: Frase de activación ('$ACTIVATION_PHRASE') detectada."
                        
                        # Paso B: Extraer el posible nombre después de la frase
                        # (Extrae todo lo que viene después de la frase de activación)
                        RAW_NAME=$(echo "$TRANSCRIPT" | sed "s/.*$ACTIVATION_PHRASE *//")
                        
                        # Paso C: Limpiar y Tokenizar el nombre (tomar solo la primera palabra)
                        # Separamos por espacios y tomamos el primer token
                        DETECTED_USER=$(echo "$RAW_NAME" | awk '{print $1}')
                        
                        if [ -n "$DETECTED_USER" ]; then
                            
                            # Paso D: Verificar si existe el directorio home del usuario detectado
                            if [ -d "/home/$DETECTED_USER" ]; then
                                # Usuario válido: Enrutamiento al correo del usuario
                                TARGET_EMAIL="${DETECTED_USER}@${DOMAIN_ATALAYA}"
                                
                                LOG_ENTRY="$(date '+%Y-%m-%d %H:%M:%S') - ENRUTADO A $DETECTED_USER ($TARGET_EMAIL) - $TRANSCRIPT"
                                echo "✅ $LOG_ENTRY" >> "$LOG_FILE"
                                echo "INFO: Mensaje enrutado para el usuario detectado: $TARGET_EMAIL"
                            else
                                # Usuario no válido: Se envía a la cuenta de archivo
                                LOG_ENTRY="$(date '+%Y-%m-%d %H:%M:%S') - USUARIO NO ENCONTRADO ($DETECTED_USER) - $TRANSCRIPT"
                                echo "⚠️ $LOG_ENTRY" >> "$LOG_FILE"
                                echo "ADVERTENCIA: Usuario '$DETECTED_USER' no válido. Enviando a archivo: $DEFAULT_TARGET_EMAIL"
                            fi
                        else
                            # No se detectó un nombre después de la frase clave
                            LOG_ENTRY="$(date '+%Y-%m-%d %H:%M:%S') - SIN NOMBRE DESPUÉS DE LA FRASE CLAVE - $TRANSCRIPT"
                            echo "⚠️ $LOG_ENTRY" >> "$LOG_FILE"
                            echo "ADVERTENCIA: Frase detectada, pero sin nombre. Enviando a archivo: $DEFAULT_TARGET_EMAIL"
                        fi
                    else
                        # No se detectó la frase clave: Se envía a la cuenta de archivo
                        LOG_ENTRY="$(date '+%Y-%m-%d %H:%M:%S') - ARCHIVO POR DEFECTO - $TRANSCRIPT"
                        echo "📢 $LOG_ENTRY" >> "$LOG_FILE"
                        echo "INFO: Frase clave no detectada. Enviando a archivo: $DEFAULT_TARGET_EMAIL"
                    fi
                    
                    
                    # 3. CONVERSIÓN y ENVÍO DE CORREO (Usa $TARGET_EMAIL)
                    
                    OGG_AUDIO="${PROCESSED_AUDIO%.wav}.ogg"
                    ffmpeg -i "$PROCESSED_AUDIO" -c:a libvorbis -qscale:a 5 "$OGG_AUDIO" -y > /dev/null 2>&1
                    
                    # Se adjunta el archivo OGG para DeltaChat/etc.
                    FILE_TO_ATTACH="$OGG_AUDIO"
                    ATTACHMENT_INFO="OGG"
                                        
                    EMAIL_SUBJECT="[Channel-9] 📬 Mensaje de Secretaría - Destino: $TARGET_EMAIL"
                    EMAIL_BODY="
==============================================
NUEVO MENSAJE DE SECRETARÍA TELEFÓNICA
==============================================
Modo: Secretaría Telefónica (Síncrono)
Destino del mensaje: $TARGET_EMAIL
Usuario Detectado: ${DETECTED_USER:-[Ninguno]}
Frase Transcrita (10s): $TRANSCRIPT

Fecha y Hora: $(date '+%Y-%m-%d %H:%M:%S')
Duración del Audio: $MexDuration segundos

Se adjunta el archivo de audio ($ATTACHMENT_INFO) completo.
"
                    # Envío de correo con mutt (Asumimos cuenta 'default' o 'local' configurada en msmtprc)
                    TEMP_MUTTRC="$RAMDISK/$USER/temp_muttrc_ch9_segreteria_$$"
                    mkdir -p "$(dirname "$TEMP_MUTTRC")"
                    
                    # Usar la cuenta por defecto/local en msmtprc
                    echo "set sendmail=\"/usr/bin/msmtp -C $HOME/.msmtprc --account=default\"" > "$TEMP_MUTTRC"
                    echo "set use_envelope_from=yes" >> "$TEMP_MUTTRC" 
                    
                    echo "$EMAIL_BODY" | /usr/bin/mutt -F "$TEMP_MUTTRC" -s "$EMAIL_SUBJECT" -a "$FILE_TO_ATTACH" -- "$TARGET_EMAIL"
                    
                    if [ $? -eq 0 ]; then
                        echo "✅ Correo enviado a $TARGET_EMAIL."
                    else
                        echo "❌ ERROR al enviar correo a $TARGET_EMAIL."
                    fi
                    rm -f "$TEMP_MUTTRC"
                    
                    # Limpieza de archivos de audio procesados
                    rm -f "$PROCESSED_AUDIO" "$OGG_AUDIO" 2>/dev/null
                    
                else
                    # Limpiar el archivo WAV si el monitoreo está deshabilitado
                    rm -f "$audio" 2>/dev/null 
                fi
            fi
        fi
    done
    
    # 6.5. LIMPIEZA Y PAUSA DEL BUCLE
    sleep 0.3
    :> $RAMDISK/$USER/size.log
    
done

exit
