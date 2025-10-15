# Creación de una clave para los usuarios de sistema
LENGTH=16
PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$LENGTH")
echo "$PASSWORD" > /home/tss/users_passwords.txt

# Actualizar la lista de paquetes y los paquetes del sistema
apt update
apt upgrade -y

# Instalación y configuración de gpsd
apt-get remove gpsd
apt-get purge gpsd
apt-get install -y gpsd
systemctl stop gpsd
systemctl stop gpsd.socket
systemctl start gpsd.socket
systemctl enable gpsd.socket
echo "OPTIONS=\"udp://*:9999\"" >> /etc/default/gpsd
sed -i 's/^USBAUTO=".*"/USBAUTO="false"/' /etc/default/gpsd
systemctl restart gpsd.socket

# Instalación y configuración de kismet
# Agregar la llave del repositorio oficial de kismet
wget -O - https://www.kismetwireless.net/repos/kismet-release.gpg.key --quiet | gpg --dearmor | sudo tee /usr/share/keyrings/kismet-archive-keyring.gpg >/dev/null
# Agregar el repositorio de kismet en las fuentes de apt
echo 'deb [signed-by=/usr/share/keyrings/kismet-archive-keyring.gpg] https://www.kismetwireless.net/repos/apt/release/bookworm bookworm main' | sudo tee /etc/apt/sources.list.d/kismet.list >/dev/null
apt-get update
apt-get install -y kismet
touch /etc/ksimet/kismet_site.conf
echo "gps=gpsd:host=localhost,port=2947" >> /etc/ksimet/kismet_site.conf
echo "source=wlan1:channels=\"1,2,3,4,5,6,7,8,9,10,11,12,13\",name=wlan1,type=linuxwifi"
echo "log_prefix=/home/tss/kismet" >> /etc/kismet/kismet_logging.conf
echo "log_template=%p/%n.%li" >> /etc/kismet/kismet_logging.conf
mkdir /home/tss/kismet
chown -R tss:tss /home/tss/kismet

# Agregar un usuario de nombre comenzar para iniciar la captura de paquetes con kismet
useradd -m -s /bin/bash comenzar
echo 'comenzar:$PASSWORD' | chpasswd
# Agregar el usuario comenzar al grupo sudo
usermod -aG sudo comenzar
echo "kismet --log-debug 2>&1 -t \"Kismet_$(date +'%d-%m-%Y_%H-%M-%S')_%i\" &" >> /home/comenzar/.bashrc

# Agregar un usuario de nombre detener para frenar la captura de paquetes con kismet
useradd -m -s /bin/bash detener
echo 'detener:$PASSWORD' | chpasswd
# Agregar el usuario detener al grupo sudo
usermod -aG sudo detener
echo "sudo pkill kismet" >> /home/detener/.bashrc

# Agregar un usuario de nombre reiniciar para bajar e iniciar kismet
useradd -m -s /bin/bash reiniciar
echo 'reiniciar:$PASSWORD' | chpasswd
# Agregar el usuario reiniciar al grupo sudo
usermod -aG sudo reiniciar
echo "echo \"Reiniciando kismet ...\"" >> /home/reiniciar/.bashrc
echo "sudo pkill kismet" >> /home/reiniciar/.bashrc
echo "sudo systemctl stop gpsd.socket" >> /home/reiniciar/.bashrc
echo "sleep 10" >> /home/reiniciar/.bashrc
echo "kismet --log-debug 2>&1 -t \"Kismet_$(date +'%d-%m-%Y_%H-%M-%S')_%i\" &"
echo "sudo systemctl start gpsd.socket" >> /home/reiniciar/.bashrc

# Agregar un usuario de nombre estado para visualizar el estado de kismet y gpsd
useradd -m -s /bin/bash estado
echo 'estado:$PASSWORD' | chpasswd
# Agregar el usuario estado al grupo sudo
usermod -aG sudo estado
echo "if pidof ksimet > /dev/null" >> /home/estado/.bashrc
echo "then" >> /home/estado/.bashrc
echo "    echo \"kismet está en ejecución\"" >> /home/estado/.bashrc
echo "else" >> /home/estado/.bashrc
echo "    echo \"kismet no se encuentra en ejecución\"" >> /home/estado/.bashrc
echo "fi" >> /home/estado/.bashrc
echo "\n" >> /home/estado/.bashrc
echo "if pidof gpsd > /dev/null" >> /home/estado/.bashrc
echo "then" >> /home/estado/.bashrc
echo "    echo \"gpsd está en ejecución\"" >> /home/estado/.bashrc
echo "else" >> /home/estado/.bashrc
echo "    echo \"gpsd no se encuentra en ejecuión\"" >> /home/estado/.bashrc
echo "fi" >> /home/estado/.bashrc
echo "\n" >> /home/estado/.bashrc

# Agregar un usuario de nombre apagar para bajar el sistema raspbian
useradd -m -s /bin/bash apagar
echo 'apagar:$PASSWORD' | chpasswd
# Agregar el usuario apagar al grupo sudo
usermod -aG sudo apagar
echo "if pidof kismet > /dev/null" >> /home/apagar/.bashrc
echo "then" >> /home/apagar/.bashrc
echo "    sudo pkill kismet" >> /home/apagar/.bashrc
echo "fi"
echo "sudo shutdown now" >> /home/apagar/.bashrc

# Crear el servicio rc.local para automatizar el inicio de kismet en el sistema
touch /etc/rc.local
echo "#!/bin/bash" >> /etc/rc.local
echo "# rc.local" >> /etc/rc.local
echo "echo \"$(date +'%d-%m-%Y_%H-%M-%S') - Arrancando rc.local ...\" >> /var/log/rc.local.log" >> /etc/rc.local
echo "kismet --log-debug 2>&1 -t \"Kismet_$(date +'%d-%m-%Y_%H-%M-%S')_%ii\" &i" >> /etc/rc.local
echo "exit 0" >> /etc/rc.local
chmod ugo+x /etc/rc.local
# Crear el archivo de unidad para el servicio rc.local
touch /etc/systemd/system/rc.local.service
echo "[Unit]" >> /etc/systemd/system/rc-local.service
echo "Description=/etc/rc.local Compatibility" >> /etc/systemd/system/rc-local.service
echo "ConditionPathExists=/etc/rc.local" >> /etc/systemd/system/rc-local.service
echo "After=network.target" >> /etc/systemd/system/rc-local.service
echo "\n" >> /etc/systemd/system/rc-local.service
echo "[Service]" >> /etc/systemd/system/rc-local.service
echo "Type=forking" >> /etc/systemd/system/rc-local.service
echo "ExecStart=/etc/rc.local start" >> /etc/systemd/system/rc-local.service
echo "TimeoutSec=0" >> /etc/systemd/system/rc-local.service
echo "StandardOutput=tty" >> /etc/systemd/system/rc-local.service
echo "RemainAfterExit=yes" >> /etc/systemd/system/rc-local.service
echo "\n" >> /etc/systemd/system/rc-local.service
echo "[Install]" >> /etc/systemd/system/rc-local.service
echo "WantedBy=multi-user.target" >> /etc/systemd/system/rc-local.service
systemctl daemon-reload
systemctl enable rc-local
systemctl start rc-local

# Reiniciar el sistema para comenzar a capturar redes Wi-Fi
reboot

