#!/bin/bash
# ==============================================================================
# SCRIPT: CH9_secretaria.sh - MODO 2: Secretaría Telefónica
# ==============================================================================

# ------------------------------------------------------------------------------
# SETUP DE WHISPER C++ (Necesario para la transcripción)
# ------------------------------------------------------------------------------

# 📢 CORRECCIÓN: Modelo 'small' configurado en build_whisper_deb.sh
MODEL="small"

export WHISPER_EXECUTABLE="/opt/whisper-cpp/bin/main"
export WHISPER_MODEL_PATH="/opt/whisper-cpp/models/ggml-$MODEL.bin"
export ASR_LANGUAGE="es"
export LD_LIBRARY_PATH="/opt/whisper-cpp/bin/:$LD_LIBRARY_PATH"

# ==============================================================================
# 1. Función de Transcripción (Copiada sin modificar el interior)
# ==============================================================================
whisper_transcribe() {
    local audio_file="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    # Define la ruta donde se guardará el archivo TXT
    local transcript_filename="$RAMDISK/$USER/transcript_${timestamp}.txt"
    
    if [ -z "$audio_file" ] || [ ! -f "$audio_file" ]; then
        echo "ERROR: La función whisper_transcribe requiere una ruta de archivo válida." >&2
        return 1
    fi

    echo "INFO: Transcribiendo archivo: $audio_file"

    # Ejecuta Whisper C++ y filtra la salida para obtener solo el texto.
    TRANSCRIPT=$(
        "$WHISPER_EXECUTABLE" -m "$WHISPER_MODEL_PATH" "$audio_file" -l "$ASR_LANGUAGE" -np -nt |\
         tail -n 1 | sed 's|^[[:space:]]*||')
    
    # Guarda la transcripción en el archivo TXT
    echo "Transcripción: $TRANSCRIPT" > "$transcript_filename"
    echo "INFO: Transcripción guardada en: $transcript_filename"

    # Devuelve el texto transcrito (lo imprime en la salida estándar)
    echo "$TRANSCRIPT"
}
# ------------------------------------------------------------------------------

# 📢 CORRECCIÓN: La configuración se carga desde .CH9-config
# 2. CARGA DE CONFIGURACIÓN
if [ ! -f $HOME/.CH9-config ]; then
    CH9-config.sh
fi
source $HOME/.CH9-config

# 3. DEFINICIÓN DE VARIABLES INICIALES
ENABLE=1
RAMDISK=/dev/shm
USER=$(whoami)
DEBUG=1 # Mantenemos el debug que estaba en el original

# 4. INICIALIZACIÓN DEL WATCHDOG (Control de tiempo de uso diario)
echo "1" > /dev/shm/$USER/watchdog.log

# ==============================================================================
# 5. PREPARACIÓN DEL ENTORNO DE GRABACIÓN
# ==============================================================================

# Crear directorio temporal para VOX y limpiar archivos .wav anteriores
mkdir -p $RAMDISK/$USER/vox
rm $RAMDISK/$USER/audio*.wav 2>/dev/null

# Cálculo de la duración mínima del mensaje en microsegundos
DURATION=$(echo "($MinMexDuration * 1000000)/1" | bc) #" ### don't touch please

# Inicialización de archivos de audio de control (tonos de 'roger' y señal)
rm $RAMDISK/$USER/vox/vox.wav 
if [ ! -f $RAMDISK/$USER/vox/vox.wav ]; then
    sox -V -r $FREQ -n -b 16 -c 1 $RAMDISK/$USER/vox/vox.wav synth 0.5 sin 440 vol -10dB
fi
cp /usr/local/share/loro/sounds/messagereceived.wav $RAMDISK/$USER/vox/ 2>/dev/null

SystemStop=0

# ==============================================================================
# 6. BUCLE PRINCIPAL DE MONITOREO (VOX Loop)
# ==============================================================================
while true; do
    echo "monitoring (Modo Secretaría Telefónica)..."
    rm *.wav 2> /dev/null

    # 6.1. CÁLCULO Y GESTIÓN DEL TIEMPO TOTAL DE USO (Watchdog)
    TotTimeDone=$(while read -r num; do ((sum += num)); done < /dev/shm/$USER/watchdog.log; echo $sum)
    if [ $TotTimeDone -gt $TimeTotal ]; then
        ENABLE=0
        SystemStop=1
    else
        SystemStop=0
    fi

    # Muestra el estado del sistema en pantalla
    if [ "$DEBUG" = 0 ]; then clear; fi
    echo "
