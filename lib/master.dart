import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:caldensmart/firebase_options.dart';
import 'package:caldensmart/secret.dart';
import 'package:caldensmart/widget/widget_handler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:msgpack_dart/msgpack_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upgrader/upgrader.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'aws/dynamo/dynamo.dart';
import 'aws/mqtt/mqtt.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'Global/stored_data.dart';
import 'package:caldensmart/logger.dart';

//! VARIABLES !\\

//*-Informacion crucial app-*\\
late String appVersionNumber;
//ACORDATE: 0 = Caldén Smart, 1 = Silema, 2 = Millenium
const int app = 0;
//*-Informacion crucial app-\*\

//*-Base de datos interna app-*\\
Map<String, Map<String, dynamic>> globalDATA = {};
//*-Base de datos interna app-*\\

//*-Colores-*\\
const Color color0 = Color(0xFFFFFFFF);
const Color color1 = Color(0xFF000000);
const Color color2 = Color(0xFFFF3D47);
const Color color3 = Color(0xFFED3724);
const Color color4 = Color(0xFF97292c);
//*-Colores-*\\

//*-Datos de la app-*\\
late bool android;
late String appName;
//*-Datos de la app-*\\

//*-Estado de app-*\\
const bool xProfileMode = bool.fromEnvironment('dart.vm.profile');
const bool xReleaseMode = bool.fromEnvironment('dart.vm.product');
const bool xDebugMode = !xProfileMode && !xReleaseMode;
// const bool xDebugMode = true;
//*-Estado de app-*\\

//*-Key de la app (uso de navegación y contextos)-*\\
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
//*-Key de la app (uso de navegación y contextos)-*\\

//*-Datos del dispositivo al que te conectaste-*\\
String deviceName = '';
String softwareVersion = '';
String hardwareVersion = '';
late bool factoryMode;
String owner = '';
bool deviceOwner = false;
int lastUser = 0;
bool userConnected = false;
bool connectionFlag = false;
bool turnOn = false;
double distOnValue = 3000;
double distOffValue = 100;
//*-Datos del dispositivo al que te conectaste-*\\

//*-Relacionado al wifi-*\\
List<WiFiAccessPoint> _wifiNetworksList = [];
String? _currentlySelectedSSID;
Map<String, String?> _wifiPasswordsMap = {};
FocusNode wifiPassNode = FocusNode();
bool _scanInProgress = false;
int? _expandedIndex;
bool wifiError = false;
String errorMessage = '';
String errorSintax = '';
String nameOfWifi = '';
bool isWifiConnected = false;
bool wifilogoConnected = false;
bool atemp = false;
String textState = '';
bool werror = false;
MaterialColor statusColor = Colors.grey;
int signalPower = 0;
String? qrResult;
bool wifiUnstable = false;
//*-Relacionado al wifi-*\\

//*-Relacionado al ble-*\\
BluetoothManager bluetoothManager = BluetoothManager();
List<int> infoValues = [];
List<int> toolsValues = [];
List<int> varsValues = [];
bool bluetoothOn = true;
List<String> keywords = [];
Map<String, DateTime> lastSeenDevices = {};

// Global Connection Manager
StreamSubscription<BluetoothConnectionState>? globalConnectionSubscription;
//*-Relacionado al ble-*\\

//*-Topics mqtt-*\\
List<String> topicsToSub = [];
//*-Topics mqtt-*\\

//*-Equipos registrados-*\\
List<String> previusConnections = [];
List<String> adminDevices = [];
List<String> alexaDevices = [];
List<Map<String, String>> savedOrder = [];

//*-Marcador para listas vacias intencionales-*\\
const String intentionallyEmptyMarker = '__INTENTIONALLY_EMPTY__';

//*-Control de estado de carga-*\\
enum DeviceLoadState {
  unknown,
  loading,
  newUser,
  existingUserLoaded,
  loadError
}

DeviceLoadState deviceLoadState = DeviceLoadState.unknown;
DateTime? lastSuccessfulLoad;
int loadRetryCount = 0;
const int maxRetryAttempts = 3;
List<MapEntry<String, String>> todosLosDispositivos = [];
//*-Equipos registrados-*\\

//*-Nicknames-*\\
late String nickname;
Map<String, String> nicknamesMap = {};
//*-Nicknames-*\\

//*-Folders-*\\
Map<String, List<String>> folders = {};
//*-Folders-*\\

//*-Notifications-*\\
Map<String, List<bool>> notificationMap = {};
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
Map<String, String> soundOfNotification = {};
int? selectedSoundDomotica;
int? selectedSoundDetector;
int? selectedSoundTermometro;

// StreamController para notificar cuando las cadenas terminan
StreamController<String> cadenaCompletedController =
    StreamController<String>.broadcast();

// StreamController para notificar cuando los riegos terminan
StreamController<String> riegoCompletedController =
    StreamController<String>.broadcast();
//*-Notifications-*\\

//*-Relacionado al Alquiler temporario (Airbnb)-*\\
bool payAT = false;
bool activatedAT = false;
int vencimientoAT = 0;
bool tenant = false;
//*-Relacionado al Alquiler temporario (Airbnb)-*\\

//*-Relacionado al Administrador secundario-*\\
bool payAdmSec = false;
bool secondaryAdmin = false;
int vencimientoAdmSec = 0;
//*-Relacionado al Administrador secundario-*\\

//*-Monitoreo Localizacion y Bluetooth*-\\
Timer? locationTimer;
Timer? bluetoothTimer;
bool bleFlag = false;
//*-Monitoreo Localizacion y Bluetooth*-\\

//*-Cognito user flow-*\\
String currentUserEmail = '';
//*-Cognito user flow-*\\

//*-Background functions-*\\
Timer? backTimerDS;
Timer? backTimerCH;
Timer? _mqttReconnectTimer; // timer de reconexión MQTT del servicio iOS
Timer? _mqttReconnectTimerBg; // timer de reconexión MQTT del servicio Android
//*-Background functions-*\\

//*-Imagenes Scan-*\\
Map<String, String> deviceImages = {};
Map<String, bool> deviceImageStyles = {};
//*-Imagenes Scan-*\\

//*-CurvedNavigationBar-*\\
typedef LetIndexPage = bool Function(int value);
//*-CurvedNavigationBar-*\\

//*-AnimSearchBar*-\\
int toggle = 0;
String textFieldValue = '';
//*-AnimSearchBar*-\\

//*-Escenas-*\\
List<String> registeredScenes = [];
List<Map<String, dynamic>> timeScenes = [];

Widget Function()? currentBuilder;
TimeOfDay? selectedTime;

int? selectedAction;
Duration? delay;
String? selectedWeatherCondition;

bool showCard = false;
bool showHorarioStep = false;
bool showHorarioStep2 = false;
bool showGrupoStep = false;
bool showCascadaStep = false;
bool showCascadaStep2 = false;
bool showClimaStep = false;
bool showClimaStep2 = false;

bool showDelay = false;

Map<String, bool> deviceActions = {};
Map<String, String> deviceUnits = {};

List<String> selectedDays = [];
List<String> deviceGroup = [];
List<String> filterDevices = [];
Map<String, Duration> deviceDelays = {};

final List<String> weatherConditions = [
  'Lluvia',
  'Sol',
  'Viento fuerte',
  'Viento moderado',
  'Viento suave',
  'Sin viento',
  'Nieve',
  'Neblina',
  'Calor extremo',
  'Frío extremo',
];

final selectWeekDaysKey = GlobalKey<SelectWeekDaysState>();
//*-Escenas-*\\

//*-Omnipresencia-*\\
List<String> devicesToTrack = [];
Map<String, bool> msgFlag = {};
Timer? bleScanTimer;
late bool tracking;
//*-Omnipresencia-*\\

//*-Notificación Desconexión-*\\
bool discNotfActivated = false;
Map<String, int> configNotiDsc = {};
//*-Notificación Desconexión-*\\

//*- Roller -*\\
bool distanceControlActive = false;
int actualPositionGrades = 0;
int actualPosition = 0;
bool rollerMoving = false;
int workingPosition = 0;
String rollerlength = '';
String rollerPolarity = '';
bool awsInit = false;
String rollerRPM = '';
String rollerSavedLength = '';
bool isCalibrated = false;
//*- Roller -*\\

//*-Detectores-*\\
List<int> workValues = [];
int lastCO = 0;
int lastCH4 = 0;
int ppmCO = 0;
int ppmCH4 = 0;
int picoMaxppmCO = 0;
int picoMaxppmCH4 = 0;
int promedioppmCO = 0;
int promedioppmCH4 = 0;
int daysToExpire = 0;
double brightnessLevel = 50.0;
bool alert = false;
bool onlineInCloud = false;
//*-Detectores-*\\

//*-Calefactores-*\\
bool alreadySubTools = false;
bool trueStatus = false;
late bool nightMode;
String actualTemp = '';
double tempValue = 10.0;
//*-Calefactores-*\\

//*-Domótica-*\\
List<int> ioValues = [];
List<String> tipo = [];
List<String> estado = [];
List<bool> alertIO = [];
List<String> common = [];
//*-Domótica-*\\

//*-Relé-*\\
bool isNC = false;
bool isAgreeChecked = false;
//*-Relé-*\\

//*-Acceso rápido BLE-*\\
List<String> quickAccess = [];
bool quickAccesActivated = false;
bool quickAction = false;
Map<String, String> pinQuickAccess = {};
//*-Acceso rápido BLE-*\\

//*-Fetch data from DynamoDB GENERALDATA-*\\
Map<String, dynamic> dbData = {};
//*-Fetch data from DynamoDB GENERALDATA-*\\

//*-Device update-*\\
String? lastSV;
bool shouldUpdateDevice = false;
//*-Device update-*\\

//*- Altura de la bottomAppBar -*\\
double bottomBarHeight = kBottomNavigationBarHeight;
//*- Altura de la bottomAppBar -*\\

//*- Última pagina visitada -*\\
int? lastPage;
//*- Última pagina visitada -*\\

//*- Tutorial -*\\
enum ShapeFocus { oval, square, roundedSquare }

enum ContentPosition { above, below }

bool tutorial = true;
//*- Tutorial -*\\

//*- Guía de usuario -*\\
Map<String, GlobalKey> keys = {
  //ManagerScreen
  'managerScreen:titulo': GlobalKey(),
  'managerScreen:reclamar': GlobalKey(),
  'managerScreen:agregarAdmin': GlobalKey(),
  'managerScreen:verAdmin': GlobalKey(),
  'managerScreen:alquiler': GlobalKey(),
  'managerScreen:accesoRapido': GlobalKey(),
  'managerScreen:historialAdmin': GlobalKey(),
  'managerScreen:horariosAdmin': GlobalKey(),
  'managerScreen:wifiAdmin': GlobalKey(),
  'managerScreen:desconexionNotificacion': GlobalKey(),
  'managerScreen:ejemploNoti': GlobalKey(),
  'managerScreen:led': GlobalKey(),
  'managerScreen:imagen': GlobalKey(),
  'managerScreen:bomba': GlobalKey(),
  //Calefactores
  'calefactores:estado': GlobalKey(),
  'calefactores:titulo': GlobalKey(),
  'calefactores:wifi': GlobalKey(),
  'calefactores:servidor': GlobalKey(),
  'calefactores:boton': GlobalKey(),
  'calefactores:chispero': GlobalKey(),
  'calefactores:temperatura': GlobalKey(),
  'calefactores:corte': GlobalKey(),
  'calefactores:controlDistancia': GlobalKey(),
  'calefactores:controlBoton': GlobalKey(),
  'calefactores:consumo': GlobalKey(),
  'calefactores:valor': GlobalKey(),
  'calefactores:consumoManual': GlobalKey(),
  'calefactores:calcular': GlobalKey(),
  'calefactores:mes': GlobalKey(),
  //Detectores
  'detectores:estado': GlobalKey(),
  'detectores:titulo': GlobalKey(),
  'detectores:wifi': GlobalKey(),
  'detectores:servidor': GlobalKey(),
  'detectores:airePuro': GlobalKey(),
  'detectores:ejemploNoti': GlobalKey(),
  'detectores:gas1': GlobalKey(),
  'detectores:co1': GlobalKey(),
  'detectores:gas2': GlobalKey(),
  'detectores:co2': GlobalKey(),
  'detectores:gas3': GlobalKey(),
  'detectores:co3': GlobalKey(),
  'detectores:brillo': GlobalKey(),
  'detectores:barraBrillo': GlobalKey(),
  'detectores:configuraciones': GlobalKey(),
  'detectores:imagen': GlobalKey(),
  'detectores:desconexion': GlobalKey(),
  //Domotica
  'domotica:estado': GlobalKey(),
  'domotica:activarNoti': GlobalKey(),
  'domotica:ejemploAlerta': GlobalKey(),
  'domotica:titulo': GlobalKey(),
  'domotica:wifi': GlobalKey(),
  'domotica:modoPines': GlobalKey(),
  'domotica:servidor': GlobalKey(),
  //Heladera
  'heladera:estado': GlobalKey(),
  'heladera:titulo': GlobalKey(),
  'heladera:wifi': GlobalKey(),
  'heladera:servidor': GlobalKey(),
  'heladera:boton': GlobalKey(),
  'heladera:temperatura': GlobalKey(),
  'heladera:corte': GlobalKey(),
  'heladera:controlDistancia': GlobalKey(),
  'heladera:controlBoton': GlobalKey(),
  'heladera:consumo': GlobalKey(),
  'heladera:valor': GlobalKey(),
  'heladera:consumoManual': GlobalKey(),
  'heladera:calcular': GlobalKey(),
  'heladera:mes': GlobalKey(),
  //Millenium
  'millenium:estado': GlobalKey(),
  'millenium:titulo': GlobalKey(),
  'millenium:wifi': GlobalKey(),
  'millenium:servidor': GlobalKey(),
  'millenium:boton': GlobalKey(),
  'millenium:temperatura': GlobalKey(),
  'millenium:corte': GlobalKey(),
  'millenium:consumo': GlobalKey(),
  'millenium:valor': GlobalKey(),
  'millenium:consumoManual': GlobalKey(),
  'millenium:calcular': GlobalKey(),
  'millenium:mes': GlobalKey(),
  //Modulo
  'modulo:estado': GlobalKey(),
  'modulo:activarNoti': GlobalKey(),
  'modulo:ejemploAlerta': GlobalKey(),
  'modulo:titulo': GlobalKey(),
  'modulo:wifi': GlobalKey(),
  'modulo:modoPines': GlobalKey(),
  'modulo:servidor': GlobalKey(),
  //Rele
  'rele:estado': GlobalKey(),
  'rele:boton': GlobalKey(),
  'rele:titulo': GlobalKey(),
  'rele:wifi': GlobalKey(),
  'rele:servidor': GlobalKey(),
  'rele:controlDistancia': GlobalKey(),
  'rele:controlBoton': GlobalKey(),
  'rele:modoPines': GlobalKey(),
  //Rele1i1o
  'rele1i1o:estado': GlobalKey(),
  'rele1i1o:activarNoti': GlobalKey(),
  'rele1i1o:ejemploAlerta': GlobalKey(),
  'rele1i1o:titulo': GlobalKey(),
  'rele1i1o:wifi': GlobalKey(),
  'rele1i1o:servidor': GlobalKey(),
  'rele1i1o:controlDistancia': GlobalKey(),
  'rele1i1o:controlBoton': GlobalKey(),
  'rele1i1o:modoPines': GlobalKey(),
  //Termometro
  'termometro:estado': GlobalKey(),
  'termometro:temperaturaActual': GlobalKey(),
  'termometro:alertaMaxima': GlobalKey(),
  'termometro:alertaMinima': GlobalKey(),
  'termometro:configAlertas': GlobalKey(),
  'termometro:configMax': GlobalKey(),
  'termometro:configMin': GlobalKey(),
  'termometro:ejemploAlerta': GlobalKey(),
  'termometro:historialTemperatura': GlobalKey(),
  'termometro:graficoTemperatura': GlobalKey(),
  'termometro:ofrecerPremium': GlobalKey(),
  //Riego
  'riego:estado': GlobalKey(),
  'riego:titulo': GlobalKey(),
  'riego:wifi': GlobalKey(),
  'riego:servidor': GlobalKey(),
  'riego:panelControl': GlobalKey(),
  'riego:panelBomba': GlobalKey(),
  'riego:noHayExtensiones': GlobalKey(),
  'riego:siHayExtensiones': GlobalKey(),
  'riego:automatico': GlobalKey(),
  'riego:rutina': GlobalKey(),
  'riego:rutinaPanel': GlobalKey(),
  'riego:extensionPanel': GlobalKey(),
  'riego:extension': GlobalKey(),
  //Termotanque
  'termotanque:estado': GlobalKey(),
  'termotanque:titulo': GlobalKey(),
  'termotanque:wifi': GlobalKey(),
  'termotanque:servidor': GlobalKey(),
  'termotanque:boton': GlobalKey(),
  'termotanque:temperatura': GlobalKey(),
  'termotanque:corte': GlobalKey(),
  'termotanque:consumo': GlobalKey(),
  'termotanque:valor': GlobalKey(),
  'termotanque:consumoManual': GlobalKey(),
  'termotanque:calcular': GlobalKey(),
  'termotanque:mes': GlobalKey(),
  //Roller
  'roller:titulo': GlobalKey(),
  'roller:wifi': GlobalKey(),
  'roller:servidor': GlobalKey(),
  'roller:animacion': GlobalKey(),
  'roller:botonesManuales': GlobalKey(),
  'roller:botonesAutomaticos': GlobalKey(),
  'roller:configuracion': GlobalKey(),
  'roller:calibracion': GlobalKey(),
  'roller:alertaCalibracionHome': GlobalKey(),
  'roller:alertaCalibracionConfig': GlobalKey(),
};
//*-Guía de usuario -*\\

//*- Toast -*\\
late FToast fToast;
//*- Toast -*\\

//*- Escenas -*\\
List<Map<String, dynamic>> eventosCreados = [];
//*- Escenas -*\\

//*- Special Users -*\\
bool specialUser = false;
bool labProcessFinished = false;
//*- Special Users -*\\

//*- Riverpod -*\\
final globalDataProvider = StateNotifierProvider<GlobalDataNotifier,
    Map<String, Map<String, dynamic>>>(
  (ref) => GlobalDataNotifier(),
);

final wifiProvider = StateNotifierProvider<WifiNotifier, WifiState>((ref) {
  return WifiNotifier();
});
//*- Riverpod -*\\

//*- Termometro -*\\
bool alertMaxFlag = false;
bool alertMinFlag = false;
String alertMaxTemp = '';
String alertMinTemp = '';
//*- Termometro -*\\

//*- Bloqueo admins -*\\
bool canUseDevice = true;
//*- Bloqueo admins -*\\

//*-Logs guardados-*\\
int printLogHistorialKey = DateTime.now().millisecondsSinceEpoch;
//*-Logs guardados-*\\

//*- In App Review -*\\
bool hasCheckedReviewThisSession = false;
//*- In App Review -*\\

// // -------------------------------------------------------------------------------------------------------------\\ \\

//! FUNCIONES !\\

//*-Tipo de Aplicación y parametros-*\\
String nameOfApp(int type) {
  return 'Caldén Smart';
}

