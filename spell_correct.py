#!/usr/bin/env python3
# ==============================================================================
# SCRIPT: spell_correct.py
# DESCRIPCIÓN: Corrige ortografía usando pyspellchecker.
# USO: Recibe el texto por stdin y el código de idioma (ej: 'es') como argumento.
# ==============================================================================
import sys
from spellchecker import SpellChecker

def correct_text():
    # 1. Determinar el idioma
    # sys.argv[1] será el código de idioma que le pasemos desde BASH (ej: 'es')
    lang_code = 'es' 
    if len(sys.argv) > 1:
        lang_code = sys.argv[1].lower()
    
    # 2. Leer el texto de la tubería (stdin)
    text = sys.stdin.read().strip()
    if not text:
        # Si no hay texto, salimos sin error
        print("")
        sys.exit(0)

    try:
        # 3. Inicializar el corrector
        # SpellChecker usará automáticamente el diccionario del idioma si está disponible.
        spell = SpellChecker(language=lang_code)
        
        # 4. Procesar la corrección
        corrected_text = text
        
        # Obtener las palabras que el corrector no conoce (misspelled)
        misspelled = spell.unknown(text.split())
        
        for word in misspelled:
            # Obtener la mejor sugerencia
            suggestion = spell.correction(word)
            
            # Si hay sugerencia y es diferente a la palabra original
            if suggestion and suggestion != word:
                # Utilizamos una sustitución simple, asegurando que solo se reemplace la palabra completa
                corrected_text = corrected_text.replace(word, suggestion, 1) # Sustituye solo la primera aparición

        # 5. Imprimir el texto corregido al stdout
        print(corrected_text)
        
    except Exception as e:
        # Si el diccionario del idioma no se pudo cargar, devolvemos el texto crudo.
        # Imprimimos el error a stderr, pero devolvemos el texto original a stdout.
        sys.stderr.write(f"ADVERTENCIA: Fallo al cargar SpellChecker para '{lang_code}' o en la corrección: {e}\n")
        print(text)

if __name__ == "__main__":
    correct_text()
