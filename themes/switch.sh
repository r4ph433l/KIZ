mv ~/.config/themes/current/ ~/.config/themes/tmp/
mv ~/.config/themes/alt/ ~/.config/themes/current/
mv ~/.config/themes/tmp/ ~/.config/themes/alt
feh --bg-fill ~/.config/themes/current/background.png
~/.config/themes/current/config.sh
xrdb ~/.config/themes/current/.Xressources
~/.config/polybar/launch.sh &
