#!/bin/bash
echo "-------------------------------------------------------------"
echo "Instalando el ToolSet Wardriving Scout en Raspberry Pi OS ..."
echo "-------------------------------------------------------------"

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

echo "----------------------------------------------------------------------"
echo "Agregando usuario tss para la gestión del ToolSet Wardriving Scout ..."
echo "----------------------------------------------------------------------"
# Agregar un usuario de nombre tss para iniciar la gestión del TSS
useradd -m -s /bin/bash tss
usermod --password $(openssl passwd -1 "$PASSWORD") tss
# Agregar el usuario tss al grupo sudo y adm
usermod -aG sudo tss
usermod -aG adm tss
echo "sudo bash menu_tss.sh" >> /home/tss/.bashrc

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
sed -i 's|^[[:space:]]*log_prefix=\./|log_prefix=/home/tss/kismet|' /etc/kismet/kismet_logging.conf
sed -i 's|log_template=%p/%n-%D-%t-%i\.%l|log_template=%p/%n\.%l|' /etc/kismet/kismet_logging.conf
mkdir /home/tss/kismet
chown -R tss:tss /home/tss/kismet

echo ""

echo "------------------------------------------------------------------"
echo "Agregando usuario comenzar para iniciar la captura de paquetes ..."
echo "------------------------------------------------------------------"
# Agregar un usuario de nombre comenzar para iniciar la captura de paquetes con kismet
useradd -m -s /bin/bash comenzar
usermod --password $(openssl passwd -1 "$PASSWORD") comenzar
# Agregar el usuario comenzar al grupo sudo y adm
usermod -aG sudo comenzar
usermod -aG adm comenzar
echo "sudo kismet --log-debug 2>&1 -t \"Kismet_\$(date +'%d-%m-%Y_%H-%M-%S')\" &" >> /home/comenzar/.bashrc

echo ""

echo "----------------------------------------------------------------"
echo "Agregando usuario detener para frenar la captura de paquetes ..."
echo "----------------------------------------------------------------"
# Agregar un usuario de nombre detener para frenar la captura de paquetes con kismet
useradd -m -s /bin/bash detener
usermod --password $(openssl passwd -1 "$PASSWORD") detener
# Agregar el usuario detener al grupo sudo y adm
usermod -aG sudo detener
usermod -aG adm detener
echo "sudo pkill kismet" >> /home/detener/.bashrc

echo ""

echo "---------------------------------------------------------------------------------------"
echo "Agregando usuario reiniciar para detener y volver a comenzar la captura de paquetes ..."
echo "---------------------------------------------------------------------------------------"
# Agregar un usuario de nombre reiniciar para bajar e iniciar kismet
useradd -m -s /bin/bash reiniciar
usermod --password $(openssl passwd -1 "$PASSWORD") reiniciar
# Agregar el usuario reiniciar al grupo sudo y adm
usermod -aG sudo reiniciar
usermod -aG adm reiniciar
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
# Agregar el usuario estado al grupo sudo y adm
usermod -aG sudo estado
usermod -aG adm estado
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
# Agregar el usuario reboot al grupo sudo y adm
usermod -aG sudo reboot
usermod -aG adm reboot
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
# Agregar el usuario apagar al grupo sudo y adm
usermod -aG sudo apagar
usermod -aG adm apagar
echo "if pidof kismet > /dev/null" >> /home/apagar/.bashrc
echo "then" >> /home/apagar/.bashrc
echo "    sudo pkill kismet" >> /home/apagar/.bashrc
echo "fi" >> /home/apagar/.bashrc
echo "sudo shutdown now" >> /home/apagar/.bashrc

echo ""

echo "-----------------------------------------------------------------"
echo "Instalando el menú para gestionar el ToolSet Wardriving Scout ..."
echo "-----------------------------------------------------------------"
# Copiar el script que administra el menú del TSS
cp menu_tss.sh /home/tss/menu_tss.sh
chmod ugo+x /home/tss/menu_tss.sh
apt install -y dialog

echo ""

echo "------------------------------------------------------------------------------------------------"
echo "Creando el servicio rc.local para automatizar el inicio de Kismet en el arranque del sistema ..."
echo "------------------------------------------------------------------------------------------------"
# Crear el servicio rc.local para automatizar el inicio de kismet en el sistema
touch /etc/rc.local
echo "#!/bin/sh -e" >> /etc/rc.local
echo "# rc.local" >> /etc/rc.local
echo "echo \"\$(date +'%d-%m-%Y_%H-%M-%S') - Arrancando rc.local ...\" >> /var/log/rc.local.log" >> /etc/rc.local
echo "bash /home/tss/config_wifi_tss.sh" >> /etc/rc.local
echo "kismet --log-debug 2>&1 -t \"Kismet_\$(date +'%d-%m-%Y_%H-%M-%S')\" &" >> /etc/rc.local
echo "exit 0" >> /etc/rc.local
chmod ugo+x /etc/rc.local
cp config_wifi_tss.sh /home/tss/config_wifi_tss.sh
chmod ugo+x /home/tss/config_wifi_tss.sh
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

echo "----------------------------------------------------------------------------------------------------"
echo "Ajustando el servicio ssh para tener una mejor seguridad en el acceso al sistema de forma remota ..."
echo "----------------------------------------------------------------------------------------------------"
# Modificar la configuración del servicio ssh para endurecer la seguridad del servicio

# Agregar una línea de configuración para No permitir login directo de root
sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
# Agregar una linea de configuración para aplicar una conexión rápida
sed -i 's/^[#]*LoginGraceTime.*/LoginGraceTime 30/' /etc/ssh/sshd_config
# Agregar una línea de configuración para aplicar un límite en cantidad de intentos
sed -i 's/^[#]*MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
# Agregar líneas de configuración para desactivar reenvíos innecesarios
sed -i 's/^[#]*X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
sed -i 's/^[#]*PermitTunnel.*/PermitTunnel no/' /etc/ssh/sshd_config
sed -i 's/^[#]*AllowTcpForwarding.*/AllowTcpForwarding no/' /etc/ssh/sshd_config

echo ""

echo "-------------------------------------------------"
echo "Instalación completada!. Se reiniciará el sistema"
echo "-------------------------------------------------"
echo "Ubicación del archivo de clave: /root/users_passwords.txt"
echo "Clave para usuarios: $PASSWORD"
# Reiniciar el sistema para comenzar a capturar redes Wi-Fi
sleep 5
reboot
