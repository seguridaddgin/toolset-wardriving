package com.example.gpsforwaredng;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import android.Manifest;
import android.content.pm.PackageManager;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Bundle;
import android.text.TextUtils;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;
import android.os.Bundle;
import android.view.WindowManager;
import androidx.appcompat.app.AppCompatActivity;
import android.widget.CheckBox;
import android.widget.CompoundButton;

public class MainActivity extends AppCompatActivity {

    private static final int LOCATION_PERMISSION_REQUEST_CODE = 1;
    private LocationManager locationManager;
    private LocationListener locationListener;
    private boolean isStreaming = false;

    // Crear varaible para editar el texto de la dirección IP del servidor GPSd
    private EditText editTextIP;
    // Crear variable para editar el texto del puerto TCP/IP del servidor GPSd
    private EditText editTextPort;

    // Crear una variable que contenga una expresión regular para validar direcciones IPs versión 4
    private static final String IPV4_REGEX =
            "^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$";
    // Crear una variable que contenga una expresión regular para validar direcciones IPs versión 6
    private static final String IPV6_REGEX =
            "^([0-9a-fA-F]{1,4}:){7}([0-9a-fA-F]{1,4}|:)$";

    private static final String CHECKBOX_STATE_KEY = "checkbox_state";

    private CheckBox keepCheckBox;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        locationManager = (LocationManager) getSystemService(LOCATION_SERVICE);

        // Crear varaible del botón Iniciar el flujo de datos del GPS
        Button startButton = findViewById(R.id.startButton);
        // Crear variable del botón Detener el flujo de datos del GPS
        Button stopButton = findViewById(R.id.stopButton);

        // Obtener la referencia al EditText
        editTextIP = findViewById(R.id.editTextIP);

        // Establecer un valor por defecto para la dirección IP del servidor GPSd
        editTextIP.setText(String.format("%s","192.168.49.121"));

        // Obtener la refencia al EditText
        editTextPort = findViewById(R.id.editTextPort);

        // Establecer un valor por defecto para el puerto del servidor GPSd
        editTextPort.setText(String.format("%s","9999"));

        // Obtener la referencia al CheckBox
        keepCheckBox = findViewById(R.id.keepCheckBox);

        locationListener = new LocationListener() {
            @Override
            public void onLocationChanged(@NonNull Location location) {
                if (isStreaming) {
                    // Guardar la latitud
                    double latitude = location.getLatitude();
                    // Guardar la longitud
                    double longitude = location.getLongitude();
                    // Guardar la altitud
                    double altitude = location.getAltitude();
                    // Crear un hilo y llamar el método para enviar los datos del GPS sobre el protocolo UDP
                    new Thread(() -> sendDataOverUDP(latitude, longitude, altitude)).start();
                }
            }

            @Override
            public void onStatusChanged(String provider, int status, Bundle extras) {}

            @Override
            public void onProviderEnabled(@NonNull String provider) {}

            @Override
            public void onProviderDisabled(@NonNull String provider) {}
        };

        // Configurar el listener para la pérdida de foco de la dirección IP
        editTextIP.setOnFocusChangeListener(new View.OnFocusChangeListener() {
            @Override
            public void onFocusChange(View v, boolean hasFocus) {
                if (!hasFocus) {
                    validarDireccionIP();
                }
            }
        });

        // Configurar el listener para la pérdida de foco del puerto
        editTextPort.setOnFocusChangeListener(new View.OnFocusChangeListener() {
            @Override
            public void onFocusChange(View v, boolean hasFocus) {
                if (!hasFocus) {
                    validarPuerto();
                }
            }
        });

