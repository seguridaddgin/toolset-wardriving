#!/bin/bash
echo "---------------------------------------------------------------"
echo "Instalando el ToolSet Wardriving Tracker en Raspberry Pi OS ..."
echo "---------------------------------------------------------------"

echo ""

echo "-----------------------------------------------------------------------------------"
echo "Creando clave para los usuarios del sistema (comenzar, detener, reiniciar, etc) ..."
echo "-----------------------------------------------------------------------------------"
# Creación de una clave para los usuarios de sistema
LENGTH=8
PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$LENGTH")
echo "$PASSWORD" > /root/users_passwords.txt
echo "Ubicación del archivo de clave: /root/users_passwords.txt"

echo ""

echo "------------------------------------------------------------------------"
echo "Agregando usuario tst para la gestión del ToolSet Wardriving Tracker ..."
echo "------------------------------------------------------------------------"
# Agregar un usuario de nombre tst para iniciar la gestión del TST
useradd -m -s /bin/bash tst
usermod --password $(openssl passwd -1 "$PASSWORD") tst
# Agregar el usuario tst al grupo sudo
usermod -aG sudo tst
echo "sudo bash menu_tst.sh" >> /home/tst/.bashrc

echo ""

echo "----------------------------------------------------------------------------"
echo "Actualizando lista de paquetes y los paquetes de sistema Raspberry Pi OS ..."
echo "----------------------------------------------------------------------------"
# Actualizar la lista de paquetes y los paquetes del sistema
# Hacer que apt sea non-interactive
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
apt update
apt upgrade -y

echo ""

echo "----------------------------------"
echo "Instalando y configurando gpsd ..."
echo "----------------------------------"
# Instalación y configuración de gpsd
apt-get remove gpsd
apt-get purge gpsd
apt-get install -y gpsd
apt-get install -y gpsd-clients
systemctl stop gpsd
systemctl stop gpsd.socket
systemctl start gpsd.socket
systemctl enable gpsd.socket
echo "OPTIONS=\"udp://*:9999\"" >> /etc/default/gpsd
sed -i 's/^USBAUTO=".*"/USBAUTO="false"/' /etc/default/gpsd
systemctl restart gpsd.socket

echo ""

echo "------------------------------------"
echo "Instalando y configurando Kismet ..."
echo "------------------------------------"
# Instalación y configuración de kismet
# Agregar la llave del repositorio oficial de kismet
wget -O - https://www.kismetwireless.net/repos/kismet-release.gpg.key --quiet | gpg --dearmor | sudo tee /usr/share/keyrings/kismet-archive-keyring.gpg >/dev/null
# Agregar el repositorio de kismet en las fuentes de apt
echo 'deb [signed-by=/usr/share/keyrings/kismet-archive-keyring.gpg] https://www.kismetwireless.net/repos/apt/release/trixie trixie main' | sudo tee /etc/apt/sources.list.d/kismet.list >/dev/null
apt-get update
apt-get install -y kismet
touch /etc/kismet/kismet_site.conf
echo "gps=gpsd:host=localhost,port=2947" >> /etc/kismet/kismet_site.conf
echo "source=wifi24:channels=\"1,2,3,4,5,6,7,8,9,10,11,12,13\",name=wifi24,type=linuxwifi" >> /etc/kismet/kismet_site.conf
echo "source=wifi58:channels=\"36,48\",name=wifi58,type=linuxwifi" >> /etc/kismet/kismet_site.conf
sed -i 's|^[[:space:]]*log_prefix=\./|log_prefix=/home/tst/kismet|' /etc/kismet/kismet_logging.conf
sed -i 's|log_template=%p/%n-%D-%t-%i\.%l|log_template=%p/%n\.%l|' /etc/kismet/kismet_logging.conf
mkdir /home/tst/kismet
chown -R tst:tst /home/tst/kismet

echo ""

