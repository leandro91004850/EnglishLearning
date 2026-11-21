#!/bin/sh
# Gera o ícone do Legendas YT em todas as plataformas (iOS, macOS e Android) a partir
# do desenho em desenhar_icone.swift. Precisa de um Mac (usa o Swift e o sips).
#
#   sh tool/icone/gerar.sh
set -eu
cd "$(dirname "$0")/../.."   # a pasta legendas_yt

saida=tool/icone/saida
swift tool/icone/desenhar_icone.swift "$saida"

# redim <pixels> <origem> <destino>
redim() { sips -z "$1" "$1" "$2" --out "$3" >/dev/null; }
vezes() { awk "BEGIN { printf \"%d\", $1 * $2 + 0.5 }"; }

# iOS: cada arquivo do AppIcon no tamanho que o nome diz (83.5x83.5@2x = 167 px)
for f in ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-*.png; do
  nome=$(basename "$f" .png)
  pontos=${nome#Icon-App-}; pontos=${pontos%%x*}
  escala=${nome##*@}; escala=${escala%x}
  redim "$(vezes "$pontos" "$escala")" "$saida/ios_1024.png" "$f"
done

# macOS
for n in 16 32 64 128 256 512 1024; do
  redim "$n" "$saida/macos_1024.png" "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$n.png"
done

# Android: o ícone antigo (48 dp) e as duas camadas do adaptativo (108 dp), em cada densidade
for d in mdpi:1 hdpi:1.5 xhdpi:2 xxhdpi:3 xxxhdpi:4; do
  pasta=android/app/src/main/res/mipmap-${d%%:*}
  x=${d#*:}
  redim "$(vezes 48 "$x")" "$saida/android_legacy_1024.png" "$pasta/ic_launcher.png"
  redim "$(vezes 108 "$x")" "$saida/android_foreground_432.png" "$pasta/ic_launcher_foreground.png"
  redim "$(vezes 108 "$x")" "$saida/android_background_432.png" "$pasta/ic_launcher_background.png"
done

# o ícone do ⋮ › Sobre, dentro do app
mkdir -p assets
redim 192 "$saida/ios_1024.png" assets/icone.png

echo "Ícone gerado para iOS, macOS e Android."
