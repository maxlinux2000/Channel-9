#!/bin/bash
# ==============================================================================
# SCRIPT: loro.sh - Sistema de Monitoreo de Voz (VOX/Squelch)
#
# DESCRIPCIÓN:
# Este script implementa un sistema de detección y grabación de voz (VOX/Squelch)
# utilizando la cadena de tuberías 'rec | sox | sox' para radios PMR/CB
# conectadas a través de una tarjeta de sonido USB.
# Incluye lógica de control por DTMF (deshabilitada para el objetivo de transcripción)
# y gestión de tiempos para un funcionamiento estable como repetidor/monitor.
#
# COMPATIBILIDAD:
# Diseñado para Linux, probado en hardware antiguo (HP laptop) con tarjeta USB
# compatible con Raspberry Pi (ARM). Requiere la activación de VOX en la radio.
#
# HISTORIAL DE VERSIONES:
# 2021-12-17 - version 0.5 (Base)
# 2024-07-21 - version 0.9 @ (Control de tiempos y Sysop)
# ------------------------------------------------------------------------------

# Ruta al binario ejecutable de Whisper C++
export WHISPER_EXECUTABLE="/opt/whisper-cpp/bin/main"

# Ruta al modelo GGML/GGHF 
export WHISPER_MODEL_PATH="/opt/whisper-cpp/models/ggml-base.bin"

# Idioma de transcripción (Importante para la precisión)
export ASR_LANGUAGE="es"

# Especificamos al cargador dinámico (ld.so) dónde encontrar libwhisper.so.1
export LD_LIBRARY_PATH="/opt/whisper-cpp/bin/:$LD_LIBRARY_PATH"


# 1. CARGA DE CONFIGURACIÓN
# Carga las variables de entorno críticas (AUDIODEV, FREQ, TIME, etc.)
# desde el archivo de configuración generado.
if [ ! -f $HOME/.loro-config ]; then
    loro-config.sh
fi
source $HOME/.loro-config

# 2. DEFINICIÓN DE VARIABLES INICIALES
# Se mantiene la variable ENABLE para control de activación/desactivación.
# RAMDISK usa /dev/shm para operaciones rápidas en memoria.
ENABLE=1
RAMDISK=/dev/shm

# 3. INICIALIZACIÓN DEL WATCHDOG (Control de tiempo de uso diario)
# Inicializa el contador de tiempo de transmisión acumulado.
# (Esta funcionalidad se mantiene, aunque se desactivará en el refactoring).
echo "1" > /dev/shm/$USER/watchdog.log

# ==============================================================================
# 4. PREPARACIÓN DEL ENTORNO DE GRABACIÓN
# ==============================================================================

# Crear directorio temporal para VOX y limpiar archivos .wav anteriores
mkdir -p $RAMDISK/$USER/vox
rm $RAMDISK/$USER/audio*.wav 2>/dev/null

# Cálculo de la duración mínima del mensaje en microsegundos
DURATION=$(echo "($MinMexDuration * 1000000)/1" | bc) #" ### don't touch please

# Inicialización de archivos de audio de control (tonos de 'roger' y señal)
# (Componentes de la función repetidor/loro, no necesarios para transcripción)
rm $RAMDISK/$USER/vox/vox.wav 
if [ ! -f $RAMDISK/$USER/vox/vox.wav ]; then
    sox -V -r $FREQ -n -b 16 -c 1 $RAMDISK/$USER/vox/vox.wav synth 0.5 sin 440 vol -10dB
fi
cp /usr/local/share/loro/sounds/messagereceived.wav $RAMDISK/$USER/vox/

SystemStop=0



# ==============================================================================
# 1. Función de Transcripción
# ==============================================================================
# La función asume que las variables WHISPER_EXECUTABLE, WHISPER_MODEL_PATH 
# y ASR_LANGUAGE están definidas y exportadas en el entorno (config.sh).

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
#    TRANSCRIPT=$(/opt/whisper-cpp/bin/main -m /opt/whisper-cpp/models/ggml-base.bin --language es -np -nt /dev/shm/max/audio001.wav | tail -n 1 | sed 's|^[[:space:]]*||' )
    # Guarda la transcripción en el archivo TXT
    echo "Transcripción: $TRANSCRIPT" > "$transcript_filename"
    echo "INFO: Transcripción guardada en: $transcript_filename"

    # Devuelve el texto transcrito (lo imprime en la salida estándar)
    echo "$TRANSCRIPT"
}

# ==============================================================================
# 2. Ejemplo de Uso (Para probar la función)
# ==============================================================================
# Para probar: Asegúrate de tener un archivo audio.wav en $RAMDISK/$USER/

# TRANSCRIPCION_FINAL=$(whisper_transcribe "$RAMDISK/$USER/audio.wav")
# echo "Resultado de la transcripción: $TRANSCRIPCION_FINAL"



# ==============================================================================
# 5. BUCLE PRINCIPAL DE MONITOREO (VOX Loop)
# ==============================================================================
while true; do
    echo "monitoring..."
    rm *.wav 2> /dev/null

    # 5.1. CÁLCULO Y GESTIÓN DEL TIEMPO TOTAL DE USO (Watchdog)
    # Acumula el tiempo total de transmisión. Si supera TimeTotal, deshabilita el sistema.
    TotTimeDone=$(while read -r num; do ((sum += num)); done < /dev/shm/$USER/watchdog.log; echo $sum)
    if [ $TotTimeDone -gt $TimeTotal ]; then
        ENABLE=0
        SystemStop=1
    else
        SystemStop=0
    fi

    # Muestra el estado del sistema en pantalla
    echo "
    ENABLE=$ENABLE
    SystemStop=$SystemStop
    TotTimeDone=$TotTimeDone
    "
    
    clear
    echo "
