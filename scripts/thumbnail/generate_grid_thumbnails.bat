rem @ECHO OFF

FOR %%i IN (*.mp4) DO (
    FOR /F "tokens=*" %%a in ('ffprobe -v error -hide_banner -print_format json -show_format -show_streams -i "%%i" ^| jq -r -c ".streams[0].nb_frames|tonumber/(5*6)|floor"') DO (ffmpeg -y -hide_banner -i "%%i" -an -frames 1 -vf "select=not(mod(n\,%%a)),scale=-1:320,tile=5X6:padding=1:color=white" "%%~ni.jpg")
)
PAUSE
