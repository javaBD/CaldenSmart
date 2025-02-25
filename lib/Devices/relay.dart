import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../aws/dynamo/dynamo.dart';
import '../aws/dynamo/dynamo_certificates.dart';
import '../aws/mqtt/mqtt.dart';
import '../master.dart';
import '../Global/stored_data.dart';

// CLASES \\

class RelayPage extends StatefulWidget {
  const RelayPage({super.key});
  @override
  RelayPageState createState() => RelayPageState();
}

class RelayPageState extends State<RelayPage> {
  bool showSecondaryAdminFields = false;
  bool showAddAdminField = false;
  bool showSecondaryAdminList = false;
  bool showSmartResident = false;
  bool dOnOk = false;
  bool dOffOk = false;
  bool showOptions = false;
  bool _showNotificationOptions = false;
  bool _isAnimating = false;
  bool _isTutorialActive = false;

  int _selectedNotificationOption = 0;
  int _selectedIndex = 0;

  final PageController _pageController = PageController(initialPage: 0);
  final TextEditingController tenantController = TextEditingController();
  TextEditingController emailController = TextEditingController();

  ///*- Elementos para tutoriales -*\\\
  List<TutorialItem> items = [];

  //*- Keys para funciones de la appbar -*\\
  final titleKey = GlobalKey(); // key para el nombre del equipo
  final wifiKey = GlobalKey(); // key para el wifi del equipo
  //*- Keys para funciones de la appbar -*\\

  //*- Keys estado del dispositivo -*\\
  final estadoKey = GlobalKey(); // key para la pantalla de estado
  final bottomKey = GlobalKey(); // key para el boton de encendido
  //*- Keys estado del dispositivo-*\\

  //*- Keys para control por distancia -*\\
  final distanceKey =
      GlobalKey(); // key para la pantalla de control por distancia
  final distanceBottomKey = GlobalKey(); // key para el boton de encendido
  //*- Keys para control por distancia -*\\

  //*- Keys para gestión -*\\
  final adminKey = GlobalKey(); // key para la pantalla de gestión
  final claimKey = GlobalKey(); // key para el boton de reclamar admin
  final fastBotonKey = GlobalKey(); // key para el boton de acceso rápido
  final fastAccessKey = GlobalKey(); // key para el boton de acceso rápido
  final imageKey = GlobalKey(); // key para la imagen del equipo
  //*- Keys para gestión -*\\

  //*- Keys para gestión siendo admin-*\\
  final agreeAdminKey =
      GlobalKey(); // key para el boton de agregar administradores
  final viewAdminKey = GlobalKey(); // key para ver la lista de administradores
  final habitKey = GlobalKey(); // key para el boton de habitantes

  //*- Keys para gestión siendo admin-*\\

  void initItems() {
    items.addAll({
      TutorialItem(
        globalKey: estadoKey,
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: const Radius.circular(0),
        shapeFocus: ShapeFocus.oval,
        radius: 0,
        pageIndex: 0,
        child: const TutorialItemContent(
          title: 'Estado del equipo',
          content:
              'En esta pantalla podrás verificar si tu equipo está Apagado o encendido',
        ),
      ),
      TutorialItem(
        globalKey: bottomKey,
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: const Radius.circular(10),
        radius: 90,
        shapeFocus: ShapeFocus.oval,
        pageIndex: 0,
        child: const TutorialItemContent(
          title: 'Botón de encendido',
          content: 'Puedes encender o apagar el equipo al presionar el botón',
        ),
      ),
      TutorialItem(
        globalKey: titleKey,
        color: Colors.black.withValues(alpha: 0.6),
        shapeFocus: ShapeFocus.roundedSquare,
        borderRadius: const Radius.circular(10.0),
        contentPosition: ContentPosition.below,
        pageIndex: 0,
        child: const TutorialItemContent(
          title: 'Nombre del equipo',
          content:
              'Podrás ponerle un apodo tocando en cualquier parte del nombre',
        ),
      ),
      TutorialItem(
        globalKey: wifiKey,
        color: Colors.black.withValues(alpha: 0.6),
        shapeFocus: ShapeFocus.oval,
        borderRadius: const Radius.circular(15.0),
        radius: 25,
        contentPosition: ContentPosition.below,
        pageIndex: 0,
        child: const TutorialItemContent(
          title: 'Menu Wifi',
          content:
              'Podrás observar el estado de la conexión wifi del dispositivo',
        ),
      ),
      TutorialItem(
        globalKey: distanceKey,
        color: Colors.black.withValues(alpha: 0.6),
        shapeFocus: ShapeFocus.oval,
        borderRadius: const Radius.circular(0),
        radius: 0,
        pageIndex: 1,
        child: const TutorialItemContent(
          title: 'Control por distancia',
          content:
              'Podrás ajustar la distancia de encendido y apagado de tu dispositivo',
        ),
      ),
      TutorialItem(
        globalKey: distanceBottomKey,
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: const Radius.circular(10),
        radius: 90,
        shapeFocus: ShapeFocus.oval,
        pageIndex: 1,
        child: const TutorialItemContent(
          title: 'Botón de encendido',
          content: 'Podrás activar esta función y configurar la distancia',
        ),
      ),
      TutorialItem(
        globalKey: adminKey,
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: const Radius.circular(0),
        shapeFocus: ShapeFocus.oval,
        pageIndex: 2,
        radius: 0,
        contentPosition: ContentPosition.below,
        child: const TutorialItemContent(
          title: 'Gestión',
          content: 'Podrás reclamar el equipo y gestionar sus funciones',
        ),
      ),
      TutorialItem(
        globalKey: claimKey,
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: const Radius.circular(20),
        shapeFocus: ShapeFocus.roundedSquare,
        pageIndex: 2,
        contentPosition: ContentPosition.below,
        child: const TutorialItemContent(
          title: 'Reclamar administrador',
          content:
              'Presiona este botón para reclamar la administración del equipo',
        ),
      ),
    });
    // SOLO PARA LOS ADMINS
    if (currentUserEmail == owner) {
      items.addAll({
        TutorialItem(
          globalKey: agreeAdminKey,
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: const Radius.circular(15),
          shapeFocus: ShapeFocus.roundedSquare,
          pageIndex: 2,
          contentPosition: ContentPosition.below,
          child: const TutorialItemContent(
            title: 'Añadir administradores secundarios',
            content: 'Podrás agregar correos secundarios hasta un límite de 3',
          ),
        ),
        TutorialItem(
          globalKey: viewAdminKey,
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: const Radius.circular(15),
          shapeFocus: ShapeFocus.roundedSquare,
          pageIndex: 2,
          contentPosition: ContentPosition.below,
          child: const TutorialItemContent(
            title: 'Ver administradores secundarios',
            content: 'Podrás ver o quitar los correos adicionales añadidos',
          ),
        ),
        TutorialItem(
          globalKey: habitKey,
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: const Radius.circular(15),
          shapeFocus: ShapeFocus.roundedSquare,
          pageIndex: 2,
          child: const TutorialItemContent(
            title: 'Alquiler temporario',
            content:
                'Puedes agregar el correo de tu inquilino al equipo y ajustarlo',
          ),
        ),
      });
    }
    items.addAll({
      TutorialItem(
        globalKey: fastBotonKey,
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: const Radius.circular(20),
        shapeFocus: ShapeFocus.roundedSquare,
        pageIndex: 2,
        child: const TutorialItemContent(
          title: 'Accesso rápido',
          content: 'Podrás encender y apagar el dispositivo desde el menú',
        ),
      ),
      TutorialItem(
        globalKey: fastAccessKey,
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: const Radius.circular(20),
        shapeFocus: ShapeFocus.roundedSquare,
        pageIndex: 2,
        child: const TutorialItemContent(
          title: 'Notificación de desconexión',
          content: 'Puedes establecer una alerta si el equipo se desconecta',
        ),
      ),
      TutorialItem(
        globalKey: imageKey,
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: const Radius.circular(20),
        shapeFocus: ShapeFocus.roundedSquare,
        pageIndex: 2,
        child: const TutorialItemContent(
          title: 'Imagen del dispositivo',
          content: 'Podrás ajustar la imagen del equipo en el menú',
        ),
      ),
    });
  }

