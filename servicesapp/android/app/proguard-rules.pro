# O google_mlkit_text_recognition (OCR do cartão frota) referencia os
# reconhecedores de chinês, devanágari, japonês e coreano, que não incluímos
# (só usamos o latino). Sem isto o R8 do build de release falha.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
