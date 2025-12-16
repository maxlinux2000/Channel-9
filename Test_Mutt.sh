# Definir variables de ejemplo (ajusta estas si las pruebas fuera del script)
LOCAL_EMAIL_TO="max@mi.arca"
FILE_TO_ATTACH="/home/max/Imágenes/1.jpg" # O cualquier otro archivo

# Comando de envío
echo "Cuerpo del mensaje de prueba (mutt directo)" | \
/usr/bin/mutt -s "Prueba Directa Mutt (Adjunto)" -a "$FILE_TO_ATTACH" -- "$LOCAL_EMAIL_TO"