echo "------------------------------------------------------------------"
echo "Agregando usuario comenzar para iniciar la captura de paquetes ..."
echo "------------------------------------------------------------------"
# Agregar un usuario de nombre comenzar para iniciar la captura de paquetes con kismet
useradd -m -s /bin/bash comenzar
usermod --password $(openssl passwd -1 "$PASSWORD") comenzar
# Agregar el usuario comenzar al grupo sudo
usermod -aG sudo comenzar
echo "sudo kismet --log-debug 2>&1 -t \"Kismet_\$(date +'%d-%m-%Y_%H-%M-%S')\" &" >> /home/comenzar/.bashrc

echo ""

echo "----------------------------------------------------------------"
echo "Agregando usuario detener para frenar la captura de paquetes ..."
echo "----------------------------------------------------------------"
# Agregar un usuario de nombre detener para frenar la captura de paquetes con kismet
useradd -m -s /bin/bash detener
usermod --password $(openssl passwd -1 "$PASSWORD") detener
# Agregar el usuario detener al grupo sudo
usermod -aG sudo detener
echo "sudo pkill kismet" >> /home/detener/.bashrc

echo ""

echo "---------------------------------------------------------------------------------------"
echo "Agregando usuario reiniciar para detener y volver a comenzar la captura de paquetes ..."
echo "---------------------------------------------------------------------------------------"
# Agregar un usuario de nombre reiniciar para bajar e iniciar kismet
useradd -m -s /bin/bash reiniciar
usermod --password $(openssl passwd -1 "$PASSWORD") reiniciar
# Agregar el usuario reiniciar al grupo sudo
usermod -aG sudo reiniciar
echo "echo \"Reiniciando kismet ...\"" >> /home/reiniciar/.bashrc
echo "sudo pkill kismet" >> /home/reiniciar/.bashrc
echo "sudo systemctl stop gpsd.socket" >> /home/reiniciar/.bashrc
echo "sleep 10" >> /home/reiniciar/.bashrc
echo "sudo systemctl start gpsd.socket" >> /home/reiniciar/.bashrc
echo "sudo kismet --log-debug 2>&1 -t \"Kismet_\$(date +'%d-%m-%Y_%H-%M-%S')\" &" >> /home/reiniciar/.bashrc

echo ""

echo "-----------------------------------------------------------------------"
echo "Agregando usuario estado para visualizar el estado de Kismet y gpsd ..."
echo "-----------------------------------------------------------------------"
# Agregar un usuario de nombre estado para visualizar el estado de kismet y gpsd
useradd -m -s /bin/bash estado
usermod --password $(openssl passwd -1 "$PASSWORD") estado
# Agregar el usuario estado al grupo sudo
usermod -aG sudo estado
echo "if pidof kismet > /dev/null" >> /home/estado/.bashrc
echo "then" >> /home/estado/.bashrc
echo "    echo \"Kismet está en ejecución\"" >> /home/estado/.bashrc
echo "else" >> /home/estado/.bashrc
echo "    echo \"Kismet no se encuentra en ejecución\"" >> /home/estado/.bashrc
echo "fi" >> /home/estado/.bashrc
echo "" >> /home/estado/.bashrc
echo "if pidof gpsd > /dev/null" >> /home/estado/.bashrc
echo "then" >> /home/estado/.bashrc
echo "    echo \"gpsd está en ejecución\"" >> /home/estado/.bashrc
echo "else" >> /home/estado/.bashrc
echo "    echo \"gpsd no se encuentra en ejecución\"" >> /home/estado/.bashrc
echo "fi" >> /home/estado/.bashrc
echo "" >> /home/estado/.bashrc

echo ""

echo "----------------------------------------------------------------"
echo "Agregando usuario reboot para reiniciar el sistema operativo ..."
echo "----------------------------------------------------------------"
# Agregar un usuario de nombre reboot para reiniciar el sistema Raspberry Pi OS
useradd -m -s /bin/bash reboot
usermod --password $(openssl passwd -1 "$PASSWORD") reboot
# Agregar el usuario reboot al grupo sudo
usermod -aG sudo reboot
echo "if pidof kismet > /dev/null" >> /home/reboot/.bashrc
echo "then" >> /home/reboot/.bashrc
echo "    sudo pkill kismet" >> /home/reboot/.bashrc
echo "fi" >> /home/reboot/.bashrc
echo "sudo reboot" >> /home/reboot/.bashrc

