#!/bin/bash
# ==============================================================================
# SCRIPT: CH9_monitor.sh - MODO 3: Monitor CB (SOLO GRABACIÓN)
# ==============================================================================

# 2. CARGA DE CONFIGURACIÓN
source $HOME/.CH9-config

# 3. DEFINICIÓN DE VARIABLES INICIALES
ENABLE=1
RAMDISK=/dev/shm
USER=$(whoami)
DEBUG=0

# 4. VARIABLE DE LOG
LOG_FILE="$HOME/ch9_monitor.log"
touch "$LOG_FILE"

# 5. PREPARACIÓN DEL ENTORNO DE GRABACIÓN
mkdir -p $RAMDISK/$USER/vox
rm $RAMDISK/$USER/audio*.wav 2>/dev/null

# ------------------------------------------------------------------------------
# 📢 INFORMACIÓN DEL SERVICIO ASÍNCRONO DE WHISPER (AHORA SYSTEMD)
# ------------------------------------------------------------------------------
echo "--- La Transcripción Asíncrona la gestiona el servicio 'ch9-whisper.service' ---"
echo "INFO: Asegúrese de que el servicio esté activo para procesar el audio."
# El proceso de CH9_monitor.sh se centra ahora sólo en la grabación.
# ------------------------------------------------------------------------------


# 6. BUCLE PRINCIPAL DE MONITOREO (VOX Loop)

DURATION=$(echo "($MinMexDuration * 1000000)/1" | bc) #"
while true; do
    
    # 6.1. ESTADO DEL SISTEMA
    if [ "$DEBUG" = 0 ]; then clear; fi
    
    echo "monitoring (Modo Monitor CB/SOLO GRABACIÓN)... PID de Monitor: $$"
    
    echo "
########################################################
# MODO MONITOR CB - ENABLE=$ENABLE
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
                # 6.4. LÓGICA DE GRABACIÓN Y ALMACENAMIENTO
                if [ "$ENABLE" = 1 ]; then
                    
                    # PASO CRÍTICO: Renombrar el archivo de audio con un sello de tiempo y mover.
                    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
                    NEW_AUDIO="$RAMDISK/$USER/vox/${TIMESTAMP}.wav"
                    
                    echo "INFO: Audio grabado ($audio). Renombrando a $NEW_AUDIO para Transcripción Asíncrona..."
                    
                    # Movimiento/Renombre al directorio 'vox' donde CH9_whisper lo espera
                    mv "$audio" "$NEW_AUDIO" || { echo "ERROR: No se pudo mover/renombrar el archivo de audio. Se queda en $audio."; continue; }

                    MexDuration=$(echo "( $size2 / 1000000 )*1" | bc) #"
                    
                    LOG_ENTRY="$(date '+%Y-%m-%d %H:%M:%S') - AUDIO GRABADO ($MexDuration s) - $NEW_AUDIO"
                    echo "$LOG_ENTRY" >> "$LOG_FILE"
                    
                    echo "INFO: Audio listo para CH9_whisper en $NEW_AUDIO."
                    
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