@ECHO OFF
cd %~dp0
SET /P video=Video: 
SET /P audio=Audio: 
SET "audiob=%audio:~47%"
SET "audiob=%audiob:~0,-1%"
ffmpeg -i %video% -i %audio% -c:a copy -c:v copy ".%audiob%.mp4"