echo ""

echo "------------------------------------------------------------"
echo "Agregando usuario apagar para bajar el sistema operativo ..."
echo "------------------------------------------------------------"
# Agregar un usuario de nombre apagar para bajar el sistema raspbian
useradd -m -s /bin/bash apagar
usermod --password $(openssl passwd -1 "$PASSWORD") apagar
# Agregar el usuario apagar al grupo sudo
usermod -aG sudo apagar
echo "if pidof kismet > /dev/null" >> /home/apagar/.bashrc
echo "then" >> /home/apagar/.bashrc
echo "    sudo pkill kismet" >> /home/apagar/.bashrc
echo "fi" >> /home/apagar/.bashrc
echo "sudo shutdown now" >> /home/apagar/.bashrc

echo ""

echo "-------------------------------------------------------------------"
echo "Instalando el menú para gestionar el ToolSet Wardriving Tracker ..."
echo "-------------------------------------------------------------------"
# Copiar el script que administra el menú del TST
cp menu_tst.sh /home/tst/menu_tst.sh
chmod ugo+x /home/tst/menu_tst.sh
apt install -y dialog

echo ""

echo "------------------------------------------------------------------------------------------------"
echo "Creando el servicio rc.local para automatizar el inicio de Kismet en el arranque del sistema ..."
echo "------------------------------------------------------------------------------------------------"
# Crear el servicio rc.local para automatizar el inicio de kismet en el sistema
touch /etc/rc.local
echo "#!/bin/bash" >> /etc/rc.local
echo "# rc.local" >> /etc/rc.local
echo "echo \"\$(date +'%d-%m-%Y_%H-%M-%S') - Arrancando rc.local ...\" >> /var/log/rc.local.log" >> /etc/rc.local
echo "bash /home/tst/config_wifi_tst.sh" >> /etc/rc.local
echo "kismet --log-debug 2>&1 -t \"Kismet_\$(date +'%d-%m-%Y_%H-%M-%S')\"" >> /etc/rc.local
echo "exit 0" >> /etc/rc.local
chmod ugo+x /etc/rc.local
cp config_wifi_tst.sh /home/tst/config_wifi_tst.sh
chmod ugo+x /home/tst/config_wifi_tst.sh
# Crear el archivo de unidad para el servicio rc.local
touch /etc/systemd/system/rc-local.service
echo "[Unit]" >> /etc/systemd/system/rc-local.service
echo "Description=/etc/rc.local Compatibility" >> /etc/systemd/system/rc-local.service
echo "ConditionPathExists=/etc/rc.local" >> /etc/systemd/system/rc-local.service
echo "After=network.target" >> /etc/systemd/system/rc-local.service
echo "" >> /etc/systemd/system/rc-local.service
echo "[Service]" >> /etc/systemd/system/rc-local.service
echo "Type=forking" >> /etc/systemd/system/rc-local.service
echo "ExecStart=/etc/rc.local start" >> /etc/systemd/system/rc-local.service
echo "TimeoutSec=0" >> /etc/systemd/system/rc-local.service
echo "StandardOutput=tty" >> /etc/systemd/system/rc-local.service
echo "RemainAfterExit=yes" >> /etc/systemd/system/rc-local.service
echo "" >> /etc/systemd/system/rc-local.service
echo "[Install]" >> /etc/systemd/system/rc-local.service
echo "WantedBy=multi-user.target" >> /etc/systemd/system/rc-local.service
timeout 5 systemctl daemon-reload
timeout 5 systemctl enable rc-local
timeout 5 systemctl start rc-local

echo ""

echo "-------------------------------------------------"
echo "Instalación completada!. Se reiniciará el sistema"
echo "-------------------------------------------------"
echo "Ubicación del archivo de clave: /root/users_passwords.txt"
echo "Clave para usuarios: $PASSWORD"
# Reiniciar el sistema para comenzar a capturar redes Wi-Fi
sleep 5
reboot
