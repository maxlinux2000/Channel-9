#!/bin/bash
# ==============================================================================
# SCRIPT: CH9_loro.sh - MODO 1: Loro/Parrot (Repetidor)
# ==============================================================================

# 📢 CORRECCIÓN: La configuración se carga desde .CH9-config (generado por CH9-config.sh)
# 1. CARGA DE CONFIGURACIÓN
if [ ! -f $HOME/.CH9-config ]; then
    CH9-config.sh
fi
source $HOME/.CH9-config

# 2. DEFINICIÓN DE VARIABLES INICIALES
ENABLE=1
RAMDISK=/dev/shm
USER=$(whoami)
DEBUG=1 # Mantenemos el debug que estaba en el original

# 3. INICIALIZACIÓN DEL WATCHDOG (Control de tiempo de uso diario)
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
rm $RAMDISK/$USER/vox/vox.wav 
if [ ! -f $RAMDISK/$USER/vox/vox.wav ]; then
    sox -V -r $FREQ -n -b 16 -c 1 $RAMDISK/$USER/vox/vox.wav synth 0.5 sin 440 vol -10dB
fi
cp /usr/local/share/loro/sounds/messagereceived.wav $RAMDISK/$USER/vox/ 2>/dev/null

SystemStop=0

# ==============================================================================
# 5. BUCLE PRINCIPAL DE MONITOREO (VOX Loop)
# ==============================================================================
while true; do
    echo "monitoring (Modo Loro)..."
    rm *.wav 2> /dev/null 

    # 5.1. CÁLCULO Y GESTIÓN DEL TIEMPO TOTAL DE USO (Watchdog)
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
# MODO LORO - ENABLE=$ENABLE - SystemStop=$SystemStop - TotTimeDone=$TotTimeDone 
########################################################"

    # 5.2. COMANDO CRÍTICO DE SQUELCH (TRIPLE PIPE)
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
            
            # Obtener duración del archivo usando ffprobe (en ms/us)
            size2=$(ffprobe -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $audio 2>/dev/null | tr -d '.')
            
            # Filtrar archivos demasiado cortos
            if [ $size2 -lt "$DURATION" ]; then
                echo "$audio file too short"
                rm -f $audio
            else
                # 5.4. GESTIÓN DTMF (Lógica de control común a todos los modos)
                DTMF=$(multimon-ng -q -a DTMF -t wav $audio | sed 's|DTMF: ||g' | tr -d '\n' | tr -d '#')
                echo "DTMF=$DTMF"

                if [ ! -z $DTMF ]; then
                    if [ $DTMF = $STOP ]; then ENABLE=0; fi
                    if [ $DTMF = $START ]; then ENABLE=1; fi
                    if [ $DTMF = $StopSysop ]; then ENABLE=0; SystemStop=1; TotTimeDone=1; fi
                    if [ $DTMF = $StartSysop ]; then ENABLE=1; SystemStop=0; echo "1" > /dev/shm/$USER/watchdog.log; fi
                else
                    # 5.5. LÓGICA ESPECÍFICA DEL MODO LORO (Repetir el mensaje)
                    if [ $ENABLE = 1 ]; then
                        MexDuration=$(echo "( $size2 / 1000000 )*1" | bc) #"
                        
                        # Solo repetir si el mensaje es más corto que el límite OneMsg
                        if [ $MexDuration -lt $OneMsg ]; then
                            
                            echo "$MexDuration" >> $RAMDISK/$USER/watchdog.log # Acumular tiempo
                            echo "🔊 Modo Loro: Reproduciendo mensaje ($MexDuration s)."

                            # Reproducir el audio
                            AUDIODRIVER=$AUDIODRIVER  AUDIODEV=$AUDIODEV play $audio
                        else
                            echo "INFO: Mensaje demasiado largo ($MexDuration s) para modo Loro. Omitiendo repetición."
                        fi
                    fi
                fi
            fi
        fi
        rm $audio 2> /dev/null # Limpieza del archivo
    done
    
    # 5.6. LIMPIEZA Y PAUSA DEL BUCLE
    sleep 0.3 # TIEMPO DE PAUSA CRÍTICO: 0.3 segundos
    :> $RAMDISK/$USER/size.log
    
    # 5.7. RESET DIARIO DEL WATCHDOG
    HOUR=$(date '+%H')
    if [ $HOUR = 23 ]; then
        echo "1" > /dev/shm/$USER/watchdog.log
        SystemStop=0
    fi
done
exit 0

