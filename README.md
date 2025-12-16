# 📻 Channel-9: Monitor de Emergencia Automático para Radio CB/PMR (Versión Previa/Desarrolladores)

## 🚨 Descripción General

**Channel-9** es una solución de software de código abierto diseñada para transformar un equipo de radio (CB o PMR) conectado a una PC Linux en un **Monitor de Emergencia y Alerta automática**.

El sistema utiliza procesamiento de audio digital (VOX/Squelch) y modelos avanzados de **Reconocimiento Automático de Voz (ASR)** para transcribir transmisiones de voz. Si la transcripción contiene palabras clave predefinidas (ej. "ayuda", "accidente", "emergencia"), el sistema genera una alerta inmediata.

**Esta es una versión previa de desarrollo.** El modo **Monitor CB (Emergencia)** está funcional y listo para pruebas. Los modos Secretaría Telefónica y Loro/Parrot están en fase de integración.

## ✨ Características Principales

| Modo Operativo | Descripción | Estado Actual |
| :--- | :--- | :--- |
| **Monitor CB (Emergencia)** | Monitorea la frecuencia, transcribe la voz en tiempo real y **envía una alerta por correo electrónico** si se detectan palabras clave. | ✅ **Funcional** |
| **Secretaría Telefónica** | Graba un mensaje cuando se detecta una transmisión y envía el archivo de audio al correo electrónico del operador. Incluye una respuesta de audio generada por TTS. | 🛠️ **En Desarrollo** |
| **Loro / Parrot** | Funciona como un repetidor de voz simple, grabando el último mensaje y repitiéndolo después de un breve periodo de silencio. | 🛠️ **En Desarrollo** |

## ⚙️ Tecnologías Utilizadas

Este proyecto se basa en *software* libre de alto rendimiento y herramientas estándar de *scripting* de Linux:

* **whisper.cpp:** Motor ultraligero y rápido para la Transcripción Automática de Voz (ASR).
* **Sox (Sound eXchange):** Utilizado para el procesamiento de audio, detección de silencio (Squelch/VOX) y manipulación de archivos `.wav`.
* **Piper TTS:** Motor de Texto-a-Voz (TTS) de alta calidad para generar respuestas audibles (Modo Secretaría).
* **YAD:** Usado en el *script* de configuración para proporcionar una Interfaz Gráfica de Usuario (GUI) sencilla.
* **fpm / dpkg:** Utilizado para la construcción de paquetes `.deb` (los *scripts* *builder* son la clave para la automatización de dependencias).

## 🔨 Despliegue para Desarrolladores (Instalación Manual)

Esta versión requiere que se compilen y se instalen las dependencias críticas (`whisper.cpp` y `piper-tts`) utilizando los *scripts* proporcionados.

### I. Requisitos Previos

1.  **Hardware:** Un equipo de radio (CB/PMR) con salida de audio y una tarjeta de sonido USB/integrada en Linux.
2.  **Sistema Operativo:** Distribución Linux basada en Debian/Ubuntu.
3.  **Dependencias del Sistema:** Instalar las herramientas necesarias para la compilación y ejecución:
    ```bash
    sudo apt update
    sudo apt install -y git cmake build-essential ruby ruby-dev python3 python3-venv sox ffmpeg zenity multimon-ng
    sudo gem install fpm # Instalar el gestor de paquetes Ruby
    ```

### II. Construcción de Dependencias

Ejecute los *scripts* *builder* en el orden indicado para compilar y generar los paquetes `.deb` con aislamiento.

| Script | Descripción | Instalación Manual |
| :--- | :--- | :--- |
| `build_whisper_deb.sh` | Compila `whisper.cpp` y genera `whisper-cpp-cli-[VERSION].deb`. | `sudo dpkg -i whisper-cpp-cli-*.deb` |
| `build_piper_deb.sh` | Crea el entorno virtual para `Piper TTS` y genera `piper-tts-[VERSION].deb`. | `sudo dpkg -i piper-tts-*.deb` |
| `build_piper_models_deb.sh`| Descarga los modelos de voz (por idioma) y genera `piper-tts-model-*.deb`. | `sudo dpkg -i piper-tts-model-es-*.deb` |

### III. Configuración y Ejecución

1.  **Configuración:** Ejecute el *script* de configuración interactivo:
    ```bash
    ./CH9-config.sh
    # Seleccione el modo "3 - Monitor CB" e introduzca las palabras clave y el email de destino.
    ```
2.  **Ejecución:** Inicie el núcleo del sistema:
    ```bash
    ./CH9.sh
    ```

## ⚠️ Estado de Funcionalidad

| Funcionalidad | Estado | Notas |
| :--- | :--- | :--- |
| **Monitor CB (Alerta por Transcripción)** | ✅ **FUNCIONAL** | El núcleo de detección de voz, transcripción de Whisper y el envío de alerta por email están **plenamente operativos y listos para pruebas en el campo.** |
| **Secretaría Telefónica** | 🛠️ **EN DESARROLLO** | La lógica de respuesta (TTS) está en integración. |
| **Loro / Parrot** | 🛠️ **EN DESARROLLO** | La lógica de DTMF y contadores requiere pruebas. |

**¡Agradecemos cualquier *feedback* o contribución para la fase de desarrollo!**