########################################################
# MODO SECRETARIA - ENABLE=$ENABLE - SystemStop=$SystemStop - TotTimeDone=$TotTimeDone 
########################################################"

    # 6.2. COMANDO CRÍTICO DE SQUELCH (TRIPLE PIPE)
    AUDIODRIVER=$AUDIODRIVER AUDIODEV=$AUDIODEV rec -V0 -r $FREQ -e signed-integer -b 16 -c 1 --endian little    -p  | sox -p -p silence 0 1 0:$TIME 10% | sox -p -r $FREQ -e signed-integer -b 16 -c 1 --endian little $RAMDISK/$USER/audio.wav compand 0.3,1 6:-70,-60,-20 -5 -90 0.2    silence 0 1 0:02 10% : newfile

    # 6.3. PROCESAMIENTO POST-GRABACIÓN
    ls $RAMDISK/$USER/*.wav > $RAMDISK/$USER/list.log
    du $RAMDISK/$USER/*.wav >> $RAMDISK/$USER/size.log

    for audio in $(cat $RAMDISK/$USER/list.log); do
        size=$(cat $audio | wc -l)
        
        if [ $size == "0" ]; then
            echo "$audio file empty"
            rm $audio
        else
            message=$(echo $audio | sed 's|.wav|_vox.wav|')
            
            size2=$(ffprobe -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $audio 2>/dev/null | tr -d '.')
            
            if [ $size2 -lt "$DURATION" ]; then
                echo "$audio file too short"
                rm -f $audio
            else
                # 6.4. GESTIÓN DTMF (Lógica de control común)
                DTMF=$(multimon-ng -q -a DTMF -t wav $audio | sed 's|DTMF: ||g' | tr -d '\n' | tr -d '#')

                if [ ! -z $DTMF ]; then
                    if [ $DTMF = $STOP ]; then ENABLE=0; fi
                    if [ $DTMF = $START ]; then ENABLE=1; fi
                    if [ $DTMF = $StopSysop ]; then ENABLE=0; SystemStop=1; TotTimeDone=1; fi
                    if [ $DTMF = $StartSysop ]; then ENABLE=1; SystemStop=0; echo "1" > /dev/shm/$USER/watchdog.log; fi
                else
                    # 6.5. LÓGICA ESPECÍFICA DEL MODO SECRETARÍA
                    if [ $ENABLE = 1 ]; then
                        MexDuration=$(echo "( $size2 / 1000000 )*1" | bc) #"
                        
                        echo "$MexDuration" >> $RAMDISK/$USER/watchdog.log # Acumular tiempo

                        # 1. Transcribir el audio.
                        TRANSCRIPT=$(whisper_transcribe "$audio")
                        
                        # 2. Enviar Correo de Notificación (siempre se notifica en modo secretaría)
                        EMAIL_SUBJECT="[Channel-9] Mensaje de Secretaría Telefónica"
                        EMAIL_BODY="
==============================================
¡NUEVO MENSAJE DE RADIO RECIBIDO!
==============================================
Modo: Secretaría Telefónica
Fecha y Hora: $(date '+%Y-%m-%d %H:%M:%S')
Duración: $MexDuration segundos

--- Transcripción ---
$TRANSCRIPT
--- Fin de Transcripción ---

Se adjunta el archivo de audio original ($audio) para su revisión.
"
                        echo "$EMAIL_BODY" | mail -s "$EMAIL_SUBJECT" "$EMAIL_RECIPIENT" -A "$audio"
                        echo "✅ Correo de notificación enviado a $EMAIL_RECIPIENT."
                        
                        # 3. Lógica de respuesta (Si hay audio de respuesta configurado)
                        if [ ! -z "$RESPONSE_MESSAGE" ] && [ -f "$RESPONSE_MESSAGE" ]; then
                            echo "🔊 Reproduciendo mensaje de respuesta de Secretaría."
                            AUDIODRIVER=$AUDIODRIVER AUDIODEV=$AUDIODEV play "$RESPONSE_MESSAGE"
                        fi
                    fi
                fi
            fi
        fi
        rm $audio 2> /dev/null # Limpieza del archivo
    done
    
    # 6.6. LIMPIEZA Y PAUSA DEL BUCLE
    sleep 0.3
    :> $RAMDISK/$USER/size.log
    
    # 6.7. RESET DIARIO DEL WATCHDOG
    HOUR=$(date '+%H')
    if [ $HOUR = 23 ]; then
        echo "1" > /dev/shm/$USER/watchdog.log
        SystemStop=0
    fi
done
exit 0