Widget contactInfo(int type) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Contacto comercial
      Container(
        decoration: BoxDecoration(
          color: color1,
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: color0),
        ),
        padding: const EdgeInsets.all(16.0),
        margin: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contacto comercial:',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color0,
              ),
            ),
            GestureDetector(
              onTap: () {
                sendWhatsAppMessage(
                  '5491162234181',
                  '¡Hola! Tengo una duda comercial sobre los productos $appName: \n',
                );
              },
              child: Row(
                children: [
                  const Icon(
                    HugeIcons.strokeRoundedWhatsapp,
                    size: 20,
                    color: color0,
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  Text(
                    '+54 9 11 6223-4181',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      color: color0,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () {
                launchEmail(
                  'comercial@caldensmart.com',
                  'Consulta comercial acerca de la línea $appName',
                  '¡Hola! Tengo la siguiente duda sobre la línea IoT:\n',
                );
              },
              child: Row(
                children: [
                  const Icon(
                    HugeIcons.strokeRoundedMail01,
                    size: 20,
                    color: color0,
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text(
                        'comercial@caldensmart.com',
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          color: color0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      // Contacto técnico
      Container(
        decoration: BoxDecoration(
          color: color1,
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: color0),
        ),
        padding: const EdgeInsets.all(16.0),
        margin: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Consulta técnica:',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color0,
              ),
            ),
            GestureDetector(
              onTap: () {
                launchEmail(
                  'serviciotecnico@caldensmart.com',
                  'Consulta ref. $appName',
                  '¡Hola! Tengo una consulta referida al área de ingeniería sobre mis equipos.\n',
                );
              },
              child: Row(
                children: [
                  const Icon(
                    HugeIcons.strokeRoundedMail01,
                    size: 20,
                    color: color0,
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text(
                        'serviciotecnico@caldensmart.com',
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          color: color0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      // Customer service
      Container(
        decoration: BoxDecoration(
          color: color1,
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: color0),
        ),
        padding: const EdgeInsets.all(16.0),
        margin: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Customer service:',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color0,
              ),
            ),
            GestureDetector(
              onTap: () {
                sendWhatsAppMessage(
                  '5491162232619',
                  '¡Hola! Me comunico en relación a uno de mis equipos: \n',
                );
              },
              child: Row(
                children: [
                  const Icon(
                    HugeIcons.strokeRoundedWhatsapp,
                    size: 20,
                    color: color0,
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  Text(
                    '+54 9 11 6223-2619',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      color: color0,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () {
                launchEmail(
                  'service@caldensmart.com',
                  'Consulta sobre línea Smart',
                  '¡Hola! Me comunico en relación a uno de mis equipos: \n',
                );
              },
              child: Row(
                children: [
                  const Icon(
                    HugeIcons.strokeRoundedMail01,
                    size: 20,
                    color: color0,
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text(
                        'service@caldensmart.com',
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          color: color0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

String linksOfApp(String link) {
  switch (link) {
    case 'Privacidad':
      return 'https://caldensmart.com/ayuda/privacidad/';
    case 'TerminosDeUso':
      return 'https://caldensmart.com/ayuda/terminos-de-uso/';
    case 'Borrar Cuenta':
      return 'https://caldensmart.com/ayuda/eliminar-cuenta/';
    case 'Instagram':
      return 'https://www.instagram.com/caldensmart/';
    case 'Facebook':
      return 'https://www.facebook.com/CalefactoresCalden';
    case 'Web':
      return 'https://caldensmart.com';
    case 'Alexa':
      return 'https://www.amazon.es/dp/B0DK94GBXW/';
    case 'GoogleHome':
      return 'https://caldensmart.com';
    case 'Siri':
      return 'https://caldensmart.com';
    case 'manuales_escenas':
      return 'https://www.caldensmart.com/docs/Manual_escenas.pdf';
    default:
      return 'https://caldensmart.com';
  }
}

String linksOfProducts(String device) {
  final String pc = DeviceManager.getProductCode(device);
  final String sn = DeviceManager.extractSerialNumber(device);
  if (globalDATA['$pc/$sn']?['riegoActive'] == true) {
    return 'https://caldensmart.com/dsraix3/';
  }
  switch (pc) {
    case '015773_IOT':
      return 'https://www.intelligentgas.com.ar/item-015773esma/';
    case '020010_IOT':
      return 'https://caldensmart.com/dmtec44/';
    case '020020_IOT':
      return 'https://caldensmart.com/dmtec22/';
    case '022000_IOT':
      return 'https://calefactorescalden.com.ar/c2k02nes-smart/';
    case '027000_IOT':
      return 'https://calefactorescalden.com.ar/cp14nnes/';
    case '023430_IOT':
      return 'https://caldensmart.com/dstmxx1/';
    case '027313_IOT':
      return 'https://caldensmart.com/dmtec11/';
    case '027345_IOT':
      return 'https://caldensmart.com/dstttx1/';
    case '028000_IOT':
      return 'https://caldensmart.com/dsttxx1/';
    default:
      return 'https://caldensmart.com';
  }
}
//*-Tipo de Aplicación y parametros-*\\

//*-Funciones diversas-*\\
void showToast(String message) {
  printLog.i('Toast: $message');
  fToast.removeCustomToast();
  Widget toast = Container(
    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(25.0),
      color: color1,
      border: Border.all(
        color: color4,
        width: 1.0,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/branch/dragon.png',
          width: 24,
          height: 24,
        ),
        const SizedBox(
          width: 12.0,
        ),
        Flexible(
          child: Text(
            message,
            style: GoogleFonts.poppins(
              fontSize: 16,
              color: color0,
            ),
            softWrap: true,
            maxLines: 10,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ),
  );

  fToast.showToast(
    child: toast,
    gravity: ToastGravity.BOTTOM,
    toastDuration: const Duration(seconds: 2),
  );
}

String generateRandomNumbers(int length) {
  Random random = Random();
  String result = '';

  for (int i = 0; i < length; i++) {
    result += random.nextInt(10).toString();
  }

  return result;
}

Future<void> sendWhatsAppMessage(String phoneNumber, String message) async {
  var whatsappUrl =
      'https://api.whatsapp.com/send?phone=$phoneNumber&text=${Uri.encodeComponent(message)}';
  Uri uri = Uri.parse(whatsappUrl);

  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else {
    showToast('No se pudo abrir WhatsApp');
  }
}

void launchEmail(
  String mail,
  String asunto,
  String cuerpo, {
  String? cc,
}) async {
  Map<String, String> queryParams = {
    'subject': asunto,
    'body': cuerpo,
  };

  if (cc != null) {
    queryParams['CC'] = cc;
  }

  final Uri emailLaunchUri = Uri(
    scheme: 'mailto',
    path: mail,
    query: encodeQueryParameters(queryParams),
  );

  if (await canLaunchUrl(emailLaunchUri)) {
    await launchUrl(emailLaunchUri, mode: LaunchMode.externalApplication);
  } else {
    showToast('No se pudo abrir el correo electrónico');
  }
}

String encodeQueryParameters(Map<String, String> params) {
  return params.entries
      .map((e) =>
          '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');
}

void launchWebURL(String url) async {
  var uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else {
    printLog.i('No se pudo abrir $url');
  }
}
//*-Funciones diversas-*\\

//*- Agrega y elimina equipos a Alexa y GoogleHome -*\\
void addDeviceToCore(String deviceName) {
  try {
    if (deviceName.contains("Termometro") ||
        deviceName.contains("Detector") ||
        ((deviceName.contains("Domotica") || deviceName.contains("Modulo") || deviceName.contains("Rele")) &&
            !deviceName.contains("_"))) {
      return;
    }
    final String pc = DeviceManager.getProductCode(
        deviceName.contains('_') ? deviceName.split('_')[0] : deviceName);
    final String sn = DeviceManager.extractSerialNumber(
        deviceName.contains('_') ? deviceName.split('_')[0] : deviceName);
    List<String> admins =
        List<String>.from(globalDATA['$pc/$sn']?['secondary_admin'] ?? []);
    String ownerEmail = globalDATA['$pc/$sn']?['owner'] ?? '';
    bool canControl = ownerEmail == currentUserEmail ||
        admins.contains(currentUserEmail) ||
        ownerEmail == '';
    if (!alexaDevices.contains(deviceName) && canControl) {
      alexaDevices.add(deviceName);
      putDevicesForAlexa(currentUserEmail, alexaDevices);
    }
  } catch (e) {
    printLog.e('Error al agregar dispositivo a Alexa: $e');
  }
}

void removeDeviceFromCore(String deviceName) {
  for (String device in alexaDevices) {
    if (device == deviceName ||
        (device.startsWith(deviceName) && device.contains('_'))) {
      alexaDevices.remove(device);
    }
  }
  putDevicesForAlexa(currentUserEmail, alexaDevices);
}
//*- Agrega y elimina equipos a Alexa y GoogleHome -*\\

//*-Wifi, menú y scanner-*\\
Future<void> sendWifitoBle(String ssid, String pass) async {
  registerAdminUsage(
      deviceName,
      ssid == 'DSC' && pass == 'DSC'
          ? 'Se desconecto el equipo del wifi'
          : 'Se conecto el equipo al wifi: $ssid');
  BluetoothManager bluetoothManager = BluetoothManager();
  String value = '$ssid#$pass';
  String deviceCommand = DeviceManager.getProductCode(deviceName);
  // printLog.i(deviceCommand);
  String dataToSend = '$deviceCommand[1]($value)';
  printLog.i(dataToSend);
  try {
    await bluetoothManager.toolsUuid.write(dataToSend.codeUnits);
    printLog.i('Se mando el wifi ANASHE');
  } catch (e) {
    printLog.e('Error al conectarse a Wifi $e');
  }
  ssid != 'DSC' ? atemp = true : null;
}

Future<List<WiFiAccessPoint>> _fetchWiFiNetworks() async {
  if (_scanInProgress) return _wifiNetworksList;

  _scanInProgress = true;

  try {
    if (await Permission.locationWhenInUse.request().isGranted) {
      final canScan =
          await WiFiScan.instance.canStartScan(askPermissions: true);
      if (canScan == CanStartScan.yes) {
        final results = await WiFiScan.instance.startScan();
        if (results == true) {
          final networks = await WiFiScan.instance.getScannedResults();

          if (networks.isNotEmpty) {
            final uniqueResults = <String, WiFiAccessPoint>{};
            for (var network in networks) {
              if (network.ssid.isNotEmpty) {
                uniqueResults[network.ssid] = network;
              }
            }

            _wifiNetworksList = uniqueResults.values.toList()
              ..sort((a, b) => b.level.compareTo(a.level));
          }
        }
      } else {
        printLog.i('No se puede iniciar el escaneo.');
      }
    } else {
      printLog.i('Permiso de ubicación denegado.');
    }
  } catch (e) {
    printLog.e('Error durante el escaneo de WiFi: $e');
  } finally {
    _scanInProgress = false;
  }

  return _wifiNetworksList;
}

void wifiText(BuildContext context) async {
  bool isAddingNetwork = false;
  String manualSSID = '';
  String manualPassword = '';
  bool obscureText = true;
  final String pc = DeviceManager.getProductCode(deviceName);
  final String sn = DeviceManager.extractSerialNumber(deviceName);
  bool redInestable = await isWifiNetworkUnstable(
    pc,
    sn,
  );
  List<String> admins =
      List<String>.from(globalDATA['$pc/$sn']?['secondary_admin'] ?? []);
  String owner = globalDATA['$pc/$sn']?['owner'] ?? '';
  bool canUseWifi = await checkAdminWifiPermission(deviceName);
  bool isRestrictedAdmin = admins.contains(currentUserEmail) &&
      owner != currentUserEmail &&
      !canUseWifi;

  if (context.mounted && isRestrictedAdmin) {
    showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            backgroundColor: color1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20.0),
              side: const BorderSide(color: color4, width: 2.0),
            ),
            title: const Text(
              'Permiso denegado',
              style: TextStyle(
                color: color0,
              ),
            ),
            content: const Text(
              'No tienes permiso para gestionar la configuración WiFi de este dispositivo.',
              style: TextStyle(
                color: color0,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text(
                  'Aceptar',
                  style: TextStyle(
                    color: color0,
                  ),
                ),
              ),
            ],
          );
        });
  }

  if (context.mounted && !isRestrictedAdmin) {
    showDialog(
      barrierDismissible: true,
      context: context,
      builder: (BuildContext context) {
        return Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? child) {
          final wifiState = ref.watch(wifiProvider);
          final wifiNotifier = ref.read(wifiProvider.notifier);
          return StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              // Función para construir la vista principal
              Widget buildMainView() {
                if (!_scanInProgress && _wifiNetworksList.isEmpty && android) {
                  _fetchWiFiNetworks().then((wifiNetworks) {
                    setState(() {
                      _wifiNetworksList = wifiNetworks;
                    });
                  });
                }

                return AlertDialog(
                  backgroundColor: color1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20.0),
                    side: const BorderSide(color: color4, width: 2.0),
                  ),
                  title: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text.rich(
                        TextSpan(
                          text: 'Estado de conexión: ',
                          style: TextStyle(
                            fontSize: 14,
                            color: color0,
                          ),
                        ),
                      ),
                      Text(
                        wifiState.status,
                        style: TextStyle(
                          color: wifiState.statusColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (werror) ...[
                          Text.rich(
                            TextSpan(
                              text: 'Error: $errorMessage',
                              style: const TextStyle(
                                fontSize: 10,
                                color: color0,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text.rich(
                            TextSpan(
                              text: 'Sintax:',
                              style: TextStyle(
                                fontSize: 10,
                                color: color0,
                              ),
                            ),
                          ),
                          Text.rich(
                            TextSpan(
                              text: errorSintax,
                              style: const TextStyle(
                                fontSize: 10,
                                color: color0,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text.rich(
                              TextSpan(
                                text: 'Red actual:',
                                style: TextStyle(
                                  fontSize: 20,
                                  color: color0,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Text(
                              nameOfWifi,
                              style: const TextStyle(
                                fontSize: 20,
                                color: color0,
                              ),
                            ),
                            if (isWifiConnected && redInestable) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.orange,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      HugeIcons.strokeRoundedAlert02,
                                      color: Colors.orange,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Red Inestable',
                                      style: GoogleFonts.poppins(
                                        color: Colors.orange,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (isWifiConnected) ...[
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: () {
                              sendWifitoBle('DSC', 'DSC');
                              wifiNotifier.updateStatus(
                                'DESCONECTANDO...',
                                Colors.orange,
                                HugeIcons.strokeRoundedSearch02,
                              );
                            },
                            style: const ButtonStyle(
                              foregroundColor: WidgetStatePropertyAll(
                                color0,
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                Icon(HugeIcons.strokeRoundedWifiOff02),
                                Text('Desconectar Red Actual')
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        if (android) ...[
                          _wifiNetworksList.isEmpty && _scanInProgress
                              ? const Center(
                                  child:
                                      CircularProgressIndicator(color: color0),
                                )
                              : SizedBox(
                                  width: double.maxFinite,
                                  height: 200.0,
                                  child: ListView.builder(
                                    itemCount: _wifiNetworksList.length,
                                    itemBuilder: (context, index) {
                                      final network = _wifiNetworksList[index];
                                      int nivel = network.level;
                                      // printLog.i('${network.ssid}: $nivel dBm ');
                                      return nivel >= -80
                                          ? SizedBox(
                                              child: ExpansionTile(
                                                initiallyExpanded:
                                                    _expandedIndex == index,
                                                onExpansionChanged:
                                                    (bool open) {
                                                  if (open) {
                                                    wifiPassNode.requestFocus();
                                                    setState(() {
                                                      _expandedIndex = index;
                                                    });
                                                  } else {
                                                    setState(() {
                                                      _expandedIndex = null;
                                                    });
                                                  }
                                                },
                                                leading: wifiPower(nivel)
                                                        is String
                                                    ? ImageIcon(
                                                        AssetImage(
                                                            wifiPower(nivel)),
                                                        color: Colors.white,
                                                      )
                                                    : Icon(
                                                        wifiPower(nivel),
                                                        color: Colors.white,
                                                      ),
                                                title: Text(
                                                  network.ssid,
                                                  style: const TextStyle(
                                                      color: color0),
                                                ),
                                                backgroundColor: color1,
                                                collapsedBackgroundColor:
                                                    color1,
                                                textColor: color0,
                                                iconColor: color0,
                                                children: [
                                                  Padding(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 16.0,
                                                        vertical: 8.0),
                                                    child: Row(
                                                      children: [
                                                        const Icon(
                                                          HugeIcons
                                                              .strokeRoundedSquareLock01,
                                                          color: color0,
                                                          size: 20,
                                                        ),
                                                        const SizedBox(
                                                            width: 8.0),
                                                        Expanded(
                                                          child: TextField(
                                                            focusNode:
                                                                wifiPassNode,
                                                            style:
                                                                const TextStyle(
                                                              color: color0,
                                                            ),
                                                            decoration:
                                                                InputDecoration(
                                                              hintText:
                                                                  'Escribir contraseña',
                                                              hintStyle:
                                                                  const TextStyle(
                                                                color:
                                                                    Colors.grey,
                                                              ),
                                                              enabledBorder:
                                                                  const UnderlineInputBorder(
                                                                borderSide:
                                                                    BorderSide(
                                                                        color:
                                                                            color0),
                                                              ),
                                                              focusedBorder:
                                                                  const UnderlineInputBorder(
                                                                borderSide: BorderSide(
                                                                    color: Colors
                                                                        .blue),
                                                              ),
                                                              border:
                                                                  const UnderlineInputBorder(
                                                                borderSide: BorderSide(
                                                                    color: Colors
                                                                        .white),
                                                              ),
                                                              suffixIcon:
                                                                  IconButton(
                                                                icon: Icon(
                                                                  obscureText
                                                                      ? Icons
                                                                          .visibility
                                                                      : Icons
                                                                          .visibility_off,
                                                                  color: color0,
                                                                ),
                                                                onPressed: () {
                                                                  setState(() {
                                                                    obscureText =
                                                                        !obscureText;
                                                                  });
                                                                },
                                                              ),
                                                            ),
                                                            obscureText:
                                                                obscureText,
                                                            onChanged: (value) {
                                                              setState(() {
                                                                _currentlySelectedSSID =
                                                                    network
                                                                        .ssid;
                                                                _wifiPasswordsMap[
                                                                        network
                                                                            .ssid] =
                                                                    value;
                                                              });
                                                            },
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          : const SizedBox.shrink();
                                    },
                                  ),
                                ),
                        ] else ...[
                          SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Campo para SSID
                                Row(
                                  children: [
                                    const Icon(
                                      HugeIcons.strokeRoundedWifi02,
                                      color: color0,
                                    ),
                                    const SizedBox(width: 8.0),
                                    Expanded(
                                      child: TextField(
                                        cursorColor: color0,
                                        style: const TextStyle(color: color0),
                                        decoration: const InputDecoration(
                                          hintText: 'Agregar WiFi',
                                          hintStyle:
                                              TextStyle(color: Colors.grey),
                                          enabledBorder: UnderlineInputBorder(
                                            borderSide:
                                                BorderSide(color: color0),
                                          ),
                                          focusedBorder: UnderlineInputBorder(
                                            borderSide:
                                                BorderSide(color: color0),
                                          ),
                                        ),
                                        onChanged: (value) {
                                          manualSSID = value;
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    const Icon(
                                      HugeIcons.strokeRoundedSquareLock01,
                                      color: color0,
                                    ),
                                    const SizedBox(width: 8.0),
                                    Expanded(
                                      child: TextField(
                                        cursorColor: color0,
                                        style: const TextStyle(color: color0),
                                        decoration: InputDecoration(
                                          hintText: 'Contraseña',
                                          hintStyle: const TextStyle(
                                              color: Colors.grey),
                                          enabledBorder:
                                              const UnderlineInputBorder(
                                            borderSide:
                                                BorderSide(color: color0),
                                          ),
                                          focusedBorder:
                                              const UnderlineInputBorder(
                                            borderSide:
                                                BorderSide(color: color0),
                                          ),
                                          suffixIcon: IconButton(
                                            icon: Icon(
                                              obscureText
                                                  ? HugeIcons.strokeRoundedView
                                                  : HugeIcons
                                                      .strokeRoundedViewOff,
                                              color: color0,
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                obscureText = !obscureText;
                                              });
                                            },
                                          ),
                                        ),
                                        obscureText: obscureText,
                                        onChanged: (value) {
                                          manualPassword = value;
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),
                  actions: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(
                            HugeIcons.strokeRoundedQrCode,
                            color: color0,
                          ),
                          iconSize: 30,
                          onPressed: () async {
                            PermissionStatus permissionStatusC =
                                await Permission.camera.request();
                            if (!permissionStatusC.isGranted) {
                              await Permission.camera.request();
                            }
                            permissionStatusC = await Permission.camera.status;
                            if (permissionStatusC.isGranted) {
                              openQRScanner(
                                  navigatorKey.currentContext ?? context);
                            }
                          },
                        ),
                        android
                            ? TextButton(
                                style: const ButtonStyle(),
                                child: const Text(
                                  'Agregar\nRed',
                                  style: TextStyle(
                                    color: color0,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                onPressed: () {
                                  setState(() {
                                    isAddingNetwork = true;
                                  });
                                },
                              )
                            : const SizedBox.shrink(),
                        TextButton(
                          style: const ButtonStyle(),
                          child: const Text(
                            'Conectar',
                            style: TextStyle(
                              color: color0,
                            ),
                          ),
                          onPressed: () {
                            if (_currentlySelectedSSID != null &&
                                _wifiPasswordsMap[_currentlySelectedSSID] !=
                                    null &&
                                android) {
                              printLog.i(
                                  '$_currentlySelectedSSID#${_wifiPasswordsMap[_currentlySelectedSSID]}');
                              sendWifitoBle(_currentlySelectedSSID!,
                                  _wifiPasswordsMap[_currentlySelectedSSID]!);
                              wifiNotifier.updateStatus(
                                'CONECTANDO...',
                                Colors.blue,
                                HugeIcons.strokeRoundedSearch02,
                              );
                            } else if (!android &&
                                manualSSID != '' &&
                                manualPassword != '') {
                              printLog.i('$manualSSID#$manualPassword');
                              sendWifitoBle(manualSSID, manualPassword);
                              wifiNotifier.updateStatus(
                                'CONECTANDO...',
                                Colors.blue,
                                HugeIcons.strokeRoundedSearch02,
                              );
                            } else {
                              showToast('Por favor, ingrese una red válida.');
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                );
              }

              Widget buildAddNetworkView() {
                return AlertDialog(
                  backgroundColor: color1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20.0),
                    side: const BorderSide(color: color4, width: 2.0),
                  ),
                  title: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          HugeIcons.strokeRoundedArrowLeft02,
                          color: color0,
                        ),
                        onPressed: () {
                          setState(() {
                            isAddingNetwork = false;
                          });
                        },
                      ),
                      const Text(
                        'Agregar red\nmanualmente',
                        style: TextStyle(
                          color: color0,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Campo para SSID
                        Row(
                          children: [
                            const Icon(
                              HugeIcons.strokeRoundedWifi02,
                              color: color0,
                            ),
                            const SizedBox(width: 8.0),
                            Expanded(
                              child: TextField(
                                cursorColor: color0,
                                style: const TextStyle(color: color0),
                                decoration: const InputDecoration(
                                  hintText: 'Agregar WiFi',
                                  hintStyle: TextStyle(color: Colors.grey),
                                  enabledBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(color: color0),
                                  ),
                                  focusedBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(color: color0),
                                  ),
                                ),
                                onChanged: (value) {
                                  manualSSID = value;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            const Icon(
                              HugeIcons.strokeRoundedSquareLock01,
                              color: color0,
                            ),
                            const SizedBox(width: 8.0),
                            Expanded(
                              child: TextField(
                                cursorColor: color0,
                                style: const TextStyle(color: color0),
                                decoration: InputDecoration(
                                  hintText: 'Contraseña',
                                  hintStyle:
                                      const TextStyle(color: Colors.grey),
                                  enabledBorder: const UnderlineInputBorder(
                                    borderSide: BorderSide(color: color0),
                                  ),
                                  focusedBorder: const UnderlineInputBorder(
                                    borderSide: BorderSide(color: color0),
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      obscureText
                                          ? HugeIcons.strokeRoundedView
                                          : HugeIcons.strokeRoundedViewOff,
                                      color: color0,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        obscureText = !obscureText;
                                      });
                                    },
                                  ),
                                ),
                                obscureText: obscureText,
                                onChanged: (value) {
                                  manualPassword = value;
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        if (manualSSID.isNotEmpty &&
                            manualPassword.isNotEmpty) {
                          printLog.i('$manualSSID#$manualPassword');

                          sendWifitoBle(manualSSID, manualPassword);
                          wifiNotifier.updateStatus(
                            'CONECTANDO...',
                            Colors.blue,
                            HugeIcons.strokeRoundedSearch02,
                          );
                          Navigator.of(context).pop();
                        } else {}
                      },
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.all<Color>(
                          color1,
                        ),
                      ),
                      child: const Text(
                        'Agregar',
                        style: TextStyle(color: color0),
                      ),
                    ),
                  ],
                );
              }

              return isAddingNetwork ? buildAddNetworkView() : buildMainView();
            },
          );
        });
      },
    ).then((_) {
      _scanInProgress = false;
      _expandedIndex = null;
    });
  }
}

dynamic wifiPower(int level) {
  if (level >= -30) {
    return HugeIcons.strokeRoundedWifi02;
  } else if (level >= -67) {
    return CaldenIcons.wifi01;
  } else if (level >= -70) {
    return CaldenIcons.wifi02;
  } else if (level >= -80) {
    return CaldenIcons.wifi02;
  } else {
    return CaldenIcons.wifi03;
  }
}

String getWifiErrorSintax(int errorCode) {
  switch (errorCode) {
    case 1:
      return "WIFI_REASON_UNSPECIFIED";
    case 2:
      return "WIFI_REASON_AUTH_EXPIRE";
    case 3:
      return "WIFI_REASON_AUTH_LEAVE";
    case 4:
      return "WIFI_REASON_ASSOC_EXPIRE";
    case 5:
      return "WIFI_REASON_ASSOC_TOOMANY";
    case 6:
      return "WIFI_REASON_NOT_AUTHED";
    case 7:
      return "WIFI_REASON_NOT_ASSOCED";
    case 8:
      return "WIFI_REASON_ASSOC_LEAVE";
    case 9:
      return "WIFI_REASON_ASSOC_NOT_AUTHED";
    case 10:
      return "WIFI_REASON_DISASSOC_PWRCAP_BAD";
    case 11:
      return "WIFI_REASON_DISASSOC_SUPCHAN_BAD";
    case 12:
      return "WIFI_REASON_BSS_TRANSITION_DISASSOC";
    case 13:
      return "WIFI_REASON_IE_INVALID";
    case 14:
      return "WIFI_REASON_MIC_FAILURE";
    case 15:
      return "WIFI_REASON_4WAY_HANDSHAKE_TIMEOUT";
    case 16:
      return "WIFI_REASON_GROUP_KEY_UPDATE_TIMEOUT";
    case 17:
      return "WIFI_REASON_IE_IN_4WAY_DIFFERS";
    case 18:
      return "WIFI_REASON_GROUP_CIPHER_INVALID";
    case 19:
      return "WIFI_REASON_PAIRWISE_CIPHER_INVALID";
    case 20:
      return "WIFI_REASON_AKMP_INVALID";
    case 21:
      return "WIFI_REASON_UNSUPP_RSN_IE_VERSION";
    case 22:
      return "WIFI_REASON_INVALID_RSN_IE_CAP";
    case 23:
      return "WIFI_REASON_802_1X_AUTH_FAILED";
    case 24:
      return "WIFI_REASON_CIPHER_SUITE_REJECTED";
    case 25:
      return "WIFI_REASON_TDLS_PEER_UNREACHABLE";
    case 26:
      return "WIFI_REASON_TDLS_UNSPECIFIED";
    case 27:
      return "WIFI_REASON_SSP_REQUESTED_DISASSOC";
    case 28:
      return "WIFI_REASON_NO_SSP_ROAMING_AGREEMENT";
    case 29:
      return "WIFI_REASON_BAD_CIPHER_OR_AKM";
    case 30:
      return "WIFI_REASON_NOT_AUTHORIZED_THIS_LOCATION";
    case 31:
      return "WIFI_REASON_SERVICE_CHANGE_PERCLUDES_TS";
    case 32:
      return "WIFI_REASON_UNSPECIFIED_QOS";
    case 33:
      return "WIFI_REASON_NOT_ENOUGH_BANDWIDTH";
    case 34:
      return "WIFI_REASON_MISSING_ACKS";
    case 35:
      return "WIFI_REASON_EXCEEDED_TXOP";
    case 36:
      return "WIFI_REASON_STA_LEAVING";
    case 37:
      return "WIFI_REASON_END_BA";
    case 38:
      return "WIFI_REASON_UNKNOWN_BA";
    case 39:
      return "WIFI_REASON_TIMEOUT";
    case 46:
      return "WIFI_REASON_PEER_INITIATED";
    case 47:
      return "WIFI_REASON_AP_INITIATED";
    case 48:
      return "WIFI_REASON_INVALID_FT_ACTION_FRAME_COUNT";
    case 49:
      return "WIFI_REASON_INVALID_PMKID";
    case 50:
      return "WIFI_REASON_INVALID_MDE";
    case 51:
      return "WIFI_REASON_INVALID_FTE";
    case 67:
      return "WIFI_REASON_TRANSMISSION_LINK_ESTABLISH_FAILED";
    case 68:
      return "WIFI_REASON_ALTERATIVE_CHANNEL_OCCUPIED";
    case 200:
      return "WIFI_REASON_BEACON_TIMEOUT";
    case 201:
      return "WIFI_REASON_NO_AP_FOUND";
    case 202:
      return "WIFI_REASON_AUTH_FAIL";
    case 203:
      return "WIFI_REASON_ASSOC_FAIL";
    case 204:
      return "WIFI_REASON_HANDSHAKE_TIMEOUT";
    case 205:
      return "WIFI_REASON_CONNECTION_FAIL";
    case 206:
      return "WIFI_REASON_AP_TSF_RESET";
    case 207:
      return "WIFI_REASON_ROAMING";
    default:
      return "Error Desconocido";
  }
}
//*-Wifi, menú y scanner-*\\

//*-Verifica si hay red inestable basado en discTime-*\\
/// Verifica si hay 3 o más desconexiones en la última hora
/// [pc] código del producto
/// [sn] número de serie
/// Retorna true si hay red inestable, false en caso contrario
Future<bool> isWifiNetworkUnstable(String pc, String sn) async {
  try {
    printLog.d("Verificando estabilidad de red para $pc/$sn");
    // Lee SOLO los timestamps de desconexión de la última hora.
    final List<String> timestamps = await getRecentDisconnectTimes(pc, sn,
        window: const Duration(hours: 1));

    if (timestamps.isEmpty) return false;

    int disconnectionsInLastHour = 0;
    final DateTime oneHourAgo =
        DateTime.now().subtract(const Duration(hours: 1));

    for (final tsString in timestamps) {
      final int? tsSec = int.tryParse(tsString);
      if (tsSec == null) continue;
      final dt = DateTime.fromMillisecondsSinceEpoch(tsSec * 1000);
      if (dt.isAfter(oneHourAgo)) disconnectionsInLastHour++;
    }

    return disconnectionsInLastHour >= 3;
  } catch (e) {
    printLog.e("Error verificando estabilidad de red: $e");
    return false;
  }
}
//*-Verifica si hay red inestable basado en discTime-*\\

//*-Qr scanner-*\\
Future<void> openQRScanner(BuildContext context) async {
  try {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Navigator.pushNamed(context, '/qr');

      if (qrResult != null) {
        var wifiData = parseWifiQR(qrResult!);
        sendWifitoBle(wifiData['SSID']!, wifiData['password']!);

        if (context.mounted) {
          final container = ProviderScope.containerOf(context);

          final wifiNotifier = container.read(wifiProvider.notifier);

          wifiNotifier.updateStatus(
            'CONECTANDO...',
            Colors.blue,
            HugeIcons.strokeRoundedSearch02,
          );
        }

        qrResult = null;
      }
    });
    if (context.mounted) {}
  } catch (e) {
    printLog.e("Error during navigation: $e");
  }
}

Map<String, String> parseWifiQR(String qrContent) {
  printLog.i(qrContent);
  final ssidMatch = RegExp(r'S:([^;]+)').firstMatch(qrContent);
  final passwordMatch = RegExp(r'P:([^;]+)').firstMatch(qrContent);

  final ssid = ssidMatch?.group(1) ?? '';
  final password = passwordMatch?.group(1) ?? '';
  return {"SSID": ssid, "password": password};
}
//*-Qr scanner-*\\

//*-Notificaciones-*\\
Future<void> initNotifications() async {
  AndroidNotificationChannel channel = AndroidNotificationChannel(
    'caldenSmart',
    'Eventos',
    description: 'Notificaciones de eventos en $appName',
    importance: Importance.high,
    enableLights: true,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (Platform.isIOS || Platform.isAndroid) {
    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(
        iOS: DarwinInitializationSettings(),
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
  }

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(alert: true, badge: true, sound: true);

  printLog.i('Notificaciones iniciadas');
}

@pragma('vm:entry-point')
Future<void> handleNotifications(RemoteMessage message) async {
  android = Platform.isAndroid;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    currentUserEmail = await loadEmail();
    nicknamesMap = await getNicknames(currentUserEmail);
    soundOfNotification = await loadSounds();
    await DeviceManager.init();
    printLog.i('Llegó esta notif: ${message.data}', color: 'lima');
    String product = message.data['pc'] ?? '000000_IOT';
    String number = message.data['sn'] ?? '00000000';
    String device = DeviceManager.recoverDeviceName(product, number);
    String sound = soundOfNotification[product] ?? 'alarm2';
    String caso = message.data['case'] ?? 'unknown';

    printLog.i('El caso que llego es $caso');

    switch (caso) {
      case 'Alarm':
        if (product == '015773_IOT') {
          final now = DateTime.now();
          String displayTitle = '¡ALERTA EN ${nicknamesMap[device] ?? device}!';
          String displayMessage =
              'El detector disparó una alarma.\nA las ${now.hour >= 10 ? now.hour : '0${now.hour}'}:${now.minute >= 10 ? now.minute : '0${now.minute}'} del ${now.day}/${now.month}/${now.year}';
          showNotification(displayTitle.toUpperCase(), displayMessage, sound);
        } else if (product == '020010_IOT' ||
            product == '020020_IOT' ||
            product == '027313_IOT') {
          notificationMap = await loadNotificationMap();
          List<bool> notis = notificationMap['$product/$number'] ??
              List<bool>.filled(8, false);
          final now = DateTime.now();
          String entry = nicknamesMap['${device}_${message.data['entry']!}'] ??
              'Entrada${message.data['entry']!}';
          String displayTitle = '¡ALERTA EN ${nicknamesMap[device] ?? device}!';
          String displayMessage =
              'La $entry disparó una alarma.\nA las ${now.hour >= 10 ? now.hour : '0${now.hour}'}:${now.minute >= 10 ? now.minute : '0${now.minute}'} del ${now.day}/${now.month}/${now.year}';
          if (notis[int.parse(message.data['entry']!)]) {
            printLog.i(
                'En la lista: ${notificationMap['$product/$number']!} en la posición ${message.data['entry']!} hay un true');
            showNotification(displayTitle.toUpperCase(), displayMessage, sound);
          }
        } else if (product == '023430_IOT') {
          final now = DateTime.now();
          String alarmType = message.data['alarmType'] ?? '';
          String deviceNickname = nicknamesMap[device] ?? device;
          String displayTitle = '¡ALERTA DE TEMPERATURA EN $deviceNickname!';
          String displayMessage = '';

          printLog.i('El alarmType es $alarmType');

          if (alarmType == 'max') {
            displayMessage =
                'Se detectó temperatura MÁXIMA alcanzada.\nA las ${now.hour >= 10 ? now.hour : '0${now.hour}'}:${now.minute >= 10 ? now.minute : '0${now.minute}'} del ${now.day}/${now.month}/${now.year}';
          } else if (alarmType == 'min') {
            displayMessage =
                'Se detectó temperatura MÍNIMA alcanzada.\nA las ${now.hour >= 10 ? now.hour : '0${now.hour}'}:${now.minute >= 10 ? now.minute : '0${now.minute}'} del ${now.day}/${now.month}/${now.year}';
          } else {
            displayMessage =
                'Se detectó una alerta de temperatura.\nA las ${now.hour >= 10 ? now.hour : '0${now.hour}'}:${now.minute >= 10 ? now.minute : '0${now.minute}'} del ${now.day}/${now.month}/${now.year}';
          }

          showNotification(displayTitle.toUpperCase(), displayMessage, sound);
        }
        break;
      case 'Disconnect':
        configNotiDsc = await loadconfigNotiDsc();
        if (configNotiDsc.keys.toList().contains(device)) {
          final now = DateTime.now();
          int espera = configNotiDsc[device] ?? 0;
          printLog.i('La espera son $espera minutos');
          printLog.i('Empezo la espera ${DateTime.now()}');
          await Future.delayed(
            Duration(minutes: espera),
          );
          printLog.i('Termino la espera ${DateTime.now()}');
          await queryItems(product, number);
          bool cstate = globalDATA['$product/$number']?['cstate'] ?? false;
          printLog.i('El cstate después de la espera es $cstate');
          bool redUnstable = await isWifiNetworkUnstable(product, number);
          printLog.i('Red inestable: $redUnstable');
          if (!cstate && !redUnstable) {
            String displayTitle =
                '¡El equipo ${nicknamesMap[device] ?? device} se desconecto!';
            String displayMessage =
                'Se detecto una desconexión a las ${now.hour >= 10 ? now.hour : '0${now.hour}'}:${now.minute >= 10 ? now.minute : '0${now.minute}'} del ${now.day}/${now.month}/${now.year}';
            showNotification(displayTitle, displayMessage, 'noti');
          }
        }
        break;
      case 'evento':
        String eventName = message.data['name'] ?? 'Evento';
        final now = DateTime.now();
        String displayTitle = '¡Se activo el evento $eventName!';
        String displayMessage =
            'A las ${now.hour >= 10 ? now.hour : '0${now.hour}'}:${now.minute >= 10 ? now.minute : '0${now.minute}'} del ${now.day}/${now.month}/${now.year}';
        showNotification(displayTitle, displayMessage, 'noti');
        break;
      case 'cadena':
        String cadenaName = message.data['name'] ?? 'Cadena';
        final now = DateTime.now();
        String displayTitle = '¡La cadena $cadenaName terminó de ejecutarse!';
        String displayMessage =
            'A las ${now.hour >= 10 ? now.hour : '0${now.hour}'}:${now.minute >= 10 ? now.minute : '0${now.minute}'} del ${now.day}/${now.month}/${now.year}';
        showNotification(displayTitle, displayMessage, 'noti');

        // Remover la flag de ejecución de la cadena
        await removeCadenaExecuting(cadenaName, currentUserEmail);
        printLog.i('Flag de ejecución removida para cadena: $cadenaName');

        // Notificar a los listeners que la cadena terminó (para UI en tiempo real)
        cadenaCompletedController.add(cadenaName);
        printLog.i('Evento de cadena completada enviado para: $cadenaName');
        break;
      case 'clima':
        String climaDetectado =
            message.data['clima_detectado'] ?? 'Desconocido';
        String nombreEvento = message.data['name'] ?? 'Evento Climático';
        final now = DateTime.now();
        String displayTitle = '🌤️ Control por Clima Activado';
        String displayMessage =
            "Se detectó '$climaDetectado' y se ejecutaron las acciones programadas para el evento '$nombreEvento'.\nA las ${now.hour >= 10 ? now.hour : '0${now.hour}'}:${now.minute >= 10 ? now.minute : '0${now.minute}'} del ${now.day}/${now.month}/${now.year}";
        showNotification(displayTitle, displayMessage, 'noti');
        break;
      case 'riego':
        String riegoName = message.data['name'] ?? 'Rutina de Riego';
        final now = DateTime.now();
        String displayTitle = '🌱 Rutina de Riego Completada';
        String displayMessage =
            "La rutina de riego '$riegoName' ha sido completada exitosamente.\nA las ${now.hour >= 10 ? now.hour : '0${now.hour}'}:${now.minute >= 10 ? now.minute : '0${now.minute}'} del ${now.day}/${now.month}/${now.year}";
        showNotification(displayTitle, displayMessage, 'noti');

        // Remover la flag de ejecución del riego
        await removeRiegoExecuting(riegoName, currentUserEmail);
        printLog.i('Flag de ejecución removida para riego: $riegoName');

        // Notificar a los listeners que el riego terminó (para UI en tiempo real)
        riegoCompletedController.add(riegoName);
        printLog.i('Evento de riego completado enviado para: $riegoName');
        break;
    }
  } catch (e, s) {
    printLog.e("Error: $e");
    printLog.t("Trace: $s");
  }
}

void showNotification(String title, String body, String sonido) async {
  printLog.i('Titulo: $title');
  printLog.i('Body: $body');
  printLog.i('Sonido: $sonido');
  try {
    // Generar ID único combinando timestamp con hash del contenido
    String uniqueContent =
        '$title|$body|$sonido|${DateTime.now().microsecondsSinceEpoch}';
    int notificationId = uniqueContent.hashCode.abs();

    // Asegurar que el ID esté en un rango válido para notificaciones
    notificationId = notificationId % 2147483647; // Max int32 value

    printLog.i('NotificationId generado: $notificationId');

    // 'alarm6' es el valor guardado cuando el usuario elige "Sin sonido"
    final bool silencioso = sonido == 'alarm6';

    await flutterLocalNotificationsPlugin.show(
      notificationId,
      title,
      body,
      NotificationDetails(
        android: silencioso
            ? AndroidNotificationDetails(
                'CaldénSmart_silent',
                'Eventos silenciosos',
                icon: '@mipmap/ic_launcher',
                playSound: false,
                enableVibration: false,
                importance: Importance.defaultImportance,
                styleInformation: BigTextStyleInformation(
                  body,
                  contentTitle: title,
                  summaryText: 'Caldén Smart',
                ),
              )
            : AndroidNotificationDetails(
                'CaldénSmart_$sonido',
                'Eventos',
                icon: '@mipmap/ic_launcher',
                sound: RawResourceAndroidNotificationSound(sonido.toLowerCase()),
                enableVibration: true,
                importance: Importance.max,
                styleInformation: BigTextStyleInformation(
                  body,
                  contentTitle: title,
                  summaryText: 'Caldén Smart',
                ),
              ),
        iOS: DarwinNotificationDetails(
          sound: silencioso ? null : '$sonido.wav',
          presentSound: !silencioso,
        ),
      ),
    );
    // printLog.i("Notificacion enviada anacardamente nasharda");
  } catch (e, s) {
    printLog.e('Error enviando notif: $e');
    printLog.t(s);
  }
}

//*-Notificaciones-*\\

//*-Admin secundarios y alquiler temporario-*\\
void analizePayment(
  String pc,
  String sn,
) {
  String fechaAT = globalDATA['$pc/$sn']?['DateAT'] ?? '';
  String fechaAdmSec = globalDATA['$pc/$sn']?['DateAdmSec'] ?? '';

  if (fechaAdmSec == '') {
    payAdmSec = false;
  } else {
    var partsAdmSec = fechaAdmSec.split('/');
    final fechaParse = DateTime(
      int.parse(partsAdmSec[0]),
      int.parse(partsAdmSec[1]),
      int.parse(partsAdmSec[2]),
    );
    vencimientoAdmSec = fechaParse.difference(DateTime.now()).inDays;

    payAdmSec = vencimientoAdmSec > 0;

    printLog.i('--------------Administradores secundarios--------------');
    printLog.i(fechaParse.toIso8601String());
    printLog.i('Se vence en $vencimientoAdmSec dias');
    printLog.i('¿Esta pago? ${payAdmSec ? 'Si' : 'No'}');
    printLog.i('--------------Administradores secundarios--------------');
  }

  if (fechaAT == '') {
    payAT = false;
  } else {
    var partsAT = fechaAT.split('/');
    final fechaParseAT = DateTime(
      int.parse(partsAT[0]),
      int.parse(partsAT[1]),
      int.parse(partsAT[2]),
    );
    vencimientoAT = fechaParseAT.difference(DateTime.now()).inDays;

    payAT = vencimientoAT > 0;

    printLog.i('--------------Alquiler Temporario--------------');
    printLog.i(fechaParseAT.toIso8601String());
    printLog.i('Se vence en $vencimientoAT dias');
    printLog.i('¿Esta pago? ${payAT ? 'Si' : 'No'}');
    printLog.i('--------------Alquiler Temporario--------------');
  }
}

void showPaymentText(bool adm, int vencimiento, BuildContext context) {
  try {
    showAlertDialog(
      context,
      false,
      const Text(
        '¡Estas por perder tu beneficio!',
      ),
      Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text(
            'Faltan $vencimiento días para que te quedes sin la opción:',
            style: const TextStyle(fontWeight: FontWeight.normal),
          ),
          adm
              ? const Text(
                  'Administradores secundarios extra',
                  style: TextStyle(fontWeight: FontWeight.bold),
                )
              : const Text(
                  'Habilitar alquiler temporario',
                  style: TextStyle(fontWeight: FontWeight.bold),
                )
        ],
      ),
      <Widget>[
        TextButton(
          child: const Text('Ignorar'),
          onPressed: () {
            navigatorKey.currentState?.pop();
          },
        ),
        TextButton(
          child: const Text('Solicitar extensión'),
          onPressed: () async {
            String cuerpo = adm
                ? '¡Hola! Me comunico porque busco extender mi beneficio de "Administradores secundarios extra" en mi equipo $deviceName\nCódigo de Producto: ${DeviceManager.getProductCode(deviceName)}\nNúmero de Serie: ${DeviceManager.extractSerialNumber(deviceName)}\nDueño actual del equipo: $owner\nVencimiento en: $vencimiento dias'
                : '¡Hola! Me comunico porque busco extender mi beneficio "Habilitar alquiler temporario" en mi equipo $deviceName\nCódigo de Producto: ${DeviceManager.getProductCode(deviceName)}\nNúmero de Serie: ${DeviceManager.extractSerialNumber(deviceName)}\nDueño actual del equipo: $owner\nVencimiento en: $vencimiento dias';
            final Uri emailLaunchUri = Uri(
              scheme: 'mailto',
              path: 'cobranzas@caldensmart.com',
              query: encodeQueryParameters(<String, String>{
                'subject': 'Extensión de beneficio',
                'body': cuerpo,
                'CC': 'serviciotecnico@caldensmart.com'
              }),
            );
            if (await canLaunchUrl(emailLaunchUri)) {
              await launchUrl(emailLaunchUri);
            } else {
              showToast('No se pudo enviar el correo electrónico');
            }
            navigatorKey.currentState?.pop();
          },
        ),
      ],
    );
  } catch (e, s) {
    printLog.e(e);
    printLog.t(s);
  }
}
//*-Admin secundarios y alquiler temporario-*\\

//*- Funciones para administradores secundarios -*\\
/// Registra el uso de un dispositivo por un administrador secundario
Future<void> registerAdminUsage(String deviceName, String action) async {
  String pc = DeviceManager.getProductCode(deviceName);
  String sn = DeviceManager.extractSerialNumber(deviceName);
  bool isAdmin = (globalDATA['$pc/$sn']?['secondary_admin'] ?? [])
      .contains(currentUserEmail);
  bool isOwner = globalDATA['$pc/$sn']?['owner'] == currentUserEmail ||
      globalDATA['$pc/$sn']?['owner'] == '' ||
      globalDATA['$pc/$sn']?['owner'] == null;
  // Solo registrar si el usuario actual es un administrador secundario
  if (currentUserEmail.isNotEmpty && isAdmin && !isOwner) {
    try {
      await putAdminUsageHistory(pc, sn, currentUserEmail, action);
      printLog.i('Uso registrado: $currentUserEmail - $action');
    } catch (e) {
      printLog.e('Error registrando uso de administrador: $e');
    }
  }
}

/// Verifica si el administrador secundario actual puede usar el dispositivo
Future<bool> checkAdminTimePermission(String deviceName) async {
  String pc = DeviceManager.getProductCode(deviceName);
  String sn = DeviceManager.extractSerialNumber(deviceName);
  bool isOwner = globalDATA['$pc/$sn']?['owner'] == currentUserEmail ||
      globalDATA['$pc/$sn']?['owner'] == '' ||
      globalDATA['$pc/$sn']?['owner'] == null;
  if (isOwner) {
    return true; // El dueño puede usarlo siempre
  }

  try {
    bool isAllowed =
        await isAdminAllowedAtCurrentTime(pc, sn, currentUserEmail);

    return isAllowed;
  } catch (e) {
    printLog.e('Error verificando permisos horarios: $e');
    return true; // En caso de error, permitir acceso
  }
}

/// Envía mensaje MQTT con verificación de permisos y registro de uso
Future<bool> sendMQTTMessageWithPermission(String deviceName, String message,
    String topic, String topic2, String action) async {
  // Verificar permisos horarios si es administrador secundario
  bool hasPermission = await checkAdminTimePermission(deviceName);
  if (!hasPermission) {
    return false;
  }

  // Enviar mensaje
  sendMessagemqtt(topic, message);
  sendMessagemqtt(topic2, message);

  // Registrar uso si es administrador secundario
  await registerAdminUsage(deviceName, action);

  return true;
}

/// Verifica si el administrador secundario actual puede usar el WiFi
Future<bool> checkAdminWifiPermission(String deviceName) async {
  String pc = DeviceManager.getProductCode(deviceName);
  String sn = DeviceManager.extractSerialNumber(deviceName);
  bool isOwner = globalDATA['$pc/$sn']?['owner'] == currentUserEmail ||
      globalDATA['$pc/$sn']?['owner'] == '' ||
      globalDATA['$pc/$sn']?['owner'] == null;
  if (isOwner) {
    return true; // El dueño puede usarlo siempre
  }

  try {
    bool isAllowed = await isAdminAllowedToUseWifi(pc, sn, currentUserEmail);

    return isAllowed;
  } catch (e) {
    printLog.e('Error verificando permisos de WiFi: $e');
    return true; // En caso de error, permitir acceso
  }
}
//*- Funciones para administradores secundarios -*\\

//*-Cognito user flow-*\\
void asking() async {
  bool alreadyLog = await isUserSignedIn();

  if (!alreadyLog) {
    printLog.i('Usuario no está logueado');
    navigatorKey.currentState?.pushReplacementNamed('/welcome');
  } else {
    printLog.i('Usuario logueado');
    navigatorKey.currentState?.pushReplacementNamed('/menu');
  }
}

Future<bool> isUserSignedIn() async {
  final result = await Amplify.Auth.fetchAuthSession();
  return result.isSignedIn;
}

Future<String> getUserMail() async {
  String email = '';
  try {
    final attributes = await Amplify.Auth.fetchUserAttributes();
    for (final attribute in attributes) {
      if (attribute.userAttributeKey.key == 'email') {
        email = attribute.value; // Retorna el correo electrónico del usuario
      }
    }
  } on AuthException catch (e) {
    printLog.e('Error fetching user attributes: ${e.message}');
  }

  await saveEmail(email);
  return email;
}
//*-Cognito user flow-*\\

//*-Background functions-*\\
Future<void> initializeService() async {
  try {
    // Solicitar exclusión de optimización de batería para control por distancia
    if (android) {
      try {
        final status = await Permission.ignoreBatteryOptimizations.status;
        if (!status.isGranted) {
          final completer = Completer<void>();

          showAlertDialog(
            navigatorKey.currentContext!,
            false,
            const Text(
              'Optimización de batería',
              style: TextStyle(color: Color(0xFFFFFFFF)),
            ),
            Text(
              '$appName utiliza un servicio en segundo plano para el control por distancia.\n\nPara que funcione correctamente, es necesario desactivar la optimización de batería.',
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
              ),
            ),
            <Widget>[
              TextButton(
                style: const ButtonStyle(
                  foregroundColor: WidgetStatePropertyAll(Color(0xFFFFFFFF)),
                ),
                child: const Text('Deshabilitar'),
                onPressed: () async {
                  try {
                    await Permission.ignoreBatteryOptimizations.request();
                    printLog.i(
                        'Exclusión de optimización de batería solicitada para control por distancia');
                    completer.complete();
                    Navigator.of(navigatorKey.currentContext!).pop();
                  } catch (e, s) {
                    printLog.e('Error solicitando exclusión de batería: $e');
                    printLog.t(s);
                    completer.completeError(e);
                  }
                },
              ),
            ],
          );

          await completer.future;
        }
      } catch (e) {
        printLog.e('Error verificando optimización de batería: $e');
      }
    }

    final backService = FlutterBackgroundService();

    await backService.configure(
      iosConfiguration: IosConfiguration(
        onBackground: onIosStart,
        autoStart: true,
        onForeground: onIosStart,
      ),
      androidConfiguration: AndroidConfiguration(
        notificationChannelId: 'caldenSmart',
        foregroundServiceNotificationId: 888,
        initialNotificationTitle: 'Eventos $appName',
        initialNotificationContent:
            'Utilizamos este servicio para ejecutar tareas en la app\nTal como el control por distancia, entre otras...',
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        foregroundServiceTypes: [
          AndroidForegroundType.location,
          AndroidForegroundType.dataSync
        ],
      ),
    );

    initNotifications();

    await backService.isRunning() ? null : await backService.startService();

    printLog.i('Se inició piola');
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasInitService', true);
  } catch (e, s) {
    printLog.e('Error al inicializar servicio $e');
    printLog.t('$s');
  }
}

@pragma('vm:entry-point')
Future<bool> onIosStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  // Marcar servicio como NO listo mientras se inicializa
  await setWidgetServiceReady(false);

  final mqttConnected = await setupMqtt();

  if (!mqttConnected) {
    printLog.e('Servicio iOS: Error conectando a MQTT');
    await Future.delayed(const Duration(seconds: 5));
    await setupMqtt();
  }

  await subscribeToWidgetTopics();

  // Sincronizar widgets con el estado real desde la base de datos
  await syncWidgetsWithDatabase();

  // Marcar servicio como LISTO
  await setWidgetServiceReady(true);

  flutterLocalNotificationsPlugin.show(
    888,
    'Servicio inicializado con exito',
    'Gracias por elegir Caldén Smart',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'caldenSmart',
        'Eventos',
        icon: '@mipmap/ic_launcher',
        sound: RawResourceAndroidNotificationSound('noti'),
        enableVibration: true,
        importance: Importance.max,
      ),
      iOS: DarwinNotificationDetails(),
    ),
  );

  service.on('stopService').listen((event) async {
    await setWidgetServiceReady(false);
    disposeWidgetListener();
    service.stopSelf();
  });

  service.on('subscribeWidgets').listen((event) async {
    printLog.i('Servicio iOS: recibida petición para suscribir widgets');
    await subscribeToWidgetTopics();
  });

  // Listener para suscribir Y sincronizar (cuando se agrega un nuevo widget)
  service.on('subscribeAndSyncWidgets').listen((event) async {
    printLog.i(
        'Servicio iOS: recibida petición para suscribir y sincronizar widgets');
    await subscribeToWidgetTopics();
    await syncWidgetsWithDatabase();
  });

  // Listener para verificar si quedan widgets activos (llamado cuando se elimina un widget)
  service.on('checkWidgetsAndStop').listen((event) async {
    printLog.i('Servicio iOS: verificando si quedan widgets activos');
    final hasWidgets = await hasActiveWidgets();
    if (!hasWidgets) {
      printLog
          .i('Servicio iOS: no hay widgets, verificando control por distancia');
      await stopWidgetService();
    } else {
      printLog.i('Servicio iOS: aún hay widgets activos');
    }
  });

  service.on('distanceControl').listen((event) {
    showNotification('Se inició el control por distancia',
        'Recuerde tener la ubicación del telefono encendida', 'noti');
    backTimerDS?.cancel();
    backTimerDS = Timer.periodic(const Duration(minutes: 2), (timer) async {
      await backFunctionDS();
    });
  });

  _mqttReconnectTimer?.cancel();
  _mqttReconnectTimer =
      Timer.periodic(const Duration(minutes: 5), (timer) async {
    if (mqttAWSFlutterClient == null ||
        mqttAWSFlutterClient!.connectionStatus?.state !=
            MqttConnectionState.connected) {
      printLog.i('Servicio iOS: Reconectando a MQTT...');
      await setWidgetServiceReady(false);
      final reconnected = await setupMqtt();
      if (reconnected) {
        await subscribeToWidgetTopics();
        await setWidgetServiceReady(true);
      }
    }
  });

  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Marcar servicio como NO listo mientras se inicializa
  await setWidgetServiceReady(false);

  final mqttConnected = await setupMqtt();

  if (!mqttConnected) {
    printLog.e('Servicio background: Error conectando a MQTT');
    // Intentar reconectar después de un delay
    await Future.delayed(const Duration(seconds: 5));
    await setupMqtt();
  }

  await subscribeToWidgetTopics();

  // Sincronizar widgets con el estado real desde la base de datos
  await syncWidgetsWithDatabase();

  // Marcar servicio como LISTO
  await setWidgetServiceReady(true);

  flutterLocalNotificationsPlugin.show(
    888,
    'Servicio inicializado con exito',
    'Gracias por elegir Caldén Smart',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'caldenSmart',
        'Eventos',
        icon: '@mipmap/ic_launcher',
        sound: RawResourceAndroidNotificationSound('noti'),
        enableVibration: true,
        importance: Importance.max,
      ),
      iOS: DarwinNotificationDetails(
        sound: 'noti.wav',
        presentSound: true,
      ),
    ),
  );

  service.on('stopService').listen((event) async {
    await setWidgetServiceReady(false);
    disposeWidgetListener();
    service.stopSelf();
  });

  service.on('subscribeWidgets').listen((event) async {
    printLog.i('Servicio: recibida petición para suscribir widgets');
    await subscribeToWidgetTopics();
  });

  // Listener para suscribir Y sincronizar (cuando se agrega un nuevo widget)
  service.on('subscribeAndSyncWidgets').listen((event) async {
    printLog
        .i('Servicio: recibida petición para suscribir y sincronizar widgets');
    await subscribeToWidgetTopics();
    await syncWidgetsWithDatabase();
  });

  // Listener para verificar si quedan widgets activos (llamado cuando se elimina un widget)
  service.on('checkWidgetsAndStop').listen((event) async {
    printLog.i('Servicio: verificando si quedan widgets activos');
    final hasWidgets = await hasActiveWidgets();
    if (!hasWidgets) {
      printLog.i('Servicio: no hay widgets, verificando control por distancia');
      await stopWidgetService();
    } else {
      printLog.i('Servicio: aún hay widgets activos');
    }
  });

  service.on('distanceControl').listen((event) {
    showNotification('Se inició el control por distancia',
        'Recuerde tener la ubicación del telefono encendida', 'noti');
    backTimerDS?.cancel();
    backTimerDS = Timer.periodic(const Duration(minutes: 2), (timer) async {
      await backFunctionDS();
    });
  });

  _mqttReconnectTimerBg?.cancel();
  _mqttReconnectTimerBg =
      Timer.periodic(const Duration(minutes: 5), (timer) async {
    if (mqttAWSFlutterClient == null ||
        mqttAWSFlutterClient!.connectionStatus?.state !=
            MqttConnectionState.connected) {
      printLog.i('Servicio background: Reconectando a MQTT...');
      await setWidgetServiceReady(false);
      final reconnected = await setupMqtt();
      if (reconnected) {
        await subscribeToWidgetTopics();
        await setWidgetServiceReady(true);
        printLog.i('Servicio background: MQTT reconectado');
      }
    }
  });
}

Future<bool> backFunctionDS() async {
  printLog.i('Entre a hacer locuritas. ${DateTime.now()}');
  // showNotification('Entre a la función', '${DateTime.now()}');
  try {
    String currentUserEmail = await loadEmail();
    List<String> devicesStored =
        await getDevicesInDistanceControl(currentUserEmail);
    Map<String, Map<String, dynamic>> globalDATA = {};
    await DeviceManager.init();
    Map<String, String> nicks = await getNicknames(currentUserEmail);

    for (int index = 0; index < devicesStored.length; index++) {
      printLog.i('Analizando dispositivo: ${devicesStored[index]}');

      String name = devicesStored[index].contains('_')
          ? devicesStored[index].split('_')[0]
          : devicesStored[index];
      String productCode = DeviceManager.getProductCode(name);
      String sn = DeviceManager.extractSerialNumber(name);

      await queryItems(productCode, sn);

      double distanceOff =
          globalDATA['$productCode/$sn']?['distanceOff'] ?? 100.0;
      double distanceOn =
          globalDATA['$productCode/$sn']?['distanceOn'] ?? 3000.0;

      String position = globalDATA['$productCode/$sn']?['deviceLocation'] ?? '';

      if (position.isEmpty) {
        printLog.i('No hay ubicación guardada para el dispositivo $name');
        continue;
      }

      // Parse the position string to extract latitude and longitude
      RegExp latRegExp = RegExp(r'Latitude: (-?\d+\.?\d*)');
      RegExp lngRegExp = RegExp(r'Longitude: (-?\d+\.?\d*)');

      Match? latMatch = latRegExp.firstMatch(position);
      Match? lngMatch = lngRegExp.firstMatch(position);

      if (latMatch == null || lngMatch == null) {
        printLog.i('Formato de ubicación inválido para $name: $position');
        continue;
      }

      double latitude = double.parse(latMatch.group(1)!);
      double longitude = double.parse(lngMatch.group(1)!);

      Position storedLocation = Position(
        latitude: latitude,
        longitude: longitude,
        timestamp: DateTime.now(),
        accuracy: 0.0,
        altitude: 0.0,
        heading: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
        floor: 0,
        isMocked: false,
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
      );

      printLog.i('Ubicación guardada $storedLocation');

      // showNotification('Ubicación guardada', '$storedLocation');

      Position currentPosition1 = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ));
      printLog.i('$currentPosition1');

      double distance1 = Geolocator.distanceBetween(
        currentPosition1.latitude,
        currentPosition1.longitude,
        storedLocation.latitude,
        storedLocation.longitude,
      );
      printLog.i('Distancia 1 : $distance1 metros');

      // showNotification('Distancia 1', '$distance1 metros');

      if (distance1 > 100.0) {
        printLog.i('Esperando 30 segundos ${DateTime.now()}');

        // showNotification('Esperando 30 segundos', '${DateTime.now()}');

        Position currentPosition2 = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ));
        printLog.i('$currentPosition2');

        double distance2 = Geolocator.distanceBetween(
          currentPosition2.latitude,
          currentPosition2.longitude,
          storedLocation.latitude,
          storedLocation.longitude,
        );
        printLog.i('Distancia 2 : $distance2 metros');

        // showNotification('Distancia 2', '$distance2 metros');

        if (distance2 <= distanceOn && distance1 > distance2) {
          printLog.i('Usuario cerca, encendiendo');

          if (devicesStored[index].contains('_')) {
            showNotification(
                'Encendimos ${nicknamesMap[devicesStored[index]] ?? 'Salida ${devicesStored[index].split('_')[1]}'} en ${nicks[devicesStored[index].split('_')[0]] ?? name}',
                'Te acercaste a menos de $distanceOn metros',
                'noti');

            String message = jsonEncode({
              'pinType': '0',
              'index': devicesStored[index].split('_')[1],
              'w_status': true,
              'r_state': '0',
            });
            String topic = 'devices_rx/$productCode/$sn';
            String topic2 = 'devices_tx/$productCode/$sn';

            globalDATA
                .putIfAbsent('$productCode/$sn', () => {})
                .addAll({"io${devicesStored[index].split('_')[1]}": message});
            sendMessagemqtt(topic, message);
            sendMessagemqtt(topic2, message);
          } else {
            showNotification('Encendimos ${nicks[name] ?? name}',
                'Te acercaste a menos de $distanceOn metros', 'noti');

            globalDATA
                .putIfAbsent('$productCode/$sn', () => {})
                .addAll({"w_status": true});

            String topic = 'devices_rx/$productCode/$sn';
            String topic2 = 'devices_tx/$productCode/$sn';
            String message = jsonEncode({"w_status": true});
            sendMessagemqtt(topic, message);
            sendMessagemqtt(topic2, message);
          }

          //Ta cerca prendo
        } else if (distance2 >= distanceOff && distance1 < distance2) {
          printLog.i('Usuario lejos, apagando');

          if (devicesStored[index].contains('_')) {
            showNotification(
                'Apagamos ${nicknamesMap[devicesStored[index]] ?? 'Salida ${devicesStored[index].split('_')[1]}'} en ${nicks[devicesStored[index].split('_')[0]] ?? name}',
                'Te alejaste a más de $distanceOff metros',
                'noti');

            String message = jsonEncode({
              'pinType': '0',
              'index': devicesStored[index].split('_')[1],
              'w_status': false,
              'r_state': '0',
            });
            String topic = 'devices_rx/$productCode/$sn';
            String topic2 = 'devices_tx/$productCode/$sn';

            globalDATA
                .putIfAbsent('$productCode/$sn', () => {})
                .addAll({"io${devicesStored[index].split('_')[1]}": message});
            sendMessagemqtt(topic, message);
            sendMessagemqtt(topic2, message);
          } else {
            showNotification('Apagamos ${nicks[name] ?? name}',
                'Te alejaste a más de $distanceOff metros', 'noti');

            globalDATA
                .putIfAbsent('$productCode/$sn', () => {})
                .addAll({"w_status": false});

            String topic = 'devices_rx/$productCode/$sn';
            String topic2 = 'devices_tx/$productCode/$sn';
            String message = jsonEncode({"w_status": false});
            sendMessagemqtt(topic, message);
            sendMessagemqtt(topic2, message);
          }

          //Estas re lejos apago el calefactor
        } else {
          printLog.i('Ningun caso');

          // showNotification('No se cumplio ningún caso', 'No hicimos nada');
        }
      } else {
        printLog.i('Esta en home');
      }
    }

    return Future.value(true);
  } catch (e, s) {
    printLog.e('Error en segundo plano $e');
    printLog.t(s);

    // showNotification('Error en segundo plano $e', '$e');

    return Future.value(false);
  }
}
//*-Background functions-*\\

//*-Verificador de conexión a internet-*\\
Future<bool> checkInternetConnection() async {
  try {
    final result = await InternetAddress.lookup('google.com')
        .timeout(const Duration(seconds: 5));
    return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
  } on SocketException catch (_) {
    return false;
  } on TimeoutException catch (_) {
    return false;
  } catch (e) {
    printLog.e('Error verificando conexión a internet: $e');
    return false;
  }
}

/// Muestra un diálogo solicitando al usuario que active internet.
/// Retorna `true` si el usuario presionó "Reintentar" y hay conexión,
/// `false` si el usuario cerró el diálogo o sigue sin internet.
Future<bool> showNoInternetDialog(BuildContext context) async {
  bool? result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (BuildContext context, Animation<double> animation,
        Animation<double> secondaryAnimation) {
      double screenWidth = MediaQuery.of(context).size.width;
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter changeState) {
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: 300.0,
                maxWidth: screenWidth - 40,
              ),
              child: IntrinsicWidth(
                child: Container(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        spreadRadius: 1,
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Card(
                    color: color1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30.0),
                    ),
                    elevation: 24,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.topCenter,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 70, 20, 20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Center(
                                child: Text(
                                  'Sin conexión a Internet',
                                  style: GoogleFonts.poppins(
                                    color: color0,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Center(
                                child: Text(
                                  'Para usar la aplicación necesitas estar conectado a Internet.\n\nPor favor, activa los datos móviles o conéctate a una red WiFi.',
                                  style: GoogleFonts.poppins(
                                    color: color0,
                                    fontSize: 14,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 12,
                                runSpacing: 10,
                                children: [
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      foregroundColor: color0,
                                      backgroundColor: color4,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                    ),
                                    icon: const Icon(
                                        HugeIcons.strokeRoundedSettings01,
                                        size: 20),
                                    label: Text(
                                      'Ajustes',
                                      style: GoogleFonts.poppins(fontSize: 14),
                                    ),
                                    onPressed: () async {
                                      // Abrir configuración del dispositivo
                                      await openAppSettings();
                                    },
                                  ),
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      foregroundColor: color1,
                                      backgroundColor: color0,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 10,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                    ),
                                    icon: const Icon(
                                        HugeIcons.strokeRoundedReload,
                                        size: 20),
                                    label: Text(
                                      'Reintentar',
                                      style: GoogleFonts.poppins(fontSize: 14),
                                    ),
                                    onPressed: () async {
                                      // Verificar si ahora hay conexión
                                      bool hasConnection =
                                          await checkInternetConnection();
                                      if (context.mounted) {
                                        Navigator.of(context)
                                            .pop(hasConnection);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: -50,
                          child: Material(
                            elevation: 10,
                            shape: const CircleBorder(),
                            shadowColor: Colors.black.withValues(alpha: 0.4),
                            child: const CircleAvatar(
                              radius: 50,
                              backgroundColor: color1,
                              child: Icon(
                                HugeIcons.strokeRoundedWifiOff02,
                                size: 50,
                                color: color3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeInOut,
        ),
        child: ScaleTransition(
          scale: CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOut,
          ),
          child: child,
        ),
      );
    },
  );
  return result ?? false;
}
//*-Verificador de conexión a internet-*\\

//*-show dialog generico-*\\
void showAlertDialog(
  BuildContext context,
  bool dismissible,
  Widget? title,
  Widget? content,
  List<Widget>? actions, {
  bool avoidKeyboard = true,
}) {
  showGeneralDialog(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (BuildContext context, Animation<double> animation,
        Animation<double> secondaryAnimation) {
      final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
      double screenWidth = MediaQuery.of(context).size.width;

      return StatefulBuilder(
        builder: (BuildContext context, StateSetter changeState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: avoidKeyboard ? keyboardHeight : 0,
            ),
            child: Center(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: 300.0,
                    maxWidth: screenWidth - 20,
                  ),
                  child: IntrinsicWidth(
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.topCenter,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 50),
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                spreadRadius: 1,
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Card(
                            color: color1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30.0),
                              side: const BorderSide(
                                color: color2,
                                width: 1.0,
                              ),
                            ),
                            elevation: 24,
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 70, 20, 20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Center(
                                    child: DefaultTextStyle(
                                      style: GoogleFonts.poppins(
                                        color: color0,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      child: title ?? const SizedBox.shrink(),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Center(
                                    child: DefaultTextStyle(
                                      style: GoogleFonts.poppins(
                                        color: color0,
                                        fontSize: 16,
                                      ),
                                      child: content ?? const SizedBox.shrink(),
                                    ),
                                  ),
                                  const SizedBox(height: 30),
                                  if (actions != null)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: actions.map(
                                        (widget) {
                                          if (widget is TextButton) {
                                            return Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 5.0),
                                              child: TextButton(
                                                style: TextButton.styleFrom(
                                                  foregroundColor: color0,
                                                  backgroundColor: color1,
                                                ),
                                                onPressed: widget.onPressed,
                                                child: widget.child!,
                                              ),
                                            );
                                          } else {
                                            return widget;
                                          }
                                        },
                                      ).toList(),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          child: Material(
                            elevation: 10,
                            color: color1,
                            shape: const CircleBorder(
                              side: BorderSide(
                                color: color2,
                                width: 1.0,
                              ),
                            ),
                            shadowColor: Colors.black.withValues(alpha: 0.4),
                            child: CircleAvatar(
                              radius: 50,
                              backgroundColor: color1,
                              child: Image.asset(
                                'assets/branch/dragon.png',
                                width: 60,
                                height: 60,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeInOut,
        ),
        child: ScaleTransition(
          scale: CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOut,
          ),
          child: child,
        ),
      );
    },
  );
}
//*-show dialog generico-*\\

//*-show dialog generico-*\\

//*-Cartel de desconexión-*\\
void showDisconnectDialog(BuildContext ctx) {
  showDialog(
    context: ctx,
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        backgroundColor: color1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.0),
          side: const BorderSide(color: color4, width: 2.0),
        ),
        content: Row(
          children: [
            Image.asset('assets/branch/dragon.gif', width: 100, height: 100),
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(left: 15),
                child: const Text(
                  "Desconectando...",
                  style: TextStyle(color: color0),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
//*-Cartel de desconexión-*\\

//*-Acceso rápido BLE-*\\
Future<void> controlDeviceBLE(String name, bool newState) async {
  printLog.i("Voy a ${newState ? 'Encender' : 'Apagar'} el equipo $name");
  final String pc = DeviceManager.getProductCode(name);
  final String sn = DeviceManager.extractSerialNumber(name);

  if (pc == '020010_IOT' || pc == '020020_IOT' || pc == '027313_IOT') {
    String? pinQuick = pinQuickAccess[name];
    if (pinQuick == null) {
      printLog.e('No se encontró el pin para acceso rápido en $name');
      return;
    }
    String fun = '$pinQuick#${newState ? '1' : '0'}';
    bluetoothManager.ioUuid.write(fun.codeUnits);
    String topic = 'devices_rx/$pc/$sn';
    String topic2 = 'devices_tx/$pc/$sn';
    String message = jsonEncode({
      'index': int.parse(pinQuick),
      'w_status': newState,
      'r_state': "0",
      'pinType': 0
    });
    sendMessagemqtt(topic, message);
    sendMessagemqtt(topic2, message);

    globalDATA
        .putIfAbsent('$pc/$sn', () => {})
        .addAll({'io$pinQuick': message});
  } else {
    int fun = newState ? 1 : 0;
    String data = '$pc[11]($fun)';
    bluetoothManager.toolsUuid.write(data.codeUnits);
    globalDATA['$pc/$sn']!['w_status'] = newState;

    try {
      String topic = 'devices_rx/$pc/$sn';
      String topic2 = 'devices_tx/$pc/$sn';
      String message = jsonEncode({'w_status': newState});
      sendMessagemqtt(topic, message);
      sendMessagemqtt(topic2, message);
    } catch (e, s) {
      printLog.e('Error al enviar valor en cdBLE $e $s');
    }
  }
}
//*-Acceso rápido BLE-*\\

//*-Revisión de actualización-*\\
void checkForUpdate(BuildContext context) async {
  final upgrader = Upgrader(
    debugLogging: false,
    durationUntilAlertAgain: const Duration(seconds: 5),
  );

  await upgrader.initialize();

  printLog.i("Vamos a revisar el skibidi toilet");

  // Verifica si hay una actualización disponible
  final shouldDisplay = upgrader.shouldDisplayUpgrade();

  printLog.i("Papu :v $shouldDisplay");

  if (shouldDisplay) {
    printLog.i("Papure papa pure");
    final actualVer = upgrader.currentInstalledVersion;
    final newVer = upgrader.currentAppStoreVersion;
    showAlertDialog(
      navigatorKey.currentContext ?? context,
      false,
      const Text(
        '¡Hay una nueva versión de la app disponible!',
        textAlign: TextAlign.start,
      ),
      Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const Text(
            'Para que la aplicación pueda funcionar correctamente y puedas disfrutar de todas sus funciones nuevas.\nTe pedimos por favor que actualices la aplicación',
            textAlign: TextAlign.start,
          ),
          if (actualVer != null && newVer != null) ...[
            const SizedBox(
              height: 10,
            ),
            Text(
              'Tu versión actual es: $actualVer',
              textAlign: TextAlign.start,
            ),
            Text(
              'La nueva versión es: $newVer',
              textAlign: TextAlign.start,
            ),
          ]
        ],
      ),
      [
        TextButton(
          onPressed: () {
            navigatorKey.currentState?.pop();
          },
          child: const Text(
            'Más tarde',
          ),
        ),
        TextButton(
          onPressed: () {
            launchWebURL(
              android
                  ? 'https://play.google.com/store/apps/details?id=com.caldensmart.sime'
                  : 'https://apps.apple.com/gb/app/calden-smart/id6737855207?uo=2',
            );
          },
          child: const Text('Actualizar ahora'),
        ),
      ],
    );
  }
}
//*-Revisión de actualización-*\\

//*-Device update-*\\
Future<void> showUpdateDialog(BuildContext ctx) {
  bool updating = false;
  bool error = false;
  int porcentaje = 0;
  final String pc = DeviceManager.getProductCode(deviceName);

  return showDialog<void>(
    barrierDismissible: false,
    context: ctx,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return AlertDialog(
            backgroundColor: color1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20.0),
              side: const BorderSide(color: color4, width: 2.0),
            ),
            title: Text(
              'Actualmente tu equipo ${nicknamesMap[deviceName] ?? deviceName} esta desactualizado',
              style: GoogleFonts.poppins(
                color: color0,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    height: 20,
                  ),
                  if (error) ...[
                    const Icon(
                      HugeIcons.strokeRoundedAlertCircle,
                      size: 20,
                      color: color4,
                    ),
                    const SizedBox(
                      height: 20,
                    ),
                    Text(
                      'Ocurrió un error actualizando el equipo, intentelo de nuevo más tarde...',
                      style: GoogleFonts.poppins(
                        color: color0,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                  if (updating && !error) ...[
                    const CircularProgressIndicator(
                      color: color0,
                    ),
                    const SizedBox(
                      height: 20,
                    ),
                    Text(
                      '$porcentaje%',
                      style: GoogleFonts.poppins(
                        color: color0,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    Text(
                      'Actualizando equipo...',
                      style: GoogleFonts.poppins(
                        color: color0,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    Text(
                      'Al finalizar la actualización el equipo se reiniciara.',
                      style: GoogleFonts.poppins(
                        color: color0,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                  if (!updating && !error) ...[
                    Text(
                      'Tu equipo no está actualizado y por lo tanto podría perderse de las últimas novedades, se solicita que por favor actualice el equipo.\nSi el equipo no está conectado a WiFi se actualizara por Bluetooth',
                      style: GoogleFonts.poppins(
                        color: color0,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: <Widget>[
              if (error) ...{
                TextButton(
                  child: Text(
                    'Cerrar',
                    style: GoogleFonts.poppins(color: color3),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                  },
                ),
              },
              if (!updating && !error) ...{
                TextButton(
                  child: Text(
                    'Mas tarde',
                    style: GoogleFonts.poppins(color: color3),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                  },
                ),
                TextButton(
                  child: Text(
                    'Actualizar ahora',
                    style: GoogleFonts.poppins(color: color3),
                  ),
                  onPressed: () async {
                    setState(() => updating = true);

                    await bluetoothManager.otaUuid.setNotifyValue(true);

                    final otaSub = bluetoothManager.otaUuid.onValueReceived
                        .listen((List<int> event) {
                      var fun = utf8.decode(event);
                      fun = fun.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
                      printLog.i(fun);
                      var parts = fun.split(':');
                      if (parts[0] == 'OTAPR') {
                        printLog.i('Se recibio');
                        setState(() {
                          porcentaje = int.parse(parts[1]);
                        });
                        printLog.i('Progreso: ${parts[1]}');
                      }
                    });

                    bluetoothManager.device.cancelWhenDisconnected(otaSub);

                    final fileName = await Versioner.fetchLatestFirmwareFile(
                        pc, hardwareVersion);

                    String url = Versioner.buildFirmwareUrl(pc, fileName);
                    printLog.i(url);

                    try {
                      if (isWifiConnected) {
                        printLog.i('Si mandé ota Wifi');
                        printLog.i('url: $url');
                        String data = '$pc[2]($url)';
                        await bluetoothManager.toolsUuid.write(data.codeUnits);
                      } else {
                        printLog.i('Arranca por la derecha la OTA BLE');
                        String dir =
                            (await getApplicationDocumentsDirectory()).path;
                        File file = File('$dir/firmware.bin');

                        if (await file.exists()) {
                          await file.delete();
                        }

                        var req = await http.get(Uri.parse(url));

                        var bytes = req.bodyBytes;

                        await file.writeAsBytes(bytes);

                        var firmware = await file.readAsBytes();

                        // printLog.i(
                        //     "Comprobando cosas ${bytes == bytes2}", "verde");

                        String data = '$pc[3](${bytes.length})';
                        printLog.i(data);
                        await bluetoothManager.toolsUuid.write(data.codeUnits);
                        printLog.i("Arranco OTA");
                        try {
                          int chunk = 255 - 3;
                          // int chunk = 1;
                          for (int i = 0; i < firmware.length; i += chunk) {
                            // printLog.i('Mande chunk');
                            List<int> subvalue = firmware.sublist(
                              i,
                              min(i + chunk, firmware.length),
                            );
                            await bluetoothManager.infoUuid
                                .write(subvalue, withoutResponse: false);
                            // recordedData.add([i, subvalue]);
                            // setState(() {
                            //   porcentaje = ((i * 100) / firmware.length).round();
                            // });
                          }
                          printLog.i('Acabe');
                        } catch (e, stackTrace) {
                          printLog.e('El error es: $e $stackTrace');
                          setState(() {
                            updating = false;
                            error = true;
                          });
                          // handleManualError(e, stackTrace);
                        }
                      }
                    } catch (e, stackTrace) {
                      printLog.e('Error al enviar la OTA $e $stackTrace');
                      // handleManualError(e, stackTrace);
                      setState(() {
                        updating = false;
                        error = true;
                      });
                    }
                  },
                ),
              }
            ],
          );
        },
      );
    },
  );
}
//*-Device update-*\\

//*- valor de consumo -*\\
double? equipmentConsumption(String productCode) {
  switch (productCode) {
    case '022000_IOT':
      return 2;
    case '050217_IOT':
      return 1.5;
    default:
      return null;
  }
}
//*- valor de consumo -*\\

bool hasLED(String productCode, String hwVersion) {
  String versionWithLED = '';
  switch (productCode) {
    case '022000_IOT':
      versionWithLED = '240924A';
    case '027000_IOT':
      versionWithLED = '241003A';
    case '041220_IOT':
      versionWithLED = '241003A';
    default:
      versionWithLED = '991231A';
  }

  bool hasIt = Versioner.isPrevious(hwVersion, versionWithLED) ||
      hwVersion == versionWithLED;

  return hasIt;
}

Future<bool> isSpecialUser(String email) async {
  printLog.i('Verificando si $email es un usuario especial');
  if (dbData.isEmpty) {
    await DeviceManager.init();
    return isSpecialUser(email);
  }
  final specialUsers = (dbData['SpecialUser'] as List<dynamic>?)
      ?.map((e) => e.toString().toLowerCase())
      .toList();
  if (specialUsers == null) return false;
  printLog.i('Special users: $specialUsers');
  return specialUsers.contains(email.toLowerCase());
}

//*- Funciones de parsing para Maps y Duration -*\\
/// Parsea un string que representa un Map toString() de vuelta a Map<String, dynamic>
/// Útil para backward compatibility con datos guardados como strings
Map<String, dynamic> parseMapString(String mapString) {
  try {
    // Remover espacios al inicio y final
    String cleaned = mapString.trim();

    // Si empieza y termina con llaves, es un Map
    if (cleaned.startsWith('{') && cleaned.endsWith('}')) {
      cleaned = cleaned.substring(1, cleaned.length - 1);

      Map<String, dynamic> result = {};

      // Parsear manualmente respetando las estructuras anidadas
      int i = 0;
      while (i < cleaned.length) {
        // Buscar el nombre de la clave
        int keyStart = i;
        while (i < cleaned.length && cleaned[i] != ':') {
          i++;
        }
        if (i >= cleaned.length) break;

        String key = cleaned.substring(keyStart, i).trim();
        i++; // saltar ':'

        // Saltar espacios
        while (i < cleaned.length && cleaned[i] == ' ') {
          i++;
        }

        // Parsear el valor
        dynamic value;
        if (i < cleaned.length && cleaned[i] == '[') {
          // Es una lista - encontrar el ] que cierra
          int listStart = i;
          int brackets = 0;
          do {
            if (cleaned[i] == '[') brackets++;
            if (cleaned[i] == ']') brackets--;
            i++;
          } while (i < cleaned.length && brackets > 0);

          String listStr = cleaned.substring(listStart + 1, i - 1);
          value = listStr.split(',').map((e) => e.trim()).toList();
        } else if (i < cleaned.length && cleaned[i] == '{') {
          // Es un Map anidado - encontrar el } que cierra
          int mapStart = i;
          int braces = 0;
          do {
            if (cleaned[i] == '{') braces++;
            if (cleaned[i] == '}') braces--;
            i++;
          } while (i < cleaned.length && braces > 0);

          String mapStr = cleaned.substring(mapStart + 1, i - 1);
          Map<String, dynamic> nestedMap = {};

          // Parsear el map anidado
          List<String> pairs = [];
          int pairStart = 0;
          int depth = 0;
          for (int j = 0; j < mapStr.length; j++) {
            if (mapStr[j] == '{') depth++;
            if (mapStr[j] == '}') depth--;
            if (mapStr[j] == ',' && depth == 0) {
              pairs.add(mapStr.substring(pairStart, j).trim());
              pairStart = j + 1;
            }
          }
          pairs.add(mapStr.substring(pairStart).trim());

          for (String pair in pairs) {
            if (pair.contains(':')) {
              int colonIndex = pair.indexOf(':');
              String nestedKey = pair.substring(0, colonIndex).trim();
              String nestedValueStr = pair.substring(colonIndex + 1).trim();

              if (nestedValueStr == 'true') {
                nestedMap[nestedKey] = true;
              } else if (nestedValueStr == 'false') {
                nestedMap[nestedKey] = false;
              } else {
                nestedMap[nestedKey] = nestedValueStr;
              }
            }
          }
          value = nestedMap;
        } else {
          // Es un valor simple - buscar hasta la próxima coma o final
          int valueStart = i;
          int depth = 0;
          while (i < cleaned.length) {
            if (cleaned[i] == '{' || cleaned[i] == '[') depth++;
            if (cleaned[i] == '}' || cleaned[i] == ']') depth--;
            if (cleaned[i] == ',' && depth == 0) break;
            i++;
          }

          String valueStr = cleaned.substring(valueStart, i).trim();
          if (valueStr.contains(':') && valueStr.contains('.')) {
            // Es un Duration
            value = parseDurationString(valueStr);
          } else {
            value = valueStr;
          }
        }

        result[key] = value;

        // Saltar la coma si existe
        if (i < cleaned.length && cleaned[i] == ',') i++;

        // Saltar espacios
        while (i < cleaned.length && cleaned[i] == ' ') {
          i++;
        }
      }

      return result;
    }
  } catch (e) {
    printLog.e('Error parseando map string: $e');
  }

  return {};
}

/// Parsea un string de Duration en formato "0:00:30.000000" de vuelta a Duration
Duration parseDurationString(String durationStr) {
  try {
    List<String> parts = durationStr.split(':');
    if (parts.length >= 3) {
      int hours = int.parse(parts[0]);
      int minutes = int.parse(parts[1]);
      double seconds = double.parse(parts[2]);

      return Duration(
        hours: hours,
        minutes: minutes,
        seconds: seconds.floor(),
        microseconds: ((seconds - seconds.floor()) * 1000000).round(),
      );
    }
  } catch (e) {
    printLog.e('Error parseando duration: $e');
  }
  return Duration.zero;
}
//*- Funciones de parsing para Maps y Duration -*\\

///*-Global Connection Manager-*\\\

/// Inicia el listener global para el estado de conexión del dispositivo
void setupGlobalConnectionListener() {
  globalConnectionSubscription?.cancel();

  globalConnectionSubscription = bluetoothManager.device.connectionState.listen(
    (BluetoothConnectionState state) {
      printLog.i('Estado de conexión global: $state');

      if (state == BluetoothConnectionState.disconnected) {
        printLog.i('Dispositivo desconectado - Manejador global');

        printLog.d('¿Es acción rápida? $quickAction');

        // Check if this is not a quick action and show toast
        if (!quickAction) {
          showToast('Dispositivo desconectado');
        }

        // Limpiar variables globales
        cleanGlobalDeviceVariables();

        // Navigate to menu if not in quick action mode
        if (!quickAction) {
          navigatorKey.currentState?.pushReplacementNamed('/menu');
        }
      }
    },
  );
}

/// Cancela el listener global de conexión
void cancelGlobalConnectionListener() {
  globalConnectionSubscription?.cancel();
  globalConnectionSubscription = null;
}

/// Limpia todas las variables globales relacionadas con el dispositivo
void cleanGlobalDeviceVariables() {
  nameOfWifi = '';
  connectionFlag = false;
  deviceName = '';
  toolsValues = [];
  varsValues = [];
  ioValues = [];
  infoValues = [];
  hardwareVersion = '';
  softwareVersion = '';
  canUseDevice = true;
  printLog.i('Variables globales del dispositivo limpiadas');
}

///*-Global Connection Manager-*\\\

//*- PrintLogHistorial -*\\
bool shouldSaveLog(String email) {
  final loglUsers = (dbData['LogEmail'] as List<dynamic>?)
      ?.map((e) => e.toString().toLowerCase())
      .toList();
  if (loglUsers == null) return false;
  return loglUsers.contains(email.toLowerCase());
}

String stringifyPrintLog(dynamic message) {
  final finalMessage = message is Function ? message() : message;
  if (finalMessage is Map || finalMessage is Iterable) {
    var encoder = JsonEncoder.withIndent('  ', (dynamic object) {
      return object.toString();
    });
    return encoder.convert(finalMessage);
  } else {
    return finalMessage.toString();
  }
}
//*- PrintLogHistorial -*\\

//*- Logger ble -*\\
/// Variable global para controlar la suscripción al registerLogger
StreamSubscription<List<int>>? registerLoggerSubscription;

/// Timestamp de cuando se inició la sesión de captura de logs
int? sessionTimestamp;

/// Función para decodificar MessagePack
dynamic decodeMessagePack(List<int> data) {
  try {
    // Convertimos List<int> a Uint8List para MessagePack
    final uint8Data = Uint8List.fromList(data);

    // Usar la librería msgpack_dart para deserializar
    // En este punto msgpack_dart debe estar instalado
    // Si no está instalado, ejecutar: flutter pub add msgpack_dart
    final result = deserialize(uint8Data);
    return result;
  } catch (e) {
    // Si falla MessagePack, intentamos como UTF-8
    try {
      String textData = utf8.decode(data, allowMalformed: true);
      textData = textData.trim();

      if (textData.isNotEmpty && !textData.contains('\uFFFD')) {
        // Si parece JSON, intentamos parsearlo
        if (textData.startsWith('{') || textData.startsWith('[')) {
          try {
            return jsonDecode(textData);
          } catch (e) {
            return textData;
          }
        }
        return textData;
      }
    } catch (e) {
      // Si UTF-8 también falla, continuamos
    }

    // Como último recurso, mostramos información de debug
    String hexData =
        data.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');
    String asciiData = data
        .map((byte) =>
            (byte >= 32 && byte <= 126) ? String.fromCharCode(byte) : '.')
        .join('');

    printLog.e('Error decodificando MessagePack: $e');
    printLog.i('Datos HEX: $hexData');
    printLog.i('Datos ASCII: $asciiData');

    return {
      'error': 'Error decodificando datos',
      'raw_hex': hexData,
      'raw_ascii': asciiData,
      'exception': e.toString()
    };
  }
}

/// Función para formatear los datos del log antes de guardar
Map<String, dynamic> formatLogData(dynamic logData) {
  try {
    String content = 'Datos inválidos';
    String level = 'INFO';
    int timestampMs = DateTime.now().millisecondsSinceEpoch;

    // Si es un mapa (JSON decodificado), extraemos la información
    if (logData is Map) {
      // Extraer el contenido
      content = logData['content']?.toString() ??
          logData['message']?.toString() ??
          logData['msg']?.toString() ??
          logData['text']?.toString() ??
          'Sin contenido';

      // Extraer el nivel de log
      level = logData['log_level']?.toString() ??
          logData['level']?.toString() ??
          logData['lvl']?.toString() ??
          logData['severity']?.toString() ??
          'INFO';

      // Extraer el timestamp (siempre viene en milisegundos)
      if (logData['timestamp'] != null) {
        try {
          timestampMs = int.parse(logData['timestamp'].toString());
        } catch (e) {
          // Si falla el parsing, usar tiempo actual
          timestampMs = DateTime.now().millisecondsSinceEpoch;
        }
      }
    }
    // Si es un string directo
    else if (logData is String) {
      content = logData;
    }
    // Para otros tipos
    else {
      content = logData.toString();
    }

    return {
      'content': content,
      'level': level.toUpperCase(),
      'timestamp': timestampMs,
    };
  } catch (e) {
    return {
      'content': 'Error formateando: $e',
      'level': 'ERROR',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }
}

/// Se suscribe a la característica de registerLoggerUuid y guarda los datos en DynamoDB
void getRecordedData(String dvName) async {
  if (!bluetoothManager.hasLoggerBle) {
    printLog.i('El dispositivo no tiene servicio de logger BLE');
    return;
  }

  try {
    // Si ya hay una suscripción activa, cancelarla primero
    await registerLoggerSubscription?.cancel();

    // Asegurarse de que las notificaciones estén habilitadas
    await bluetoothManager.registerLoggerUuid.setNotifyValue(true);

    // Obtener información del dispositivo
    final String pc = DeviceManager.getProductCode(dvName);
    final String sn = DeviceManager.extractSerialNumber(dvName);

    // Crear timestamp de sesión (momento de conexión)
    sessionTimestamp = DateTime.now().millisecondsSinceEpoch;

    printLog.i(
        'Iniciando suscripción a registerLogger para $pc/$sn con timestamp de sesión: $sessionTimestamp');

    // Suscribirse a la característica
    registerLoggerSubscription =
        bluetoothManager.registerLoggerUuid.onValueReceived.listen(
      (data) async {
        if (data.isNotEmpty) {
          try {
            final decoded = decodeMessagePack(data);
            List<Map<String, dynamic>> logsToSave = [];

            // Si es una lista de logs, procesamos cada uno
            if (decoded is List) {
              for (var logEntry in decoded) {
                final formattedLog = formatLogData(logEntry);
                logsToSave.add(formattedLog);
              }
            } else {
              // Si es un solo entry, lo agregamos a la lista
              final formattedLog = formatLogData(decoded);
              logsToSave.add(formattedLog);
            }

            // Guardar todos los logs de esta lectura en DynamoDB
            if (logsToSave.isNotEmpty) {
              await saveDeviceRegisterLog(
                pc,
                sn,
                sessionTimestamp!,
                logsToSave,
              );
              printLog.i(
                  'Se guardaron ${logsToSave.length} registros en DynamoDB para $pc/$sn bajo timestamp $sessionTimestamp');
            }
          } catch (e) {
            printLog.e('Error procesando datos del registerLogger: $e');
          }
        }
      },
      onError: (error) {
        printLog.e('Error en suscripción del registro: $error');
      },
      cancelOnError: false,
    );

    // Asegurarse de que las notificaciones estén habilitadas
    await bluetoothManager.registerLoggerUuid.setNotifyValue(true);

    printLog.i('Suscripción al registerLogger iniciada correctamente');
  } catch (e) {
    printLog.e('Error iniciando suscripción del registerLogger: $e');
  }
}

/// Detiene la suscripción al registerLogger
void stopRecordedData() async {
  try {
    await registerLoggerSubscription?.cancel();
    registerLoggerSubscription = null;
    sessionTimestamp = null;

    if (bluetoothManager.hasLoggerBle) {
      await bluetoothManager.registerLoggerUuid.setNotifyValue(false);
    }

    printLog.i('Desuscrito del registerLogger');
  } catch (e) {
    printLog.e('Error deteniendo suscripción del registerLogger: $e');
  }
}
//*- Logger ble -*\\

//*- Extraer coordenadas -*\\
Map<String, double>? extractCoordinates(String locationString) {
  try {
    // Formato esperado: "Latitude: -34.6233784, Longitude: -58.5565867"
    final latMatch =
        RegExp(r'Latitude:\s*([-+]?\d+\.?\d*)').firstMatch(locationString);
    final lonMatch =
        RegExp(r'Longitude:\s*([-+]?\d+\.?\d*)').firstMatch(locationString);

    if (latMatch != null && lonMatch != null) {
      final lat = double.parse(latMatch.group(1)!);
      final lon = double.parse(lonMatch.group(1)!);
      return {'lat': lat, 'lon': lon};
    }
    return null;
  } catch (e) {
    printLog.e('Error extrayendo coordenadas: $e');
    return null;
  }
}
//*- Extraer coordenadas -*\\

// // -------------------------------------------------------------------------------------------------------------\\ \\

//! CLASES !\\

//*- Funciones relacionadas a los equipos*-\\
class DeviceManager {
  ///Extrae el número de serie desde el deviceName
  static String extractSerialNumber(String productName) {
    RegExp regExp = RegExp(r'(\d{8})');

    Match? match = regExp.firstMatch(productName);

    return match?.group(0) ?? '';
  }

  ///Conseguir el código de producto en base al deviceName
  static String getProductCode(String device) {
    Map<String, String> data = (dbData['PC'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(
        key,
        value.toString(),
      ),
    );
    String cmd = '';
    for (String key in data.keys) {
      if (device.contains(key)) {
        cmd = data[key].toString();
      }
    }
    return cmd;
  }

  ///Recupera el deviceName en base al productCode y al SerialNumber
  static String recoverDeviceName(String pc, String sn) {
    Map<String, String> data = (dbData['PC'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(
        key,
        value.toString(),
      ),
    );

    String code = '';
    for (String key in data.keys) {
      if (data[key] == pc) {
        code = key;
        break;
      }
    }

    return '$code$sn';
  }

  ///Devuelve un nombre común para los usuarios
  static String getComercialName(String name) {
    String pc = DeviceManager.getProductCode(name);
    Map<String, String> data = (dbData['CN'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(
        key,
        value.toString(),
      ),
    );
    String cn = '';
    for (String key in data.keys) {
      if (pc.contains(key)) {
        cn = data[key].toString();
      }
    }
    return cn;
  }

  ///Recupera la data de GENERALDATA de DynamoDB para que funcione la clase
  static FutureOr<void> init() async {
    try {
      Map<String, dynamic> data = await getGeneralData();
      dbData = data;
    } catch (e) {
      printLog.e("Error al leer GENERALDATA: $e");
      dbData = {};
    }
  }
}
//*- Funciones relacionadas a los equipos*-\\

//*-BLE, configuraciones del equipo-*\\
class BluetoothManager {
  static final BluetoothManager _singleton = BluetoothManager._internal();

  factory BluetoothManager() {
    return _singleton;
  }

  BluetoothManager._internal();

  late BluetoothDevice device;
  late BluetoothCharacteristic infoUuid;
  late BluetoothCharacteristic registerLoggerUuid;
  late BluetoothCharacteristic toolsUuid;
  late BluetoothCharacteristic otaUuid;
  late BluetoothCharacteristic varsUuid;
  late BluetoothCharacteristic workUuid;
  late BluetoothCharacteristic lightUuid;
  late BluetoothCharacteristic ioUuid;

  bool hasLoggerBle = false;

  Future<bool> setup(BluetoothDevice connectedDevice) async {
    try {
      device = connectedDevice;

      List<BluetoothService> services =
          await device.discoverServices(timeout: 3);
      // printLog.i('Los servicios: $services');

      try {
        BluetoothService loggerService = services.firstWhere(
            (s) => s.uuid == Guid('ad04c0c7-6a98-4ab7-a29c-4c59ef1d0077'));
        registerLoggerUuid = loggerService.characteristics.firstWhere(
            (c) => c.uuid == Guid('b6abd12d-9b1c-452e-875d-28f99421e17a'));
        hasLoggerBle = true;
      } catch (e) {
        printLog.i("Error al configurar los loggers: $e");
        hasLoggerBle = false;
      }

      BluetoothService infoService = services.firstWhere(
          (s) => s.uuid == Guid('6a3253b4-48bc-4e97-bacd-325a1d142038'));
      infoUuid = infoService.characteristics.firstWhere((c) =>
          c.uuid ==
          Guid(
              'fc5c01f9-18de-4a75-848b-d99a198da9be')); //ProductType:SerialNumber:SoftVer:HardVer:Owner
      toolsUuid = infoService.characteristics.firstWhere((c) =>
          c.uuid ==
          Guid(
              '89925840-3d11-4676-bf9b-62961456b570')); //WifiStatus:WifiSSID/WifiError:BleStatus(users)

      infoValues = await infoUuid.read();
      String str = utf8.decode(infoValues);
      var partes = str.split(':');
      softwareVersion = partes[2];
      hardwareVersion = partes[3];
      factoryMode = softwareVersion.contains('_F');
      printLog.i(
          'Product code: ${DeviceManager.getProductCode(device.platformName)}',
          color: 'cyan');
      printLog.i(
          'Serial number: ${DeviceManager.extractSerialNumber(device.platformName)}',
          color: 'cyan');

      printLog.i("Hardware Version: $hardwareVersion", color: 'cyan');

      printLog.i("Software Version: $softwareVersion", color: 'cyan');

      globalDATA.putIfAbsent(
          '${DeviceManager.getProductCode(device.platformName)}/${DeviceManager.extractSerialNumber(device.platformName)}',
          () => {});

      switch (DeviceManager.getProductCode(device.platformName)) {
        case '022000_IOT' ||
              '027000_IOT' ||
              '028000_IOT' ||
              '023430_IOT' ||
              '027345_IOT':
          BluetoothService espService = services.firstWhere(
              (s) => s.uuid == Guid('6f2fa024-d122-4fa3-a288-8eca1af30502'));

          varsUuid = espService.characteristics.firstWhere((c) =>
              c.uuid ==
              Guid(
                  '52a2f121-a8e3-468c-a5de-45dca9a2a207')); //WorkingTemp:WorkingStatus:EnergyTimer:HeaterOn:NightMode
          otaUuid = espService.characteristics.firstWhere((c) =>
              c.uuid ==
              Guid(
                  'ae995fcd-2c7a-4675-84f8-332caf784e9f')); //Ota comandos (Solo notify)
          break;
        case '015773_IOT':
          BluetoothService service = services.firstWhere(
              (s) => s.uuid == Guid('dd249079-0ce8-4d11-8aa9-53de4040aec6'));

          workUuid = service.characteristics.firstWhere((c) =>
              c.uuid ==
              Guid(
                  '6869fe94-c4a2-422a-ac41-b2a7a82803e9')); //Array de datos (ppm,etc)
          lightUuid = service.characteristics.firstWhere((c) =>
              c.uuid == Guid('12d3c6a1-f86e-4d5b-89b5-22dc3f5c831f')); //No leo
          BluetoothService otaService = services.firstWhere(
              (s) => s.uuid == Guid('33e3a05a-c397-4bed-81b0-30deb11495c7'));
          otaUuid = otaService.characteristics.firstWhere((c) =>
              c.uuid ==
              Guid(
                  'ae995fcd-2c7a-4675-84f8-332caf784e9f')); //Ota comandos (Solo notify)

          break;
        case '020010_IOT' || '020020_IOT':
          BluetoothService service = services.firstWhere(
              (s) => s.uuid == Guid('6f2fa024-d122-4fa3-a288-8eca1af30502'));
          ioUuid = service.characteristics.firstWhere(
              (c) => c.uuid == Guid('03b1c5d9-534a-4980-aed3-f59615205216'));
          otaUuid = service.characteristics.firstWhere((c) =>
              c.uuid ==
              Guid(
                  'ae995fcd-2c7a-4675-84f8-332caf784e9f')); //Ota comandos (Solo notify)
          varsUuid = service.characteristics.firstWhere(
              (c) => c.uuid == Guid('52a2f121-a8e3-468c-a5de-45dca9a2a207'));
          break;
        case '027313_IOT':
          BluetoothService service = services.firstWhere(
              (s) => s.uuid == Guid('6f2fa024-d122-4fa3-a288-8eca1af30502'));
          ioUuid = service.characteristics.firstWhere(
              (c) => c.uuid == Guid('03b1c5d9-534a-4980-aed3-f59615205216'));
          otaUuid = service.characteristics.firstWhere((c) =>
              c.uuid ==
              Guid(
                  'ae995fcd-2c7a-4675-84f8-332caf784e9f')); //Ota comandos (Solo notify)
          varsUuid = service.characteristics.firstWhere(
              (c) => c.uuid == Guid('52a2f121-a8e3-468c-a5de-45dca9a2a207'));

          break;
        case '024011_IOT':
          BluetoothService espService = services.firstWhere(
              (s) => s.uuid == Guid('6f2fa024-d122-4fa3-a288-8eca1af30502'));

          varsUuid = espService.characteristics.firstWhere((c) =>
              c.uuid ==
              Guid(
                  '52a2f121-a8e3-468c-a5de-45dca9a2a207')); //DstCtrl:LargoRoller:InversionGiro:VelocidadMotor:PosicionActual:PosicionTrabajo:RollerMoving:AWSinit
          otaUuid = espService.characteristics.firstWhere((c) =>
              c.uuid ==
              Guid(
                  'ae995fcd-2c7a-4675-84f8-332caf784e9f')); //Ota comandos (Solo notify)
          break;
      }

      return Future.value(true);
    } catch (e, stackTrace) {
      printLog.e('Lcdtmbe $e $stackTrace');

      return Future.value(false);
    }
  }
}
//*-BLE, configuraciones del equipo-*\\

//*-Metodos, interacción con código Nativo-*\\
class NativeService {
  static const platform = MethodChannel('com.caldensmart.sime/native');

  static Future<void> isBluetoothServiceEnabled() async {
    try {
      final bool isBluetoothOn = await platform.invokeMethod('isBluetoothOn');

      if (!isBluetoothOn && !bleFlag) {
        bleFlag = true;
        final bool turnedOn = await platform.invokeMethod('turnOnBluetooth');

        if (turnedOn) {
          bleFlag = false;
        } else {
          printLog.i("El usuario rechazó encender Bluetooth");
        }
      }
    } on PlatformException catch (e) {
      android
          ? printLog.e("Error al verificar o encender Bluetooth: ${e.message}")
          : null;

      bleFlag = false;
    }
  }

  void playNativeSound(String soundName, int delay) {
    try {
      printLog.i("Invoking playSound with: $soundName");
      platform
          .invokeMethod('playSound', {'soundName': soundName, 'delay': delay});
    } on PlatformException catch (e) {
      printLog.e("Failed to play sound: '${e.message}'.");
    }
  }

  static Future<bool> isLocationServiceEnabled() async {
    try {
      final bool isEnabled =
          await platform.invokeMethod("isLocationServiceEnabled");
      return isEnabled;
    } on PlatformException catch (e) {
      printLog.e('Error verificando ubicación: $e');
      return false;
    }
  }

  static Future<void> openLocationOptions() async {
    try {
      await platform.invokeMethod("openLocationSettings");
    } on PlatformException catch (e) {
      printLog.e('Error abriendo la configuración de ubicación: $e');
    }
  }

  static Future<void> stopNativeSound() async {
    try {
      await platform.invokeMethod('stopSound');
    } catch (e) {
      printLog.e("Error al detener sonido: $e");
    }
  }
}
//*-Metodos, interacción con código Nativo-*\\

//*-Versionador, comparador de versiones-*\\
/// Clase para comparar y recuperar versiones de firmware,
/// incluyendo la obtención de la última subversión (SV),
/// el nombre del archivo .bin y la URL de descarga.
class Versioner {
  // ---------------------- CONFIGURACIÓN ----------------------
  static const String _owner = 'barberop';
  static const String _repo = 'sime-domotica';
  static const String _branch = 'main';

  // ---------------------- COMPARADORES ----------------------
  /// Compara si la primera versión (AAMMDDL) salió después o es igual a la segunda.
  static bool isPosterior(String myVersion, String versionToCompare) {
    try {
      final v1 = _parseVersion(myVersion);
      final v2 = _parseVersion(versionToCompare);
      if (v1.date.isAtSameMomentAs(v2.date)) {
        return v1.letter.compareTo(v2.letter) >= 0;
      }
      return v1.date.isAfter(v2.date);
    } catch (e) {
      // Si hay error en el parseado, asumimos que la versión no es posterior
      printLog.e(
          'Error comparing versions "$myVersion" vs "$versionToCompare": $e');
      return false;
    }
  }

  /// Compara si la primera versión salió antes que la segunda.
  static bool isPrevious(String myVersion, String versionToCompare) {
    try {
      final v1 = _parseVersion(myVersion);
      final v2 = _parseVersion(versionToCompare);
      if (v1.date.isAtSameMomentAs(v2.date)) {
        return v1.letter.compareTo(v2.letter) < 0;
      }
      return v1.date.isBefore(v2.date);
    } catch (e) {
      // Si hay error en el parseado, asumimos que la versión no es anterior
      printLog.e(
          'Error comparing versions "$myVersion" vs "$versionToCompare": $e');
      return false;
    }
  }

  // ---------------------- PARSEADO ----------------------
  /// Auxiliar para parsear AAMMDD(Letra) en DateTime y letra.
  static _VersionData _parseVersion(String version) {
    // Validar que la versión tenga al menos 7 caracteres (AAMMDDL)
    if (version == '') {
      version = '999999A';
    }

    try {
      final yy = int.parse('20${version.substring(0, 2)}');
      final mm = int.parse(version.substring(2, 4));
      final dd = int.parse(version.substring(4, 6));
      final letter = version.substring(6, 7);
      return _VersionData(DateTime(yy, mm, dd), letter);
    } catch (e) {
      printLog.e('Error parsing version $version: $e');
      throw FormatException('Error parsing version $version: $e');
    }
  }

  // ---------------------- LISTADO Y OBTENCIÓN ----------------------

  /// Lista los archivos .bin en GitHub bajo OTA_FW/W y devuelve
  /// el nombre del archivo con la última subversión cuyo prefijo
  /// coincida EXACTAMENTE con la versión de hardware (hwVersion) recibida.
  ///
  /// [productCode]: Carpeta del producto (ej. '015773_IOT').
  /// [hwVersion]: Fecha+letra de hardware (ej. '240214A').
  static Future<String> fetchLatestFirmwareFile(
      String productCode, String hwVersion) async {
    // Nos aseguramos de quitar espacios extras y mantener el case original.
    final sanitizedHw = hwVersion.trim();
    final prefix = 'hv${sanitizedHw}sv';
    printLog.i('Prefix hardware: $prefix');

    final path = '$productCode/OTA_FW/W';
    final uri = Uri.https(
      'api.github.com',
      '/repos/$_owner/$_repo/contents/$path',
      {'ref': _branch},
    );
    printLog.i('Fetching OTA_FW/W from: $uri');
    final response = await http.get(uri, headers: {
      'Authorization': 'Bearer $githubToken',
      'Accept': 'application/vnd.github.v3+json',
    });
    printLog.i('GitHub API status: ${response.statusCode}');
    if (response.statusCode != 200) {
      printLog.e('Error listing OTA_FW/W: ${response.body}');
      throw Exception('Error al listar OTA_FW/W: ${response.statusCode}');
    }

    final List<dynamic> items = jsonDecode(response.body);
    final firmwareFiles = <String>[];

    for (final item in items) {
      if (item['type'] == 'file') {
        final name = item['name'] as String;
        // Comprobamos que el nombre empiece exactamente con el prefijo y termine en ".bin"
        final matchesPrefix = name.startsWith(prefix);
        final isBin = name.endsWith('.bin');
        // printLog.i(
        //     'Found item: $name (startsWith prefix? $matchesPrefix, endsWith .bin? $isBin)');
        if (matchesPrefix && isBin) {
          firmwareFiles.add(name);
        }
      }
    }

    if (firmwareFiles.isEmpty) {
      printLog.i(
          'No matching firmware found for HW $sanitizedHw with prefix $prefix');
      throw Exception('No se encontró firmware para HW $sanitizedHw');
    }

    // Ordenamos alfabéticamente para que el último tenga la subversión más alta.
    firmwareFiles.sort();
    final latest = firmwareFiles.last;
    printLog.i('Latest firmware file: $latest');
    return latest;
  }

  /// A partir del nombre de archivo devuelto por fetchLatestFirmwareFile,
  /// extrae y retorna solo la subversión (SV) sin prefijos ni extensión.
  /// Ejemplo: de 'hv240214Asv240528H.bin' devuelve '240528H'.
  static String extractSV(String firmwareFileName, String hwVersion) {
    printLog
        .i('Extracting SV from $firmwareFileName for HW version $hwVersion');
    final prefix = 'hv${hwVersion}sv';
    return firmwareFileName.replaceFirst(prefix, '').replaceFirst('.bin', '');
  }

  /// Construye la URL raw de GitHub para la última versión de firmware.
  static String buildFirmwareUrl(String productCode, String firmwareFileName) {
    return 'https://raw.githubusercontent.com/$_owner/$_repo/$_branch/'
        '$productCode/OTA_FW/W/$firmwareFileName';
  }
}

/// Datos internos de versión.
class _VersionData {
  final DateTime date;
  final String letter;
  _VersionData(this.date, this.letter);
}

//*-Versionador, comparador de versiones-*\\

//*-Gestión centralizada de tokens-*\\
class TokenManager {
  /// Configura el token del usuario para todos sus dispositivos (llamar desde menu)
  static Future<void> setupUserTokens() async {
    try {
      printLog.i('Configurando tokens para el usuario...');

      // Si es iOS, verificar APNS primero
      if (!android) {
        final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        printLog.i("Token APNS: $apnsToken");
        if (apnsToken == null) {
          printLog.e("Error al obtener el APNS");
          return;
        }
      }

      // Obtener token actual de Firebase
      String? currentToken = await FirebaseMessaging.instance.getToken();
      if (currentToken == null) {
        printLog.e('No se pudo obtener el token de Firebase');
        return;
      }

      printLog.i('Token actual del usuario: $currentToken');

      String userEmail = currentUserEmail;
      if (userEmail.isEmpty) {
        printLog.e('No hay usuario logueado');
        return;
      }

      // Obtener tokens actuales del usuario desde Alexa-Devices
      List<String> userTokens = await getTokensFromAlexaDevices(userEmail);
      String oldToken = await loadToken();

      // Actualizar token local si es diferente
      if (oldToken != currentToken) {
        await saveToken(currentToken);
        printLog.i('Token local actualizado');

        // Eliminar token antiguo de la lista si existe
        if (userTokens.contains(oldToken)) {
          userTokens.remove(oldToken);
          printLog
              .i('Token antiguo eliminado de alexa-devices para $userEmail');
        }
      }

      // Añadir nuevo token solo si no existe
      if (!userTokens.contains(currentToken)) {
        userTokens.add(currentToken);
        printLog.i('Token añadido a alexa-devices para $userEmail');
      }

      await putTokensInAlexaDevicesGuarded(userEmail, userTokens, currentToken);

      printLog.i('Setup de tokens del usuario completado');
    } catch (e, s) {
      printLog.e('Error en setup de tokens del usuario: $e');
      printLog.t('Stack trace: $s');
    }
  }
}
//*-Gestión centralizada de tokens-*\\

//*-Provider, actualización de data en un widget-*\\

class GlobalDataNotifier
    extends StateNotifier<Map<String, Map<String, dynamic>>> {
  GlobalDataNotifier() : super({});

  // Obtener datos por topic específico
  Map<String, dynamic> getData(String topic) {
    return state[topic] ?? {};
  }

  // Actualizar datos para un topic específico y notificar a los oyentes
  void updateData(String topic, Map<String, dynamic> newData) {
    final current = Map<String, dynamic>.from(state[topic] ?? {});
    current.addAll(newData);
    state = {
      ...state,
      topic: current,
    };
  }
}

class WifiState {
  final String status;
  final Color statusColor;
  final dynamic wifiIcon;

  const WifiState({
    this.status = 'DESCONECTADO',
    this.statusColor = Colors.red,
    this.wifiIcon = HugeIcons.strokeRoundedWifiOff02,
  });

  WifiState copyWith({
    String? status,
    Color? statusColor,
    dynamic wifiIcon,
  }) {
    return WifiState(
      status: status ?? this.status,
      statusColor: statusColor ?? this.statusColor,
      wifiIcon: wifiIcon ?? this.wifiIcon,
    );
  }
}

class WifiNotifier extends StateNotifier<WifiState> {
  WifiNotifier() : super(const WifiState());

  void updateStatus(String status, Color statusColor, dynamic wifiIcon) {
    state = state.copyWith(
      status: status,
      statusColor: statusColor,
      wifiIcon: wifiIcon,
    );
  }
}

//*-Provider, actualización de data en un widget-*\\

//*-QR Scan, lee datos de qr wifi-*\\
class QRScanPage extends StatefulWidget {
  const QRScanPage({super.key});
  @override
  QRScanPageState createState() => QRScanPageState();
}

class QRScanPageState extends State<QRScanPage>
    with SingleTickerProviderStateMixin {
  Barcode? result;
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  MobileScannerController controller = MobileScannerController();
  AnimationController? animationController;
  bool flashOn = false;
  late Animation<double> animation;

  @override
  void initState() {
    super.initState();

    animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    animation = Tween<double>(begin: 10, end: 350).animate(animationController!)
      ..addListener(() {
        setState(() {});
      });

    animationController!.repeat(reverse: true);
  }

  @override
  void dispose() {
    controller.dispose();
    animationController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        MobileScanner(
          controller: controller,
          onDetect: (
            barcode,
          ) {
            setState(() {
              result = barcode.barcodes.first;
            });
            if (result != null) {
              qrResult = result!.rawValue;
              Navigator.of(context).pop();
            }
          },
        ),
        // Arriba
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 250,
          child: Container(
              color: Colors.black54,
              child: const Center(
                child: Text(
                  'Escanea el QR',
                  style: TextStyle(
                    color: Color(0xFFB2B5AE),
                  ),
                ),
              )),
        ),
        // Abajo
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 250,
          child: Container(
            color: Colors.black54,
          ),
        ),
        // Izquierda
        Positioned(
          top: 250,
          bottom: 250,
          left: 0,
          width: 50,
          child: Container(
            color: Colors.black54,
          ),
        ),
        // Derecha
        Positioned(
          top: 250,
          bottom: 250,
          right: 0,
          width: 50,
          child: Container(
            color: Colors.black54,
          ),
        ),
        // Área transparente con bordes redondeados
        Positioned(
          top: 250,
          left: 50,
          right: 50,
          bottom: 250,
          child: Stack(
            children: [
              Positioned(
                top: animation.value,
                left: 0,
                right: 0,
                child: Container(
                  height: 4,
                  color: const Color(0xFF1E242B),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 3,
                  color: const Color(0xFFB2B5AE),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 3,
                  color: const Color(0xFFB2B5AE),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                child: Container(
                  width: 3,
                  color: const Color(0xFFB2B5AE),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                child: Container(
                  width: 3,
                  color: const Color(0xFFB2B5AE),
                ),
              ),
            ],
          ),
        ),
        // Botón de Flash
        Positioned(
          bottom: 20,
          right: 20,
          child: IconButton(
            icon: Icon(
              controller.torchEnabled
                  ? HugeIcons.strokeRoundedFlash
                  : HugeIcons.strokeRoundedFlashOff,
            ),
            onPressed: () => controller.toggleTorch(),
          ),
        ),
      ]),
    );
  }
}
//*-QR Scan, lee datos de qr wifi-*\\

//*-CurvedNativationAppBar*-\\
class CurvedNavigationBar extends StatefulWidget {
  final List<Widget> items;
  final int index;
  final Color color;
  final Color? buttonBackgroundColor;
  final Color backgroundColor;
  final ValueChanged<int>? onTap;
  final LetIndexPage letIndexChange;
  final Curve animationCurve;
  final Duration animationDuration;
  final double height;
  final double? maxWidth;

  CurvedNavigationBar({
    super.key,
    required this.items,
    this.index = 0,
    this.color = Colors.white,
    this.buttonBackgroundColor,
    this.backgroundColor = Colors.blueAccent,
    this.onTap,
    LetIndexPage? letIndexChange,
    this.animationCurve = Curves.easeOut,
    this.animationDuration = const Duration(milliseconds: 600),
    this.height = 75.0,
    this.maxWidth,
  })  : letIndexChange = letIndexChange ?? ((_) => true),
        assert(items.isNotEmpty),
        assert(0 <= index && index < items.length),
        assert(0 <= height && height <= 75.0),
        assert(maxWidth == null || 0 <= maxWidth);

  @override
  CurvedNavigationBarState createState() => CurvedNavigationBarState();
}

class CurvedNavigationBarState extends State<CurvedNavigationBar>
    with SingleTickerProviderStateMixin {
  late double _startingPos;
  late int _endingIndex;
  late double _pos;
  double _buttonHide = 0;
  late Widget _icon;
  late AnimationController _animationController;
  late int _length;

  @override
  void initState() {
    super.initState();
    _icon = widget.items[widget.index];
    _length = widget.items.length;
    _pos = widget.index / _length;
    _startingPos = widget.index / _length;
    _endingIndex = widget.index;
    _animationController = AnimationController(vsync: this, value: _pos);
    _animationController.addListener(() {
      setState(() {
        _pos = _animationController.value;
        final endingPos = _endingIndex / widget.items.length;
        final middle = (endingPos + _startingPos) / 2;
        if ((endingPos - _pos).abs() < (_startingPos - _pos).abs()) {
          _icon = widget.items[_endingIndex];
        }
        _buttonHide =
            (1 - ((middle - _pos) / (_startingPos - middle)).abs()).abs();
      });
    });
  }

  @override
  void didUpdateWidget(CurvedNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      final newPosition = widget.index / _length;
      _startingPos = _pos;
      _endingIndex = widget.index;
      _animationController.animateTo(newPosition,
          duration: widget.animationDuration, curve: widget.animationCurve);
    }
    if (!_animationController.isAnimating) {
      _icon = widget.items[_endingIndex];
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = min(
              constraints.maxWidth, widget.maxWidth ?? constraints.maxWidth);
          return Align(
            alignment: textDirection == TextDirection.ltr
                ? Alignment.bottomLeft
                : Alignment.bottomRight,
            child: Container(
              color: widget.backgroundColor,
              width: maxWidth,
              child: ClipRect(
                clipper: NavCustomClipper(
                  deviceHeight: MediaQuery.sizeOf(context).height,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: <Widget>[
                    Positioned(
                      bottom: -40 - (75.0 - widget.height),
                      left: textDirection == TextDirection.rtl
                          ? null
                          : _pos * maxWidth,
                      right: textDirection == TextDirection.rtl
                          ? _pos * maxWidth
                          : null,
                      width: maxWidth / _length,
                      child: Center(
                        child: Transform.translate(
                          offset: Offset(
                            0,
                            -(1 - _buttonHide) * 80,
                          ),
                          child: Material(
                            color: widget.buttonBackgroundColor ?? widget.color,
                            type: MaterialType.circle,
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: _icon,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0 - (75.0 - widget.height),
                      child: CustomPaint(
                        painter: NavCustomPainter(
                            _pos, _length, widget.color, textDirection),
                        child: Container(
                          height: 75.0,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0 - (75.0 - widget.height),
                      child: SizedBox(
                        height: 100.0,
                        child: Row(
                          children: widget.items.map((item) {
                            return NavButton(
                              onTap: _buttonTap,
                              position: _pos,
                              length: _length,
                              index: widget.items.indexOf(item),
                              child: Center(child: item),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void setPage(int index) {
    _buttonTap(index);
  }

  void _buttonTap(int index) {
    if (!widget.letIndexChange(index) || _animationController.isAnimating) {
      return;
    }
    if (widget.onTap != null) {
      widget.onTap!(index);
    }
    final newPosition = index / _length;
    setState(() {
      _startingPos = _pos;
      _endingIndex = index;
      _animationController.animateTo(newPosition,
          duration: widget.animationDuration, curve: widget.animationCurve);
    });
  }
}

class NavCustomPainter extends CustomPainter {
  late double loc;
  late double s;
  Color color;
  TextDirection textDirection;

  NavCustomPainter(
      double startingLoc, int itemsLength, this.color, this.textDirection) {
    final span = 1.0 / itemsLength;
    s = 0.2;
    double l = startingLoc + (span - s) / 2;
    loc = textDirection == TextDirection.rtl ? 0.8 - l : l;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo((loc - 0.1) * size.width, 0)
      ..cubicTo(
        (loc + s * 0.20) * size.width,
        size.height * 0.05,
        loc * size.width,
        size.height * 0.60,
        (loc + s * 0.50) * size.width,
        size.height * 0.60,
      )
      ..cubicTo(
        (loc + s) * size.width,
        size.height * 0.60,
        (loc + s - s * 0.20) * size.width,
        size.height * 0.05,
        (loc + s + 0.1) * size.width,
        0,
      )
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return this != oldDelegate;
  }
}

class NavButton extends StatelessWidget {
  final double position;
  final int length;
  final int index;
  final ValueChanged<int> onTap;
  final Widget child;

  const NavButton({
    super.key,
    required this.onTap,
    required this.position,
    required this.length,
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final desiredPosition = 1.0 / length * index;
    final difference = (position - desiredPosition).abs();
    final verticalAlignment = 1 - length * difference;
    final opacity = length * difference;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          onTap(index);
        },
        child: SizedBox(
          height: 75.0,
          child: Transform.translate(
            offset: Offset(
                0, difference < 1.0 / length ? verticalAlignment * 40 : 0),
            child: Opacity(
                opacity: difference < 1.0 / length * 0.99 ? opacity : 1.0,
                child: child),
          ),
        ),
      ),
    );
  }
}

class NavCustomClipper extends CustomClipper<Rect> {
  final double deviceHeight;

  NavCustomClipper({required this.deviceHeight});

  @override
  Rect getClip(Size size) {
    //Clip only the bottom of the widget
    return Rect.fromLTWH(
      0,
      -deviceHeight + size.height,
      size.width,
      deviceHeight,
    );
  }

  @override
  bool shouldReclip(NavCustomClipper oldClipper) {
    return oldClipper.deviceHeight != deviceHeight;
  }
}
//*-CurvedNativationAppBar*-\\

//*-AnimSearchBar*-\\
class AnimSearchBar extends StatefulWidget {
  final double width;
  final TextEditingController textController;
  final Icon? suffixIcon;
  final Icon? prefixIcon;
  final String helpText;
  final int animationDurationInMilli;
  final dynamic onSuffixTap;
  final bool rtl;
  final bool autoFocus;
  final TextStyle? style;
  final bool closeSearchOnSuffixTap;
  final Color? color;
  final Color? textFieldColor;
  final Color? searchIconColor;
  final Color? textFieldIconColor;
  final List<TextInputFormatter>? inputFormatters;
  final bool boxShadow;
  final Function(String) onSubmitted;

  const AnimSearchBar({
    super.key,

    /// The width cannot be null
    required this.width,

    /// The textController cannot be null
    required this.textController,
    this.suffixIcon,
    this.prefixIcon,
    this.helpText = "Search...",

    /// choose your custom color
    this.color = Colors.white,

    /// choose your custom color for the search when it is expanded
    this.textFieldColor = Colors.white,

    /// choose your custom color for the search when it is expanded
    this.searchIconColor = Colors.black,

    /// choose your custom color for the search when it is expanded
    this.textFieldIconColor = Colors.black,

    /// The onSuffixTap cannot be null
    required this.onSuffixTap,
    this.animationDurationInMilli = 375,

    /// The onSubmitted cannot be null
    required this.onSubmitted,

    /// make the search bar to open from right to left
    this.rtl = false,

    /// make the keyboard to show automatically when the searchbar is expanded
    this.autoFocus = false,

    /// TextStyle of the contents inside the searchbar
    this.style,

    /// close the search on suffix tap
    this.closeSearchOnSuffixTap = false,

    /// enable/disable the box shadow decoration
    this.boxShadow = true,

    /// can add list of inputformatters to control the input
    this.inputFormatters,
    required Null Function() onTap,
  });

  @override
  AnimSearchBarState createState() => AnimSearchBarState();
}

class AnimSearchBarState extends State<AnimSearchBar>
    with SingleTickerProviderStateMixin {
  ///initializing the AnimationController
  late AnimationController _con;
  FocusNode focusNode = FocusNode();

  @override
  void initState() {
    super.initState();

    ///Initializing the animationController which is responsible for the expanding and shrinking of the search bar
    _con = AnimationController(
      vsync: this,

      /// animationDurationInMilli is optional, the default value is 375
      duration: Duration(milliseconds: widget.animationDurationInMilli),
    );
  }

  @override
  void dispose() {
    _con.dispose();
    super.dispose();
  }

  unfocusKeyboard() {
    final FocusScopeNode currentScope = FocusScope.of(context);
    if (!currentScope.hasPrimaryFocus && currentScope.hasFocus) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100.0,

      ///if the rtl is true, search bar will be from right to left
      alignment:
          widget.rtl ? Alignment.centerRight : const Alignment(-1.0, 0.0),

      ///Using Animated container to expand and shrink the widget
      child: AnimatedContainer(
        duration: Duration(milliseconds: widget.animationDurationInMilli),
        height: 48.0,
        width: (toggle == 0) ? 48.0 : widget.width,
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          /// can add custom  color or the color will be white
          color: toggle == 1 ? widget.textFieldColor : widget.color,
          borderRadius: BorderRadius.circular(30.0),

          /// show boxShadow unless false was passed
          boxShadow: !widget.boxShadow
              ? null
              : [
                  const BoxShadow(
                    color: Colors.black26,
                    spreadRadius: -10.0,
                    blurRadius: 10.0,
                    offset: Offset(0.0, 10.0),
                  ),
                ],
        ),
        child: Stack(
          children: [
            ///Using Animated Positioned widget to expand and shrink the widget
            AnimatedPositioned(
              duration: Duration(milliseconds: widget.animationDurationInMilli),
              top: 6.0,
              right: 7.0,
              curve: Curves.easeOut,
              child: AnimatedOpacity(
                opacity: (toggle == 0) ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    /// can add custom color or the color will be white
                    color: widget.color,
                    borderRadius: BorderRadius.circular(30.0),
                  ),
                  child: AnimatedBuilder(
                    builder: (context, widget) {
                      ///Using Transform.rotate to rotate the suffix icon when it gets expanded
                      return Transform.rotate(
                        angle: _con.value * 2.0 * pi,
                        child: widget,
                      );
                    },
                    animation: _con,
                    child: GestureDetector(
                      onTap: () {
                        try {
                          ///trying to execute the onSuffixTap function
                          widget.onSuffixTap();

                          // * if field empty then the user trying to close bar
                          if (textFieldValue == '') {
                            unfocusKeyboard();
                            setState(() {
                              toggle = 0;
                            });

                            ///reverse == close
                            _con.reverse();
                          }

                          // * why not clear textfield here?
                          widget.textController.clear();
                          textFieldValue = '';

                          ///closeSearchOnSuffixTap will execute if it's true
                          if (widget.closeSearchOnSuffixTap) {
                            unfocusKeyboard();
                            setState(() {
                              toggle = 0;
                            });
                          }
                        } catch (e) {
                          ///print the error if the try block fails
                          printLog.e(e);
                        }
                      },

                      ///suffixIcon is of type Icon
                      child: widget.suffixIcon ??
                          Icon(
                            HugeIcons.strokeRoundedCancel01,
                            size: 20.0,
                            color: widget.textFieldIconColor,
                          ),
                    ),
                  ),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: Duration(milliseconds: widget.animationDurationInMilli),
              left: (toggle == 0) ? 20.0 : 40.0,
              curve: Curves.easeOut,
              top: 11.0,

              ///Using Animated opacity to change the opacity of th textField while expanding
              child: AnimatedOpacity(
                opacity: (toggle == 0) ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.only(left: 10),
                  alignment: Alignment.topCenter,
                  width: widget.width / 1.7,
                  child: TextField(
                    ///Text Controller. you can manipulate the text inside this textField by calling this controller.
                    controller: widget.textController,
                    inputFormatters: widget.inputFormatters,
                    focusNode: focusNode,
                    cursorRadius: const Radius.circular(10.0),
                    cursorWidth: 2.0,
                    onChanged: (value) {
                      textFieldValue = value;
                    },
                    onSubmitted: (value) => {
                      widget.onSubmitted(value),
                      unfocusKeyboard(),
                      setState(() {
                        toggle = 0;
                      }),
                      widget.textController.clear(),
                    },
                    onEditingComplete: () {
                      /// on editing complete the keyboard will be closed and the search bar will be closed
                      unfocusKeyboard();
                      setState(() {
                        toggle = 0;
                      });
                    },

                    ///style is of type TextStyle, the default is just a color black
                    style: widget.style ?? const TextStyle(color: Colors.black),
                    cursorColor: Colors.black,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.only(bottom: 5),
                      isDense: true,
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                      labelText: widget.helpText,
                      labelStyle: const TextStyle(
                        color: Color(0xff5B5B5B),
                        fontSize: 17.0,
                        fontWeight: FontWeight.w500,
                      ),
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20.0),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            ///Using material widget here to get the ripple effect on the prefix icon
            Material(
              /// can add custom color or the color will be white
              /// toggle button color based on toggle state
              color: toggle == 0 ? widget.color : widget.textFieldColor,
              borderRadius: BorderRadius.circular(30.0),
              child: IconButton(
                splashRadius: 19.0,

                ///if toggle is 1, which means it's open. so show the back icon, which will close it.
                ///if the toggle is 0, which means it's closed, so tapping on it will expand the widget.
                ///prefixIcon is of type Icon
                icon: widget.prefixIcon != null
                    ? toggle == 1
                        ? Icon(
                            HugeIcons.strokeRoundedArrowLeft01,
                            color: widget.textFieldIconColor,
                          )
                        : widget.prefixIcon!
                    : Icon(
                        toggle == 1
                            ? HugeIcons.strokeRoundedArrowLeft01
                            : HugeIcons.strokeRoundedSearch01,
                        // search icon color when closed
                        color: toggle == 0
                            ? widget.searchIconColor
                            : widget.textFieldIconColor,
                        size: 20.0,
                      ),
                onPressed: () {
                  setState(
                    () {
                      ///if the search bar is closed
                      if (toggle == 0) {
                        toggle = 1;
                        setState(() {
                          ///if the autoFocus is true, the keyboard will pop open, automatically
                          if (widget.autoFocus) {
                            FocusScope.of(context).requestFocus(focusNode);
                          }
                        });

                        ///forward == expand
                        _con.forward();
                      } else {
                        ///if the search bar is expanded
                        toggle = 0;

                        ///if the autoFocus is true, the keyboard will close, automatically
                        setState(() {
                          if (widget.autoFocus) unfocusKeyboard();
                        });

                        ///reverse == close
                        _con.reverse();
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
//*-AnimSearchBar*-\\

//*-pantalla para usuario no autorizo a entrar al equipo-*\\
class AccessDeniedScreen extends StatelessWidget {
  const AccessDeniedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, A) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20.0),
                side: const BorderSide(color: color4, width: 2.0),
              ),
              backgroundColor: color1,
              content: Row(
                children: [
                  Image.asset('assets/branch/dragon.gif',
                      width: 100, height: 100),
                  Container(
                    margin: const EdgeInsets.only(left: 15),
                    child: const Text(
                      "Desconectando...",
                      style: TextStyle(
                        color: color0,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
        Future.delayed(const Duration(seconds: 2), () async {
          await bluetoothManager.device.disconnect();
          if (context.mounted) {
            Navigator.pop(context);
            Navigator.pushReplacementNamed(context, '/menu');
          }
        });
        return;
      },
      child: Scaffold(
        backgroundColor: color0,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(HugeIcons.strokeRoundedArrowLeft02,
                      color: color1),
                  onPressed: () {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) {
                        return AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20.0),
                            side: const BorderSide(color: color4, width: 2.0),
                          ),
                          backgroundColor: color1,
                          content: Row(
                            children: [
                              Image.asset('assets/branch/dragon.gif',
                                  width: 100, height: 100),
                              Container(
                                margin: const EdgeInsets.only(left: 15),
                                child: const Text(
                                  "Desconectando...",
                                  style: TextStyle(
                                    color: color0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                    Future.delayed(const Duration(seconds: 2), () async {
                      await bluetoothManager.device.disconnect();
                      if (context.mounted) {
                        Navigator.pop(context);
                        Navigator.pushReplacementNamed(context, '/menu');
                      }
                    });
                    return;
                  },
                ),
              ),
              const Spacer(),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    HugeIcons.strokeRoundedAlertDiamond,
                    size: 80,
                    color: color1,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No eres dueño de este equipo',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      color: color1,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      color: color1,
                    ),
                    children: [
                      const TextSpan(text: 'Si crees que es un error,\n'),
                      TextSpan(
                        text: 'contáctanos por correo',
                        style: const TextStyle(
                          decoration: TextDecoration.underline,
                          color: color1,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            String adminActual = globalDATA[
                                        '${DeviceManager.getProductCode(deviceName)}/${DeviceManager.extractSerialNumber(deviceName)}']
                                    ?['owner'] ??
                                'Desconocido';
                            String message =
                                'Hola, te hablo en relación a mi equipo $deviceName.\nEste mismo me dice que no soy dueño.\nDatos del equipo:\nCódigo de producto: ${DeviceManager.getProductCode(deviceName)}\nNúmero de serie: ${DeviceManager.extractSerialNumber(deviceName)}\nDueño actual: $adminActual\n';

                            launchEmail(
                              'service@caldensmart.com',
                              'Consulta sobre línea Smart',
                              message,
                            );
                          },
                      ),
                      const TextSpan(text: ' o '),
                      TextSpan(
                        text: 'WhatsApp',
                        style: const TextStyle(
                          decoration: TextDecoration.underline,
                          color: color1,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            String phoneNumber = '5491162232619';

                            String adminActual = globalDATA[
                                        '${DeviceManager.getProductCode(deviceName)}/${DeviceManager.extractSerialNumber(deviceName)}']
                                    ?['owner'] ??
                                'Desconocido';

                            String message =
                                'Hola, te hablo en relación a mi equipo $deviceName.\nEste mismo me dice que no soy dueño.\n*Datos del equipo:*\nCódigo de producto: ${DeviceManager.getProductCode(deviceName)}\nNúmero de serie: ${DeviceManager.extractSerialNumber(deviceName)}\nDueño actual: $adminActual\n';

                            sendWhatsAppMessage(phoneNumber, message);
                          },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
//*-pantalla para usuario no autorizo a entrar al equipo-*\\

//*-pantalla para usuario no autorizo a entrar al equipo-*\\
class NotAllowedScreen extends StatelessWidget {
  const NotAllowedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, A) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20.0),
                side: const BorderSide(color: color4, width: 2.0),
              ),
              backgroundColor: color1,
              content: Row(
                children: [
                  Image.asset('assets/branch/dragon.gif',
                      width: 100, height: 100),
                  Container(
                    margin: const EdgeInsets.only(left: 15),
                    child: const Text(
                      "Desconectando...",
                      style: TextStyle(
                        color: color0,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
        Future.delayed(const Duration(seconds: 2), () async {
          await bluetoothManager.device.disconnect();
          if (context.mounted) {
            Navigator.pop(context);
            Navigator.pushReplacementNamed(context, '/menu');
          }
        });
        return;
      },
      child: Scaffold(
        backgroundColor: color0,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(HugeIcons.strokeRoundedArrowLeft02,
                      color: color1),
                  onPressed: () {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) {
                        return AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20.0),
                            side: const BorderSide(color: color4, width: 2.0),
                          ),
                          backgroundColor: color1,
                          content: Row(
                            children: [
                              Image.asset('assets/branch/dragon.gif',
                                  width: 100, height: 100),
                              Container(
                                margin: const EdgeInsets.only(left: 15),
                                child: const Text(
                                  "Desconectando...",
                                  style: TextStyle(
                                    color: color0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                    Future.delayed(const Duration(seconds: 2), () async {
                      await bluetoothManager.device.disconnect();
                      if (context.mounted) {
                        Navigator.pop(context);
                        Navigator.pushReplacementNamed(context, '/menu');
                      }
                    });
                    return;
                  },
                ),
              ),
              const Spacer(),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    HugeIcons.strokeRoundedAlertDiamond,
                    size: 80,
                    color: color1,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No puedes controlar el equipo en este momento',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      color: color1,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  'El dueño del equipo inhabilito tus funciones por el momento',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: color1,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

//*-si el equipo ya tiene un usuario conectado -*\\
class DeviceInUseScreen extends StatelessWidget {
  const DeviceInUseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, A) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20.0),
                side: const BorderSide(color: color4, width: 2.0),
              ),
              backgroundColor: color1,
              content: Row(
                children: [
                  Image.asset('assets/branch/dragon.gif',
                      width: 100, height: 100),
                  Container(
                    margin: const EdgeInsets.only(left: 15),
                    child: const Text(
                      "Desconectando...",
                      style: TextStyle(color: color0),
                    ),
                  ),
                ],
              ),
            );
          },
        );
        Future.delayed(const Duration(seconds: 2), () async {
          await bluetoothManager.device.disconnect();
          if (context.mounted) {
            Navigator.pop(context);
            Navigator.pushReplacementNamed(context, '/menu');
          }
        });
        return;
      },
      child: Scaffold(
        backgroundColor: color0,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(HugeIcons.strokeRoundedArrowLeft02,
                      color: color1),
                  onPressed: () {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) {
                        return AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20.0),
                            side: const BorderSide(color: color4, width: 2.0),
                          ),
                          backgroundColor: color1,
                          content: Row(
                            children: [
                              Image.asset('assets/branch/dragon.gif',
                                  width: 100, height: 100),
                              Container(
                                margin: const EdgeInsets.only(left: 15),
                                child: const Text(
                                  "Desconectando...",
                                  style: TextStyle(color: color0),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                    Future.delayed(const Duration(seconds: 2), () async {
                      await bluetoothManager.device.disconnect();
                      if (context.mounted) {
                        Navigator.pop(context);
                        Navigator.pushReplacementNamed(context, '/menu');
                      }
                    });
                    return;
                  },
                ),
              ),
              const Spacer(),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    HugeIcons.strokeRoundedAlertDiamond,
                    size: 80,
                    color: color1,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Actualmente hay un usuario usando el equipo por bluetooth...',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      color: color1,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  Text(
                    'Espere a que\nse desconecte\npara poder usarlo',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      color: color1,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  Image.asset(
                    'assets/branch/dragon.gif',
                    width: 150,
                    height: 150,
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20.0),
                              side: const BorderSide(color: color4, width: 2.0),
                            ),
                            backgroundColor: color1,
                            title: Row(
                              children: [
                                const Icon(
                                  HugeIcons.strokeRoundedInformationCircle,
                                  color: color0,
                                  size: 30,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  '¿Qué hacer?',
                                  style: GoogleFonts.poppins(
                                    color: color0,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            content: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Tienes las siguientes opciones:',
                                    style: GoogleFonts.poppins(
                                      color: color0,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        HugeIcons.strokeRoundedPowerSocket01,
                                        color: color3,
                                        size: 24,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Opción 1: Reiniciar el equipo',
                                              style: GoogleFonts.poppins(
                                                color: color0,
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            Text(
                                              'Desconecta el equipo de la energía, espera unos segundos y vuelve a conectarlo. Esto reiniciará la conexión Bluetooth.',
                                              style: GoogleFonts.poppins(
                                                color: color0,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        HugeIcons.strokeRoundedSmartPhone01,
                                        color: color3,
                                        size: 24,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Opción 2: Buscar el teléfono conectado',
                                              style: GoogleFonts.poppins(
                                                color: color0,
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            Text(
                                              'Busca en las cercanías el teléfono que está actualmente conectado al equipo y pídele al usuario que se desconecte.',
                                              style: GoogleFonts.poppins(
                                                color: color0,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(
                                  'Entendido',
                                  style: GoogleFonts.poppins(
                                    color: color0,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                    icon: const Icon(
                      HugeIcons.strokeRoundedInformationCircle,
                      color: color0,
                    ),
                    label: Text(
                      '¿Qué hacer?',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: color0,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color3,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 5,
                    ),
                  ),
                ],
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
//*-si el equipo ya tiene un usuario conectado -*\\

//*-si no se termino el proceso de laboratorio-*\\
class LabProcessNotFinished extends StatelessWidget {
  const LabProcessNotFinished({super.key});

  @override
  Widget build(BuildContext context) {
    final TextStyle poppinsStyle = GoogleFonts.poppins();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, A) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20.0),
                side: const BorderSide(color: color4, width: 2.0),
              ),
              backgroundColor: color1,
              content: Row(
                children: [
                  Image.asset('assets/branch/dragon.gif',
                      width: 100, height: 100),
                  Container(
                    margin: const EdgeInsets.only(left: 15),
                    child: const Text(
                      "Desconectando...",
                      style: TextStyle(color: color0),
                    ),
                  ),
                ],
              ),
            );
          },
        );
        Future.delayed(const Duration(seconds: 2), () async {
          await bluetoothManager.device.disconnect();
          if (context.mounted) {
            Navigator.pop(context);
            Navigator.pushReplacementNamed(context, '/menu');
          }
        });
        return;
      },
      child: Scaffold(
        backgroundColor: color0,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(HugeIcons.strokeRoundedArrowLeft02,
                      color: color1),
                  onPressed: () {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) {
                        return AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20.0),
                            side: const BorderSide(color: color4, width: 2.0),
                          ),
                          backgroundColor: color1,
                          content: Row(
                            children: [
                              Image.asset('assets/branch/dragon.gif',
                                  width: 100, height: 100),
                              Container(
                                margin: const EdgeInsets.only(left: 15),
                                child: const Text(
                                  "Desconectando...",
                                  style: TextStyle(color: color0),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                    Future.delayed(const Duration(seconds: 2), () async {
                      await bluetoothManager.device.disconnect();
                      if (context.mounted) {
                        Navigator.pop(context);
                        Navigator.pushReplacementNamed(context, '/menu');
                      }
                    });
                    return;
                  },
                ),
              ),
              const Spacer(),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    margin: const EdgeInsets.all(16),
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: color0,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: const BoxDecoration(
                              color: color2,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              HugeIcons.strokeRoundedAlertDiamond,
                              size: 64,
                              color: color0,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'PROCEDIMIENTO NO FINALIZADO',
                            textAlign: TextAlign.center,
                            style: poppinsStyle.copyWith(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: color2,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: color0,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: color0, width: 2),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      HugeIcons.strokeRoundedAlert02,
                                      color: color2,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'El equipo no ha completado su procedimiento de laboratorio.',
                                        style: poppinsStyle.copyWith(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          color: color1,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      HugeIcons.strokeRoundedArrowLeft02,
                                      color: color2,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'El equipo debe ser rechazado y devuelto al laboratorio para completar los procedimientos especificados.',
                                        style: poppinsStyle.copyWith(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          color: color1,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
//*-si no se termino el proceso de laboratorio-*\\

//*- imagenes de los equipos -*\\
class ImageManager {
  static void openImageOptions(
      BuildContext context, String deviceName, VoidCallback onImageChanged) {
    showModalBottomSheet(
      context: context,
      backgroundColor: color1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (BuildContext bc) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading:
                    const Icon(HugeIcons.strokeRoundedAlbum02, color: color0),
                title: const Text('Elegir de la galería',
                    style: TextStyle(color: color0)),
                onTap: () async {
                  Navigator.of(context).pop();
                  await pickFromGallery(deviceName, context);
                  onImageChanged();
                },
              ),
              const Divider(color: color0),
              ListTile(
                leading:
                    const Icon(HugeIcons.strokeRoundedCamera01, color: color0),
                title: const Text('Tomar una foto',
                    style: TextStyle(color: color0)),
                onTap: () async {
                  Navigator.of(context).pop();
                  await takePhoto(deviceName, context);
                  onImageChanged();
                },
              ),
              if (deviceImages.containsKey(deviceName)) ...[
                const Divider(color: color0),
                ListTile(
                  leading:
                      const Icon(HugeIcons.strokeRoundedImage02, color: color0),
                  title: const Text('Cambiar estilo (Centro / Completo)',
                      style: TextStyle(color: color0)),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _askImageStyle(context, deviceName);
                    onImageChanged();
                  },
                ),
              ],
              const Divider(color: color0),
              ListTile(
                leading:
                    const Icon(HugeIcons.strokeRoundedReload, color: color0),
                title: const Text('Restablecer imagen',
                    style: TextStyle(color: color0)),
                onTap: () {
                  Navigator.of(context).pop();
                  removeDeviceImage(deviceName);
                  removeDeviceImageStyle(deviceName);
                  onImageChanged();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Función para elegir una imagen de la galería
  static Future<void> pickFromGallery(
      String deviceName, BuildContext context) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      final String savedPath = await _saveImageLocally(image);
      await saveDeviceImage(deviceName, savedPath);
      if (context.mounted) await _askImageStyle(context, deviceName);
    }
  }

  /// Función para tomar una foto
  static Future<void> takePhoto(String deviceName, BuildContext context) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);

    if (image != null) {
      final String savedPath = await _saveImageLocally(image);
      await saveDeviceImage(deviceName, savedPath);
      if (context.mounted) await _askImageStyle(context, deviceName);
    }
  }

  /// Diálogo para preguntar el estilo de la imagen
  static Future<void> _askImageStyle(
      BuildContext context, String deviceName) async {
    bool? isFullCover = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: color1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.0),
            side: const BorderSide(color: color4, width: 2.0),
          ),
          title: Text(
            'Estilo de imagen',
            style:
                GoogleFonts.poppins(color: color0, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          content: Text(
            '¿Deseas que la imagen ocupe toda la tarjeta o solo el centro?',
            style: GoogleFonts.poppins(color: color0),
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Centro', style: GoogleFonts.poppins(color: color0)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Fondo completo',
                  style: GoogleFonts.poppins(
                      color: color0, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (isFullCover != null) {
      await saveDeviceImageStyle(deviceName, isFullCover);
    }
  }

  /// Función privada para guardar la imagen localmente
  static Future<String> _saveImageLocally(XFile image) async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final String path = appDir.path;
    final String fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${image.name}';
    final File localImage = await File(image.path).copy('$path/$fileName');
    return localImage.path;
  }

  /// Función para obtener la ruta de la imagen
  static String getImagePath(String deviceName) {
    return deviceImages[deviceName] ?? rutaDeImagen(deviceName);
  }

  /// Ruta de imágenes predeterminadas
  static String rutaDeImagen(String device) {
    String pc = DeviceManager.getProductCode(device);
    switch (pc) {
      case '022000_IOT':
        return 'assets/devices/022000.jpg';
      case '027000_IOT':
        return 'assets/devices/027000.jpg';
      case '015773_IOT':
        return 'assets/devices/015773.jpg';
      case '020010_IOT':
        return 'assets/devices/020010.jpg';
      case '050217_IOT':
        return 'assets/devices/050217.jpg';
      case '027313_IOT':
        return 'assets/devices/027313.jpg';
      case '041220_IOT':
        return 'assets/devices/041220.jpg';
      case '028000_IOT':
        return 'assets/devices/028000.jpg';
      case '024011_IOT':
        return 'assets/devices/024011.jpg';
      case '020020_IOT':
        return 'assets/devices/020020.jpg';
      case '023430_IOT':
        return 'assets/devices/023430.jpg';
      case '027345_IOT':
        return 'assets/devices/027345.jpg';
      default:
        return 'assets/branch/Logo.png';
    }
  }
}

//*- imagenes de los equipos -*\\

//*- icono en el boton de la slide -*\\
class IconThumbSlider extends SliderComponentShape {
  final IconData iconData;
  final double thumbRadius;

  const IconThumbSlider({required this.iconData, required this.thumbRadius});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(thumbRadius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    // Draw the thumb as a circle
    final paint = Paint()
      ..color = sliderTheme.thumbColor!
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, thumbRadius, paint);

    // Draw the icon on the thumb
    TextSpan span = TextSpan(
      style: TextStyle(
        fontSize: thumbRadius,
        fontFamily: iconData.fontFamily,
        color: sliderTheme.valueIndicatorColor,
      ),
      text: String.fromCharCode(iconData.codePoint),
    );
    TextPainter tp = TextPainter(
        text: span,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr);
    tp.layout();
    Offset iconOffset = Offset(
      center.dx - (tp.width / 2),
      center.dy - (tp.height / 2),
    );
    tp.paint(canvas, iconOffset);
  }
}
//*- icono en el boton de la slide -*\\

//*- Cerrando sesión -*\\
class ClosingSessionScreen extends StatefulWidget {
  const ClosingSessionScreen({super.key});

  @override
  State<ClosingSessionScreen> createState() => ClosingSessionScreenState();
}

class ClosingSessionScreenState extends State<ClosingSessionScreen> {
  String _dots = '';
  int dot = 0;
  late Timer _dotTimer;

  @override
  void initState() {
    super.initState();
    _dotTimer =
        Timer.periodic(const Duration(milliseconds: 800), (Timer timer) {
      setState(
        () {
          dot++;
          if (dot >= 4) dot = 0;
          _dots = '.' * dot;
        },
      );
    });
  }

  @override
  void dispose() {
    _dotTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: color1,
      body: Center(
        child: Stack(
          alignment: AlignmentDirectional.center,
          children: <Widget>[
            Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/branch/dragon.gif',
                  width: 150,
                  height: 150,
                ),
                const SizedBox(
                  height: 20,
                ),
                RichText(
                  text: TextSpan(
                    text: 'Cerrando sesión',
                    style: const TextStyle(
                      color: color0,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    children: <TextSpan>[
                      TextSpan(
                        text: _dots,
                        style: const TextStyle(
                          color: color0,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Align(
                    alignment: Alignment.bottomCenter,
                    child: Text(
                      'Versión $appVersionNumber',
                      style: const TextStyle(
                        color: color0,
                        fontSize: 12,
                      ),
                    )),
                const SizedBox(
                  height: 20,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
//*- Cerrando sesión -*\\

//*- animacion para los iconos al estar calentando-*\\
class AnimatedIconWidget extends StatefulWidget {
  final bool isHeating;
  final IconData icon;

  const AnimatedIconWidget({
    required this.isHeating,
    required this.icon,
    super.key,
  });

  @override
  AnimatedIconWidgetState createState() => AnimatedIconWidgetState();
}

class AnimatedIconWidgetState extends State<AnimatedIconWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.isHeating
        ? AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              double offsetX = 5.0 * (_controller.value - 0.5);
              double scale = 1.0 + 0.05 * (_controller.value - 0.5);

              return Transform.translate(
                offset: Offset(offsetX, 0),
                child: Transform.scale(
                  scale: scale,
                  child: Icon(
                    widget.icon,
                    size: 85,
                    color: Colors.white,
                  ),
                ),
              );
            },
          )
        : Icon(
            widget.icon,
            size: 85,
            color: Colors.white,
          );
  }
}
//*- animacion para los iconos al estar calentando-*\\

//*- tutorial -*-\\

/// Describe cada paso del tutorial:
/// - globalKey: el widget a enfocar.
/// - child: tu TutorialItemContent (título + texto).
/// - pageIndex: página (si usas PageView).
/// - shapeFocus: forma del halo (oval, roundedSquare, square).
/// - contentPosition: si el texto va arriba o abajo.
/// - focusMargin: separación extra antes de pintar.
/// - borderRadius: esquinas del halo redondeado.
/// - onStepReached: función que se ejecuta cuando se llega a este paso del tutorial.
/// - ButtonAction: Función que agrega un boton a al paso, se le debe agrega una acción.

class TutorialItem {
  final GlobalKey globalKey;
  final Widget child;
  final int? pageIndex;
  final ShapeFocus shapeFocus;
  final ContentPosition contentPosition;
  final double focusMargin;
  final Radius borderRadius;
  final bool fullBackground;
  final double contentOffsetY;
  final VoidCallback? onStepReached;
  final ElevatedButton? buttonAction;

  TutorialItem({
    required this.globalKey,
    required this.child,
    required this.pageIndex,
    this.shapeFocus = ShapeFocus.roundedSquare,
    this.contentPosition = ContentPosition.above,
    this.focusMargin = 8.0,
    this.borderRadius = const Radius.circular(12.0),
    this.fullBackground = false,
    this.contentOffsetY = 0.0,
    this.onStepReached,
    this.buttonAction,
  });
}

class FillBackground extends CustomPainter {
  final double dx, dy, width, height;
  final ShapeFocus shapeFocus;
  final double margin;
  final Radius borderRadius;
  final bool fullBackground;

  static const Color _bgColor = Color(0xFF000000);
  static const double _borderWidth = 2.0;
  static const Radius _cornerRad = Radius.circular(12.0);

  FillBackground({
    required this.dx,
    required this.dy,
    required this.width,
    required this.height,
    this.shapeFocus = ShapeFocus.roundedSquare,
    this.margin = 8.0,
    this.borderRadius = _cornerRad,
    this.fullBackground = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintBg = Paint()..color = _bgColor.withValues(alpha: 0.8);

    if (fullBackground) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paintBg);
      return;
    }

    final w = width + margin * 2;
    final h = height + margin * 2;
    final center = Offset(dx, dy);

    Path path;
    switch (shapeFocus) {
      case ShapeFocus.oval:
        path = Path()
          ..addOval(Rect.fromCenter(center: center, width: w, height: h));
        break;
      case ShapeFocus.roundedSquare:
        path = Path()
          ..addRRect(RRect.fromRectAndCorners(
            Rect.fromCenter(center: center, width: w, height: h),
            topLeft: borderRadius,
            topRight: borderRadius,
            bottomLeft: borderRadius,
            bottomRight: borderRadius,
          ));
        break;
      case ShapeFocus.square:
        path = Path()
          ..addRect(Rect.fromCenter(center: center, width: w, height: h));
    }
    path.close();

    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        path,
      ),
      paintBg,
    );

    final paintBorder = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = _borderWidth;
    canvas.drawPath(path, paintBorder);
  }

  @override
  bool shouldRepaint(covariant FillBackground old) {
    return old.dx != dx ||
        old.dy != dy ||
        old.width != width ||
        old.height != height ||
        old.margin != margin ||
        old.borderRadius != borderRadius ||
        old.fullBackground != fullBackground;
  }
}

class AnimatedFocusHalo extends StatefulWidget {
  final double dx, dy, width, height;
  final ShapeFocus shapeFocus;
  final double baseMargin;
  final Radius borderRadius;
  final bool fullBackground;

  const AnimatedFocusHalo({
    required this.dx,
    required this.dy,
    required this.width,
    required this.height,
    required this.shapeFocus,
    this.baseMargin = 8.0,
    this.borderRadius = const Radius.circular(12.0),
    this.fullBackground = false,
    super.key,
  });

  @override
  AnimatedFocusHaloState createState() => AnimatedFocusHaloState();
}

class AnimatedFocusHaloState extends State<AnimatedFocusHalo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _anim = Tween(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canvasSize = MediaQuery.of(context).size;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final m = widget.baseMargin * _anim.value;
        return CustomPaint(
          size: canvasSize,
          painter: FillBackground(
            dx: widget.dx,
            dy: widget.dy,
            width: widget.width,
            height: widget.height,
            shapeFocus: widget.shapeFocus,
            margin: m,
            borderRadius: widget.borderRadius,
            fullBackground: widget.fullBackground,
          ),
        );
      },
    );
  }
}

class Tutorial {
  static List<OverlayEntry> entries = [];
  static late int _current;

  static bool _active = false;

  static Future<void> showTutorial(
    BuildContext context,
    List<TutorialItem> items,
    PageController controller, {
    required VoidCallback onTutorialComplete,
  }) async {
    clearEntries();
    _active = true;

    final overlay = Overlay.of(context);
    _current = 0;
    final completer = Completer<void>();

    void removeLast() {
      if (entries.isNotEmpty) {
        try {
          entries.removeLast().remove();
        } catch (_) {}
      }
    }

    Future<void> showStep() async {
      if (!_active) {
        if (!completer.isCompleted) completer.complete();
        return;
      }

      if (_current >= items.length) {
        if (!completer.isCompleted) completer.complete();
        onTutorialComplete();
        return;
      }

      removeLast();

      final item = items[_current];

      if (item.onStepReached != null) {
        item.onStepReached!();
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (!_active) {
        removeLast();
        if (!completer.isCompleted) completer.complete();
        return;
      }

      if (item.pageIndex != null &&
          item.pageIndex != controller.page?.toInt()) {
        await controller.animateToPage(
          item.pageIndex!,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (!_active) {
        if (!completer.isCompleted) completer.complete();
        return;
      }

      if (item.globalKey.currentContext == null ||
          !item.globalKey.currentContext!.mounted) {
        clearEntries();
        if (!completer.isCompleted) completer.complete();
        return;
      }

      final render = item.globalKey.currentContext?.findRenderObject();
      if (render is RenderBox) {
        await Scrollable.ensureVisible(
          item.globalKey.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.5,
        );
      }

      void next() {
        if (!_active) return;

        if (_current == items.length - 1) {
          clearEntries();
          if (!completer.isCompleted) completer.complete();
          onTutorialComplete();
        } else {
          _current++;
          showStep();
        }
      }

      if (item.globalKey.currentContext == null) return;
      final box =
          item.globalKey.currentContext!.findRenderObject() as RenderBox;
      final offset = box.localToGlobal(Offset.zero);
      final sizeW = box.size;

      final entry = OverlayEntry(builder: (_) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: next,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                AnimatedFocusHalo(
                  dx: offset.dx + sizeW.width / 2,
                  dy: offset.dy + sizeW.height / 2,
                  width: sizeW.width,
                  height: sizeW.height,
                  shapeFocus: item.shapeFocus,
                  baseMargin: item.focusMargin,
                  borderRadius: item.borderRadius,
                  fullBackground: item.fullBackground,
                ),
                _buildTutorialText(
                  context: context,
                  item: item,
                  targetOffset: offset,
                  targetSize: sizeW,
                ),
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: SafeArea(
                      minimum: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (item.buttonAction != null)
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomLeft,
                                child: item.buttonAction!,
                              ),
                            )
                          else
                            const Spacer(),
                          const SizedBox(width: 20),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: color4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 17),
                            ),
                            icon: const Icon(HugeIcons.strokeRoundedCancel01,
                                color: color0),
                            label: const Text('Saltar',
                                style: TextStyle(color: color0)),
                            onPressed: () {
                              clearEntries();
                              if (!completer.isCompleted) completer.complete();
                              onTutorialComplete();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      });

      entries.add(entry);
      if (_active) {
        overlay.insert(entry);
      }
    }

    await showStep();
    return completer.future;
  }

  static Widget _buildTutorialText({
    required BuildContext context,
    required TutorialItem item,
    required Offset targetOffset,
    required Size targetSize,
  }) {
    final mediaQuery = MediaQuery.of(context);
    final sw = mediaQuery.size.width;
    final sh = mediaQuery.size.height;
    final bottomReservedSpace = 90.0 + mediaQuery.padding.bottom;

    final cw = sw * 0.8;

    double topY;
    double maxHeightConstraint;

    if (item.contentPosition == ContentPosition.above) {
      const estimatedHeight = 150.0;
      topY = targetOffset.dy -
          estimatedHeight -
          item.focusMargin +
          item.contentOffsetY;

      if (topY < mediaQuery.padding.top + 20) {
        topY = mediaQuery.padding.top + 20;
      }
      maxHeightConstraint = targetOffset.dy - item.focusMargin - topY - 10;
    } else {
      topY = targetOffset.dy +
          item.focusMargin +
          targetSize.height +
          20 +
          item.contentOffsetY;

      maxHeightConstraint = sh - topY - bottomReservedSpace;
    }

    if (maxHeightConstraint < 100) maxHeightConstraint = 100;

    final title = (item.child as TutorialItemContent).title;
    final content = (item.child as TutorialItemContent).content;

    Text strokedText(
        String txt, double fontSize, FontWeight fw, Color fillColor) {
      return Text(
        txt,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fw,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = fontSize * 0.08
            ..color = Colors.black,
        ),
      );
    }

    Text filledText(
        String txt, double fontSize, FontWeight fw, Color fillColor) {
      return Text(
        txt,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fw,
          color: fillColor,
        ),
      );
    }

    return Positioned(
      top: topY,
      left: (sw - cw) / 2,
      width: cw,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxHeightConstraint,
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  strokedText(title, 20, FontWeight.bold, Colors.white),
                  filledText(title, 20, FontWeight.bold, Colors.white),
                ],
              ),
              const SizedBox(height: 8),
              Stack(
                alignment: Alignment.center,
                children: [
                  strokedText(content, 16, FontWeight.normal, Colors.white70),
                  filledText(content, 16, FontWeight.normal, Colors.white70),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void clearEntries() {
    _active = false;

    final List<OverlayEntry> currentEntries = List.from(entries);
    entries.clear();

    for (var e in currentEntries) {
      try {
        if (e.mounted) {
          e.remove();
        }
      } catch (_) {}
    }
  }
}

class TutorialItemContent extends StatelessWidget {
  final String title;
  final String content;

  const TutorialItemContent({
    super.key,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
//*- tutorial -*\\

//*- Selector de dias -*\\

class DayInWeek {
  DayInWeek(
    this.dayName, {
    required this.dayKey,
    this.isSelected = false,
  });

  String dayName;
  String dayKey;
  bool isSelected = false;

  void toggleIsSelected() {
    isSelected = !isSelected;
  }
}

class SelectWeekDays extends StatefulWidget {
  /// `SelectWeekDays` takes a list of days of type `DayInWeek`.
  /// `onSelect` property will return `list` of days that are selected.
  const SelectWeekDays({
    required this.onSelect,
    required this.days,
    this.backgroundColor,
    this.fontWeight,
    this.fontSize,
    this.selectedDaysFillColor,
    this.unselectedDaysFillColor,
    this.selectedDaysBorderColor,
    this.unselectedDaysBorderColor,
    this.selectedDayTextColor,
    this.unSelectedDayTextColor,
    this.border = true,
    this.boxDecoration,
    this.padding = 8.0,
    this.width,
    this.borderWidth,
    this.elevation = 2.0,
    super.key,
  });

  /// [onSelect] callBack to handle the Selected days
  final void Function(List<String> days) onSelect;

  /// List of days of type `DayInWeek`
  final List<DayInWeek> days;

  /// [backgroundColor] - property to change the color of the container.
  final Color? backgroundColor;

  /// [fontWeight] - property to change the weight of selected text
  final FontWeight? fontWeight;

  /// [fontSize] - property to change the size of selected text
  final double? fontSize;

  /// [selectedDaysFillColor] -  property to change the button color of days
  /// when the button is selected.
  final Color? selectedDaysFillColor;

  /// [unselectedDaysFillColor] -  property to change the button color of days
  /// when the button is not selected.
  final Color? unselectedDaysFillColor;

  /// [selectedDaysBorderColor] - property to change the border color of the
  /// rounded buttons when day is selected.
  final Color? selectedDaysBorderColor;

  /// [unselectedDaysBorderColor] - property to change the border color of
  /// the rounded buttons when day is unselected.
  final Color? unselectedDaysBorderColor;

  /// [selectedDayTextColor] - property to change the color of text when the
  /// day is selected.
  final Color? selectedDayTextColor;

  /// [unSelectedDayTextColor] - property to change the text color when
  /// the day is not selected.
  final Color? unSelectedDayTextColor;

  /// [border] Boolean to handle the day button border by
  /// default the border will be true.
  final bool border;

  /// [boxDecoration] to handle the decoration of the container.
  final BoxDecoration? boxDecoration;

  /// [padding] property  to handle the padding between the
  /// container and buttons by default it is 8.0
  final double padding;

  /// The property that can be used to specify the [width] of
  /// the [SelectWeekDays] container.
  /// By default this property will take the full width of the screen.
  final double? width;

  /// [borderWidth] property  to handle the width border of
  /// the container by default it is 2.0
  final double? borderWidth;

  /// [elevation] property  to change the elevation of  RawMaterialButton
  /// by default it is 2.0
  final double elevation;

  @override
  SelectWeekDaysState createState() => SelectWeekDaysState();
}

class SelectWeekDaysState extends State<SelectWeekDays> {
  // list to insert the selected days.
  List<String> selectedDays = [];

  // list of days in a week.
  List<DayInWeek> _daysInWeek = [];

  @override
  void initState() {
    _daysInWeek = widget.days;
    for (final day in _daysInWeek) {
      if (day.isSelected) {
        selectedDays.add(day.dayKey);
      }
    }
    super.initState();
  }

  // Set days to new value
  void setDaysState(List<DayInWeek> newDays) {
    selectedDays = [];
    for (final dayInWeek in newDays) {
      if (dayInWeek.isSelected) {
        selectedDays.add(dayInWeek.dayKey);
      }
    }
    setState(() {
      _daysInWeek = newDays;
    });
  }

  void _getSelectedWeekDays(bool isSelected, String day) {
    if (isSelected == true) {
      if (!selectedDays.contains(day)) {
        selectedDays.add(day);
      }
    } else if (isSelected == false) {
      if (selectedDays.contains(day)) {
        selectedDays.remove(day);
      }
    }
    widget.onSelect(selectedDays.toList());
  }

  // getter to handle background color of container.
  Color? get _handleBackgroundColor {
    if (widget.backgroundColor == null) {
      return Theme.of(context).colorScheme.secondary;
    } else {
      return widget.backgroundColor;
    }
  }

  // getter to handle fill color of buttons.
  Color? _handleDaysFillColor(bool onSelect) {
    if (!onSelect && widget.unselectedDaysFillColor == null) {
      return null;
    }

    return _selectedUnselectedLogic(
      onSelect: onSelect,
      selectedColor: widget.selectedDaysFillColor,
      unSelectedColor: widget.unselectedDaysFillColor,
      defaultSelectedColor: Colors.white,
      defaultUnselectedColor: Colors.white,
    );
  }

  // getter to handle border color of days[buttons].
  Color _handleBorderColorOfDays(bool onSelect) {
    return _selectedUnselectedLogic(
      onSelect: onSelect,
      selectedColor: widget.selectedDaysBorderColor,
      unSelectedColor: widget.unselectedDaysBorderColor,
      defaultSelectedColor: Colors.white,
      defaultUnselectedColor: Colors.white,
    );
  }

  // Handler to change the text color when the button is pressed
  // and not pressed.
  Color? _handleTextColor(bool onSelect) {
    return _selectedUnselectedLogic(
      onSelect: onSelect,
      selectedColor: widget.selectedDayTextColor,
      unSelectedColor: widget.unSelectedDayTextColor,
      defaultSelectedColor: Colors.black,
      defaultUnselectedColor: Colors.white,
    );
  }

  Color _selectedUnselectedLogic({
    required bool onSelect,
    required Color? selectedColor,
    required Color? unSelectedColor,
    required Color defaultSelectedColor,
    required Color defaultUnselectedColor,
  }) {
    if (onSelect) {
      return selectedColor ?? defaultSelectedColor;
    }
    return unSelectedColor ?? defaultUnselectedColor;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width ?? MediaQuery.of(context).size.width,
      decoration: widget.boxDecoration ??
          BoxDecoration(
            color: _handleBackgroundColor,
            borderRadius: BorderRadius.circular(0),
          ),
      child: Padding(
        padding: EdgeInsets.all(widget.padding),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: _daysInWeek.map(
            (day) {
              return Expanded(
                child: RawMaterialButton(
                  fillColor: _handleDaysFillColor(day.isSelected),
                  shape: CircleBorder(
                    side: widget.border
                        ? BorderSide(
                            color: _handleBorderColorOfDays(day.isSelected),
                            width: widget.borderWidth ?? 2.0,
                          )
                        : BorderSide.none,
                  ),
                  elevation: widget.elevation,
                  onPressed: () {
                    setState(() {
                      day.toggleIsSelected();
                    });
                    _getSelectedWeekDays(day.isSelected, day.dayKey);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      day.dayName.length < 3
                          ? day.dayName
                          : day.dayName.substring(0, 3),
                      style: TextStyle(
                        fontSize: widget.fontSize,
                        fontWeight: widget.fontWeight,
                        color: _handleTextColor(day.isSelected),
                      ),
                    ),
                  ),
                ),
              );
            },
          ).toList(),
        ),
      ),
    );
  }
}
//*- Selector de dias -*\\

//*- Selector de horas -*\\
class TimeSelector extends StatefulWidget {
  final Function(TimeOfDay) onTimeChanged;

  const TimeSelector({super.key, required this.onTimeChanged});

  @override
  State<TimeSelector> createState() => TimeSelectorState();
}

class TimeSelectorState extends State<TimeSelector> {
  static const int repeatCount = 100;
  static List<int> hours = List.generate(24, (index) => index);
  static List<int> minutes = List.generate(60, (index) => index);

  late List<int> repeatedHours;
  late List<int> repeatedMinutes;

  late FixedExtentScrollController hourController;
  late FixedExtentScrollController minuteController;

  int selectedHour = 12;
  int selectedMinute = 30;

  @override
  void initState() {
    super.initState();
    repeatedHours = List.generate(
        hours.length * repeatCount, (i) => hours[i % hours.length]);
    repeatedMinutes = List.generate(
        minutes.length * repeatCount, (i) => minutes[i % minutes.length]);

    // Empieza en el centro para permitir scroll infinito hacia ambos lados
    int initialHourIndex = (repeatCount ~/ 2) * hours.length + selectedHour;
    int initialMinuteIndex =
        (repeatCount ~/ 2) * minutes.length + selectedMinute;

    hourController = FixedExtentScrollController(initialItem: initialHourIndex);
    minuteController =
        FixedExtentScrollController(initialItem: initialMinuteIndex);
  }

  @override
  void dispose() {
    hourController.dispose();
    minuteController.dispose();
    super.dispose();
  }

  void _notifyChange() {
    widget.onTimeChanged(TimeOfDay(hour: selectedHour, minute: selectedMinute));
  }

  void _onHourChanged(int index) {
    setState(() {
      selectedHour = repeatedHours[index % repeatedHours.length];
    });
    _notifyChange();

    if (index < hours.length || index > repeatedHours.length - hours.length) {
      int middleIndex = (repeatCount ~/ 2) * hours.length + selectedHour;
      hourController.jumpToItem(middleIndex);
    }
  }

  void _onMinuteChanged(int index) {
    setState(() {
      selectedMinute = repeatedMinutes[index % repeatedMinutes.length];
    });
    _notifyChange();

    if (index < minutes.length ||
        index > repeatedMinutes.length - minutes.length) {
      int middleIndex = (repeatCount ~/ 2) * minutes.length + selectedMinute;
      minuteController.jumpToItem(middleIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: NumberWheel(
                controller: hourController,
                values: repeatedHours,
                onChanged: _onHourChanged,
              ),
            ),
            const Text(
              ':',
              style: NumberWheel.wheelTextStyle,
            ),
            Expanded(
              child: NumberWheel(
                controller: minuteController,
                values: repeatedMinutes,
                onChanged: _onMinuteChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class NumberWheel extends StatelessWidget {
  final FixedExtentScrollController controller;
  final List<int> values;
  final Function(int) onChanged;

  const NumberWheel({
    super.key,
    required this.controller,
    required this.values,
    required this.onChanged,
  });

  static const TextStyle wheelTextStyle = TextStyle(
    color: color0,
    fontSize: 36,
    fontWeight: FontWeight.bold,
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.20,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: 50,
        diameterRatio: 1.2,
        perspective: 0.002,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: onChanged,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: values.length,
          builder: (context, index) => Center(
            child: Text(
              values[index].toString().padLeft(2, '0'),
              style: wheelTextStyle,
            ),
          ),
        ),
      ),
    );
  }
}
//*- Selector de horas -*\\

//*- ScrollText -*\\
class AutoScrollingText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Duration pauseDuration;
  final double velocity;

  const AutoScrollingText({
    super.key,
    required this.text,
    required this.style,
    this.pauseDuration = const Duration(seconds: 1),
    this.velocity = 50.0,
  });

  @override
  AutoScrollingTextState createState() => AutoScrollingTextState();
}

class AutoScrollingTextState extends State<AutoScrollingText>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  late ScrollController _scrollController;
  late AnimationController _animationController;
  bool _isScrolling = false;
  bool _needsScroll = false;
  bool _isMounted = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _isMounted = true;
    _scrollController = ScrollController();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    _scrollController.addListener(_checkIfNeedsScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isMounted) {
        _checkIfNeedsScroll();
        if (_needsScroll) {
          _startScrollingCycle();
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant AutoScrollingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text && _isMounted) {
      _animationController.reset();
      _scrollController.jumpTo(0.0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isMounted) {
          _checkIfNeedsScroll();
          if (_needsScroll) {
            _startScrollingCycle();
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _isMounted = false;
    _animationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _checkIfNeedsScroll() {
    if (_scrollController.hasClients && _isMounted) {
      final maxScrollExtent = _scrollController.position.maxScrollExtent;
      _needsScroll = maxScrollExtent > 0;
    }
  }

  void _startScrollingCycle() {
    if (!_needsScroll || _isScrolling || !_isMounted) return;

    _isScrolling = true;

    final maxScrollExtent = _scrollController.position.maxScrollExtent;
    final calculatedDuration = Duration(
      milliseconds: (maxScrollExtent / widget.velocity * 1000).toInt(),
    );

    _animationController.animateTo(1.0, duration: calculatedDuration).then((_) {
      if (!_isMounted) return;
      Future.delayed(widget.pauseDuration, () {
        if (!_isMounted) return;
        _animationController
            .animateTo(0.0, duration: calculatedDuration)
            .then((_) {
          if (_isMounted) {
            _isScrolling = false;
            if (_needsScroll) {
              Future.delayed(widget.pauseDuration, _startScrollingCycle);
            }
          }
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        if (_scrollController.hasClients && _needsScroll && _isMounted) {
          final maxScrollExtent = _scrollController.position.maxScrollExtent;
          final scrollPosition = maxScrollExtent * _animationController.value;
          _scrollController.jumpTo(scrollPosition);
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: _scrollController,
          physics: const NeverScrollableScrollPhysics(),
          child: Text(
            widget.text,
            style: widget.style,
            softWrap: false,
          ),
        );
      },
    );
  }
}
//*- ScrollText -*\\

//*- PaintBottomAppBar -*\\
class PaintBottomAppBar extends CustomPainter {
  final Color borderColor;
  final double width;
  final double radius;
  final double notchMargin;

  PaintBottomAppBar({
    required this.borderColor,
    required this.width,
    required this.radius,
    required this.notchMargin,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;

    final Rect oversizedRect =
        Rect.fromLTWH(0, 0, size.width, size.height + 20);

    final Path notchPath = const CircularNotchedRectangle().getOuterPath(
      oversizedRect,
      Rect.fromCircle(
          center: Offset(size.width / 2, 0), radius: 28.0 + notchMargin),
    );

    final Path roundedPath = Path()
      ..addRRect(RRect.fromRectAndCorners(
        oversizedRect,
        topLeft: Radius.circular(radius),
        topRight: Radius.circular(radius),
      ));

    final Path finalPath = Path.combine(
      PathOperation.intersect,
      notchPath,
      roundedPath,
    );

    canvas.drawPath(finalPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
//*- PaintBottomAppBar -*\\

//*- iconos -*\\
class CaldenIcons {
  static const String unLock = 'assets/icons/unlock.png';
  static const String cloudOff = 'assets/icons/cloudOff.png';
  static const String cloud = 'assets/icons/cloud.png';
  static const String snowOff = 'assets/icons/snowOff.png';
  static const String waterOff = 'assets/icons/waterOff.png';
  static const String wifi01 = 'assets/icons/wifi01.png';
  static const String wifi02 = 'assets/icons/wifi02.png';
  static const String wifi03 = 'assets/icons/wifi03.png';
  static const String termometro = 'assets/icons/termometro.png';
  static const String termometroPlus = 'assets/icons/termometroPlus.png';
  static const String termometroMenos = 'assets/icons/termometroMenos.png';
}
//*- iconos -*\\

//*- Pantalla configuración de pines -*\\
class PinConfigurationScreen extends StatefulWidget {
  final String deviceName;

  const PinConfigurationScreen({super.key, required this.deviceName});

  @override
  State<PinConfigurationScreen> createState() => _PinConfigurationScreenState();
}

class _PinConfigurationScreenState extends State<PinConfigurationScreen> {
  late String pc;
  late String sn;
  late String hardwareVersion;

  List<Map<String, dynamic>> pins = [];

  bool isSpecialRelay = false;
  bool localIsNC = false;

  @override
  void initState() {
    super.initState();
    pc = DeviceManager.getProductCode(widget.deviceName);
    sn = DeviceManager.extractSerialNumber(widget.deviceName);
    hardwareVersion = globalDATA['$pc/$sn']?['HardwareVersion'] ?? '240423A';

    _loadDeviceData();
  }

  void _loadDeviceData() {
    if (pc == '023430_IOT') {
      isSpecialRelay = true;
      localIsNC = isNC;
    } else {
      Map<String, dynamic> deviceData = globalDATA['$pc/$sn'] ?? {};
      List<int> indices = [];

      for (String key in deviceData.keys) {
        if (key.startsWith('io') && key.length > 2) {
          int? index = int.tryParse(key.substring(2));
          if (index != null) indices.add(index);
        }
      }
      indices.sort();

      for (int i in indices) {
        try {
          Map<String, dynamic> ioData = jsonDecode(deviceData['io$i']);
          pins.add({
            'index': i,
            'tipo': ioData['pinType'] == '0' ? 'Salida' : 'Entrada',
            'common': ioData['r_state'] ?? '0',
          });
        } catch (e) {
          printLog.e('Error al parsear pin $i: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: color0,
      appBar: AppBar(
        backgroundColor: color1,
        title: Text(
          'Configuración de Pines',
          style:
              GoogleFonts.poppins(color: color0, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(HugeIcons.strokeRoundedArrowLeft02, color: color0),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (isSpecialRelay) {
      return _buildRelayCard();
    }

    if (pins.isEmpty) {
      return Center(
        child: Text(
          'No se encontraron configuraciones para este equipo.',
          style: GoogleFonts.poppins(color: color1, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: pins.length,
      itemBuilder: (context, index) {
        final pin = pins[index];
        return _buildPinCard(pin);
      },
    );
  }

  Widget _buildRelayCard() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Card(
        color: color1,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Relé Principal',
                style: GoogleFonts.poppins(
                    color: color0, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                'Puedes cambiar entre Normal Abierto (NA) y Normal Cerrado (NC):',
                style: GoogleFonts.poppins(fontSize: 14, color: color0),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              _buildNANCSelector(
                isNCState: localIsNC,
                onTapNA: () {
                  setState(() => localIsNC = false);
                  saveNC(pc, sn, false);
                },
                onTapNC: () {
                  setState(() => localIsNC = true);
                  saveNC(pc, sn, true);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinCard(Map<String, dynamic> pin) {
    final int i = pin['index'];
    final String tipo = pin['tipo'];
    final String common = pin['common'];
    final String pinName =
        nicknamesMap['${widget.deviceName}_$i'] ?? '$tipo $i';

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Card(
        color: color1,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pinName,
                style: GoogleFonts.poppins(
                    color: color0, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),
              if (tipo == 'Entrada') ...[
                Text(
                  'Configuración Normal Abierto (NA) / Normal Cerrado (NC):',
                  style: GoogleFonts.poppins(fontSize: 14, color: color0),
                ),
                const SizedBox(height: 15),
                _buildNANCSelector(
                  isNCState: common == '1',
                  onTapNA: () => _sendBluetoothCommand(pin, i, '0'),
                  onTapNC: () => _sendBluetoothCommand(pin, i, '1'),
                ),
              ],
              if (Versioner.isPrevious(hardwareVersion, '240423A')) ...[
                if (tipo == 'Entrada') ...[
                  const Divider(color: color0, height: 30),
                ],
                Center(
                  child: Text(
                    tipo == 'Entrada'
                        ? '¿Cambiar de entrada a salida?'
                        : '¿Cambiar de salida a entrada?',
                    style: GoogleFonts.poppins(color: color0, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      foregroundColor: color1,
                      backgroundColor: color0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      String newTypeNum = tipo == 'Entrada' ? '0' : '1';
                      String fun = '$pc[13]($i#$newTypeNum)';
                      bluetoothManager.toolsUuid.write(fun.codeUnits);

                      setState(() {
                        pin['tipo'] = tipo == 'Entrada' ? 'Salida' : 'Entrada';
                      });

                      showToast('Configuración actualizada correctamente');
                    },
                    child: const Text('CAMBIAR',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNANCSelector(
      {required bool isNCState,
      required VoidCallback onTapNA,
      required VoidCallback onTapNC}) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30.0),
        border: Border.all(color: color0, width: 2),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onTapNA,
              child: Container(
                decoration: BoxDecoration(
                  color: !isNCState ? color0 : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(28),
                      bottomLeft: Radius.circular(28)),
                ),
                child: Center(
                  child: Text(
                    'Normal Abierto',
                    style: GoogleFonts.poppins(
                        fontSize: 14, color: !isNCState ? color1 : color0),
                  ),
                ),
              ),
            ),
          ),
          Container(width: 2, color: color0),
          Expanded(
            child: GestureDetector(
              onTap: onTapNC,
              child: Container(
                decoration: BoxDecoration(
                  color: isNCState ? color0 : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(28),
                      bottomRight: Radius.circular(28)),
                ),
                child: Center(
                  child: Text(
                    'Normal Cerrado',
                    style: GoogleFonts.poppins(
                        fontSize: 14, color: isNCState ? color1 : color0),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _sendBluetoothCommand(
      Map<String, dynamic> pin, int index, String stateValue) {
    setState(() {
      pin['common'] = stateValue;
    });
    String data = '$pc[14]($index#$stateValue)';
    bluetoothManager.toolsUuid.write(data.codeUnits);
  }
}
//*- Pantalla configuración de pines -*\\