        startButton.setOnClickListener(view -> {
            if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED && checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION}, LOCATION_PERMISSION_REQUEST_CODE);
                return;
            }
            if (esValidaIP(editTextIP.getText().toString().trim()) && esValidoPuerto(editTextPort.getText().toString().trim())) {
                startStreaming();
            } else {
                if (!esValidaIP(editTextIP.getText().toString().trim())) {
                    validarDireccionIP();
                } else if (!esValidoPuerto(editTextPort.getText().toString().trim())) {
                    validarPuerto();;
                }

            }
        });

        stopButton.setOnClickListener(view -> stopStreaming());

        // Restaura el estado del CheckBox si hay un estado guardado
        if (savedInstanceState != null) {
            boolean isChecked = savedInstanceState.getBoolean(CHECKBOX_STATE_KEY, false);
            keepCheckBox.setChecked(isChecked);
        }

        // Manejar el cambio en el estado del CheckBox
        keepCheckBox.setOnCheckedChangeListener(new CompoundButton.OnCheckedChangeListener() {
            @Override
            public void onCheckedChanged(CompoundButton buttonView, boolean isChecked) {
                // Realiza acciones basadas en el nuevo estado del CheckBox

                // Mantener la pantalla encendida mientras esta actividad esté visible
                getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            }
        });

    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);

        // Guarda el estado del CheckBox en el Bundle
        outState.putBoolean(CHECKBOX_STATE_KEY, keepCheckBox.isChecked());
    }

    // rear método para validar el formato del texto de la dirección IP y notificar al usuario final
    private void validarDireccionIP() {
        String input = editTextIP.getText().toString().trim();

        if (TextUtils.isEmpty(input)) {
            // Notificar de que el campo se encuentra vacío
            Toast.makeText(this, "El campo no puede estar vacío", Toast.LENGTH_SHORT).show();
        } else if (!esValidaIP(input)) {
            // Notificar que la dirección IP no tiene un formato válido
            Toast.makeText(this, "Dirección IP no válida", Toast.LENGTH_SHORT).show();
        } else {
            // Notificar que la dirección IP es válida
            Toast.makeText(this, "Dirección IP válida", Toast.LENGTH_SHORT).show();
        }
    }

    // Crear método para validar el formato del texto del puerto y notificar al usuario final
    private void validarPuerto() {
        String input = editTextPort.getText().toString().trim();

        if (TextUtils.isEmpty(input)) {
            Toast.makeText(this, "El campo no puede estar vacío", Toast.LENGTH_SHORT).show();
        } else {
            try {
                Integer.parseInt(input);
                Toast.makeText(this, "Número entero válido para un puerto", Toast.LENGTH_SHORT).show();
            } catch (NumberFormatException e) {
                Toast.makeText(this, "Número entero no válido para un puerto", Toast.LENGTH_SHORT).show();
            }
        }
    }

    // Crear un método para validar el formato de la dirección IP en versión 4 y 6
    private boolean esValidaIP(String ip) {
        return ip.matches(IPV4_REGEX) || ip.matches(IPV6_REGEX);
    }

    // Crear un método para validar el formato del puerto
    private boolean esValidoPuerto(String puerto) {
        try {
            Integer.parseInt(puerto);
            return true;
        } catch (NumberFormatException e) {
            return false;
        }
    }

    // Crear método para iniciar el flujo de datos
    private void startStreaming() {
        isStreaming = true;
        try {
            locationManager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 5000, 0, locationListener);
            Toast.makeText(this, "Iniciando flujo de datos del GPS", Toast.LENGTH_SHORT).show();
        } catch (SecurityException e) {
            e.printStackTrace();
        }
    }

    // Crear método para detener el flujo de datos
    private void stopStreaming() {
        isStreaming = false;
        locationManager.removeUpdates(locationListener);
        Toast.makeText(this, "Deteniendo flujo de datos del GPS", Toast.LENGTH_SHORT).show();
    }

    // Método para calcular el checksum del formato NMEA 0183
    private static int calcularChecksum(String sentence) {
        // Excluir el '$' al inicio y '*' y el checksum al final
        String data = sentence.substring(1, sentence.indexOf('*'));

        // Iniciar el checksum
        int checksum = 0;

        // XOR todos los caracteres entre sí
        for (int i = 0; i < data.length(); i++) {
            checksum ^= data.charAt(i);
        }

        return checksum;
    }

    // Crear método para enviar datos sobre el protocolo UDP
   private void sendDataOverUDP(double latitude, double longitude, double altitude) {
        try {
            // Crear variable para mostrar el nombre del programa y la versión
            TextView textView;
            // Crear variable para mostrar el flujo de datos (en formato NMEA) a enviar por el protocolo UDP
            TextView textViewNMEA;

            // Obtener la referencia al EditText
            editTextIP = findViewById(R.id.editTextIP);

            // Obtener el texto ingresado en el EditText
            String direccionIP = editTextIP.getText().toString();

            // Obtener la refencia al EditText
            editTextPort = findViewById(R.id.editTextPort);

            // Obtener el texto ingresado en el EditText
            String puerto = editTextPort.getText().toString();

            // Crear un socket para enviar datagramas
            DatagramSocket socket = new DatagramSocket();

            // Crear una variable para almacenar la dirección IP del servidor GPSd
            // Reemplaza con la dirección IP de tu servidor
            InetAddress serverAddress = InetAddress.getByName(direccionIP);

            // Crear una variable para almacenar el puerto del servidor GPSd
            // Reemplaza con el puerto que uses en tu servidor
            int port = Integer.parseInt(puerto);

            // Declarar e inicializar la cadena de texto que almacena el formato NMEA 01083 con un mensaje GPGGA
            String nmeaSentence = String.format("$GPGGA,%s,%02d%07.4f,%s,%03d%07.4f,%s,1,08,0.9,%4.1f,M,46.9,M,,%s", getCurrentTimeUTC(), (int) Math.abs(latitude), (Math.abs(latitude) - (int) Math.abs(latitude)) * 60, latitude >= 0 ? "N" : "S", (int) Math.abs(longitude), (Math.abs(longitude) - (int) Math.abs(longitude)) * 60, longitude >= 0 ? "E" : "W", altitude,"*");

            // Calcular el checksum
            int checksum = calcularChecksum(nmeaSentence);
            // Formatear el checksum a hexadecimal, es importante agregar \r\n para que el servidor gpsd pueda leer e interpretar los datos enviados
            String checksumHex = String.format("%02X\r\n", checksum);

            // Completar/concatenar el mensaje GPGGA con el checksum en hexadecimal
            nmeaSentence = nmeaSentence + checksumHex;

            // Guardar en un buffer la sentencia NMEA
            byte[] buffer = nmeaSentence.getBytes();

            // Crear una variable que almacene el paquete a enviar
            DatagramPacket packet = new DatagramPacket(buffer, buffer.length, serverAddress, port);

            // Enviar el paquete
            socket.send(packet);

            // Cerrar el socket
            socket.close();

            // Obtener referencia al TextView desde el layout
            textViewNMEA = findViewById(R.id.textViewNMEA);

            // Establecer la cadena NMEA en el TextoView
            textViewNMEA.setText(String.format("%s", nmeaSentence));

        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    // Formatear la fecha para agregar a la cadena que almacena el texto con el formato NMEA 0183
    private String getCurrentTimeUTC() {
        SimpleDateFormat sdf = new SimpleDateFormat("HHmmss", Locale.US);
        sdf.setTimeZone(TimeZone.getTimeZone("UTC"));
        return sdf.format(new Date());
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();

        // Eliminar la bandera cuando la actividad se destruya
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    }

}