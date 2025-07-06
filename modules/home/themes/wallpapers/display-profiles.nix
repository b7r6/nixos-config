profile:
if profile == "samsung-e6" then
  ''
    magick wallpaper-raw.png \
      -modulate 100,110 \
      -gamma 0.95 \
      -level 8%,100% \
      wallpaper-processed.png
  ''
else if profile == "lg-ultragear-oled" then
  ''
    magick wallpaper-raw.png \
      -modulate 100,120 \
      -gamma 0.90 \
      -level 5%,100% \
      -colorspace sRGB \
      -depth 10 \
      wallpaper-processed.png
  ''
else if profile == "oled" then
  ''
    magick wallpaper-raw.png \
      -level 8%,100% \
      -modulate 100,115 \
      -gamma 0.92 \
      wallpaper-processed.png
  ''
else
  ''
    cp wallpaper-raw.png wallpaper-processed.png
  ''