########################################################
# DTMF=$DTMF - ENABLE=$ENABLE - SystemStop=$SystemStop - TotTimeDone=$TotTimeDone 
########################################################"

    # 5.2. COMANDO CRÍTICO DE SQUELCH (TRIPLE PIPE)
    # Esta es la línea que funciona para detección de audio, grabándolo en $RAMDISK/$USER/audio.wav
    # SQUELCH INICIO: silence 0 1 0:$TIME 10%
    # SQUELCH FIN: silence 0 1 0:02 10%
    AUDIODRIVER=$AUDIODRIVER AUDIODEV=$AUDIODEV rec -V0 -r $FREQ -e signed-integer -b 16 -c 1 --endian little    -p  | sox -p -p silence 0 1 0:$TIME 10% | sox -p -r $FREQ -e signed-integer -b 16 -c 1 --endian little $RAMDISK/$USER/audio.wav compand 0.3,1 6:-70,-60,-20 -5 -90 0.2    silence 0 1 0:02 10% : newfile

    # 5.3. PROCESAMIENTO POST-GRABACIÓN
    ls $RAMDISK/$USER/*.wav > $RAMDISK/$USER/list.log
    du $RAMDISK/$USER/*.wav >> $RAMDISK/$USER/size.log

    for audio in $(cat $RAMDISK/$USER/list.log); do
        size=$(cat $audio | wc -l)
        
        # Filtrar archivos vacíos (cero bytes)
        if [ $size == "0" ]; then
            echo "$audio file empty"
            rm $audio
        else
            message=$(echo $audio | sed 's|.wav|_vox.wav|')
            echo "MIX"
            echo message=$message
            
            # Obtener duración del archivo usando ffprobe (en ms/us)
            size2=$(ffprobe -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $audio 2>/dev/null | tr -d '.')
            
            # Filtrar archivos demasiado cortos
            if [ $size2 -lt "$DURATION" ]; then
                echo "$audio file empty"
                rm -f $audio
            else
                # 5.4. GESTIÓN DTMF (Control remoto por tonos)
                # Esta sección será reemplazada por la lógica de transcripción de Whisper.
                DTMF=$(multimon-ng -q -a DTMF -t wav $audio | sed 's|DTMF: ||g' | tr -d '\n' | tr -d '#')
                echo DTMF=$DTMF

                if [ ! -z $DTMF ]; then
                    # Lógica de control START/STOP por DTMF (se mantiene original)
                    if [ $DTMF = $STOP ]; then
                        echo STOP
                        ENABLE=0
                        echo "ENABLE=$ENABLE"
                    fi
                    if [ $DTMF = $START ]; then
                        echo START
                        ENABLE=1
                        echo "ENABLE=$ENABLE"
                    fi
                    if [ $DTMF = $StopSysop ]; then
                        echo STOP
                        ENABLE=0
                        SystemStop=1
                        TotTimeDone=1
                        echo "
                        ENABLE=$ENABLE
                        SystemStop=$SystemStop
                        TotTimeDone=$TotTimeDone
                        "
                    fi
                    if [ $DTMF = $StartSysop ]; then
                        echo START
                        ENABLE=1
                        SystemStop=0
                        echo "1" > /dev/shm/$USER/watchdog.log
                        echo "
                        ENABLE=$ENABLE
                        SystemStop=$SystemStop
                        TotTimeDone=$TotTimeDone
                        "
                    fi
                else
                    # 5.5. PROCESAMIENTO DE MENSAJE SIN DTMF
                    if [ $ENABLE = 1 ]; then
                        MexDuration=$(echo "( $size2 / 1000000 )*1" | bc) #"

                        if [ $MexDuration -lt $OneMsg ]; then
                            # Lógica para reproducir el mensaje (Comportamiento Loro/Repetidor)
                            clear
                            echo "
########################################################
# DTMF=$DTMF - ENABLE=$ENABLE - SystemStop=$SystemStop - TotTimeDone=$TotTimeDone 
########################################################"
                            echo "$MexDuration" >> $RAMDISK/$USER/watchdog.log
                            AUDIODRIVER=$AUDIODRIVER  AUDIODEV=$AUDIODEV play $audio
                        fi



# ==============================================================================
# 2. Ejemplo de Uso (Para probar la función)
# ==============================================================================
# Para probar: Asegúrate de tener un archivo audio.wav en $RAMDISK/$USER/

#TRANSCRIPCION_FINAL=$(whisper_transcribe "$RAMDISK/$USER/audio.wav")
TRANSCRIPCION_FINAL=$(whisper_transcribe "/dev/shm/max/audio001.wav")

echo "Resultado de la transcripción: $TRANSCRIPCION_FINAL"

exit

                        # PUNTO DE INTEGRACIÓN: Aquí se integrará la llamada a Whisper y la lógica de alerta.
                        # STOPPED EMAIL FOR NOW  echo "Acaba de llegar este nuevo mensaje"  | mail -s "Nuevo Mensaje por radio" $USER@$DOMAIN -A $audio
                    fi
                    rm $RAMDISK/$USER/*.wav 2> /dev/null
                fi
            fi
        fi
    done
    
    # 5.6. LIMPIEZA Y PAUSA DEL BUCLE
    rm $RAMDISK/$USER/*.wav 2> /dev/null
    sleep 0.3 # TIEMPO DE PAUSA CRÍTICO: 0.3 segundos
    :> $RAMDISK/$USER/size.log
    
    # 5.7. RESET DIARIO DEL WATCHDOG (a las 23:xx)
    HOUR=$(date '+%Y-%m-%d')
    if [ $HOUR = 23 ]; then
        echo "1" > /dev/shm/$USER/watchdog.log
        SystemStop=0
    fi
done
exit 0