  @override
  void initState() {
    super.initState();

    tracking = devicesToTrack.contains(deviceName);
    nickname = nicknamesMap[deviceName] ?? deviceName;
    showOptions = currentUserEmail == owner;

    printLog('¿Encendido? $turnOn');
    printLog('¿Alquiler temporario? $activatedAT');
    printLog('¿Inquilino? $tenant');

    updateWifiValues(toolsValues);
    subscribeToWifiStatus();
    subscribeTrueStatus();

    if (!oldRelay.contains(deviceName)) {
      oldRelay.add(deviceName);
      saveOldRelay(oldRelay);
    }

    if (!alexaDevices.contains(deviceName)) {
      alexaDevices.add(deviceName);
      saveAlexaDevices(alexaDevices);
      putDevicesForAlexa(service, currentUserEmail, alexaDevices);
    }

    // WidgetsBinding.instance.addPostFrameCallback((_) async {
    //   if (shouldUpdateDevice) {
    //     await showUpdateDialog(context);
    //   }
    // });
  }

  @override
  void dispose() {
    super.dispose();
    _pageController.dispose();
    tenantController.dispose();
    emailController.dispose();
  }

  void onItemChanged(int index) {
    if (!_isAnimating) {
      setState(() {
        _isAnimating = true;
        _selectedIndex = index;
      });

      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _isAnimating = false;
          });
        }
      });
    }
  }

  void onItemTapped(int index) {
    if (_selectedIndex != index && !_isAnimating) {
      setState(() {
        _isAnimating = true;
      });

      _pageController
          .animateToPage(
        index,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      )
          .then((_) {
        if (mounted) {
          setState(() {
            _selectedIndex = index;
            _isAnimating = false;
          });
        }
      });
    }
  }

  Future<void> addSecondaryAdmin(String email) async {
    if (!isValidEmail(email)) {
      showToast('Por favor, introduce un correo electrónico válido.');
      return;
    }

    if (adminDevices.contains(email)) {
      showToast('Este administrador ya está añadido.');
      return;
    }

    try {
      List<String> updatedAdmins = List.from(adminDevices)..add(email);

      await putSecondaryAdmins(
          service,
          DeviceManager.getProductCode(deviceName),
          DeviceManager.extractSerialNumber(deviceName),
          updatedAdmins);

      setState(() {
        adminDevices = updatedAdmins;
        emailController.clear();
      });

      showToast('Administrador añadido correctamente.');
    } catch (e) {
      printLog('Error al añadir administrador secundario: $e');
      showToast('Error al añadir el administrador. Inténtalo de nuevo.');
    }
  }

  Future<void> removeSecondaryAdmin(String email) async {
    try {
      List<String> updatedAdmins = List.from(adminDevices)..remove(email);

      await putSecondaryAdmins(
          service,
          DeviceManager.getProductCode(deviceName),
          DeviceManager.extractSerialNumber(deviceName),
          updatedAdmins);

      setState(() {
        adminDevices.remove(email);
      });

      showToast('Administrador eliminado correctamente.');
    } catch (e) {
      printLog('Error al eliminar administrador secundario: $e');
      showToast('Error al eliminar el administrador. Inténtalo de nuevo.');
    }
  }

  bool isValidEmail(String email) {
    final RegExp emailRegex = RegExp(
      r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@"
      r"[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*$",
    );
    return emailRegex.hasMatch(email);
  }

  void updateWifiValues(List<int> data) {
    var fun = utf8.decode(data); //Wifi status | wifi ssid | ble status(users)
    fun = fun.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
    printLog(fun);
    var parts = fun.split(':');
    final regex = RegExp(r'\((\d+)\)');
    final match = regex.firstMatch(parts[2]);
    int users = int.parse(match!.group(1).toString());
    printLog('Hay $users conectados');
    userConnected = users > 1;

    WifiNotifier wifiNotifier =
        Provider.of<WifiNotifier>(context, listen: false);

    if (parts[0] == 'WCS_CONNECTED') {
      atemp = false;
      nameOfWifi = parts[1];
      isWifiConnected = true;
      printLog('sis $isWifiConnected');
      errorMessage = '';
      errorSintax = '';
      werror = false;
      if (parts.length > 3) {
        signalPower = int.tryParse(parts[3]) ?? -30;
      } else {
        signalPower = -30;
      }
      wifiNotifier.updateStatus(
          'CONECTADO', Colors.green, wifiPower(signalPower));
    } else if (parts[0] == 'WCS_DISCONNECTED') {
      isWifiConnected = false;
      printLog('non $isWifiConnected');

      nameOfWifi = '';
      wifiNotifier.updateStatus(
          'DESCONECTADO', Colors.red, Icons.signal_wifi_off);

      if (atemp) {
        setState(() {
          wifiNotifier.updateStatus(
              'DESCONECTADO', Colors.red, Icons.warning_amber_rounded);
          werror = true;
          if (parts[1] == '202' || parts[1] == '15') {
            errorMessage = 'Contraseña incorrecta';
          } else if (parts[1] == '201') {
            errorMessage = 'La red especificada no existe';
          } else if (parts[1] == '1') {
            errorMessage = 'Error desconocido';
          } else {
            errorMessage = parts[1];
          }

          errorSintax = getWifiErrorSintax(int.parse(parts[1]));
        });
      }
    }

    setState(() {});
  }

  void subscribeToWifiStatus() async {
    printLog('Se subscribió a wifi');
    await myDevice.toolsUuid.setNotifyValue(true);

    final wifiSub =
        myDevice.toolsUuid.onValueReceived.listen((List<int> status) {
      printLog('Llegaron cositas wifi');
      updateWifiValues(status);
    });

    myDevice.device.cancelWhenDisconnected(wifiSub);
  }

  void subscribeTrueStatus() async {
    printLog('Me subscribo a vars');
    await myDevice.varsUuid.setNotifyValue(true);

    final trueStatusSub =
        myDevice.varsUuid.onValueReceived.listen((List<int> status) {
      var parts = utf8.decode(status).split(':');
      setState(() {
        turnOn = parts[0] == '1';
      });
    });

    myDevice.device.cancelWhenDisconnected(trueStatusSub);
  }

  void turnDeviceOn(bool on) async {
    int fun = on ? 1 : 0;
    String data = '${DeviceManager.getProductCode(deviceName)}[11]($fun)';
    myDevice.toolsUuid.write(data.codeUnits);
    globalDATA[
            '${DeviceManager.getProductCode(deviceName)}/${DeviceManager.extractSerialNumber(deviceName)}']![
        'w_status'] = on;
    saveGlobalData(globalDATA);
    try {
      String topic =
          'devices_rx/${DeviceManager.getProductCode(deviceName)}/${DeviceManager.extractSerialNumber(deviceName)}';
      String topic2 =
          'devices_tx/${DeviceManager.getProductCode(deviceName)}/${DeviceManager.extractSerialNumber(deviceName)}';
      String message = jsonEncode({'w_status': on});
      sendMessagemqtt(topic, message);
      sendMessagemqtt(topic2, message);
    } catch (e, s) {
      printLog('Error al enviar valor a firebase $e $s');
    }
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      showToast('La ubicación esta desactivada\nPor favor enciendala');
      return Future.error('Los servicios de ubicación están deshabilitados.');
    }
    // Cuando los permisos están OK, obtenemos la ubicación actual
    return await Geolocator.getCurrentPosition();
  }

  void controlTask(bool value, String device) async {
    setState(() {
      isTaskScheduled.addAll({device: value});
    });
    if (isTaskScheduled[device]!) {
      // Programar la tarea.
      try {
        showToast('Recuerda tener la ubicación encendida.');
        String data = '${DeviceManager.getProductCode(deviceName)}[5](1)';
        myDevice.toolsUuid.write(data.codeUnits);
        List<String> deviceControl = await loadDevicesForDistanceControl();
        deviceControl.add(deviceName);
        saveDevicesForDistanceControl(deviceControl);
        printLog(
            'Hay ${deviceControl.length} equipos con el control x distancia');
        Position position = await _determinePosition();
        Map<String, double> maplatitude = await loadLatitude();
        maplatitude.addAll({deviceName: position.latitude});
        savePositionLatitude(maplatitude);
        Map<String, double> maplongitude = await loadLongitud();
        maplongitude.addAll({deviceName: position.longitude});
        savePositionLongitud(maplongitude);

        if (deviceControl.length == 1) {
          await initializeService();
          final backService = FlutterBackgroundService();
          await backService.startService();
          backService.invoke('distanceControl');
          printLog('Servicio iniciado a las ${DateTime.now()}');
        }
      } catch (e) {
        showToast('Error al iniciar control por distancia.');
        printLog('Error al setear la ubicación $e');
      }
    } else {
      // Cancelar la tarea.
      showToast('Se cancelo el control por distancia');
      String data = '${DeviceManager.getProductCode(deviceName)}[5](0)';
      myDevice.toolsUuid.write(data.codeUnits);
      List<String> deviceControl = await loadDevicesForDistanceControl();
      deviceControl.remove(deviceName);
      saveDevicesForDistanceControl(deviceControl);
      printLog(
          'Quedan ${deviceControl.length} equipos con el control x distancia');
      Map<String, double> maplatitude = await loadLatitude();
      maplatitude.remove(deviceName);
      savePositionLatitude(maplatitude);
      Map<String, double> maplongitude = await loadLongitud();
      maplongitude.remove(deviceName);
      savePositionLongitud(maplongitude);

      if (deviceControl.isEmpty) {
        final backService = FlutterBackgroundService();
        backService.invoke("stopService");
        backTimerDS?.cancel();
        printLog('Servicio apagado');
      }
    }
  }

  Future<bool> verifyPermission() async {
    try {
      var permissionStatus4 = await Permission.locationAlways.status;
      if (!permissionStatus4.isGranted) {
        // Usamos un Completer para esperar a que el diálogo se cierre
        final completer = Completer<void>();

        showAlertDialog(
          navigatorKey.currentContext ?? context,
          false,
          const Text(
            'Habilita la ubicación todo el tiempo',
            style: TextStyle(color: Color(0xFFFFFFFF)),
          ),
          Text(
            '$appName utiliza tu ubicación, incluso cuando la app está cerrada o en desuso, para poder encender o apagar el calefactor en base a tu distancia con el mismo.',
            style: const TextStyle(
              color: Color(0xFFFFFFFF),
            ),
          ),
          <Widget>[
            TextButton(
              style: const ButtonStyle(
                foregroundColor: WidgetStatePropertyAll(Color(0xFFFFFFFF)),
              ),
              child: const Text('Habilitar'),
              onPressed: () async {
                try {
                  var permissionStatus4 =
                      await Permission.locationAlways.request();

                  if (!permissionStatus4.isGranted) {
                    await Permission.locationAlways.request();
                  }
                  permissionStatus4 = await Permission.locationAlways.status;

                  // Completa el Completer una vez que el permiso ha sido manejado
                  completer.complete();
                  Navigator.of(navigatorKey.currentContext ?? context).pop();
                } catch (e, s) {
                  printLog(e);
                  printLog(s);
                  completer.completeError(
                      e); // Completa con error si ocurre una excepción
                }
              },
            ),
          ],
        );

        // Espera a que el Completer se complete
        await completer.future;
      }

      // Vuelve a verificar el estado del permiso
      permissionStatus4 = await Permission.locationAlways.status;

      if (permissionStatus4.isGranted) {
        return true;
      } else {
        return false;
      }
    } catch (e, s) {
      printLog('Error al habilitar la ubicación: $e');
      printLog(s);
      return false;
    }
  }

  //! VISUAL
  @override
  Widget build(BuildContext context) {
    final TextStyle poppinsStyle = GoogleFonts.poppins();
    WifiNotifier wifiNotifier =
        Provider.of<WifiNotifier>(context, listen: false);

    bool isRegularUser = !deviceOwner && !secondaryAdmin;

    // si hay un usuario conectado al equipo no lo deje ingresar
    if (userConnected && lastUser > 1) {
      return const DeviceInUseScreen();
    }

    // Condición para mostrar la pantalla de acceso restringido
    if (isRegularUser && owner != '' && !tenant) {
      return const AccessDeniedScreen();
    }

    final List<Widget> pages = [
      //*- Página 1: Estado del Dispositivo -*\\
      SingleChildScrollView(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Center(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20.0, vertical: 30.0),
              // Usamos Column para ordenar el contenido verticalmente
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20.0, vertical: 30.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'Estado del Dispositivo',
                            style: GoogleFonts.poppins(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: color3,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 40),
                          GestureDetector(
                            onTap: () {
                              if (deviceOwner ||
                                  secondaryAdmin ||
                                  owner == '' ||
                                  tenant) {
                                turnDeviceOn(!turnOn);
                                setState(() {
                                  turnOn = !turnOn;
                                });
                              } else {
                                showToast(
                                    'No tienes permiso para realizar esta acción');
                              }
                            },
                            child: AnimatedContainer(
                              key: bottomKey,
                              duration: const Duration(milliseconds: 500),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: turnOn
                                    ? Colors.greenAccent
                                    : Colors.redAccent,
                                shape: BoxShape.circle,
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 10,
                                    offset: Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: AnimatedCrossFade(
                                firstChild: Icon(
                                  isNC ? Icons.lock_open : Icons.lock,
                                  size: 80,
                                  color: Colors.white,
                                ),
                                secondChild: Icon(
                                  isNC ? Icons.lock : Icons.lock_open,
                                  size: 80,
                                  color: Colors.white,
                                ),
                                crossFadeState: turnOn
                                    ? CrossFadeState.showFirst
                                    : CrossFadeState.showSecond,
                                duration: const Duration(milliseconds: 500),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            key: estadoKey,
                            turnOn ? 'ENCENDIDO' : 'APAGADO',
                            style: GoogleFonts.poppins(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              color: color3,
                            ),
                          ),
                          const SizedBox(height: 50),
                          if (deviceOwner || owner == '')
                            Card(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              elevation: 5,
                              color: color3,
                              child: Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Puedes cambiar entre Normal Abierto (NA) y Normal Cerrado (NC). Selecciona una opción:',
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        color: color0,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 20),
                                    Container(
                                      height: 40,
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(30.0),
                                        border: Border.all(
                                          color: color0,
                                          width: 2,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  isNC = false;
                                                });
                                                saveNC(
                                                  service,
                                                  DeviceManager.getProductCode(
                                                      deviceName),
                                                  DeviceManager
                                                      .extractSerialNumber(
                                                          deviceName),
                                                  false,
                                                );
                                              },
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: !isNC
                                                      ? color0
                                                      : Colors.transparent,
                                                  borderRadius:
                                                      const BorderRadius.only(
                                                    topLeft:
                                                        Radius.circular(28),
                                                    bottomLeft:
                                                        Radius.circular(28),
                                                  ),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    'Normal Abierto',
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 14,
                                                      color: !isNC
                                                          ? color3
                                                          : color0,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Container(
                                            width: 2,
                                            color: color0,
                                          ),
                                          Expanded(
                                            child: GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  isNC = true;
                                                });
                                                saveNC(
                                                  service,
                                                  DeviceManager.getProductCode(
                                                      deviceName),
                                                  DeviceManager
                                                      .extractSerialNumber(
                                                          deviceName),
                                                  true,
                                                );
                                              },
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: isNC
                                                      ? color0
                                                      : Colors.transparent,
                                                  borderRadius:
                                                      const BorderRadius.only(
                                                    topRight:
                                                        Radius.circular(28),
                                                    bottomRight:
                                                        Radius.circular(28),
                                                  ),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    'Normal Cerrado',
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 14,
                                                      color: isNC
                                                          ? color3
                                                          : color0,
                                                    ),
                                                  ),
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
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (isRegularUser && owner != '' && !tenant) ...{
                    Container(
                      color: Colors.black.withValues(alpha: 0.7),
                      child: const Center(
                        child: Text(
                          'No tienes acceso a esta función',
                          style: TextStyle(color: Colors.white, fontSize: 18),
                        ),
                      ),
                    ),
                  },
                  if (tracking) ...{
                    Container(
                      color: Colors.black.withValues(alpha: 0.7),
                      child: const Center(
                        child: Text(
                          'Desactiva control por presencia para utilizar esta función',
                          style: TextStyle(color: Colors.white, fontSize: 18),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  },
                ],
              ),
            ),
          ),
        ),
      ),

      //*- Página 2: Trackeo Bluetooth -*\\

      //TODO se quita temporalmente
      // Stack(
      //   children: [
      //     SingleChildScrollView(
      //       child: Padding(
      //         padding:
      //             const EdgeInsets.symmetric(horizontal: 20.0, vertical: 30.0),
      //         child: Column(
      //           crossAxisAlignment: CrossAxisAlignment.center,
      //           children: [
      //             Text(
      //               'Control por presencia',
      //               style: GoogleFonts.poppins(
      //                 fontSize: 28,
      //                 fontWeight: FontWeight.bold,
      //                 color: color3,
      //               ),
      //               textAlign: TextAlign.center,
      //             ),
      //             const SizedBox(height: 40),
      //             GestureDetector(
      //               onTap: () {
      //                 if (deviceOwner || owner == '') {
      //                   if (isAgreeChecked) {
      //                     verifyPermission().then((accepted) async {
      //                       if (accepted) {
      //                         setState(() {
      //                           tracking = !tracking;
      //                         });
      //                         if (tracking) {
      //                           devicesToTrack.add(deviceName);
      //                           saveDeviceListToTrack(devicesToTrack);
      //                           SharedPreferences prefs =
      //                               await SharedPreferences.getInstance();
      //                           bool hasInitService =
      //                               prefs.getBool('hasInitService') ?? false;
      //                           if (!hasInitService) {
      //                             await initializeService();
      //                             await prefs.setBool('hasInitService', true);
      //                           }
      //                           await Future.delayed(
      //                               const Duration(seconds: 30));
      //                           printLog("Achi");
      //                           final backService = FlutterBackgroundService();
      //                           backService.invoke('presenceControl');
      //                         } else {
      //                           devicesToTrack.remove(deviceName);
      //                           saveDeviceListToTrack(devicesToTrack);
      //                           if (devicesToTrack.isEmpty) {
      //                             final backService =
      //                                 FlutterBackgroundService();
      //                             backService.invoke('CancelpresenceControl');
      //                           }
      //                         }
      //                       } else {
      //                         showToast(
      //                             'Debes habilitar la ubicación constante\npara el uso del\ncontrol por presencia');
      //                       }
      //                     });
      //                   } else {
      //                     showToast(
      //                         'Debes aceptar el uso de control por presencia');
      //                   }
      //                 } else {
      //                   showToast(
      //                       'No tienes permiso para realizar esta acción');
      //                 }
      //               },
      //               child: AnimatedContainer(
      //                 duration: const Duration(milliseconds: 500),
      //                 padding: const EdgeInsets.all(20),
      //                 decoration: BoxDecoration(
      //                   color: tracking ? Colors.greenAccent : Colors.redAccent,
      //                   shape: BoxShape.circle,
      //                   boxShadow: const [
      //                     BoxShadow(
      //                       color: Colors.black26,
      //                       blurRadius: 10,
      //                       offset: Offset(0, 5),
      //                     ),
      //                   ],
      //                 ),
      //                 child: Icon(
      //                   Icons.directions_walk,
      //                   size: 80,
      //                   color: tracking ? Colors.white : Colors.grey[300],
      //                 ),
      //               ),
      //             ),
      //             const SizedBox(height: 70),
      //             Card(
      //               shape: RoundedRectangleBorder(
      //                 borderRadius: BorderRadius.circular(20),
      //               ),
      //               elevation: 5,
      //               color: color3,
      //               child: Padding(
      //                 padding: const EdgeInsets.all(20.0),
      //                 child: Column(
      //                   crossAxisAlignment: CrossAxisAlignment.start,
      //                   children: [
      //                     Text(
      //                       'Habilitar esta función hará que la aplicación use más recursos de lo común, si a pesar de esto decides utilizarlo es bajo tu responsabilidad.',
      //                       style: GoogleFonts.poppins(
      //                         fontSize: 16,
      //                         color: color0,
      //                       ),
      //                     ),
      //                     const SizedBox(height: 10),
      //                     CheckboxListTile(
      //                       title: Text(
      //                         'Sí, estoy de acuerdo',
      //                         style: GoogleFonts.poppins(
      //                           fontSize: 16,
      //                           color: color0,
      //                         ),
      //                       ),
      //                       value: isAgreeChecked,
      //                       activeColor: color0,
      //                       onChanged: (bool? value) {
      //                         setState(() {
      //                           isAgreeChecked = value ?? false;
      //                           if (!isAgreeChecked && tracking) {
      //                             tracking = false;
      //                             devicesToTrack.remove(deviceName);
      //                             saveDeviceListToTrack(devicesToTrack);
      //                           }
      //                         });
      //                       },
      //                       controlAffinity: ListTileControlAffinity.leading,
      //                     ),
      //                   ],
      //                 ),
      //               ),
      //             ),
      //           ],
      //         ),
      //       ),
      //     ),
      //     if (!deviceOwner && owner != '')
      //       Container(
      //         color: Colors.black.withValues(alpha: 0.7),
      //         child: const Center(
      //           child: Text(
      //             'No tienes acceso a esta función',
      //             style: TextStyle(color: Colors.white, fontSize: 18),
      //           ),
      //         ),
      //       ),
      //   ],
      // ),

      //*- Página 3 - Control por distancia -*\\
      SingleChildScrollView(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      key: distanceKey,
                      'Control por distancia',
                      style: GoogleFonts.poppins(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: color3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Activar control por distancia',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: color3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 30),
                    GestureDetector(
                      key: distanceBottomKey,
                      onTap: () {
                        if (deviceOwner || owner == '' || tenant) {
                          verifyPermission().then((result) {
                            if (result == true) {
                              setState(() {
                                isTaskScheduled[deviceName] =
                                    !(isTaskScheduled[deviceName] ?? false);
                              });
                              saveControlValue(isTaskScheduled);
                              controlTask(isTaskScheduled[deviceName] ?? false,
                                  deviceName);
                            } else {
                              showToast(
                                'Permitir ubicación todo el tiempo\nPara usar el control por distancia',
                              );
                              openAppSettings();
                            }
                          });
                        } else {
                          showToast('No tienes acceso a esta función');
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isTaskScheduled[deviceName] ?? false
                              ? Colors.greenAccent
                              : Colors.redAccent,
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 10,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Icon(
                            (isTaskScheduled[deviceName] ?? false)
                                ? Icons.check_circle_outline_rounded
                                : Icons.cancel_rounded,
                            size: 80,
                            color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 10),
                    AnimatedOpacity(
                      opacity: isTaskScheduled[deviceName] ?? false ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 500),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeInOut,
                        child: isTaskScheduled[deviceName] ?? false
                            ? Column(
                                children: [
                                  // Tarjeta de Distancia de apagado
                                  Card(
                                    color: color3.withValues(alpha: 0.9),
                                    elevation: 6,
                                    margin: const EdgeInsets.symmetric(
                                        vertical: 8.0, horizontal: 20.0),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                      side: BorderSide(
                                        color: Color.lerp(
                                            Colors.blueAccent,
                                            Colors.redAccent,
                                            (distOffValue - 100) / 200)!,
                                        width: 2,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(10.0),
                                      child: Column(
                                        children: [
                                          const Text(
                                            'Distancia de apagado',
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: color1,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                distOffValue.round().toString(),
                                                style: const TextStyle(
                                                  fontSize: 24,
                                                  color: color1,
                                                ),
                                              ),
                                              const Text(
                                                ' Metros',
                                                style: TextStyle(
                                                  fontSize: 24,
                                                  color: color1,
                                                ),
                                              ),
                                            ],
                                          ),
                                          SliderTheme(
                                            data: SliderTheme.of(context)
                                                .copyWith(
                                              trackHeight: 20.0,
                                              thumbColor: color3,
                                              activeTrackColor:
                                                  Colors.blueAccent,
                                              inactiveTrackColor:
                                                  Colors.blueGrey[100],
                                              thumbShape:
                                                  const RoundSliderThumbShape(
                                                enabledThumbRadius: 12.0,
                                                elevation: 0.0,
                                                pressedElevation: 0.0,
                                              ),
                                            ),
                                            child: Slider(
                                              activeColor: Colors.white,
                                              inactiveColor:
                                                  const Color(0xFFBDBDBD),
                                              value: distOffValue,
                                              divisions: 20,
                                              onChanged: (value) {
                                                setState(() {
                                                  distOffValue = value;
                                                });
                                              },
                                              onChangeEnd: (value) {
                                                printLog(
                                                    'Valor enviado: ${value.round()}');
                                                putDistanceOff(
                                                  service,
                                                  DeviceManager.getProductCode(
                                                      deviceName),
                                                  DeviceManager
                                                      .extractSerialNumber(
                                                          deviceName),
                                                  value.toString(),
                                                );
                                              },
                                              min: 100,
                                              max: 300,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 15),
                                  Card(
                                    color: color3.withValues(alpha: 0.9),
                                    elevation: 6,
                                    margin: const EdgeInsets.symmetric(
                                        vertical: 8.0, horizontal: 20.0),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                      side: BorderSide(
                                        color: Color.lerp(
                                            Colors.blueAccent,
                                            Colors.redAccent,
                                            (distOnValue - 3000) / 2000)!,
                                        width: 2,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(10.0),
                                      child: Column(
                                        children: [
                                          const Text(
                                            'Distancia de encendido',
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: color1,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                distOnValue.round().toString(),
                                                style: const TextStyle(
                                                  fontSize: 24,
                                                  color: color1,
                                                ),
                                              ),
                                              const Text(
                                                ' Metros',
                                                style: TextStyle(
                                                  fontSize: 24,
                                                  color: color1,
                                                ),
                                              ),
                                            ],
                                          ),
                                          SliderTheme(
                                            data: SliderTheme.of(context)
                                                .copyWith(
                                              trackHeight: 20.0,
                                              thumbColor: color3,
                                              activeTrackColor:
                                                  Colors.blueAccent,
                                              inactiveTrackColor:
                                                  Colors.blueGrey[100],
                                              thumbShape:
                                                  const RoundSliderThumbShape(
                                                enabledThumbRadius: 12.0,
                                                elevation: 0.0,
                                                pressedElevation: 0.0,
                                              ),
                                            ),
                                            child: Slider(
                                              activeColor: Colors.white,
                                              inactiveColor:
                                                  const Color(0xFFBDBDBD),
                                              value: distOnValue,
                                              divisions: 20,
                                              onChanged: (value) {
                                                setState(() {
                                                  distOnValue = value;
                                                });
                                              },
                                              onChangeEnd: (value) {
                                                printLog(
                                                    'Valor enviado: ${value.round()}');
                                                putDistanceOn(
                                                  service,
                                                  DeviceManager.getProductCode(
                                                      deviceName),
                                                  DeviceManager
                                                      .extractSerialNumber(
                                                          deviceName),
                                                  value.toString(),
                                                );
                                              },
                                              min: 3000,
                                              max: 5000,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : const SizedBox(),
                      ),
                    ),
                  ],
                ),
              ),
              if (!deviceOwner && owner != '' && !tenant)
                Container(
                  color: Colors.black.withValues(alpha: 0.7),
                  child: const Center(
                    child: Text(
                      'No tienes acceso a esta función',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      //*- Página 4: Gestión del Equipo -*\\
      SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 30.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                key: adminKey,
                'Gestión del equipo',
                style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: color3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              //! Opción - Reclamar propiedad del equipo o dejar de ser propietario
              InkWell(
                key: claimKey,
                onTap: () async {
                  if (deviceOwner) {
                    showAlertDialog(
                      context,
                      false,
                      const Text(
                        '¿Dejar de ser administrador del equipo?',
                      ),
                      const Text(
                        'Esto hará que otras personas puedan conectarse al dispositivo y modificar sus parámetros',
                      ),
                      <Widget>[
                        TextButton(
                          child: const Text('Cancelar'),
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                        ),
                        TextButton(
                          child: const Text('Aceptar'),
                          onPressed: () {
                            try {
                              putOwner(
                                service,
                                DeviceManager.getProductCode(deviceName),
                                DeviceManager.extractSerialNumber(deviceName),
                                '',
                              );
                              Navigator.of(context).pop();
                              setState(() {
                                owner = '';
                                deviceOwner = false;
                                showOptions = false;
                              });
                            } catch (e, s) {
                              printLog('Error al borrar owner $e Trace: $s');
                              showToast('Error al borrar el administrador.');
                            }
                          },
                        ),
                      ],
                    );
                  } else if (owner == '') {
                    try {
                      putOwner(
                        service,
                        DeviceManager.getProductCode(deviceName),
                        DeviceManager.extractSerialNumber(deviceName),
                        currentUserEmail,
                      );
                      setState(() {
                        owner = currentUserEmail;
                        deviceOwner = true;
                        showOptions = true;
                      });
                      showToast('Ahora eres el propietario del equipo');
                    } catch (e, s) {
                      printLog('Error al agregar owner $e Trace: $s');
                      showToast('Error al agregar el administrador.');
                    }
                  } else {
                    showToast('El equipo ya esta reclamado');
                  }
                },
                borderRadius: BorderRadius.circular(15),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: color6,
                    shape: BoxShape.rectangle,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Text(
                    deviceOwner
                        ? 'Dejar de ser dueño del equipo'
                        : 'Reclamar propiedad del equipo',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              //! Opciones adicionales con animación
              AnimatedSize(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeInOut,
                child: AnimatedOpacity(
                  opacity: showOptions ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 600),
                  child: showOptions
                      ? Column(
                          children: [
                            //! Opciones adicionales existentes (deviceOwner)
                            if (deviceOwner) ...[
                              //! Opción 2 - Añadir administradores secundarios
                              InkWell(
                                key: agreeAdminKey,
                                onTap: () {
                                  setState(() {
                                    showSecondaryAdminFields =
                                        !showSecondaryAdminFields;
                                  });
                                },
                                borderRadius: BorderRadius.circular(15),
                                child: Container(
                                  padding: const EdgeInsets.all(15),
                                  decoration: BoxDecoration(
                                    color: color3,
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Añadir administradores\nsecundarios',
                                        style: GoogleFonts.poppins(
                                          fontSize: 15,
                                          color: color0,
                                        ),
                                      ),
                                      Icon(
                                        showSecondaryAdminFields
                                            ? Icons.arrow_drop_up
                                            : Icons.arrow_drop_down,
                                        color: color0,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 600),
                                curve: Curves.easeInOut,
                                child: showSecondaryAdminFields
                                    ? Column(
                                        children: [
                                          const SizedBox(height: 10),
                                          AnimatedOpacity(
                                            opacity: showSecondaryAdminFields
                                                ? 1.0
                                                : 0.0,
                                            duration: const Duration(
                                                milliseconds: 600),
                                            child: TextField(
                                              controller: emailController,
                                              cursorColor: color3,
                                              style: GoogleFonts.poppins(
                                                color: color3,
                                              ),
                                              decoration: InputDecoration(
                                                labelText: 'Correo electrónico',
                                                labelStyle: GoogleFonts.poppins(
                                                  fontSize: 16,
                                                  color: color3,
                                                ),
                                                filled: true,
                                                fillColor: Colors.transparent,
                                                focusedBorder:
                                                    OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(15),
                                                  borderSide: const BorderSide(
                                                    color: color3,
                                                    width: 2,
                                                  ),
                                                ),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(15),
                                                  borderSide: const BorderSide(
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          InkWell(
                                            onTap: () {
                                              if (emailController
                                                  .text.isNotEmpty) {
                                                addSecondaryAdmin(
                                                    emailController.text
                                                        .trim());
                                              }
                                            },
                                            borderRadius:
                                                BorderRadius.circular(15),
                                            child: Container(
                                              padding: const EdgeInsets.all(15),
                                              decoration: BoxDecoration(
                                                color: color3,
                                                borderRadius:
                                                    BorderRadius.circular(15),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  'Añadir administrador',
                                                  style: GoogleFonts.poppins(
                                                    color: color0,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : const SizedBox(),
                              ),
                              const SizedBox(height: 10),
                              //! Opción 3 - Ver administradores secundarios
                              InkWell(
                                key: viewAdminKey,
                                onTap: () {
                                  setState(() {
                                    showSecondaryAdminList =
                                        !showSecondaryAdminList;
                                  });
                                },
                                borderRadius: BorderRadius.circular(15),
                                child: Container(
                                  padding: const EdgeInsets.all(15),
                                  decoration: BoxDecoration(
                                    color: color3,
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Ver administradores\nsecundarios',
                                        style: GoogleFonts.poppins(
                                          fontSize: 15,
                                          color: color0,
                                        ),
                                      ),
                                      Icon(
                                        showSecondaryAdminList
                                            ? Icons.arrow_drop_up
                                            : Icons.arrow_drop_down,
                                        color: color0,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 600),
                                curve: Curves.easeInOut,
                                child: showSecondaryAdminList
                                    ? adminDevices.isEmpty
                                        ? Text(
                                            'No hay administradores secundarios.',
                                            style: GoogleFonts.poppins(
                                              fontSize: 16,
                                              color: color3,
                                            ),
                                          )
                                        : Column(
                                            children: adminDevices.map((email) {
                                              return AnimatedContainer(
                                                duration: const Duration(
                                                    milliseconds: 300),
                                                curve: Curves.easeInOut,
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 5),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 10,
                                                        horizontal: 15),
                                                decoration: BoxDecoration(
                                                  color: color3,
                                                  borderRadius:
                                                      BorderRadius.circular(15),
                                                  border: Border.all(
                                                    color: color0,
                                                    width: 2,
                                                  ),
                                                  boxShadow: const [
                                                    BoxShadow(
                                                      color: Colors.black12,
                                                      blurRadius: 4,
                                                      offset: Offset(2, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        email,
                                                        style:
                                                            GoogleFonts.poppins(
                                                          fontSize: 16,
                                                          color: color0,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(
                                                          Icons.delete,
                                                          color: color5),
                                                      onPressed: () {
                                                        removeSecondaryAdmin(
                                                            email);
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }).toList(),
                                          )
                                    : const SizedBox(),
                              ),
                              const SizedBox(height: 10),
                              //! Opción 4 - Alquiler temporario
                              InkWell(
                                key: habitKey,
                                onTap: () {
                                  if (activatedAT) {
                                    setState(() {
                                      showSmartResident = !showSmartResident;
                                    });
                                  } else {
                                    if (!payAT) {
                                      showAlertDialog(
                                        context,
                                        true,
                                        Text(
                                          'Actualmente no tienes habilitado este beneficio',
                                          style: GoogleFonts.poppins(
                                              color: color0),
                                        ),
                                        Text(
                                          'En caso de requerirlo puedes solicitarlo vía mail',
                                          style: GoogleFonts.poppins(
                                              color: color0),
                                        ),
                                        [
                                          TextButton(
                                            style: TextButton.styleFrom(
                                              foregroundColor:
                                                  const Color(0xFFFFFFFF),
                                            ),
                                            onPressed: () async {
                                              String cuerpo =
                                                  '¡Hola! Me comunico porque busco habilitar la opción de "Alquiler temporario" en mi equipo $deviceName\nCódigo de Producto: ${DeviceManager.getProductCode(deviceName)}\nNúmero de Serie: ${DeviceManager.extractSerialNumber(deviceName)}\nDueño actual del equipo: $owner';
                                              final Uri emailLaunchUri = Uri(
                                                scheme: 'mailto',
                                                path:
                                                    'cobranzas@ibsanitarios.com.ar',
                                                query:
                                                    encodeQueryParameters(<String,
                                                        String>{
                                                  'subject':
                                                      'Habilitación Alquiler temporario',
                                                  'body': cuerpo,
                                                  'CC':
                                                      'pablo@intelligentgas.com.ar'
                                                }),
                                              );
                                              if (await canLaunchUrl(
                                                  emailLaunchUri)) {
                                                await launchUrl(emailLaunchUri);
                                              } else {
                                                showToast(
                                                    'No se pudo enviar el correo electrónico');
                                              }
                                              navigatorKey.currentState?.pop();
                                            },
                                            child: const Text('Solicitar'),
                                          ),
                                        ],
                                      );
                                    } else {
                                      setState(() {
                                        showSmartResident = !showSmartResident;
                                      });
                                    }
                                  }
                                },
                                borderRadius: BorderRadius.circular(15),
                                child: Container(
                                  padding: const EdgeInsets.all(15),
                                  decoration: BoxDecoration(
                                    color: color3,
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Alquiler temporario',
                                        style: GoogleFonts.poppins(
                                            fontSize: 15, color: color0),
                                      ),
                                      Icon(
                                        showSmartResident
                                            ? Icons.arrow_drop_up
                                            : Icons.arrow_drop_down,
                                        color: color0,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 600),
                                curve: Curves.easeInOut,
                                child: showSmartResident && payAT
                                    ? Column(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(20),
                                            margin:
                                                const EdgeInsets.only(top: 20),
                                            decoration: BoxDecoration(
                                              color: color3,
                                              borderRadius:
                                                  BorderRadius.circular(15),
                                              boxShadow: const [
                                                BoxShadow(
                                                  color: Colors.black26,
                                                  blurRadius: 5,
                                                  offset: Offset(0, 3),
                                                ),
                                              ],
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Configura los parámetros del alquiler',
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                    color: color0,
                                                  ),
                                                ),
                                                const SizedBox(height: 20),
                                                TextField(
                                                  controller: tenantController,
                                                  keyboardType: TextInputType
                                                      .emailAddress,
                                                  style: GoogleFonts.poppins(
                                                      color: color0),
                                                  decoration: InputDecoration(
                                                    labelText:
                                                        "Email del inquilino",
                                                    labelStyle:
                                                        GoogleFonts.poppins(
                                                            color: color0),
                                                    enabledBorder:
                                                        OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              15),
                                                      borderSide:
                                                          const BorderSide(
                                                              color: color0),
                                                    ),
                                                    focusedBorder:
                                                        OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              15),
                                                      borderSide:
                                                          const BorderSide(
                                                              color: color0),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 20),
                                                // Mostrar el email actual solo si existe
                                                if (activatedAT)
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            15),
                                                    decoration: BoxDecoration(
                                                      color: color3,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              15),
                                                      border: Border.all(
                                                          color: color0,
                                                          width: 2),
                                                      boxShadow: const [
                                                        BoxShadow(
                                                          color: Colors.black12,
                                                          blurRadius: 4,
                                                          offset: Offset(2, 2),
                                                        ),
                                                      ],
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'Inquilino actual:',
                                                          style: GoogleFonts
                                                              .poppins(
                                                            fontSize: 16,
                                                            color: color0,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            height: 5),
                                                        Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .spaceBetween,
                                                          children: [
                                                            Expanded(
                                                              child: Text(
                                                                globalDATA[
                                                                        '${DeviceManager.getProductCode(deviceName)}/${DeviceManager.extractSerialNumber(deviceName)}']
                                                                    ?['tenant'],
                                                                style:
                                                                    GoogleFonts
                                                                        .poppins(
                                                                  fontSize: 14,
                                                                  color: color0,
                                                                ),
                                                              ),
                                                            ),
                                                            IconButton(
                                                              icon: const Icon(
                                                                  Icons.delete,
                                                                  color: Colors
                                                                      .redAccent),
                                                              onPressed:
                                                                  () async {
                                                                await saveATData(
                                                                  service,
                                                                  DeviceManager
                                                                      .getProductCode(
                                                                          deviceName),
                                                                  DeviceManager
                                                                      .extractSerialNumber(
                                                                          deviceName),
                                                                  false,
                                                                  '',
                                                                  '3000',
                                                                  '100',
                                                                );

                                                                setState(() {
                                                                  tenantController
                                                                      .clear();
                                                                  globalDATA[
                                                                          '${DeviceManager.getProductCode(deviceName)}/${DeviceManager.extractSerialNumber(deviceName)}']
                                                                      ?[
                                                                      'tenant'] = '';
                                                                  activatedAT =
                                                                      false;
                                                                  dOnOk = false;
                                                                  dOffOk =
                                                                      false;
                                                                });
                                                                showToast(
                                                                    "Inquilino eliminado correctamente.");
                                                              },
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),

                                                const SizedBox(height: 10),

                                                // Distancia de apagado y encendido sliders
                                                Text(
                                                  'Distancia de apagado (${distOffValue.round()} metros)',
                                                  style: GoogleFonts.poppins(
                                                      color: color0),
                                                ),
                                                Slider(
                                                  value: distOffValue,
                                                  min: 100,
                                                  max: 300,
                                                  divisions: 200,
                                                  activeColor: color0,
                                                  inactiveColor: color0
                                                      .withValues(alpha: 0.3),
                                                  onChanged: (double value) {
                                                    setState(() {
                                                      distOffValue = value;
                                                      dOffOk = true;
                                                    });
                                                  },
                                                ),
                                                const SizedBox(height: 10),
                                                Text(
                                                  'Distancia de encendido (${distOnValue.round()} metros)',
                                                  style: GoogleFonts.poppins(
                                                      color: color0),
                                                ),
                                                Slider(
                                                  value: distOnValue,
                                                  min: 3000,
                                                  max: 5000,
                                                  divisions: 200,
                                                  activeColor: color0,
                                                  inactiveColor: color0
                                                      .withValues(alpha: 0.3),
                                                  onChanged: (double value) {
                                                    setState(() {
                                                      distOnValue = value;
                                                      dOnOk = true;
                                                    });
                                                  },
                                                ),
                                                const SizedBox(height: 20),

                                                // Botones de Activar y Cancelar
                                                Center(
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      TextButton(
                                                        onPressed: () {
                                                          if (dOnOk &&
                                                              dOffOk &&
                                                              tenantController
                                                                  .text
                                                                  .isNotEmpty) {
                                                            saveATData(
                                                              service,
                                                              DeviceManager
                                                                  .getProductCode(
                                                                      deviceName),
                                                              DeviceManager
                                                                  .extractSerialNumber(
                                                                      deviceName),
                                                              true,
                                                              tenantController
                                                                  .text
                                                                  .trim(),
                                                              distOnValue
                                                                  .round()
                                                                  .toString(),
                                                              distOffValue
                                                                  .round()
                                                                  .toString(),
                                                            );

                                                            setState(() {
                                                              activatedAT =
                                                                  true;
                                                              globalDATA['${DeviceManager.getProductCode(deviceName)}/${DeviceManager.extractSerialNumber(deviceName)}']
                                                                      ?[
                                                                      'tenant'] =
                                                                  tenantController
                                                                      .text
                                                                      .trim();
                                                            });
                                                            showToast(
                                                                'Configuración guardada para el inquilino.');
                                                          } else {
                                                            showToast(
                                                                'Por favor, completa todos los campos');
                                                          }
                                                        },
                                                        style: TextButton
                                                            .styleFrom(
                                                          backgroundColor:
                                                              color0,
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal:
                                                                      30,
                                                                  vertical: 15),
                                                          shape:
                                                              RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        15),
                                                          ),
                                                        ),
                                                        child: Text(
                                                          'Activar',
                                                          style: GoogleFonts
                                                              .poppins(
                                                                  color: color3,
                                                                  fontSize: 16),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 20),
                                                      TextButton(
                                                        onPressed: () {
                                                          setState(() {
                                                            showSmartResident =
                                                                false;
                                                          });
                                                        },
                                                        style: TextButton
                                                            .styleFrom(
                                                          backgroundColor:
                                                              color0,
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal:
                                                                      30,
                                                                  vertical: 15),
                                                          shape:
                                                              RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        15),
                                                          ),
                                                        ),
                                                        child: Text(
                                                          'Cancelar',
                                                          style: GoogleFonts
                                                              .poppins(
                                                                  color: color3,
                                                                  fontSize: 16),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      )
                                    : const SizedBox(),
                              ),
                              const SizedBox(height: 10),
                            ],
                          ],
                        )
                      : const SizedBox(),
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                key: fastBotonKey,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (!quickAccesActivated) {
                      quickAccess.add(deviceName);
                      await savequickAccess(quickAccess);
                      setState(() {
                        quickAccesActivated = true;
                      });
                    } else {
                      quickAccess.remove(deviceName);
                      await savequickAccess(quickAccess);
                      setState(() {
                        quickAccesActivated = false;
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: color0,
                    backgroundColor: color3,
                    padding: const EdgeInsets.symmetric(
                        vertical: 11, horizontal: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: Text(
                    quickAccesActivated
                        ? 'Desactivar acceso rápido'
                        : 'Activar acceso rápido',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              if (owner == '' || deviceOwner || secondaryAdmin) ...{
                //! activar notificación
                ElevatedButton(
                  key: fastAccessKey,
                  onPressed: () async {
                    if (discNotfActivated) {
                      showAlertDialog(
                        context,
                        true,
                        Text(
                          'Confirmar Desactivación',
                          style: GoogleFonts.poppins(color: color0),
                        ),
                        Text(
                          '¿Estás seguro de que deseas desactivar la notificación de desconexión?',
                          style: GoogleFonts.poppins(color: color0),
                        ),
                        [
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            child: Text(
                              'Cancelar',
                              style: GoogleFonts.poppins(color: color0),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              // Actualizar el estado para desactivar la notificación
                              setState(() {
                                discNotfActivated = false;
                                _showNotificationOptions = false;
                              });

                              // Eliminar la configuración de notificación para el dispositivo actual
                              configNotiDsc.removeWhere(
                                  (key, value) => key == deviceName);
                              await saveconfigNotiDsc(configNotiDsc);

                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                            child: Text(
                              'Aceptar',
                              style: GoogleFonts.poppins(color: color0),
                            ),
                          ),
                        ],
                      );
                    } else {
                      setState(() {
                        _showNotificationOptions = !_showNotificationOptions;
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: color0,
                    backgroundColor: color3,
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        discNotfActivated
                            ? 'Desactivar notificación\nde desconexión'
                            : 'Activar notificación\nde desconexión',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          color: color0,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              },
              // Tarjeta de opciones de notificación
              AnimatedSize(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeInOut,
                child: _showNotificationOptions
                    ? Container(
                        padding: const EdgeInsets.all(20),
                        margin: const EdgeInsets.only(top: 20),
                        decoration: BoxDecoration(
                          color: color3,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Selecciona cuándo deseas recibir una notificación en caso de que el equipo se desconecte:',
                              style: GoogleFonts.poppins(
                                  color: color0, fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            RadioListTile<int>(
                              value: 0,
                              groupValue: _selectedNotificationOption,
                              onChanged: (int? value) {
                                setState(() {
                                  _selectedNotificationOption = value!;
                                });
                              },
                              activeColor: color1,
                              title: Text(
                                'Instantáneo',
                                style: GoogleFonts.poppins(color: color0),
                              ),
                            ),
                            RadioListTile<int>(
                              value: 10,
                              groupValue: _selectedNotificationOption,
                              onChanged: (int? value) {
                                setState(() {
                                  _selectedNotificationOption = value!;
                                });
                              },
                              activeColor: color1,
                              title: Text(
                                'Si permanece 10 minutos desconectado',
                                style: GoogleFonts.poppins(color: color0),
                              ),
                            ),
                            RadioListTile<int>(
                              value: 60,
                              groupValue: _selectedNotificationOption,
                              onChanged: (int? value) {
                                setState(() {
                                  _selectedNotificationOption = value!;
                                });
                              },
                              activeColor: color1,
                              title: Text(
                                'Si permanece 1 hora desconectado',
                                style: GoogleFonts.poppins(color: color0),
                              ),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: () async {
                                setState(() {
                                  discNotfActivated = true;
                                  _showNotificationOptions = false;
                                });

                                configNotiDsc[deviceName] =
                                    _selectedNotificationOption;
                                await saveconfigNotiDsc(configNotiDsc);

                                showNotification(
                                  'Notificación Activada',
                                  'Has activado la notificación de desconexión con la opción seleccionada.',
                                  'noti',
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: color0,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 15, horizontal: 15),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                              child: Text(
                                'Aceptar',
                                style: GoogleFonts.poppins(
                                    color: color3, fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              const SizedBox(height: 10),
              SizedBox(
                key: imageKey,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    ImageManager.openImageOptions(context, deviceName, () {
                      setState(() {
                        // La UI se reconstruirá automáticamente para mostrar la nueva imagen
                      });
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: color0,
                    backgroundColor: color3,
                    padding: const EdgeInsets.symmetric(
                        vertical: 11, horizontal: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text(
                    'Cambiar imagen del dispositivo',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    showAlertDialog(
                      context,
                      true,
                      Text(
                        'Beneficios',
                        style: GoogleFonts.poppins(color: color0),
                      ),
                      Text(
                        '- Encendio rapido y sencillo al alcance de tu mano\n- Configura tu temperatura ideal\n- Mayor eficiencia energética\n- Control de consumo inmediato\n- Mayor comodidad\n- Seguridad corte automático sobre temperatura superior a la establecida\n- Programación de encendido por dias o por franjas horarias\n- Mayor durabilidad',
                        style: GoogleFonts.poppins(color: color0),
                      ),
                      [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: Text(
                            'Cerrar',
                            style: GoogleFonts.poppins(color: color0),
                          ),
                        ),
                      ],
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    foregroundColor: color0,
                    backgroundColor: color3,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text(
                    'Beneficios de termotanque smart',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              Container(
                width: MediaQuery.of(context).size.width * 1.5,
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                decoration: BoxDecoration(
                  color: color3,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Versión de Hardware: $hardwareVersion',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    textStyle: const TextStyle(
                      color: color0,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: MediaQuery.of(context).size.width * 1.5,
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                decoration: BoxDecoration(
                  color: color3,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Versión de Software: $softwareVersion',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    textStyle: const TextStyle(
                      color: color0,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(bottom: bottomBarHeight + 30),
              ),
            ],
          ),
        ),
      ),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, A) {
        if (_isTutorialActive) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              backgroundColor: const Color(0xFF252223),
              content: Row(
                children: [
                  Image.asset('assets/branch/dragon.gif',
                      width: 100, height: 100),
                  Container(
                    margin: const EdgeInsets.only(left: 15),
                    child: const Text(
                      "Desconectando...",
                      style: TextStyle(color: Color(0xFFFFFFFF)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
        Future.delayed(const Duration(seconds: 2), () async {
          await myDevice.device.disconnect();
          if (context.mounted) {
            Navigator.pop(context);
            Navigator.pushReplacementNamed(context, '/menu');
          }
        });
        return;
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: color3,
          title: GestureDetector(
            onTap: () async {
              if (_isTutorialActive) return;
              TextEditingController nicknameController =
                  TextEditingController(text: nickname);
              showAlertDialog(
                context,
                false,
                const Text(
                  'Editar identificación del dispositivo',
                  style: TextStyle(color: color0),
                ),
                TextField(
                  style: const TextStyle(color: color0),
                  cursorColor: const Color(0xFFFFFFFF),
                  controller: nicknameController,
                  decoration: const InputDecoration(
                    hintText:
                        "Introduce tu nueva identificación del dispositivo",
                    hintStyle: TextStyle(color: color0),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: color0),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: color0),
                    ),
                  ),
                ),
                <Widget>[
                  TextButton(
                    style: ButtonStyle(
                      foregroundColor: WidgetStateProperty.all(color0),
                    ),
                    child: const Text('Cancelar'),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                  TextButton(
                    style: ButtonStyle(
                      foregroundColor: WidgetStateProperty.all(color0),
                    ),
                    child: const Text('Guardar'),
                    onPressed: () {
                      setState(() {
                        String newNickname = nicknameController.text;
                        nickname = newNickname;
                        nicknamesMap[deviceName] = newNickname;
                        saveNicknamesMap(nicknamesMap);
                      });
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              );
            },
            child: Row(
              children: [
                Expanded(
                  key: titleKey,
                  child: ScrollingText(
                    text: nickname,
                    style: poppinsStyle.copyWith(color: color0),
                  ),
                ),
                const SizedBox(width: 3),
                const Icon(Icons.edit, size: 20, color: color0)
              ],
            ),
          ),
          leading: IconButton(
            key: estadoKey,
            icon: const Icon(Icons.arrow_back_ios_new),
            color: color0,
            onPressed: () {
              if (_isTutorialActive) return;

              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) {
                  return AlertDialog(
                    backgroundColor: const Color(0xFF252223),
                    content: Row(
                      children: [
                        Image.asset('assets/branch/dragon.gif',
                            width: 100, height: 100),
                        Container(
                          margin: const EdgeInsets.only(left: 15),
                          child: const Text(
                            "Desconectando...",
                            style: TextStyle(color: Color(0xFFFFFFFF)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
              Future.delayed(const Duration(seconds: 2), () async {
                await myDevice.device.disconnect();
                if (context.mounted) {
                  Navigator.pop(context);
                  Navigator.pushReplacementNamed(context, '/menu');
                }
              });
              return;
            },
          ),
          actions: [
            IconButton(
              key: wifiKey,
              icon: Icon(wifiNotifier.wifiIcon, color: color0),
              onPressed: () {
                if (_isTutorialActive) return;

                wifiText(context);
              },
            ),
          ],
        ),
        backgroundColor: color1,
        resizeToAvoidBottomInset: false,
        body: IgnorePointer(
          ignoring: _isTutorialActive,
          child: Stack(
            children: [
              PageView(
                controller: _pageController,
                physics: _isAnimating || _isTutorialActive
                    ? const NeverScrollableScrollPhysics()
                    : const BouncingScrollPhysics(),
                onPageChanged: onItemChanged,
                children: pages,
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  ignoring: _isTutorialActive,
                  child: CurvedNavigationBar(
                    index: _selectedIndex,
                    height: 75.0,
                    items: <Widget>[
                      const Icon(Icons.home, size: 30, color: color0),
                      const Icon(Icons.bluetooth, size: 30, color: color0),
                      if (hardwareVersion == '240422A') ...{
                        const Icon(Icons.input, size: 30, color: color0),
                      },
                      const Icon(Icons.settings, size: 30, color: color0),
                    ],
                    color: color3,
                    buttonBackgroundColor: color3,
                    backgroundColor: Colors.transparent,
                    animationCurve: Curves.easeInOut,
                    animationDuration: const Duration(milliseconds: 600),
                    onTap: onItemTapped,
                    letIndexChange: (index) => true,
                  ),
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: Visibility(
          visible: tutorial,
          child: AnimatedSlide(
            offset: _isTutorialActive ? const Offset(1.5, 0) : Offset.zero,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomBarHeight + 20),
              child: FloatingActionButton(
                onPressed: () {
                  items = [];
                  initItems();
                  setState(() {
                    _isAnimating = true;
                    _selectedIndex = 0;
                    _isTutorialActive = true;
                  });
                  _pageController
                      .animateToPage(
                    0,
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeInOut,
                  )
                      .then((_) {
                    setState(() {
                      _isAnimating = false;
                    });
                    if (context.mounted) {
                      Tutorial.showTutorial(
                        context,
                        items,
                        _pageController,
                        onTutorialComplete: () {
                          setState(() {
                            _isTutorialActive = false;
                          });
                          printLog('Tutorial is complete!', 'verde');
                        },
                      );
                    }
                  });
                },
                backgroundColor: color6,
                shape: const CircleBorder(),
                child: const Icon(Icons.help, size: 30, color: color0),
              ),
            ),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }
}
