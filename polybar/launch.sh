killall -q polybar
echo "---" | tee -a /tmp/polybar1.log
polybar basedbar 2>&1 | tee -a /tmp/polybar1.log & disown
echo "Bar launched..."
