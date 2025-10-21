#!/bin/bash

# Listado de direcciones MAC a las que les queremos asignar un nombre específico
declare -A mac_to_name
mac_to_name["14:cc:20:26:af:4e"]="wifi24"
mac_to_name["ec:75:0c:42:b1:6b"]="wifi58"
mac_to_name["98:ba:5f:a6:ab:6d"]="wifi58"
mac_to_name["18:a6:f7:0d:d7:72"]="wificonnect"
mac_to_name["30:a9:de:df:e2:e6"]="wificonnect"

# Obtener la lista de interfaces wlanX
for interface in $(ip link show | grep -oP 'wlan\d' | sort | uniq); do
    # Obtener la dirección MAC de la interfaz
    mac_address=$(cat /sys/class/net/$interface/address)
    
    # Verificar si la dirección MAC está en nuestra lista
    if [[ -n "${mac_to_name[$mac_address]}" ]]; then
        new_name="${mac_to_name[$mac_address]}"
        
        # Renombrar la interfaz
        echo "Renombrando $interface ($mac_address) a $new_name"
        sudo ip link set $interface down
        sudo ip link set $interface name $new_name
        sudo ip link set $new_name up
        
        echo "Interfaz $interface renombrada a $new_name"
        
    else
        echo "La dirección MAC $mac_address no tiene un nombre asignado."
    fi
done

