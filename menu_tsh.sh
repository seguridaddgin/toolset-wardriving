#!/bin/bash
# menu_tsh.sh - Administrador interactivo del ToolSet Wardriving Hunter

# Verificar si el paquete dialog se encuentra instalado
if ! command -v dialog &> /dev/null; then
    echo "Error: el paquete 'dialog' no está instalado."
    echo "Por favor, instalalo con:"
    echo "sudo apt install dialog"
    exit 1
fi

# Configuración de las variables
PROC_NAME="kismet"
DEVICE="/dev/ttyACM0"
KISMET_BIN="/usr/bin/kismet"
KISMET_USER="root"            # Usuario que ejecuta kismet
KISMET_LOGDIR="/var/log/kismet"
PIDFILE="/var/run/kismet.pid"

mkdir -p $KISMET_LOGDIR

# Detectar si el proceso se encuentra corriendo
PID=$(pgrep -x "$PROC_NAME")

if [ -n "$PID" ]; then
	echo "$PID" > "$PIDFILE"
fi

# --- Funciones --------------------------------------------------

start_kismet() {
    if [ -f "$PIDFILE" ] && ps -p $(cat "$PIDFILE") > /dev/null; then
        dialog --msgbox "Kismet ya está en ejecución (PID $(cat $PIDFILE))." 6 60
        return
    fi

    dialog --infobox "Iniciando Kismet en segundo plano..." 4 50
    sleep 1

    # Ejecutar Kismet en segundo plano, sin interferir con ncurses
    $KISMET_BIN --log-debug \
        -t "Kismet_$(date +'%d-%m-%Y_%H-%M-%S')" \
        > "$KISMET_LOGDIR/kismet_$(date +'%Y%m%d_%H%M%S').log" 2>&1 < /dev/null &

    echo $! | sudo tee "$PIDFILE" > /dev/null
    sleep 1
    dialog --msgbox "Kismet iniciado en segundo plano (PID $(cat $PIDFILE))" 6 60
}

stop_kismet() {
    if [ -f "$PIDFILE" ] && ps -p $(cat "$PIDFILE") > /dev/null; then
        sudo kill $(cat "$PIDFILE")
        sudo rm -f "$PIDFILE"
        dialog --msgbox "Kismet detenido correctamente." 6 50
    else
        dialog --msgbox "Kismet no está en ejecución." 6 50
    fi
}

restart_kismet() {
    stop_kismet
    sleep 1
    start_kismet
}

status_kismet() {
    if [ -f "$PIDFILE" ] && ps -p $(cat "$PIDFILE") > /dev/null; then
        STATUS="Kismet está corriendo con PID $(cat $PIDFILE)."
    else
        STATUS="Kismet no se está ejecutando."
    fi
    dialog --msgbox "$STATUS" 6 60
}

reboot_system() {
    if [ -f "$PIDFILE" ] && ps -p $(cat "$PIDFILE") > /dev/null; then
        sudo kill $(cat "$PIDFILE")
        sudo rm -f "$PIDFILE"
    fi
    sleep 1
    reboot
}

shutdown_system() {
    if [ -f "$PIDFILE" ] && ps -p $(cat "$PIDFILE") > /dev/null; then
        sudo kill $(cat "$PIDFILE")
        sudo rm -f "$PIDFILE"
    fi
    sleep 1
    shutdown now
}

view_file_capture() {
    if [ -f "$PIDFILE" ] && ps -p $(cat "$PIDFILE") > /dev/null; then
        LINE=$(ps aux | grep '[k]ismet' | head -n 1)
        TARGET=$(echo "$LINE" | sed -n 's/.*-t \([^ ]*\).*/\1/p')
        FILE_NAME_CAP="/home/lasi/kismet/${TARGET}.kismet"
        SIZE_FILE_CAP=$(stat -c %s "$FILE_NAME_CAP")
        dialog --msgbox "Nombre: $FILE_NAME_CAP\nTamaño: $SIZE_FILE_CAP bytes" 7 70
    else
        dialog --msgbox "Nombre: \nTamaño: " 7 70
    fi
}

kismet_check_status() {
    if [ -f "$PIDFILE" ] && ps -p $(cat "$PIDFILE") > /dev/null; then
        echo "KISMET Ok"
    else
        echo "No Kismet"
    fi
}

gps_check_status() {
    TIMEOUT=3
    DATA=$(timeout "$TIMEOUT" cat "$DEVICE" 2>/dev/null | grep -m 1 '^\$GP')

    if [ -n "$DATA" ]; then
        echo "GPSd Ok"
    else
        echo "No GPSd"
    fi
}

status_gps() {
    TIMEOUT=3
    DATA=$(timeout "$TIMEOUT" cat "$DEVICE" 2>/dev/null | grep -m 1 '^\$GP')

    if [ -n "$DATA" ]; then
        STATUS="Kismet recibe datos del GPS"
    else
        STATUS="Kismet NO recibe datos del GPS"
    fi
    dialog --msgbox "$STATUS" 6 50
}

# --- Menú principal ---------------------------------------------

while true; do

    STATUS_KISMET_MSG=$(kismet_check_status)
    STATUS_GPS_MSG=$(gps_check_status)

    CHOICE=$(dialog --clear --stdout \
        --title " ToolSet Wardriving Hunter | $STATUS_KISMET_MSG | $STATUS_GPS_MSG " \
        --menu "Seleccione una acción:" 16 70 6 \
        1 "Iniciar Kismet" \
        2 "Detener Kismet" \
        3 "Reiniciar Kismet" \
        4 "Ver estado de Kismet" \
        5 "Ver archivo de captura de Kismet" \
	6 "Ver estado gps" \
	7 "Reiniciar el sistema" \
	8 "Apagar el sistema" \
	0 "Salir") 
    
    case $CHOICE in
        1) start_kismet ;;
        2) stop_kismet ;;
        3) restart_kismet ;;
        4) status_kismet ;;
        5) view_file_capture ;;
        6) status_gps ;;
        7) reboot_system ;;
        8) shutdown_system ;;
        0) clear; exit 0 ;;
        *) clear; exit 0 ;;
    esac
done

