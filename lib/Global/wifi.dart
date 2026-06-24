import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:caldensmart/master.dart';
import 'package:caldensmart/Global/stored_data.dart';
import 'package:caldensmart/aws/mqtt/mqtt.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import '../aws/dynamo/dynamo.dart';
import 'package:caldensmart/logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:caldensmart/secret.dart';

class WifiPage extends ConsumerStatefulWidget {
  const WifiPage({super.key});

  @override
  ConsumerState<WifiPage> createState() => WifiPageState();
}

class WifiPageState extends ConsumerState<WifiPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final Map<String, bool> _expandedStates = {};
  final Set<String> _processingGroups = {};
  final Set<String> _processingRiegos = {};
  StreamSubscription<String>? _riegoCompletedSubscription;

  // Flags para control de riego
  bool _isPumpShuttingDown = false;
  bool _isAutoStarting = false;

  // Mapa para almacenar permisos de WiFi por dispositivo
  Map<String, bool> _wifiPermissions = {};

  // Cache de "red inestable" por dispositivo. Se carga una vez en initState
  // y se refresca individualmente cuando un device se desconecta (cstate=false
  // en el globalDataProvider). Si nada cambia, no hace falta refrescar nada.
  Map<String, bool> _networkUnstableCache = {};
  // Para detectar transiciones cstate true→false necesitamos recordar el
  // estado anterior por device entre rebuilds.
  final Map<String, bool> _previousCstate = {};

  int _totalDispositivosReal = 0;

  late TabController _tabController;

  Timer? _saveOrderTimer;
  List<MapEntry<String, String>> _listaIndividuales = [];
  List<MapEntry<String, String>> _listaEventos = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _tabController = TabController(length: 2, vsync: this);

    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });

    setState(() {
      _buildDeviceListFromLoadedData();
    });

    // Verificar el estado de los riegos al inicializar
    _checkRiegosStatus();

    // Escuchar notificaciones de riegos completados
    _setupRiegoCompletedListener();

    // Cargar permisos de WiFi
    _loadWifiPermissions();

    // Cargar estado inicial de "red inestable" por device. Después se
    // actualiza individualmente vía ref.listen en build() cuando un device
    // se desconecta (transición cstate true→false).
    _refreshNetworkUnstableCache();

    // 🆕 Suscribirse a los topics de eventos MQTT
    _subscribeToEventosTopics();
  }

  // 🆕 Suscribirse a los topics MQTT de los eventos del usuario
  void _subscribeToEventosTopics() async {
    try {
      // 1. Primero cargar estados iniciales desde DynamoDB
      await loadInitialEventosState(currentUserEmail, ref);

      // 2. Luego suscribirse a actualizaciones en tiempo real
      subscribeToAllUserEventos(currentUserEmail, eventosCreados);
      printLog.i('✅ Suscrito a todos los eventos del usuario');
    } catch (e) {
      printLog.e('Error suscribiéndose a eventos: $e');
    }
  }

  @override
  void dispose() {
    _saveOrderTimer?.cancel();
    _tabController.dispose();

    WidgetsBinding.instance.removeObserver(this);
    _riegoCompletedSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Verificar el estado cuando la app vuelve al foreground
      _checkRiegosStatus();
      _loadWifiPermissions(); // Recargar permisos de WiFi

      // Re-suscribirse a eventos por si se desconectó MQTT
      _subscribeToEventosTopics();
    }
  }

  // Verificar el estado de los riegos en SharedPreferences
  Future<void> _checkRiegosStatus() async {
    List<String> executingRiegos = await getExecutingRiegos(currentUserEmail);
    setState(() {
      _processingRiegos.clear();
      _processingRiegos.addAll(executingRiegos);
    });
    printLog.i('Riegos en ejecución recuperados: $executingRiegos');
  }

  // Configurar listener para riegos completados en tiempo real
  void _setupRiegoCompletedListener() {
    _riegoCompletedSubscription =
        riegoCompletedController.stream.listen((riegoName) {
      // printLog.i(
      //     'Recibida notificación de riego completado en WiFi UI: $riegoName');
      if (mounted) {
        setState(() {
          _processingRiegos.remove(riegoName);
        });
        showToast('🌱 ¡Rutina de riego "$riegoName" completada exitosamente!');
      }
    });
  }

  // Cargar permisos de WiFi para todos los dispositivos
  Future<void> _loadWifiPermissions() async {
    Map<String, bool> permissions = {};

    // Usar la lista de dispositivos ya construida
    for (var device in todosLosDispositivos) {
      if (device.value.isNotEmpty) {
        try {
          String deviceName = device.value;
          String pc = DeviceManager.getProductCode(deviceName);
          String sn = DeviceManager.extractSerialNumber(deviceName);
          String key = '$pc/$sn';

          bool hasPermission = await checkAdminWifiPermission(deviceName);
          permissions[key] = hasPermission;
        } catch (e) {
          printLog
              .e('Error verificando permisos WiFi para ${device.value}: $e');
          String pc = DeviceManager.getProductCode(device.value);
          String sn = DeviceManager.extractSerialNumber(device.value);
          String key = '$pc/$sn';
          permissions[key] = true; // En caso de error, permitir acceso
        }
      }
    }

    if (mounted) {
      setState(() {
        _wifiPermissions = permissions;
      });
    }
  }

  Future<void> _refreshNetworkUnstableCache() async {
    final Map<String, bool> updated = {};

    for (final device in todosLosDispositivos) {
      if (device.value.isEmpty) continue;
      final String deviceName = device.value;
      final String pc = DeviceManager.getProductCode(deviceName);
      final String sn = DeviceManager.extractSerialNumber(deviceName);
      final String key = '$pc/$sn';

      try {
        updated[key] = await isWifiNetworkUnstable(pc, sn);
      } catch (e) {
        printLog.e('Error chequeando red inestable para $deviceName: $e');
        updated[key] = false; // Ante error, asumimos red estable.
      }
    }

    if (mounted) {
      setState(() {
        _networkUnstableCache = updated;
      });
    }
  }

  /// Refresca el flag "red inestable" para UN device puntual.
  /// Se llama cuando ese device dispara un evento de desconexión por MQTT
  /// (transición cstate true→false detectada con ref.listen en build).
  Future<void> _refreshNetworkUnstableForDevice(String pc, String sn) async {
    try {
      final unstable = await isWifiNetworkUnstable(pc, sn);
      if (mounted) {
        setState(() {
          _networkUnstableCache['$pc/$sn'] = unstable;
        });
      }
    } catch (e) {
      printLog.e('Error refrescando red inestable para $pc/$sn: $e');
    }
  }

  void _buildDeviceListFromLoadedData() {
    try {
      List<MapEntry<String, String>> listaFinal = [];

      Set<String> devicesInFolders = {};

      folders.forEach((folderName, devices) {
        List<String> validDevices =
            devices.where((dev) => previusConnections.contains(dev)).toList();

        folders[folderName] = validDevices;
        devicesInFolders.addAll(validDevices);
      });

      Set<String> processedKeys = {};

      for (var saved in savedOrder) {
        String key = saved['key']!;
        String value = saved['value']!;

        if (key == 'folder') {
          if (value.startsWith('{')) {
            try {
              value = jsonDecode(value)['name'];
            } catch (_) {}
          }

          if (folders.containsKey(value)) {
            listaFinal.add(MapEntry('folder', value));
            processedKeys.add('folder:$value');
          }
        } else if (key == 'individual') {
          if (previusConnections.contains(value) &&
              !devicesInFolders.contains(value)) {
            listaFinal.add(MapEntry('individual', value));
            processedKeys.add('individual:$value');
          }
        } else {
          bool existe = eventosCreados.any((e) =>
              e['title'] == key &&
              (e['deviceGroup'] as List).join(',') == value);
          if (existe) {
            listaFinal.add(MapEntry(key, value));
            processedKeys.add('event:$key:$value');
          }
        }
      }

      List<MapEntry<String, String>> newFolders = [];
      for (var fName in folders.keys) {
        if (!processedKeys.contains('folder:$fName')) {
          newFolders.add(MapEntry('folder', fName));
        }
      }
      listaFinal.insertAll(0, newFolders);

      for (String device in previusConnections) {
        if (!devicesInFolders.contains(device) &&
            !processedKeys.contains('individual:$device')) {
          listaFinal.add(MapEntry('individual', device));
        }
      }

      for (var evento in eventosCreados) {
        String tipo = evento['evento'];
        if (['grupo', 'cadena', 'riego', 'clima', 'disparador', 'horario']
            .contains(tipo)) {
          String key = evento['title'] ?? 'Evento';
          String value = (evento['deviceGroup'] as List<dynamic>).join(',');

          if (!processedKeys.contains('event:$key:$value')) {
            listaFinal.add(MapEntry(key, value));
            processedKeys.add(
                'event:$key:$value'); // evita duplicados si eventosCreados tiene el mismo evento más de una vez
          }
        }
      }

      todosLosDispositivos = listaFinal;
      _saveOrder();
      _actualizarListasUI();

      if (mounted) {
        setState(() {});
      }
    } catch (e, s) {
      printLog.e('Error construyendo lista de dispositivos: $e');
      printLog.t(s);
    }
  }

  // Detecta si un device es un roller (024011_IOT)
  bool _isRollerDevice(String device) {
    final cleanName = device.contains('_') ? device.split('_')[0] : device;
    return DeviceManager.getProductCode(cleanName) == '024011_IOT';
  }

  //*-Prender y apagar los equipos-*\\
  void toggleState(String deviceName, bool newState) async {
    String deviceSerialNumber = DeviceManager.extractSerialNumber(deviceName);
    String productCode = DeviceManager.getProductCode(deviceName);
    globalDATA['$productCode/$deviceSerialNumber']!['w_status'] = newState;

    String topic = 'devices_rx/$productCode/$deviceSerialNumber';
    String topic2 = 'devices_tx/$productCode/$deviceSerialNumber';
    String message = jsonEncode({"w_status": newState});
    bool result = await sendMQTTMessageWithPermission(
        deviceName,
        message,
        topic,
        topic2,
        newState
            ? 'Encendió dispositivo desde WiFi'
            : 'Apagó dispositivo desde WiFi');

    if (!result) {
      showToast('No tienes permisos de controlar el equipo');
    }
  }
  //*-Prender y apagar los equipos-*\\

  //*-Controlar posición del roller-*\\
  void _sendRollerCommand(String deviceName, int position) async {
    String deviceSerialNumber = DeviceManager.extractSerialNumber(deviceName);
    String productCode = DeviceManager.getProductCode(deviceName);

    globalDATA
        .putIfAbsent('$productCode/$deviceSerialNumber', () => {})
        .addAll({'working_position': "$position%"});

    String topic = 'devices_rx/$productCode/$deviceSerialNumber';
    String topic2 = 'devices_tx/$productCode/$deviceSerialNumber';
    String message = jsonEncode({'working_position': "$position%"});

    bool result = await sendMQTTMessageWithPermission(
      deviceName,
      message,
      topic,
      topic2,
      position == 100 ? 'Cerró cortina desde WiFi' : 'Abrió cortina desde WiFi',
    );

    if (!result) {
      showToast('No tienes permisos de controlar el equipo');
    } else {
      setState(() {});
    }
  }
//*-Controlar posición del roller-*\\

  //*-Borrar equipo de la lista-*\\
  void _confirmDelete(String deviceName, String equipo) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: color1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.0),
            side: const BorderSide(color: color4, width: 2.0),
          ),
          title: Text(
            'Confirmación',
            style: GoogleFonts.poppins(color: color0),
          ),
          content: Text(
            '¿Seguro que quieres eliminar el dispositivo de la lista?',
            style: GoogleFonts.poppins(color: color0),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                'Cancelar',
                style: GoogleFonts.poppins(color: color0),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text(
                'Aceptar',
                style: GoogleFonts.poppins(color: color0),
              ),
              onPressed: () {
                // Cerrar el diálogo inmediatamente
                Navigator.of(context).pop();

                // Ejecutar las operaciones de eliminación de forma asíncrona
                _performDelete(deviceName, equipo);
              },
            ),
          ],
        );
      },
    );
  }
  //*-Borrar equipo de la lista-*\\

  //*-Ejecutar operaciones de eliminación-*\\
  Future<void> _performDelete(String deviceName, String equipo) async {
    // Remover de listas locales
    previusConnections.remove(deviceName);
    alexaDevices.removeWhere((d) => d.contains(deviceName));
    todosLosDispositivos.removeWhere((e) => e.value == deviceName);

    bool removedFromFolder = false;
    List<String> emptyFolders = [];

    folders.forEach((folderName, devices) {
      if (devices.contains(deviceName)) {
        devices.remove(deviceName);
        removedFromFolder = true;
        if (devices.isEmpty) {
          emptyFolders.add(folderName);
        }
      }
    });

    for (String fName in emptyFolders) {
      folders.remove(fName);
    }
    _buildDeviceListFromLoadedData();

    _actualizarListasUI();
    await _saveOrder();

    setState(() {});
    final String sn = DeviceManager.extractSerialNumber(deviceName);

    // Actualizar datos remotos - usar marcador fantasma si la lista queda vacía
    bool isListEmpty = previusConnections.isEmpty;
    await putPreviusConnections(currentUserEmail, previusConnections,
        isIntentionalClear: isListEmpty);
    if (removedFromFolder) {
      await putFolders(currentUserEmail, folders);
    }
    await putDevicesForAlexa(currentUserEmail, alexaDevices);
    removeDeviceFromCore(deviceName);
    await removeFromActiveUsers(equipo, sn, currentUserEmail);

    final topic = 'devices_tx/$equipo/$sn';
    unSubToTopicMQTT(topic);
    topicsToSub.remove(topic);
  }
  //*-Ejecutar operaciones de eliminación-*\\

  //*-Determina si el grupo está online-*\\
  bool isGroupOnline(String devicesInGroup) {
    // 1. Convertir el string a lista
    List<String> deviceList = devicesInGroup
        .replaceAll('[', '')
        .replaceAll(']', '')
        .split(',')
        .map((e) => e.trim())
        .toList();

    for (String deviceName in deviceList) {
      String equipo = DeviceManager.getProductCode(deviceName);
      String serial = DeviceManager.extractSerialNumber(deviceName);

      Map<String, dynamic> deviceDATA = globalDATA['$equipo/$serial'] ?? {};

      bool online = deviceDATA['cstate'] ?? false;

      if (!online) {
        return false;
      }
    }

    return true;
  }
//*-Determina si el grupo está online-*\\

  //*-Determina si la cadena está online-*\\
  bool isCadenaOnline(List<dynamic> deviceGroup) {
    for (dynamic deviceName in deviceGroup) {
      String deviceStr = deviceName.toString();
      String equipo = DeviceManager.getProductCode(deviceStr);
      String serial = DeviceManager.extractSerialNumber(deviceStr);

      Map<String, dynamic> deviceDATA = globalDATA['$equipo/$serial'] ?? {};

      bool online = deviceDATA['cstate'] ?? false;

      if (!online) {
        return false;
      }
    }

    return true;
  }
//*-Determina si la cadena está online-*\\

  //*-Determina si el grupo está on-*\\
  bool isGroupOn(String devicesInGroup) {
    // 1. Convertir el string a lista
    List<String> deviceList = devicesInGroup
        .replaceAll('[', '')
        .replaceAll(']', '')
        .split(',')
        .map((e) => e.trim())
        .toList();

    for (String deviceName in deviceList) {
      if (deviceName.contains('_')) {
        final list = deviceName.split('_');
        String equipo = DeviceManager.getProductCode(list[0]);
        String serial = DeviceManager.extractSerialNumber(list[0]);

        Map<String, dynamic> deviceDATA =
            jsonDecode(globalDATA['$equipo/$serial']?['io${list[1]}']) ?? {};

        bool turnOn = deviceDATA['w_status'] ?? false;

        if (!turnOn) {
          return false;
        }
      } else {
        String equipo = DeviceManager.getProductCode(deviceName);
        String serial = DeviceManager.extractSerialNumber(deviceName);

        Map<String, dynamic> deviceDATA = globalDATA['$equipo/$serial'] ?? {};

        bool turnOn = deviceDATA['w_status'] ?? false;

        if (!turnOn) {
          return false;
        }
      }
    }

    return true;
  }
  //*-Determina si el grupo está on-*\\

  //*-Determina si puedo controlar el grupo-*\\
  bool canControlGroup(String devicesInGroup) {
    // 1. Convertir el string a lista
    List<String> deviceList = devicesInGroup
        .replaceAll('[', '')
        .replaceAll(']', '')
        .split(',')
        .map((e) => e.trim())
        .toList();

    for (String deviceName in deviceList) {
      String equipo = DeviceManager.getProductCode(deviceName);
      String serial = DeviceManager.extractSerialNumber(deviceName);

      Map<String, dynamic> deviceDATA = globalDATA['$equipo/$serial'] ?? {};

      List<dynamic> admins = deviceDATA['secondary_admin'] ?? [];

      bool owner = deviceDATA['owner'] == currentUserEmail ||
          admins.contains(currentUserEmail) ||
          deviceDATA['owner'] == '' ||
          deviceDATA['owner'] == null;
      bool canUseWifi = _wifiPermissions['$equipo/$serial'] ?? true;

      if (!owner || !canUseWifi) {
        return false;
      }
    }

    return true;
  }
  //*-Determina si puedo controlar el grupo-*\\

  //*-Controlar el grupo-*\\
  void controlGroup(String email, bool state, String grupo) async {
    // Verificar si el grupo ya está siendo procesado
    if (_processingGroups.contains(grupo)) {
      showToast(
          '⏳ El grupo "$grupo" ya se está procesando, aguarde un momento...');
      return;
    }

    // Agregar el grupo al Set de procesamiento
    _processingGroups.add(grupo);

    String url = controlGruposAPI;
    Uri uri = Uri.parse(url);

    String bd = jsonEncode(
      {
        'email': email,
        'on': state,
        'grupo': grupo,
        'app': app,
      },
    );

    printLog.i('Body: $bd');

    try {
      var response = await http.post(uri, body: bd);

      printLog.i('Response status: ${response.statusCode}');
      printLog.i('Response body: ${response.body}');

      if (response.statusCode == 200) {
        // Respuesta exitosa - todos los dispositivos se controlaron
        final responseData = jsonDecode(response.body);

        printLog.i('Grupo controlado exitosamente');
        showToast(
            '¡Perfecto! Todos los equipos del grupo se ${state ? 'encendieron' : 'apagaron'} correctamente 🎉');

        // Log adicional con detalles
        if (responseData['exitosos'] != null &&
            responseData['total_dispositivos'] != null) {
          printLog.i(
              'Dispositivos procesados: ${responseData['exitosos']}/${responseData['total_dispositivos']}');
        }
      } else if (response.statusCode == 207) {
        // Multi-Status - algunos dispositivos fallaron
        final responseData = jsonDecode(response.body);

        printLog.e('Algunos dispositivos no pudieron ser controlados');

        final exitosos = responseData['exitosos'] ?? 0;
        final fallidos = responseData['fallidos'] ?? 0;
        final dispositivosOffline = responseData['dispositivos_offline'] ?? [];

        // Mostrar mensaje detallado al usuario
        String message = '⚠️ Acción parcialmente completada:\n\n';
        message +=
            '✅ $exitosos equipos se ${state ? 'encendieron' : 'apagaron'} correctamente\n';

        if (fallidos > 0) {
          message += '❌ $fallidos equipos no disponibles en este momento';
          if (dispositivosOffline.isNotEmpty) {
            // Mostrar nombres de dispositivos offline (máximo 3 para no saturar)
            final deviceNames = dispositivosOffline.take(3).map((device) {
              return nicknamesMap[device] ?? device;
            }).join(', ');
            message += '\n\n📱 Equipos sin conexión: $deviceNames';
            if (dispositivosOffline.length > 3) {
              message += ' y ${dispositivosOffline.length - 3} más...';
            }
          }
        }

        showToast(message);
      } else if (response.statusCode == 400) {
        // Error de validación
        final responseData = jsonDecode(response.body);
        final errorMessage = responseData['error'] ?? 'Error de validación';

        printLog.e('Error de validación: $errorMessage');
        showToast(
            '🚫 Ups, algo no está bien configurado. Por favor intenta nuevamente');
      } else if (response.statusCode == 404) {
        // Grupo no encontrado
        printLog.e('Grupo no encontrado');
        showToast(
            '🔍 No encontramos el grupo "$grupo". Verifica que tengas permisos para controlarlo');
      } else {
        // Otros errores del servidor
        printLog.e('Error del servidor: ${response.statusCode}');
        showToast(
            '⚡ Hubo un problema en nuestros servidores. Por favor intenta en unos momentos');
      }
    } catch (e) {
      // Error de conexión o parsing
      printLog.e('Error de conexión al controlar el grupo: $e');
      showToast(
          '📶 Sin conexión a internet. Verifica tu red y vuelve a intentar');
    } finally {
      // Remover el grupo del Set de procesamiento
      _processingGroups.remove(grupo);
    }
  }
  //*-Controlar el grupo-*\\

  //*- Controlar la cadena -*\\
  void controlarCadena(String name) async {
    String bd = jsonEncode(
        {'nombreEvento': name, 'email': currentUserEmail, 'accion': 'start'});

    printLog.i('Controlling cadena with body: $bd', color: 'rosa');

    try {
      showToast('🔄 Iniciando cadena "$name"...');

      final response = await http.post(
        Uri.parse(controlCadenaAPI),
        body: bd,
      );

      if (response.statusCode == 200) {
        printLog.i('Cadena iniciada exitosamente');
        showToast('✅ Cadena "$name" iniciada exitosamente');
      } else if (response.statusCode == 404) {
        printLog.e('Cadena no encontrada: ${response.statusCode}');
        showToast(
            '🔍 No se encontró la cadena "$name". Verifica que existe y tienes permisos.');
      } else if (response.statusCode == 400) {
        printLog.e('Error de validación: ${response.statusCode}');
        showToast(
            '🚫 Error en los datos de la cadena. Por favor intenta nuevamente.');
      } else {
        printLog.e('Error al controlar la cadena: ${response.statusCode}');
        showToast('⚡ Error del servidor. Intenta nuevamente en unos momentos.');
      }
    } catch (e) {
      printLog.e('Error de conexión al controlar la cadena: $e');
      showToast(
          '📶 Sin conexión a internet. Verifica tu red y vuelve a intentar.');
    }
  }
  //*- Controlar la cadena -*\\

  //*- Pausar cadena -*\\
  void pausarCadena(String name) async {
    String bd = jsonEncode(
        {'nombreEvento': name, 'email': currentUserEmail, 'accion': 'pause'});

    printLog.i('Pausando cadena with body: $bd', color: 'rosa');

    try {
      showToast('⏸️ Pausando cadena "$name"...');

      final response = await http.post(
        Uri.parse(controlCadenaAPI),
        body: bd,
      );

      if (response.statusCode == 200) {
        printLog.i('Cadena pausada exitosamente');
        showToast('⏸️ Cadena "$name" pausada');
      } else if (response.statusCode == 400) {
        final responseData = jsonDecode(response.body);
        printLog.e('Error pausando cadena: ${responseData['error']}');
        showToast(
            '⚠️ ${responseData['error'] ?? 'No se pudo pausar la cadena'}');
      } else {
        printLog.e('Error al pausar la cadena: ${response.statusCode}');
        showToast('⚡ Error del servidor. Intenta nuevamente en unos momentos.');
      }
    } catch (e) {
      printLog.e('Error de conexión al pausar la cadena: $e');
      showToast(
          '📶 Sin conexión a internet. Verifica tu red y vuelve a intentar.');
    }
  }
  //*- Pausar cadena -*\\

  //*- Reanudar cadena -*\\
  void reanudarCadena(String name) async {
    String bd = jsonEncode(
        {'nombreEvento': name, 'email': currentUserEmail, 'accion': 'resume'});

    printLog.i('Reanudando cadena with body: $bd', color: 'rosa');

    try {
      showToast('▶️ Reanudando cadena "$name"...');

      final response = await http.post(
        Uri.parse(controlCadenaAPI),
        body: bd,
      );

      if (response.statusCode == 200) {
        printLog.i('Cadena reanudada exitosamente');
        showToast('▶️ Cadena "$name" reanudada');
      } else if (response.statusCode == 400) {
        final responseData = jsonDecode(response.body);
        printLog.e('Error reanudando cadena: ${responseData['error']}');
        showToast(
            '⚠️ ${responseData['error'] ?? 'No se pudo reanudar la cadena'}');
      } else {
        printLog.e('Error al reanudar la cadena: ${response.statusCode}');
        showToast('⚡ Error del servidor. Intenta nuevamente en unos momentos.');
      }
    } catch (e) {
      printLog.e('Error de conexión al reanudar la cadena: $e');
      showToast(
          '📶 Sin conexión a internet. Verifica tu red y vuelve a intentar.');
    }
  }
  //*- Reanudar cadena -*\\

  //*- Cancelar cadena -*\\
  void cancelarCadena(String name) async {
    // Mostrar diálogo de confirmación
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: color1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.0),
          side: const BorderSide(color: color4, width: 2.0),
        ),
        title: Text(
          'Cancelar Cadena',
          style: GoogleFonts.poppins(color: color0),
        ),
        content: Text(
          '¿Estás seguro que deseas cancelar la ejecución de "$name"?\n\nEsta acción no se puede deshacer.',
          style: GoogleFonts.poppins(color: color0),
        ),
        actions: <Widget>[
          TextButton(
            child: Text(
              'No',
              style: GoogleFonts.poppins(color: color0),
            ),
            onPressed: () {
              Navigator.of(context).pop(false);
            },
          ),
          TextButton(
            child: Text(
              'Sí, Cancelar',
              style: GoogleFonts.poppins(
                  color: color4, fontWeight: FontWeight.bold),
            ),
            onPressed: () {
              Navigator.of(context).pop(true);
            },
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    String bd = jsonEncode(
        {'nombreEvento': name, 'email': currentUserEmail, 'accion': 'cancel'});

    printLog.i('Cancelando cadena with body: $bd', color: 'rosa');

    try {
      showToast('❌ Cancelando cadena "$name"...');

      final response = await http.post(
        Uri.parse(controlCadenaAPI),
        body: bd,
      );

      if (response.statusCode == 200) {
        printLog.i('Cadena cancelada exitosamente');
        showToast('❌ Cadena "$name" cancelada');
      } else if (response.statusCode == 400) {
        final responseData = jsonDecode(response.body);
        printLog.e('Error cancelando cadena: ${responseData['error']}');
        showToast(
            '⚠️ ${responseData['error'] ?? 'No se pudo cancelar la cadena'}');
      } else {
        printLog.e('Error al cancelar la cadena: ${response.statusCode}');
        showToast('⚡ Error del servidor. Intenta nuevamente en unos momentos.');
      }
    } catch (e) {
      printLog.e('Error de conexión al cancelar la cadena: $e');
      showToast(
          '📶 Sin conexión a internet. Verifica tu red y vuelve a intentar.');
    }
  }
  //*- Cancelar cadena -*\\

  //*- Pausar riego -*\\
  void pausarRiego(String name) async {
    try {
      showToast('⏸️ Pausando riego "$name"...');

      final response = await http.post(
        Uri.parse(controlRiegoAPI),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'operation': 'pausar',
          'email': currentUserEmail,
          'nombreEvento': name,
        }),
      );

      if (response.statusCode == 200) {
        printLog.i('Riego pausado exitosamente');
        showToast('⏸️ Riego "$name" pausado');
      } else {
        printLog.e('Error al pausar riego: ${response.statusCode}');
        showToast('⚡ Error al pausar el riego. Intenta nuevamente.');
      }
    } catch (e) {
      printLog.e('Error de conexión al pausar riego: $e');
      showToast(
          '📶 Sin conexión a internet. Verifica tu red y vuelve a intentar.');
    }
  }
  //*- Pausar riego -*\\

  //*- Reanudar riego -*\\
  void reanudarRiego(String name) async {
    try {
      showToast('▶️ Reanudando riego "$name"...');

      final response = await http.post(
        Uri.parse(controlRiegoAPI),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'operation': 'reanudar',
          'email': currentUserEmail,
          'nombreEvento': name,
        }),
      );

      if (response.statusCode == 200) {
        printLog.i('Riego reanudado exitosamente');
        showToast('▶️ Riego "$name" reanudado');
      } else {
        printLog.e('Error al reanudar riego: ${response.statusCode}');
        showToast('⚡ Error al reanudar el riego. Intenta nuevamente.');
      }
    } catch (e) {
      printLog.e('Error de conexión al reanudar riego: $e');
      showToast(
          '📶 Sin conexión a internet. Verifica tu red y vuelve a intentar.');
    }
  }
  //*- Reanudar riego -*\\

  //*- Cancelar riego -*\\
  void cancelarRiego(String name) async {
    // Mostrar diálogo de confirmación
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: color1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.0),
          side: const BorderSide(color: color4, width: 2.0),
        ),
        title: Text(
          'Cancelar Riego',
          style: GoogleFonts.poppins(color: color0),
        ),
        content: Text(
          '¿Estás seguro que deseas cancelar la ejecución de "$name"?\n\nEsta acción no se puede deshacer.',
          style: GoogleFonts.poppins(color: color0),
        ),
        actions: <Widget>[
          TextButton(
            child: Text(
              'No',
              style: GoogleFonts.poppins(color: color0),
            ),
            onPressed: () {
              Navigator.of(context).pop(false);
            },
          ),
          TextButton(
            child: Text(
              'Sí, Cancelar',
              style: GoogleFonts.poppins(
                  color: color4, fontWeight: FontWeight.bold),
            ),
            onPressed: () {
              Navigator.of(context).pop(true);
            },
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      showToast('❌ Cancelando riego "$name"...');

      final response = await http.post(
        Uri.parse(controlRiegoAPI),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'operation': 'cancelar',
          'email': currentUserEmail,
          'nombreEvento': name,
        }),
      );

      if (response.statusCode == 200) {
        printLog.i('Riego cancelado exitosamente');
        showToast('❌ Riego "$name" cancelado');
      } else {
        printLog.e('Error al cancelar riego: ${response.statusCode}');
        showToast('⚡ Error al cancelar el riego. Intenta nuevamente.');
      }
    } catch (e) {
      printLog.e('Error de conexión al cancelar riego: $e');
      showToast(
          '📶 Sin conexión a internet. Verifica tu red y vuelve a intentar.');
    }
  }
  //*- Cancelar riego -*\\

  //*- Guardar orden de equipos -*\\
  Future<void> _saveOrder({bool immediate = true}) async {
    if (immediate) {
      List<Map<String, String>> orderedDevices = todosLosDispositivos
          .map((e) => {'key': e.key, 'value': e.value})
          .toList();

      await saveWifiOrderDevices(orderedDevices, currentUserEmail);
      savedOrder
        ..clear()
        ..addAll(orderedDevices);
    } else {
      _saveOrderTimer?.cancel();
      _saveOrderTimer = Timer(const Duration(milliseconds: 500), () async {
        List<Map<String, String>> orderedDevices = todosLosDispositivos
            .map((e) => {'key': e.key, 'value': e.value})
            .toList();

        await saveWifiOrderDevices(orderedDevices, currentUserEmail);
        savedOrder
          ..clear()
          ..addAll(orderedDevices);
      });
    }
  }
  //*- Guardar orden de equipos -*\\

  void activarRutinaRiego(Map<String, dynamic> eventoRiego) async {
    String name = eventoRiego['title'] ?? 'Rutina de Riego';

    // Verificar si la rutina ya está siendo procesada usando SharedPreferences
    bool isAlreadyExecuting = await isRiegoExecuting(name, currentUserEmail);
    if (isAlreadyExecuting) {
      showToast(
          '⏳ La rutina de riego "$name" ya se está ejecutando, aguarde un momento...');
      return;
    }

    // Agregar la rutina al Set de procesamiento y actualizar UI
    setState(() {
      _processingRiegos.add(name);
    });

    String bd = jsonEncode({'nombreEvento': name, 'email': currentUserEmail});

    printLog.i('Controlling riego with body: $bd', color: 'rosa');

    try {
      showToast('🌱 Iniciando rutina de riego "$name"...');

      final response = await http.post(
        Uri.parse(controlRiegoAPI),
        body: bd,
      );

      if (response.statusCode == 200) {
        printLog.i('Rutina de riego iniciada exitosamente');
        showToast('✅ Rutina de riego "$name" iniciada exitosamente');

        // Marcar la rutina como en ejecución en SharedPreferences
        await setRiegoExecuting(name, currentUserEmail);

        // Ya no usamos timer, la rutina se desmarcará cuando llegue la notificación
        printLog.i(
            'Rutina de riego "$name" marcada como en ejecución en SharedPreferences');
      } else if (response.statusCode == 404) {
        printLog.e('Rutina de riego no encontrada: ${response.statusCode}');
        showToast(
            '🔍 No se encontró la rutina de riego "$name". Verifica que existe y tienes permisos.');
        // Remover inmediatamente si hay error
        setState(() {
          _processingRiegos.remove(name);
        });
      } else if (response.statusCode == 400) {
        printLog.e('Error de validación: ${response.statusCode}');
        showToast(
            '🚫 Error en los datos de la rutina. Por favor intenta nuevamente.');
        // Remover inmediatamente si hay error
        setState(() {
          _processingRiegos.remove(name);
        });
      } else {
        printLog
            .e('Error al controlar la rutina de riego: ${response.statusCode}');
        showToast('⚡ Error del servidor. Intenta nuevamente en unos momentos.');
        // Remover inmediatamente si hay error
        setState(() {
          _processingRiegos.remove(name);
        });
      }
    } catch (e) {
      printLog.e('Error de conexión al controlar la rutina de riego: $e');
      showToast(
          '📶 Sin conexión a internet. Verifica tu red y vuelve a intentar.');
      // Remover inmediatamente si hay error de conexión
      setState(() {
        _processingRiegos.remove(name);
      });
    }
  }

  void _actualizarListasUI() {
    setState(() {
      _listaIndividuales = todosLosDispositivos.where((device) {
        if (device.key == 'folder') return true;

        if (device.key != 'individual') return false;

        String deviceName = device.value;
        String pc = DeviceManager.getProductCode(deviceName);
        String sn = DeviceManager.extractSerialNumber(deviceName);
        var data = globalDATA['$pc/$sn'] ?? {};

        bool isExtension = data['riegoMaster'] != null &&
            data['riegoMaster'].toString().isNotEmpty;

        return !isExtension;
      }).toList();

      _listaEventos = todosLosDispositivos
          .where(
              (device) => device.key != 'individual' && device.key != 'folder')
          .toList();

      int contador = 0;
      for (var item in _listaIndividuales) {
        if (item.key == 'individual') {
          contador++;
        } else if (item.key == 'folder') {
          String folderName = item.value;
          if (folders.containsKey(folderName)) {
            contador += folders[folderName]!.length;
          }
        }
      }
      _totalDispositivosReal = contador;
    });
  }

  //*- Función para habilitar/inhabilitar eventos -*\\
  Future<void> _toggleEventEnabled(
      Map<String, dynamic> evento, bool nuevoValor) async {
    String nombre = evento['title'];
    String tipo = evento['evento'];

    String? activador;
    String? horario;

    if (tipo == 'disparador') {
      if (evento['activadores'] != null &&
          (evento['activadores'] as List).isNotEmpty) {
        activador = evento['activadores'].first.toString();
      } else {
        List<dynamic> deviceGroup = evento['deviceGroup'] ?? [];
        if (deviceGroup.isNotEmpty) {
          activador = deviceGroup.first.toString();
        }
      }
    } else if (tipo == 'horario') {
      horario = evento['selectedTime'];
    }

    setState(() {
      evento['enabled'] = nuevoValor;

      int index = eventosCreados.indexOf(evento);
      if (index != -1) {
        eventosCreados[index] = evento;
      }
    });

    putEventos(currentUserEmail, eventosCreados);

    setEventEnabled(
        nombre, currentUserEmail, nuevoValor, tipo, activador, horario);
  }

  bool _hasRestrictedDevicesInGroup(dynamic deviceGroup) {
    List<String> devices = [];

    if (deviceGroup is String) {
      devices = deviceGroup
          .replaceAll('[', '')
          .replaceAll(']', '')
          .split(',')
          .map((e) => e.trim())
          .toList();
    } else if (deviceGroup is List) {
      devices = deviceGroup.map((e) => e.toString()).toList();
    }

    for (String devName in devices) {
      String cleanName =
          devName.contains('_') ? devName.split('_')[0] : devName;

      String pc = DeviceManager.getProductCode(cleanName);
      String sn = DeviceManager.extractSerialNumber(cleanName);
      String key = '$pc/$sn';

      if (_wifiPermissions.containsKey(key) && _wifiPermissions[key] == false) {
        return true;
      }
    }
    return false;
  }
  //*- Función para habilitar/inhabilitar eventos -*\\

  //*- Funciones y widgets para crear, borrar y añadir equipos a carpetas -*\\

  //Logica para crear carpeta
  Future<void> _createFolder(
      String name, List<String> selectedDeviceIds) async {
    if (name.trim().isEmpty) return;

    setState(() {
      folders[name] = selectedDeviceIds;
      _buildDeviceListFromLoadedData();
    });

    await putFolders(currentUserEmail, folders);
  }

  //Logica para desagrupar carpeta
  void _unGroupFolder(String folderName) async {
    setState(() {
      folders.remove(folderName);

      _buildDeviceListFromLoadedData();
    });

    await putFolders(currentUserEmail, folders);
  }

  //Logica para añadir dispositivo a la carpeta
  void _addDeviceToFolder(String folderName, String deviceToAdd) async {
    if (folders.containsKey(folderName)) {
      setState(() {
        if (!folders[folderName]!.contains(deviceToAdd)) {
          folders[folderName]!.add(deviceToAdd);
        }
        _buildDeviceListFromLoadedData();
      });

      await putFolders(currentUserEmail, folders);
    }
  }

  //Logica para eliminar equipo de carpeta
  Future<void> _removeFromFolder(
      String folderName, String deviceToRemove) async {
    if (folders.containsKey(folderName)) {
      setState(() {
        folders[folderName]!.remove(deviceToRemove);
        // Si la carpeta quedó vacía, la eliminamos automáticamente
        if (folders[folderName]!.isEmpty) {
          folders.remove(folderName);
        }
        _buildDeviceListFromLoadedData();
      });

      await putFolders(currentUserEmail, folders);
      showToast('Equipo quitado de la carpeta');
    }
  }

  //Visual de crear carpeta
  void _showCreateFolderDialog() {
    List<String> availableDevices = todosLosDispositivos
        .where((e) => e.key == 'individual')
        .map((e) => e.value)
        .toList();

    List<String> selected = [];
    TextEditingController nameCtrl = TextEditingController();

    if (availableDevices.isEmpty) {
      showToast('No tienes equipos individuales disponibles para agrupar');
      return;
    }

    showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setStateDialog) {
              return AlertDialog(
                backgroundColor: color1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(
                    color: Colors.red,
                    width: 2.0,
                  ),
                ),
                title: Text('Crear carpeta',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold, color: color0)),
                content: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        style: GoogleFonts.poppins(color: color0),
                        decoration: InputDecoration(
                          labelText: 'Nombre de la carpeta',
                          labelStyle:
                              TextStyle(color: color0.withValues(alpha: 0.6)),
                          enabledBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: color4)),
                          focusedBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: color4)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text('Selecciona los equipos:',
                          style: GoogleFonts.poppins(
                              color: color0,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      Flexible(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: color4.withValues(alpha: 0.3)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          constraints: const BoxConstraints(maxHeight: 250),
                          child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: availableDevices.length,
                              itemBuilder: (context, i) {
                                String dev = availableDevices[i];
                                bool isSelected = selected.contains(dev);
                                return CheckboxListTile(
                                  title: Text(nicknamesMap[dev] ?? dev,
                                      style: GoogleFonts.poppins(
                                          color: color0, fontSize: 14)),
                                  value: isSelected,
                                  activeColor: color4,
                                  checkColor: color1,
                                  side: BorderSide(
                                      color: color0.withValues(alpha: 0.5)),
                                  onChanged: (val) {
                                    setStateDialog(() {
                                      if (val == true) {
                                        selected.add(dev);
                                      } else {
                                        selected.remove(dev);
                                      }
                                    });
                                  },
                                );
                              }),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    child: Text('Cancelar',
                        style: GoogleFonts.poppins(color: color0)),
                    onPressed: () => Navigator.pop(context),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: color4),
                    child: Text('Crear',
                        style: GoogleFonts.poppins(
                            color: color0, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      if (nameCtrl.text.isEmpty) {
                        showToast('Ingresa un nombre para la carpeta');
                        return;
                      }
                      if (selected.isEmpty) {
                        showToast('Selecciona al menos un equipo');
                        return;
                      }
                      _createFolder(nameCtrl.text, selected);
                      Navigator.pop(context);
                    },
                  )
                ],
              );
            },
          );
        });
  }

  //Visual para agregar equipo a carpeta
  void _showAddDeviceToFolderDialog(String folderJson) {
    List<String> availableDevices = todosLosDispositivos
        .where((e) => e.key == 'individual')
        .map((e) => e.value)
        .toList();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: color1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(
              color: Colors.red,
              width: 2.0,
            ),
          ),
          title: Text('Agregar a carpeta',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold, color: color0)),
          content: availableDevices.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Text('No hay equipos sueltos para agregar.',
                      style: GoogleFonts.poppins(color: color0)),
                )
              : SizedBox(
                  width: double.maxFinite,
                  height: 300,
                  child: ListView.builder(
                    itemCount: availableDevices.length,
                    itemBuilder: (ctx, i) {
                      String dev = availableDevices[i];
                      return ListTile(
                        title: Text(nicknamesMap[dev] ?? dev,
                            style: GoogleFonts.poppins(color: color0)),
                        trailing: const Icon(HugeIcons.strokeRoundedPlusSign,
                            color: color4),
                        onTap: () {
                          _addDeviceToFolder(folderJson, dev);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
        );
      },
    );
  }

  //Visual de eliminar equipo de carpeta
  void _showRemoveDeviceFromFolderDialog(String folderName) {
    List<String> devicesInFolder = folders[folderName] ?? [];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: color1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(
              color: color4,
              width: 2.0,
            ),
          ),
          title: Text('Quitar de carpeta',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold, color: color0)),
          content: devicesInFolder.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Text('La carpeta ya está vacía.',
                      style: GoogleFonts.poppins(color: color0)),
                )
              : SizedBox(
                  width: double.maxFinite,
                  height: 300,
                  child: ListView.builder(
                    itemCount: devicesInFolder.length,
                    itemBuilder: (ctx, i) {
                      String dev = devicesInFolder[i];
                      return ListTile(
                        title: Text(nicknamesMap[dev] ?? dev,
                            style: GoogleFonts.poppins(color: color0)),
                        trailing: const Icon(HugeIcons.strokeRoundedMinusSign,
                            color: Colors.orange), // Icono de resta
                        onTap: () {
                          _removeFromFolder(folderName, dev);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
        );
      },
    );
  }

  //Visual de la carpeta en la lista
  Widget _buildFolderWidget(String folderName, int index) {
    try {
      List<String> devices = folders[folderName] ?? [];

      if (!folders.containsKey(folderName)) return const SizedBox.shrink();

      return Card(
        key: ValueKey('folder_$folderName'),
        color: color1,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        elevation: 3,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: color4, width: 1)),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Icon(HugeIcons.strokeRoundedMenu01,
                    color: Colors.grey),
              ),
              const SizedBox(width: 12),
              CircleAvatar(
                backgroundColor: color4.withValues(alpha: 0.1),
                child:
                    const Icon(HugeIcons.strokeRoundedFolder01, color: color4),
              ),
            ],
          ),
          title: Text(folderName,
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold, color: color0, fontSize: 16)),
          subtitle: Text('${devices.length} dispositivos',
              style: GoogleFonts.poppins(
                  fontSize: 12, color: color0.withValues(alpha: 0.6))),
          trailing: PopupMenuButton<String>(
            color: color1,
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
              side: const BorderSide(color: color3, width: 2),
            ),
            icon: const Icon(HugeIcons.strokeRoundedMoreVerticalCircle01,
                color: color0),
            onSelected: (value) {
              if (value == 'add') _showAddDeviceToFolderDialog(folderName);
              if (value == 'remove') {
                _showRemoveDeviceFromFolderDialog(folderName);
              }
              if (value == 'delete') _unGroupFolder(folderName);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'add',
                height: 50,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color4.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        HugeIcons.strokeRoundedPlusSign,
                        color: color4,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        'Agregar equipo',
                        style: GoogleFonts.poppins(
                          color: color0,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(height: 1),
              PopupMenuItem(
                value: 'remove',
                height: 50,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        HugeIcons.strokeRoundedMinusSign,
                        color: Colors.orange,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        'Quitar equipo',
                        style: GoogleFonts.poppins(
                          color: color0,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(height: 1),
              PopupMenuItem(
                value: 'delete',
                height: 50,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        HugeIcons.strokeRoundedDelete02,
                        color: Colors.red,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        'Desagrupar carpeta',
                        style: GoogleFonts.poppins(
                          color: color0,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          children: [
            Container(
              decoration: BoxDecoration(
                color: color0.withValues(alpha: 0.03),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(15),
                  bottomRight: Radius.circular(15),
                ),
              ),
              padding: const EdgeInsets.all(8.0),
              child: ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                proxyDecorator:
                    (Widget child, int index, Animation<double> animation) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      cardTheme: Theme.of(context).cardTheme.copyWith(
                            surfaceTintColor: Colors.transparent,
                            color: color1,
                            shadowColor: Colors.transparent,
                          ),
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: child,
                    ),
                  );
                },
                onReorder: (int oldIndex, int newIndex) async {
                  if (newIndex > oldIndex) newIndex -= 1;

                  setState(() {
                    final item = devices.removeAt(oldIndex);
                    devices.insert(newIndex, item);
                    folders[folderName] = devices;
                  });

                  await putFolders(currentUserEmail, folders);
                },
                children: devices.asMap().entries.map((entry) {
                  final int innerIndex = entry.key;
                  final String deviceName = entry.value;

                  return KeyedSubtree(
                    key: ValueKey('folder_${folderName}_inner_$deviceName'),
                    child: _buildDeviceCard(deviceName, innerIndex,
                        isInsideFolder: true),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      printLog.e('Error mostrando carpeta: $e');
      return Card(
        color: Colors.red.withValues(alpha: 0.1),
        child: ListTile(
          leading: const Icon(Icons.error, color: Colors.red),
          title: Text('Error en carpeta',
              style: GoogleFonts.poppins(color: color0)),
          subtitle: Text('Datos corruptos. Toca para borrar.',
              style: GoogleFonts.poppins(color: color0, fontSize: 10)),
          onTap: () => _unGroupFolder(folderName),
        ),
      );
    }
  }
  //*- Funciones y widgets para crear, borrar y añadir equipos a carpetas -*\\

  Widget _buildDeviceCard(String deviceName, int index,
      {bool isInsideFolder = false}) {
    String productCode = DeviceManager.getProductCode(deviceName);
    String serialNumber = DeviceManager.extractSerialNumber(deviceName);

    final topicData = ref.watch(globalDataProvider
        .select((data) => data['$productCode/$serialNumber'] ?? {}));
    globalDATA
        .putIfAbsent('$productCode/$serialNumber', () => {})
        .addAll(topicData);

    globalDATA
        .putIfAbsent('$productCode/$serialNumber', () => {})
        .addAll(topicData);

    Map<String, dynamic> deviceDATA =
        globalDATA['$productCode/$serialNumber'] ?? {};

    bool online = deviceDATA['cstate'] ?? false;

    List<dynamic> admins = deviceDATA['secondary_admin'] ?? [];

    bool owner = deviceDATA['owner'] == currentUserEmail ||
        admins.contains(currentUserEmail) ||
        deviceDATA['owner'] == '' ||
        deviceDATA['owner'] == null;

    bool canUseWifi = _wifiPermissions['$productCode/$serialNumber'] ?? true;
    bool isRestrictedAdmin = admins.contains(currentUserEmail) &&
        deviceDATA['owner'] != currentUserEmail &&
        !canUseWifi;

    // Lectura sincrónica del cache. El cache se carga en initState y se
    // refresca por device cuando llega un evento MQTT de desconexión
    // (ver el ref.listen al principio de build). Si todavía no se cargó,
    // asumimos red estable para no mostrar el warning prematuramente.
    bool networkUnstable =
        _networkUnstableCache['$productCode/$serialNumber'] ?? false;

    String? riegoMaster = deviceDATA['riegoMaster'];
    if (riegoMaster != null &&
        riegoMaster.isNotEmpty &&
        riegoMaster != '' &&
        riegoMaster.trim().isNotEmpty) {
      return SizedBox.shrink(
        key: ValueKey('extension_$deviceName'),
      );
    }

    final cardColor = isInsideFolder ? color1.withValues(alpha: 0.2) : color1;

    final double cardElevation = isInsideFolder ? 0 : 2;

    final EdgeInsets cardMargin = isInsideFolder
        ? const EdgeInsets.symmetric(vertical: 8, horizontal: 4)
        : const EdgeInsets.symmetric(vertical: 5, horizontal: 10);

    final ShapeBorder cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(15),
      side: isInsideFolder
          ? const BorderSide(color: color3, width: 1)
          : BorderSide.none,
    );

    try {
      switch (productCode) {
        case '015773_IOT':
          int ppmCO = deviceDATA['ppmco'] ?? 0;
          int ppmCH4 = deviceDATA['ppmch4'] ?? 0;
          bool alert = deviceDATA['alert'] == 1;
          return RepaintBoundary(
            key: ValueKey(deviceName),
            child: Card(
              color: cardColor,
              margin: cardMargin,
              elevation: cardElevation,
              shape: cardShape,
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16.0),
                  iconColor: color4,
                  collapsedIconColor: color4,
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(HugeIcons.strokeRoundedMenu01,
                            color: Colors.grey),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nicknamesMap[deviceName] ?? deviceName,
                              style: GoogleFonts.poppins(
                                color: color0,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              spacing: 10,
                              children: [
                                Text(
                                  online ? '● CONECTADO' : '● DESCONECTADO',
                                  style: GoogleFonts.poppins(
                                    color: online ? Colors.green : color3,
                                    fontSize: 15,
                                  ),
                                ),
                                online
                                    ? ImageIcon(
                                        const AssetImage(CaldenIcons.cloud),
                                        color: online ? Colors.green : color3,
                                        size: 25,
                                      )
                                    : ImageIcon(
                                        const AssetImage(CaldenIcons.cloudOff),
                                        color: online ? Colors.green : color3,
                                        size: 15,
                                      ),
                              ],
                            ),
                            if (online && networkUnstable) ...[
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    HugeIcons.strokeRoundedAlert02,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Red inestable',
                                    style: GoogleFonts.poppins(
                                      color: Colors.orange,
                                      fontSize: 15,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    HugeIcons.strokeRoundedAlert02,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                ],
                              )
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: ListTile(
                            title: online
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'PPM CO: $ppmCO',
                                        style: GoogleFonts.poppins(
                                          color: color0,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        'CH4 LIE: ${(ppmCH4 / 500).round()}%',
                                        style: GoogleFonts.poppins(
                                          color: color0,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          Text(
                                            alert ? 'PELIGRO' : 'AIRE PURO',
                                            style: GoogleFonts.poppins(
                                              color: color0,
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                          alert
                                              ? const Icon(
                                                  HugeIcons
                                                      .strokeRoundedAlert02,
                                                  color: color4,
                                                )
                                              : const Icon(
                                                  HugeIcons.strokeRoundedLeaf01,
                                                  color: Colors.green,
                                                ),
                                        ],
                                      ),
                                    ],
                                  )
                                : Text(
                                    'El equipo debe estar\nconectado para su uso',
                                    style: GoogleFonts.poppins(
                                      color: color3,
                                      fontSize: 15,
                                    ),
                                  ),
                          ),
                        ),
                        Padding(
                          padding:
                              const EdgeInsets.only(right: 8.0, bottom: 8.0),
                          child: IconButton(
                            icon: const Icon(
                              HugeIcons.strokeRoundedDelete02,
                              color: color0,
                              size: 20,
                            ),
                            onPressed: () {
                              _confirmDelete(deviceName, productCode);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        case '022000_IOT':
          bool estado = deviceDATA['w_status'] ?? false;
          bool heaterOn = deviceDATA['f_status'] ?? false;
          return RepaintBoundary(
            key: ValueKey(deviceName),
            child: Card(
              color: cardColor,
              margin: cardMargin,
              elevation: cardElevation,
              shape: cardShape,
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16.0),
                  iconColor: color4,
                  collapsedIconColor: color4,
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(HugeIcons.strokeRoundedMenu01,
                            color: Colors.grey),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nicknamesMap[deviceName] ?? deviceName,
                              style: GoogleFonts.poppins(
                                color: color0,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              spacing: 10,
                              children: [
                                Text(
                                  online ? '● CONECTADO' : '● DESCONECTADO',
                                  style: GoogleFonts.poppins(
                                    color: online ? Colors.green : color3,
                                    fontSize: 15,
                                  ),
                                ),
                                online
                                    ? ImageIcon(
                                        const AssetImage(CaldenIcons.cloud),
                                        color: online ? Colors.green : color3,
                                        size: 25,
                                      )
                                    : ImageIcon(
                                        const AssetImage(CaldenIcons.cloudOff),
                                        color: online ? Colors.green : color3,
                                        size: 15,
                                      ),
                              ],
                            ),
                            if (online && networkUnstable) ...[
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    HugeIcons.strokeRoundedAlert02,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Red inestable',
                                    style: GoogleFonts.poppins(
                                      color: Colors.orange,
                                      fontSize: 15,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    HugeIcons.strokeRoundedAlert02,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                ],
                              )
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  children: <Widget>[
                    isRestrictedAdmin
                        ? Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 5.0),
                                  child: Text(
                                    'El dueño del equipo restringió su uso por wifi.',
                                    style: GoogleFonts.poppins(
                                      color: color3,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 5.0),
                                  child: online
                                      ? Row(
                                          children: [
                                            estado
                                                ? Row(
                                                    children: [
                                                      if (heaterOn) ...[
                                                        Text(
                                                          'Calentando',
                                                          style: GoogleFonts
                                                              .poppins(
                                                            color: Colors
                                                                .amber[800],
                                                            fontSize: 15,
                                                          ),
                                                        ),
                                                        Icon(
                                                          HugeIcons
                                                              .strokeRoundedFlash,
                                                          size: 15,
                                                          color:
                                                              Colors.amber[800],
                                                        ),
                                                      ] else ...[
                                                        Text(
                                                          'Encendido',
                                                          style: GoogleFonts
                                                              .poppins(
                                                            color: Colors.green,
                                                            fontSize: 15,
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  )
                                                : Text(
                                                    'Apagado',
                                                    style: GoogleFonts.poppins(
                                                        color: color4,
                                                        fontSize: 15),
                                                  ),
                                            const SizedBox(width: 5),
                                            owner
                                                ? Switch(
                                                    activeThumbColor:
                                                        const Color(0xFF9C9D98),
                                                    activeTrackColor:
                                                        const Color(0xFFB2B5AE),
                                                    inactiveThumbColor:
                                                        const Color(0xFFB2B5AE),
                                                    inactiveTrackColor:
                                                        const Color(0xFF9C9D98),
                                                    value: estado,
                                                    onChanged: (newValue) {
                                                      toggleState(
                                                          deviceName, newValue);
                                                      setState(() {
                                                        estado = newValue;
                                                      });
                                                    },
                                                  )
                                                : const SizedBox(
                                                    height: 0, width: 0),
                                            if (!owner) ...[
                                              _buildNotOwnerWarning()
                                            ],
                                          ],
                                        )
                                      : Text(
                                          'El equipo debe estar\nconectado para su uso',
                                          style: GoogleFonts.poppins(
                                            color: color3,
                                            fontSize: 15,
                                          ),
                                        ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                    right: 8.0, bottom: 8.0),
                                child: IconButton(
                                  icon: const Icon(
                                    HugeIcons.strokeRoundedDelete02,
                                    color: color0,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    _confirmDelete(deviceName, productCode);
                                  },
                                ),
                              ),
                            ],
                          ),
                  ],
                ),
              ),
            ),
          );
        case '027000_IOT':
          bool estado = deviceDATA['w_status'] ?? false;
          bool heaterOn = deviceDATA['f_status'] ?? false;
          return RepaintBoundary(
            key: ValueKey(deviceName),
            child: Card(
              color: cardColor,
              margin: cardMargin,
              elevation: cardElevation,
              shape: cardShape,
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16.0),
                  iconColor: color4,
                  collapsedIconColor: color4,
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(HugeIcons.strokeRoundedMenu01,
                            color: Colors.grey),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nicknamesMap[deviceName] ?? deviceName,
                              style: GoogleFonts.poppins(
                                color: color0,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              spacing: 10,
                              children: [
                                Text(
                                  online ? '● CONECTADO' : '● DESCONECTADO',
                                  style: GoogleFonts.poppins(
                                    color: online ? Colors.green : color3,
                                    fontSize: 15,
                                  ),
                                ),
                                online
                                    ? ImageIcon(
                                        const AssetImage(CaldenIcons.cloud),
                                        color: online ? Colors.green : color3,
                                        size: 25,
                                      )
                                    : ImageIcon(
                                        const AssetImage(CaldenIcons.cloudOff),
                                        color: online ? Colors.green : color3,
                                        size: 15,
                                      ),
                              ],
                            ),
                            if (online && networkUnstable) ...[
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    HugeIcons.strokeRoundedAlert02,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Red inestable',
                                    style: GoogleFonts.poppins(
                                      color: Colors.orange,
                                      fontSize: 15,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    HugeIcons.strokeRoundedAlert02,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                ],
                              )
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  children: <Widget>[
                    isRestrictedAdmin
                        ? Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 5.0),
                                  child: Text(
                                    'El dueño del equipo restringió su uso por wifi.',
                                    style: GoogleFonts.poppins(
                                      color: color3,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 5.0),
                                  child: online
                                      ? Row(
                                          children: [
                                            estado
                                                ? Row(
                                                    children: [
                                                      if (heaterOn) ...[
                                                        Text(
                                                          'Calentando',
                                                          style: GoogleFonts
                                                              .poppins(
                                                            color: Colors
                                                                .amber[800],
                                                            fontSize: 15,
                                                          ),
                                                        ),
                                                        Icon(
                                                          HugeIcons
                                                              .strokeRoundedFire,
                                                          size: 15,
                                                          color:
                                                              Colors.amber[800],
                                                        ),
                                                      ] else ...[
                                                        Text(
                                                          'Encendido',
                                                          style: GoogleFonts
                                                              .poppins(
                                                            color: Colors.green,
                                                            fontSize: 15,
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  )
                                                : Text(
                                                    'Apagado',
                                                    style: GoogleFonts.poppins(
                                                      color: color4,
                                                      fontSize: 15,
                                                    ),
                                                  ),
                                            const SizedBox(width: 5),
                                            owner
                                                ? Switch(
                                                    activeThumbColor:
                                                        const Color(0xFF9C9D98),
                                                    activeTrackColor:
                                                        const Color(0xFFB2B5AE),
                                                    inactiveThumbColor:
                                                        const Color(0xFFB2B5AE),
                                                    inactiveTrackColor:
                                                        const Color(0xFF9C9D98),
                                                    value: estado,
                                                    onChanged: online
                                                        ? (newValue) {
                                                            toggleState(
                                                                deviceName,
                                                                newValue);
                                                            setState(
                                                              () {
                                                                estado =
                                                                    newValue;
                                                                if (!newValue) {
                                                                  heaterOn =
                                                                      false;
                                                                }
                                                              },
                                                            );
                                                          }
                                                        : null)
                                                : const SizedBox(
                                                    height: 0, width: 0),
                                            if (!owner) ...[
                                              _buildNotOwnerWarning()
                                            ],
                                          ],
                                        )
                                      : Text(
                                          'El equipo debe estar\nconectado para su uso',
                                          style: GoogleFonts.poppins(
                                            color: color3,
                                            fontSize: 15,
                                          ),
                                        ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                    right: 8.0, bottom: 8.0),
                                child: IconButton(
                                  icon: const Icon(
                                    HugeIcons.strokeRoundedDelete02,
                                    color: color0,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    _confirmDelete(deviceName, productCode);
                                  },
                                ),
                              ),
                            ],
                          ),
                  ],
                ),
              ),
            ),
          );
        case '020010_IOT':

          // Verificar si es un equipo de riego
          bool isRiegoActive = deviceDATA['riegoActive'] == true;
          if (isRiegoActive) {
            return _buildRiegoCard(deviceName, productCode, serialNumber,
                deviceDATA, online, owner, index,
                isInsideFolder: isInsideFolder);
          }

          // Código original para equipos normales
          return RepaintBoundary(
            key: ValueKey(deviceName),
            child: Card(
              color: cardColor,
              margin: cardMargin,
              elevation: cardElevation,
              shape: cardShape,
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                  ),
                  iconColor: color4,
                  collapsedIconColor: color4,
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(HugeIcons.strokeRoundedMenu01,
                            color: Colors.grey),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nicknamesMap[deviceName] ?? deviceName,
                              style: GoogleFonts.poppins(
                                color: color0,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              spacing: 10,
                              children: [
                                Text(
                                  online ? '● CONECTADO' : '● DESCONECTADO',
                                  style: GoogleFonts.poppins(
                                    color: online ? Colors.green : color3,
                                    fontSize: 15,
                                  ),
                                ),
                                online
                                    ? ImageIcon(
                                        const AssetImage(CaldenIcons.cloud),
                                        color: online ? Colors.green : color3,
                                        size: 25,
                                      )
                                    : ImageIcon(
                                        const AssetImage(CaldenIcons.cloudOff),
                                        color: online ? Colors.green : color3,
                                        size: 15,
                                      ),
                              ],
                            ),
                            if (online && networkUnstable) ...[
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    HugeIcons.strokeRoundedAlert02,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Red inestable',
                                    style: GoogleFonts.poppins(
                                      color: Colors.orange,
                                      fontSize: 15,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    HugeIcons.strokeRoundedAlert02,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                ],
                              )
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  children: <Widget>[
                    isRestrictedAdmin
                        ? Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 5.0),
                                  child: Text(
                                    'El dueño del equipo restringió su uso por wifi.',
                                    style: GoogleFonts.poppins(
                                      color: color3,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : online
                            ? Column(
                                children: [
                                  ...(deviceDATA.keys
                                          .where((key) =>
                                              key.startsWith('io') &&
                                              RegExp(r'^io\d+$').hasMatch(key))
                                          .where((ioKey) =>
                                              deviceDATA[ioKey] != null)
                                          .toList()
                                        ..sort((a, b) {
                                          int indexA =
                                              int.parse(a.substring(2));
                                          int indexB =
                                              int.parse(b.substring(2));
                                          return indexA.compareTo(indexB);
                                        }))
                                      .map((ioKey) {
                                    // Extraer el índice del ioKey (ejemplo: "io0" -> 0)
                                    int i = int.parse(ioKey.substring(2));
                                    Map<String, dynamic> equipo =
                                        jsonDecode(deviceDATA[ioKey]);
                                    // printLog.i(
                                    //   'Voy a realizar el cambio: $equipo',
                                    // );
                                    String tipoWifi =
                                        equipo['pinType'].toString() == '0'
                                            ? 'Salida'
                                            : 'Entrada';
                                    bool estadoWifi = equipo['w_status'];
                                    String comunWifi =
                                        (equipo['r_state'] ?? '0').toString();
                                    bool entradaWifi = tipoWifi == 'Entrada';
                                    return ListTile(
                                      title: Row(
                                        children: [
                                          Text(
                                            nicknamesMap['${deviceName}_$i'] ??
                                                '$tipoWifi $i',
                                            style: GoogleFonts.poppins(
                                              color: color0,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                        ],
                                      ),
                                      subtitle: Align(
                                        alignment:
                                            AlignmentDirectional.centerStart,
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.start,
                                          children: [
                                            entradaWifi
                                                ? estadoWifi
                                                    ? comunWifi == '1'
                                                        ? Text(
                                                            'Cerrado',
                                                            style: GoogleFonts
                                                                .poppins(
                                                              color:
                                                                  Colors.green,
                                                              fontSize: 15,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          )
                                                        : Text(
                                                            'Abierto',
                                                            style: GoogleFonts
                                                                .poppins(
                                                              color: color4,
                                                              fontSize: 15,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          )
                                                    : comunWifi == '1'
                                                        ? Text(
                                                            'Abierto',
                                                            style: GoogleFonts
                                                                .poppins(
                                                              color: color4,
                                                              fontSize: 15,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          )
                                                        : Text(
                                                            'Cerrado',
                                                            style: GoogleFonts
                                                                .poppins(
                                                              color:
                                                                  Colors.green,
                                                              fontSize: 15,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          )
                                                : estadoWifi
                                                    ? Text(
                                                        'Encendido',
                                                        style:
                                                            GoogleFonts.poppins(
                                                          color: Colors.green,
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      )
                                                    : Text(
                                                        'Apagado',
                                                        style:
                                                            GoogleFonts.poppins(
                                                          color: color4,
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                          ],
                                        ),
                                      ),
                                      trailing: owner
                                          ? entradaWifi
                                              ? estadoWifi
                                                  ? comunWifi == '1'
                                                      ? const Icon(
                                                          HugeIcons
                                                              .strokeRoundedAlertDiamond,
                                                          color: Color(
                                                            0xff9b9b9b,
                                                          ),
                                                        )
                                                      : const Icon(
                                                          HugeIcons
                                                              .strokeRoundedAlertDiamond,
                                                          color: color4,
                                                        )
                                                  : comunWifi == '1'
                                                      ? const Icon(
                                                          HugeIcons
                                                              .strokeRoundedAlertDiamond,
                                                          color: color4,
                                                        )
                                                      : const Icon(
                                                          HugeIcons
                                                              .strokeRoundedAlertDiamond,
                                                          color: Color(
                                                            0xff9b9b9b,
                                                          ),
                                                        )
                                              : Switch(
                                                  activeThumbColor: const Color(
                                                    0xFF9C9D98,
                                                  ),
                                                  activeTrackColor: const Color(
                                                    0xFFB2B5AE,
                                                  ),
                                                  inactiveThumbColor:
                                                      const Color(
                                                    0xFFB2B5AE,
                                                  ),
                                                  inactiveTrackColor:
                                                      const Color(
                                                    0xFF9C9D98,
                                                  ),
                                                  value: estadoWifi,
                                                  onChanged: (value) async {
                                                    String topic =
                                                        'devices_rx/$productCode/$serialNumber';
                                                    String topic2 =
                                                        'devices_tx/$productCode/$serialNumber';
                                                    String message =
                                                        jsonEncode({
                                                      'pinType':
                                                          tipoWifi == 'Salida'
                                                              ? 0
                                                              : 1,
                                                      'index': i,
                                                      'w_status': value,
                                                      'r_state': comunWifi,
                                                    });
                                                    bool result =
                                                        await sendMQTTMessageWithPermission(
                                                            deviceName,
                                                            message,
                                                            topic,
                                                            topic2,
                                                            value
                                                                ? 'Encendió dispositivo desde WiFi'
                                                                : 'Apagó dispositivo desde WiFi');
                                                    if (result) {
                                                      setState(() {
                                                        estadoWifi = value;
                                                      });
                                                      globalDATA
                                                          .putIfAbsent(
                                                              '$productCode/$serialNumber',
                                                              () => {})
                                                          .addAll({
                                                        'io$i': message
                                                      });
                                                    } else {
                                                      showToast(
                                                        'No tienes permisos para realizar esta acción en este momento',
                                                      );
                                                    }
                                                  },
                                                )
                                          : null,
                                    );
                                  }),
                                  if (!owner) ...[_buildNotOwnerWarning()],
                                ],
                              )
                            : const SizedBox(height: 0),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Padding(
                            padding:
                                const EdgeInsets.only(left: 20.0, bottom: 16.0),
                            child: !online
                                ? Text(
                                    'El equipo debe estar\nconectado para su uso',
                                    style: GoogleFonts.poppins(
                                      color: color3,
                                      fontSize: 15,
                                    ),
                                  )
                                : const SizedBox(height: 0),
                          ),
                        ),
                        if (!online)
                          Padding(
                            padding:
                                const EdgeInsets.only(right: 8.0, bottom: 8.0),
                            child: IconButton(
                              icon: const Icon(
                                HugeIcons.strokeRoundedDelete02,
                                color: color0,
                                size: 20,
                              ),
                              onPressed: () {
                                _confirmDelete(deviceName, productCode);
                              },
                            ),
                          ),
                      ],
                    ),
                    if (online)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding:
                              const EdgeInsets.only(right: 16.0, bottom: 8.0),
                          child: IconButton(
                            icon: const Icon(
                              HugeIcons.strokeRoundedDelete02,
                              color: color0,
                              size: 20,
                            ),
                            onPressed: () {
                              _confirmDelete(deviceName, productCode);
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        case '027313_IOT':

          // Verificar si es un equipo de riego
          bool isRiegoActive = deviceDATA['riegoActive'] == true;
          if (isRiegoActive) {
            return _buildRiegoCard(deviceName, productCode, serialNumber,
                deviceDATA, online, owner, index);
          }
          bool hasEntry = deviceDATA['hasEntry'] ?? false;
          return RepaintBoundary(
            key: ValueKey(deviceName),
            child: Card(
              color: cardColor,
              margin: cardMargin,
              elevation: cardElevation,
              shape: cardShape,
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                  ),
                  iconColor: color4,
                  collapsedIconColor: color4,
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(HugeIcons.strokeRoundedMenu01,
                            color: Colors.grey),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nicknamesMap[deviceName] ?? deviceName,
                              style: GoogleFonts.poppins(
                                color: color0,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              spacing: 10,
                              children: [
                                Text(
                                  online ? '● CONECTADO' : '● DESCONECTADO',
                                  style: GoogleFonts.poppins(
                                    color: online ? Colors.green : color3,
                                    fontSize: 15,
                                  ),
                                ),
                                online
                                    ? ImageIcon(
                                        const AssetImage(CaldenIcons.cloud),
                                        color: online ? Colors.green : color3,
                                        size: 25,
                                      )
                                    : ImageIcon(
                                        const AssetImage(CaldenIcons.cloudOff),
                                        color: online ? Colors.green : color3,
                                        size: 15,
                                      ),
                              ],
                            ),
                            if (online && networkUnstable) ...[
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    HugeIcons.strokeRoundedAlert02,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Red inestable',
                                    style: GoogleFonts.poppins(
                                      color: Colors.orange,
                                      fontSize: 15,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    HugeIcons.strokeRoundedAlert02,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                ],
                              )
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  children: <Widget>[
                    isRestrictedAdmin
                        ? Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 5.0),
                                  child: Text(
                                    'El dueño del equipo restringió su uso por wifi.',
                                    style: GoogleFonts.poppins(
                                      color: color3,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : online
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // POSICIÓN 0: Salida con switch
                                  if (deviceDATA['io0'] == null) ...[
                                    const SizedBox
                                        .shrink() // No mostrar nada si no hay datos
                                  ] else ...[
                                    if (deviceDATA['io0'] == null) ...[
                                      const SizedBox
                                          .shrink() // No mostrar nada si no hay datos
                                    ] else ...[
                                      if (hasEntry) ...[
                                        ListTile(
                                          title: Text(
                                            nicknamesMap['${deviceName}_0'] ??
                                                'Salida 0',
                                            style: GoogleFonts.poppins(
                                              color: color0,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          trailing: owner
                                              ? Switch(
                                                  activeThumbColor:
                                                      const Color(0xFF9C9D98),
                                                  activeTrackColor:
                                                      const Color(0xFFB2B5AE),
                                                  inactiveThumbColor:
                                                      const Color(0xFFB2B5AE),
                                                  inactiveTrackColor:
                                                      const Color(0xFF9C9D98),
                                                  value: (jsonDecode(deviceDATA[
                                                          'io0'])['w_status'] ??
                                                      false),
                                                  onChanged: (value) async {
                                                    final deviceSerialNumber =
                                                        DeviceManager
                                                            .extractSerialNumber(
                                                                deviceName);
                                                    final productCode =
                                                        DeviceManager
                                                            .getProductCode(
                                                                deviceName);
                                                    final topicRx =
                                                        'devices_rx/$productCode/$deviceSerialNumber';
                                                    final topicTx =
                                                        'devices_tx/$productCode/$deviceSerialNumber';
                                                    final Map<String, dynamic>
                                                        io0Map = jsonDecode(
                                                            deviceDATA['io0']);
                                                    final rState =
                                                        (io0Map['r_state'] ??
                                                                '0')
                                                            .toString();
                                                    final message = jsonEncode({
                                                      'pinType': 0,
                                                      'index': 0,
                                                      'w_status': value,
                                                      'r_state': rState,
                                                    });
                                                    bool result =
                                                        await sendMQTTMessageWithPermission(
                                                            deviceName,
                                                            message,
                                                            topicRx,
                                                            topicTx,
                                                            value
                                                                ? 'Encendió dispositivo desde WiFi'
                                                                : 'Apagó dispositivo desde WiFi');

                                                    if (result) {
                                                      setState(() {});
                                                      globalDATA
                                                          .putIfAbsent(
                                                              '$productCode/$deviceSerialNumber',
                                                              () => {})
                                                          .addAll(
                                                              {'io0': message});
                                                    } else {
                                                      showToast(
                                                        'No tienes permisos para realizar esta acción en este momento',
                                                      );
                                                    }
                                                  },
                                                )
                                              : null,
                                        ),
                                      ] else ...[
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16.0,
                                            vertical: 5.0,
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              online
                                                  ? Row(
                                                      children: [
                                                        (jsonDecode(deviceDATA[
                                                                        'io0'])[
                                                                    'w_status'] ??
                                                                false)
                                                            ? Text(
                                                                'ENCENDIDO',
                                                                style:
                                                                    GoogleFonts
                                                                        .poppins(
                                                                  color: Colors
                                                                      .green,
                                                                  fontSize: 15,
                                                                ),
                                                              )
                                                            : Text(
                                                                'APAGADO',
                                                                style:
                                                                    GoogleFonts
                                                                        .poppins(
                                                                  color: color4,
                                                                  fontSize: 15,
                                                                ),
                                                              ),
                                                        const SizedBox(
                                                            width: 5),
                                                        owner
                                                            ? Switch(
                                                                activeThumbColor:
                                                                    const Color(
                                                                        0xFF9C9D98),
                                                                activeTrackColor:
                                                                    const Color(
                                                                        0xFFB2B5AE),
                                                                inactiveThumbColor:
                                                                    const Color(
                                                                        0xFFB2B5AE),
                                                                inactiveTrackColor:
                                                                    const Color(
                                                                        0xFF9C9D98),
                                                                value: (jsonDecode(
                                                                            deviceDATA['io0'])[
                                                                        'w_status'] ??
                                                                    false),
                                                                onChanged:
                                                                    (value) async {
                                                                  final topicRx =
                                                                      'devices_rx/$productCode/$serialNumber';
                                                                  final topicTx =
                                                                      'devices_tx/$productCode/$serialNumber';
                                                                  final Map<
                                                                          String,
                                                                          dynamic>
                                                                      io0Map =
                                                                      jsonDecode(
                                                                          deviceDATA[
                                                                              'io0']);
                                                                  final rState =
                                                                      (io0Map['r_state'] ??
                                                                              '0')
                                                                          .toString();
                                                                  final message =
                                                                      jsonEncode({
                                                                    'pinType':
                                                                        0,
                                                                    'index': 0,
                                                                    'w_status':
                                                                        value,
                                                                    'r_state':
                                                                        rState,
                                                                  });
                                                                  bool result = await sendMQTTMessageWithPermission(
                                                                      deviceName,
                                                                      message,
                                                                      topicRx,
                                                                      topicTx,
                                                                      value
                                                                          ? 'Encendió dispositivo desde WiFi'
                                                                          : 'Apagó dispositivo desde WiFi');
                                                                  if (result) {
                                                                    setState(
                                                                        () {});
                                                                    globalDATA
                                                                        .putIfAbsent(
                                                                            '$productCode/$serialNumber',
                                                                            () =>
                                                                                {})
                                                                        .addAll({
                                                                      'io0':
                                                                          message
                                                                    });
                                                                  } else {
                                                                    showToast(
                                                                      'No tienes permisos para realizar esta acción en este momento',
                                                                    );
                                                                  }
                                                                },
                                                              )
                                                            : const SizedBox(
                                                                height: 0,
                                                                width: 0),
                                                      ],
                                                    )
                                                  : Text(
                                                      'El equipo debe estar\nconectado para su uso',
                                                      style:
                                                          GoogleFonts.poppins(
                                                        color: color3,
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                            ],
                                          ),
                                        )
                                      ],
                                    ],
                                  ],
                                  // POSICIÓN 1: Entrada, solo si hasEntry == true
                                  if (hasEntry) ...[
                                    if (deviceDATA['io1'] == null) ...[
                                      const SizedBox
                                          .shrink() // No mostrar nada si no hay datos
                                    ] else ...[
                                      ListTile(
                                        title: Text(
                                          nicknamesMap['${deviceName}_1'] ??
                                              'Entrada 1',
                                          style: GoogleFonts.poppins(
                                            color: color0,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        trailing: Icon(
                                          HugeIcons.strokeRoundedAlertCircle,
                                          color: (() {
                                            final io1 =
                                                jsonDecode(deviceDATA['io1']);
                                            final bool wStatus =
                                                io1['w_status'] ?? false;
                                            final String rState =
                                                (io1['r_state'] ?? '0')
                                                    .toString();
                                            final bool mismatch =
                                                (rState == '0' && wStatus) ||
                                                    (rState == '1' && !wStatus);
                                            return mismatch
                                                ? color4
                                                : const Color(0xFF9C9D98);
                                          })(),
                                        ),
                                      ),
                                    ]
                                  ]
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                          left: 16.0, bottom: 16.0),
                                      child: Text(
                                        'El equipo debe estar\nconectado para su uso',
                                        style: GoogleFonts.poppins(
                                          color: color3,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        right: 8.0, bottom: 8.0),
                                    child: IconButton(
                                      icon: const Icon(
                                        HugeIcons.strokeRoundedDelete02,
                                        color: color0,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        _confirmDelete(deviceName, productCode);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                    if (online)
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          icon: const Icon(
                            HugeIcons.strokeRoundedDelete02,
                            color: color0,
                            size: 20,
                          ),
                          onPressed: () {
                            _confirmDelete(deviceName, productCode);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        case '050217_IOT':
          bool estado = deviceDATA['w_status'] ?? false;
          bool heaterOn = deviceDATA['f_status'] ?? false;
          return RepaintBoundary(
            key: ValueKey(deviceName),
            child: Card(
              color: cardColor,
              margin: cardMargin,
              elevation: cardElevation,
              shape: cardShape,
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16.0),
                  iconColor: color4,
                  collapsedIconColor: color4,
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(HugeIcons.strokeRoundedMenu01,
                            color: Colors.grey),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nicknamesMap[deviceName] ?? deviceName,
                              style: GoogleFonts.poppins(
                                color: color0,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              spacing: 10,
                              children: [
                                Text(
                                  online ? '● CONECTADO' : '● DESCONECTADO',
                                  style: GoogleFonts.poppins(
                                    color: online ? Colors.green : color3,
                                    fontSize: 15,
                                  ),
                                ),
                                online
                                    ? ImageIcon(
                                        const AssetImage(CaldenIcons.cloud),
                                        color: online ? Colors.green : color3,
                                        size: 25,
                                      )
                                    : ImageIcon(
                                        const AssetImage(CaldenIcons.cloudOff),
                                        color: online ? Colors.green : color3,
                                        size: 15,
                                      ),
                              ],
                            ),
                            if (online && networkUnstable) ...[
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    HugeIcons.strokeRoundedAlert02,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Red inestable',
                                    style: GoogleFonts.poppins(
                                      color: Colors.orange,
                                      fontSize: 15,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    HugeIcons.strokeRoundedAlert02,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                ],
                              )
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  children: <Widget>[
                    isRestrictedAdmin
                        ? Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 5.0),
                                  child: Text(
                                    'El dueño del equipo restringió su uso por wifi.',
                                    style: GoogleFonts.poppins(
                                      color: color3,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 5.0),
                                  child: online
                                      ? Row(
                                          children: [
                                            estado
                                                ? Row(
                                                    children: [
                                                      if (heaterOn) ...[
                                                        Text(
                                                          'Calentando',
                                                          style: GoogleFonts
                                                              .poppins(
                                                            color: Colors
                                                                .amber[800],
                                                            fontSize: 15,
                                                          ),
                                                        ),
                                                        Icon(
                                                          HugeIcons
                                                              .strokeRoundedRainDrop,
                                                          size: 15,
                                                          color:
                                                              Colors.amber[800],
                                                        ),
                                                      ] else ...[
                                                        Text(
                                                          'Encendido',
                                                          style: GoogleFonts
                                                              .poppins(
                                                            color: Colors.green,
                                                            fontSize: 15,
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  )
                                                : Text(
                                                    'Apagado',
                                                    style: GoogleFonts.poppins(
                                                        color: color4,
                                                        fontSize: 15),
                                                  ),
                                            const SizedBox(width: 5),
                                            owner
                                                ? Switch(
                                                    activeThumbColor:
                                                        const Color(0xFF9C9D98),
                                                    activeTrackColor:
                                                        const Color(0xFFB2B5AE),
                                                    inactiveThumbColor:
                                                        const Color(0xFFB2B5AE),
                                                    inactiveTrackColor:
                                                        const Color(0xFF9C9D98),
                                                    value: estado,
                                                    onChanged: (newValue) {
                                                      toggleState(
                                                          deviceName, newValue);
                                                      setState(() {
                                                        estado = newValue;
                                                      });
                                                    },
                                                  )
                                                : const SizedBox(
                                                    height: 0, width: 0),
                                            if (!owner) ...[
                                              _buildNotOwnerWarning()
                                            ],
                                          ],
                                        )
                                      : Padding(
                                          padding: const EdgeInsets.only(
                                              left: 8.0, bottom: 8.0),
                                          child: Text(
                                            'El equipo debe estar\nconectado para su uso',
                                            style: GoogleFonts.poppins(
                                              color: color3,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                    right: 8.0, bottom: 8.0),
                                child: IconButton(
                                  icon: const Icon(
                                    HugeIcons.strokeRoundedDelete02,
                                    color: color0,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    _confirmDelete(deviceName, productCode);
                                  },
                                ),
                              ),
                            ],
                          ),
                  ],
                ),
              ),
            ),
          );
        case '020020_IOT':
          // Verificar si es un equipo de riego
          bool isRiegoActive = deviceDATA['riegoActive'] == true;
          if (isRiegoActive) {
            return _buildRiegoCard(deviceName, productCode, serialNumber,
                deviceDATA, online, owner, index);
          }

          // Código original para equipos normales
          return RepaintBoundary(
            key: ValueKey(deviceName),
            child: Card(
              color: cardColor,
              margin: cardMargin,
              elevation: cardElevation,
              shape: cardShape,
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16.0),
                  iconColor: color4,
                  collapsedIconColor: color4,
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(HugeIcons.strokeRoundedMenu01,
                            color: Colors.grey),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nicknamesMap[deviceName] ?? deviceName,
                              style: GoogleFonts.poppins(
                                color: color0,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              spacing: 10,
                              children: [
                                Text(
                                  online ? '● CONECTADO' : '● DESCONECTADO',
                                  style: GoogleFonts.poppins(
                                    color: online ? Colors.green : color3,
                                    fontSize: 15,
                                  ),
                                ),
                                online
                                    ? ImageIcon(
                                        const AssetImage(CaldenIcons.cloud),
                                        color: online ? Colors.green : color3,
                                        size: 25,
                                      )
                                    : ImageIcon(
                                        const AssetImage(CaldenIcons.cloudOff),
                                        color: online ? Colors.green : color3,
                                        size: 15,
                                      ),
                              ],
                            ),
                            if (online && networkUnstable) ...[
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    HugeIcons.strokeRoundedAlert02,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Red inestable',
                                    style: GoogleFonts.poppins(
                                      color: Colors.orange,
                                      fontSize: 15,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    HugeIcons.strokeRoundedAlert02,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                ],
                              )
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  children: <Widget>[
                    isRestrictedAdmin
                        ? Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 5.0),
                                  child: Text(
                                    'El dueño del equipo restringió su uso por wifi.',
                                    style: GoogleFonts.poppins(
                                      color: color3,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : online
                            ? Column(
                                children: [
                                  ...(deviceDATA.keys
                                          .where((key) =>
                                              key.startsWith('io') &&
                                              RegExp(r'^io\d+$').hasMatch(key))
                                          .where((ioKey) =>
                                              deviceDATA[ioKey] != null)
                                          .toList()
                                        ..sort((a, b) {
                                          int indexA =
                                              int.parse(a.substring(2));
                                          int indexB =
                                              int.parse(b.substring(2));
                                          return indexA.compareTo(indexB);
                                        }))
                                      .map((ioKey) {
                                    // Extraer el índice del ioKey (ejemplo: "io0" -> 0)
                                    int i = int.parse(ioKey.substring(2));
                                    Map<String, dynamic> equipo =
                                        jsonDecode(deviceDATA[ioKey]);
                                    // printLog.i(
                                    //   'Voy a realizar el cambio: $equipo',
                                    // );
                                    String tipoWifi =
                                        equipo['pinType'].toString() == '0'
                                            ? 'Salida'
                                            : 'Entrada';
                                    bool estadoWifi = equipo['w_status'];
                                    String comunWifi =
                                        (equipo['r_state'] ?? '0').toString();
                                    bool entradaWifi = tipoWifi == 'Entrada';
                                    return ListTile(
                                      title: Row(
                                        children: [
                                          Text(
                                            nicknamesMap['${deviceName}_$i'] ??
                                                '$tipoWifi $i',
                                            style: GoogleFonts.poppins(
                                              color: color0,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                        ],
                                      ),
                                      subtitle: Align(
                                        alignment:
                                            AlignmentDirectional.centerStart,
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.start,
                                          children: [
                                            entradaWifi
                                                ? estadoWifi
                                                    ? comunWifi == '1'
                                                        ? Text(
                                                            'Cerrado',
                                                            style: GoogleFonts
                                                                .poppins(
                                                              color:
                                                                  Colors.green,
                                                              fontSize: 15,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          )
                                                        : Text(
                                                            'Abierto',
                                                            style: GoogleFonts
                                                                .poppins(
                                                              color: color4,
                                                              fontSize: 15,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          )
                                                    : comunWifi == '1'
                                                        ? Text(
                                                            'Abierto',
                                                            style: GoogleFonts
                                                                .poppins(
                                                              color: color4,
                                                              fontSize: 15,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          )
                                                        : Text(
                                                            'Cerrado',
                                                            style: GoogleFonts
                                                                .poppins(
                                                              color:
                                                                  Colors.green,
                                                              fontSize: 15,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          )
                                                : estadoWifi
                                                    ? Text(
                                                        'Encendido',
                                                        style:
                                                            GoogleFonts.poppins(
                                                          color: Colors.green,
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      )
                                                    : Text(
                                                        'Apagado',
                                                        style:
                                                            GoogleFonts.poppins(
                                                          color: color4,
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                          ],
                                        ),
                                      ),
                                      trailing: owner
                                          ? entradaWifi
                                              ? estadoWifi
                                                  ? comunWifi == '1'
                                                      ? const Icon(
                                                          HugeIcons
                                                              .strokeRoundedAlertDiamond,
                                                          color: Color(
                                                            0xff9b9b9b,
                                                          ),
                                                        )
                                                      : const Icon(
                                                          HugeIcons
                                                              .strokeRoundedAlertDiamond,
                                                          color: color4,
                                                        )
                                                  : comunWifi == '1'
                                                      ? const Icon(
                                                          HugeIcons
                                                              .strokeRoundedAlertDiamond,
                                                          color: color4,
                                                        )
                                                      : const Icon(
                                                          HugeIcons
                                                              .strokeRoundedAlertDiamond,
                                                          color: Color(
                                                            0xff9b9b9b,
                                                          ),
                                                        )
                                              : Switch(
                                                  activeThumbColor: const Color(
                                                    0xFF9C9D98,
                                                  ),
                                                  activeTrackColor: const Color(
                                                    0xFFB2B5AE,
                                                  ),
                                                  inactiveThumbColor:
                                                      const Color(
                                                    0xFFB2B5AE,
                                                  ),
                                                  inactiveTrackColor:
                                                      const Color(
                                                    0xFF9C9D98,
                                                  ),
                                                  value: estadoWifi,
                                                  onChanged: (value) async {
                                                    String topic =
                                                        'devices_rx/$productCode/$serialNumber';
                                                    String topic2 =
                                                        'devices_tx/$productCode/$serialNumber';
                                                    String message =
                                                        jsonEncode({
                                                      'pinType':
                                                          tipoWifi == 'Salida'
                                                              ? 0
                                                              : 1,
                                                      'index': i,
                                                      'w_status': value,
                                                      'r_state': comunWifi,
                                                    });
                                                    bool result =
                                                        await sendMQTTMessageWithPermission(
                                                            deviceName,
                                                            message,
                                                            topic,
                                                            topic2,
                                                            value
                                                                ? 'Encendió dispositivo desde WiFi'
                                                                : 'Apagó dispositivo desde WiFi');
                                                    if (result) {
                                                      setState(() {
                                                        estadoWifi = value;
                                                      });
                                                      globalDATA
                                                          .putIfAbsent(
                                                              '$productCode/$serialNumber',
                                                              () => {})
                                                          .addAll({
                                                        'io$i': message
                                                      });
                                                    } else {
                                                      showToast(
                                                        'No tienes permisos para realizar esta acción en este momento',
                                                      );
                                                    }
                                                  },
                                                )
                                          : null,
                                    );
                                  }),
                                  if (!owner) ...[_buildNotOwnerWarning()],
                                ],
                              )
                            : const SizedBox(height: 0),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Padding(
                            padding:
                                const EdgeInsets.only(left: 20.0, bottom: 16.0),
                            child: !online
                                ? Text(
                                    'El equipo debe estar\nconectado para su uso',
                                    style: GoogleFonts.poppins(
                                      color: color3,
                                      fontSize: 15,
                                    ),
                                  )
                                : const SizedBox(height: 0),
                          ),
                        ),
                        if (!online)
                          Padding(
                            padding:
                                const EdgeInsets.only(right: 8.0, bottom: 8.0),
                            child: IconButton(
                              icon: const Icon(
                                HugeIcons.strokeRoundedDelete02,
                                color: color0,
                                size: 20,
                              ),
                              onPressed: () {
                                _confirmDelete(deviceName, productCode);
                              },
                            ),
                          ),
                      ],
                    ),
                    if (online)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding:
                              const EdgeInsets.only(right: 16.0, bottom: 8.0),
                          child: IconButton(
                            icon: const Icon(
                              HugeIcons.strokeRoundedDelete02,
                              color: color0,
                              size: 20,
                            ),
                            onPressed: () {
                              _confirmDelete(deviceName, productCode);
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        case '041220_IOT':
          bool estado = deviceDATA['w_status'] ?? false;
          bool heaterOn = deviceDATA['f_status'] ?? false;

          return RepaintBoundary(
            key: ValueKey(deviceName),
            child: Card(
              color: cardColor,
              margin: cardMargin,
              elevation: cardElevation,
              shape: cardShape,
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16.0),
                  iconColor: color4,
                  collapsedIconColor: color4,
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(HugeIcons.strokeRoundedMenu01,
                            color: Colors.grey),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nicknamesMap[deviceName] ?? deviceName,
                              style: GoogleFonts.poppins(
                                color: color0,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              spacing: 10,
                              children: [
                                Text(
                                  online ? '● CONECTADO' : '● DESCONECTADO',
                                  style: GoogleFonts.poppins(
                                    color: online ? Colors.green : color3,
                                    fontSize: 15,
                                  ),
                                ),
                                online
                                    ? ImageIcon(
                                        const AssetImage(CaldenIcons.cloud),
                                        color: online ? Colors.green : color3,
                                        size: 25,
                                      )
                                    : ImageIcon(
                                        const AssetImage(CaldenIcons.cloudOff),
                                        color: online ? Colors.green : color3,
                                        size: 15,
                                      ),
                              ],
                            ),
                            if (online && networkUnstable) ...[
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    HugeIcons.strokeRoundedAlert02,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Red inestable',
                                    style: GoogleFonts.poppins(
                                      color: Colors.orange,
                                      fontSize: 15,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    HugeIcons.strokeRoundedAlert02,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                ],
                              )
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  children: <Widget>[
                    isRestrictedAdmin
                        ? Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 5.0),
                                  child: Text(
                                    'El dueño del equipo restringió su uso por wifi.',
                                    style: GoogleFonts.poppins(
                                      color: color3,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16.0, vertical: 5.0),
                                    child: online
                                        ? Row(
                                            children: [
                                              estado
                                                  ? Row(
                                                      children: [
                                                        if (heaterOn) ...[
                                                          Text(
                                                            'Calentando',
                                                            style: GoogleFonts
                                                                .poppins(
                                                              color: Colors
                                                                  .amber[800],
                                                              fontSize: 15,
                                                            ),
                                                          ),
                                                          Icon(
                                                            HugeIcons
                                                                .strokeRoundedFlash,
                                                            size: 15,
                                                            color: Colors
                                                                .amber[800],
                                                          ),
                                                        ] else ...[
                                                          Text(
                                                            'Encendido',
                                                            style: GoogleFonts
                                                                .poppins(
                                                              color:
                                                                  Colors.green,
                                                              fontSize: 15,
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    )
                                                  : Text(
                                                      'Apagado',
                                                      style:
                                                          GoogleFonts.poppins(
                                                              color: color4,
                                                              fontSize: 15),
                                                    ),
                                              const SizedBox(width: 5),
                                              owner
                                                  ? Switch(
                                                      activeThumbColor:
                                                          const Color(
                                                              0xFF9C9D98),
                                                      activeTrackColor:
                                                          const Color(
                                                              0xFFB2B5AE),
                                                      inactiveThumbColor:
                                                          const Color(
                                                              0xFFB2B5AE),
                                                      inactiveTrackColor:
                                                          const Color(
                                                              0xFF9C9D98),
                                                      value: estado,
                                                      onChanged: (newValue) {
                                                        toggleState(deviceName,
                                                            newValue);
                                                        setState(() {
                                                          estado = newValue;
                                                        });
                                                      },
                                                    )
                                                  : const SizedBox(
                                                      height: 0, width: 0),
                                              if (!owner) ...[
                                                _buildNotOwnerWarning()
                                              ],
                                            ],
                                          )
                                        : Text(
                                            'El equipo debe estar\nconectado para su uso',
                                            style: GoogleFonts.poppins(
                                              color: color3,
                                              fontSize: 15,
                                            ),
                                          )),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                    right: 8.0, bottom: 8.0),
                                child: IconButton(
                                  icon: const Icon(
                                    HugeIcons.strokeRoundedDelete02,
                                    color: color0,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    _confirmDelete(deviceName, productCode);
                                  },
                                ),
                              ),
                            ],
                          ),
                  ],
                ),
              ),
            ),
          );
        case '028000_IOT':
          bool estado = deviceDATA['w_status'] ?? false;
          bool heaterOn = deviceDATA['f_status'] ?? false;
          return RepaintBoundary(
            key: ValueKey(deviceName),
            child: Card(
              color: cardColor,
              margin: cardMargin,
              elevation: cardElevation,
              shape: cardShape,
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16.0),
                  iconColor: color4,
                  collapsedIconColor: color4,
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(HugeIcons.strokeRoundedMenu01,
                            color: Colors.grey),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nicknamesMap[deviceName] ?? deviceName,
                              style: GoogleFonts.poppins(
                                color: color0,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              spacing: 10,
                              children: [
                                Text(
                                  online ? '● CONECTADO' : '● DESCONECTADO',
                                  style: GoogleFonts.poppins(
                                    color: online ? Colors.green : color3,
                                    fontSize: 15,
                                  ),
                                ),
                                online
                                    ? ImageIcon(
                                        const AssetImage(CaldenIcons.cloud),
                                        color: online ? Colors.green : color3,
                                        size: 25,
                                      )
                                    : ImageIcon(
                                        const AssetImage(CaldenIcons.cloudOff),
                                        color: online ? Colors.green : color3,
                                        size: 15,
                                      ),
                              ],
                            ),
                            if (online && networkUnstable) ...[
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    HugeIcons.strokeRoundedAlert02,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Red inestable',
                                    style: GoogleFonts.poppins(
                                      color: Colors.orange,
                                      fontSize: 15,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    HugeIcons.strokeRoundedAlert02,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                ],
                              )
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  children: <Widget>[
                    isRestrictedAdmin
                        ? Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 5.0),
                                  child: Text(
                                    'El dueño del equipo restringió su uso por wifi.',
                                    style: GoogleFonts.poppins(
                                      color: color3,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16.0, vertical: 16.0),
                                    child: online
                                        ? Row(
                                            children: [
                                              estado
                                                  ? Row(
                                                      children: [
                                                        if (heaterOn) ...[
                                                          Text(
                                                            'Enfriando',
                                                            style: GoogleFonts
                                                                .poppins(
                                                              color: Colors
                                                                  .lightBlueAccent
                                                                  .shade400,
                                                              fontSize: 15,
                                                            ),
                                                          ),
                                                          Icon(
                                                            HugeIcons
                                                                .strokeRoundedSnow,
                                                            size: 15,
                                                            color: Colors
                                                                .lightBlueAccent
                                                                .shade400,
                                                          ),
                                                        ] else ...[
                                                          Text(
                                                            'Encendido',
                                                            style: GoogleFonts
                                                                .poppins(
                                                              color:
                                                                  Colors.green,
                                                              fontSize: 15,
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    )
                                                  : Text(
                                                      'Apagado',
                                                      style:
                                                          GoogleFonts.poppins(
                                                              color: color4,
                                                              fontSize: 15),
                                                    ),
                                              const SizedBox(width: 5),
                                              owner
                                                  ? Switch(
                                                      activeThumbColor:
                                                          const Color(
                                                              0xFF9C9D98),
                                                      activeTrackColor:
                                                          const Color(
                                                              0xFFB2B5AE),
                                                      inactiveThumbColor:
                                                          const Color(
                                                              0xFFB2B5AE),
                                                      inactiveTrackColor:
                                                          const Color(
                                                              0xFF9C9D98),
                                                      value: estado,
                                                      onChanged: (newValue) {
                                                        toggleState(deviceName,
                                                            newValue);
                                                        setState(() {
                                                          estado = newValue;
                                                        });
                                                      },
                                                    )
                                                  : const SizedBox(
                                                      height: 0, width: 0),
                                              if (!owner) ...[
                                                _buildNotOwnerWarning()
                                              ],
                                            ],
                                          )
                                        : Text(
                                            'El equipo debe estar\nconectado para su uso',
                                            style: GoogleFonts.poppins(
                                              color: color3,
                                              fontSize: 15,
                                            ),
                                          )),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                    right: 8.0, bottom: 8.0),
                                child: IconButton(
                                  icon: const Icon(
                                    HugeIcons.strokeRoundedDelete02,
                                    color: color0,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    _confirmDelete(deviceName, productCode);
                                  },
                                ),
                              ),
                            ],
                          ),
                  ],
                ),
              ),
            ),
          );
        case '023430_IOT':
          String temp = deviceDATA['actualTemp'].toString();
          bool alertMaxFlag = deviceDATA['alert_maxflag'] ?? false;
          bool alertMinFlag = deviceDATA['alert_minflag'] ?? false;
          bool init = deviceDATA['startup_evaluated'] ?? false;
          return RepaintBoundary(
            key: ValueKey(deviceName),
            child: Card(
              color: cardColor,
              margin: cardMargin,
              elevation: cardElevation,
              shape: cardShape,
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16.0),
                  iconColor: color4,
                  collapsedIconColor: color4,
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(HugeIcons.strokeRoundedMenu01,
                            color: Colors.grey),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nicknamesMap[deviceName] ?? deviceName,
                              style: GoogleFonts.poppins(
                                color: color0,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              spacing: 10,
                              children: [
                                Text(
                                  online ? '● CONECTADO' : '● DESCONECTADO',
                                  style: GoogleFonts.poppins(
                                    color: online ? Colors.green : color3,
                                    fontSize: 15,
                                  ),
                                ),
                                online
                                    ? ImageIcon(
                                        const AssetImage(CaldenIcons.cloud),
                                        color: online ? Colors.green : color3,
                                        size: 25,
                                      )
                                    : ImageIcon(
                                        const AssetImage(CaldenIcons.cloudOff),
                                        color: online ? Colors.green : color3,
                                        size: 15,
                                      ),
                              ],
                            ),
                            if (online && networkUnstable) ...[
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    HugeIcons.strokeRoundedAlert02,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Red inestable',
                                    style: GoogleFonts.poppins(
                                      color: Colors.orange,
                                      fontSize: 15,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    HugeIcons.strokeRoundedAlert02,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                ],
                              )
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  children: <Widget>[
                    isRestrictedAdmin
                        ? Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 5.0),
                                  child: Text(
                                    'El dueño del equipo restringió su uso por wifi.',
                                    style: GoogleFonts.poppins(
                                      color: color3,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 5.0),
                                  child: online
                                      ? Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              init ? 'Temperatura: $temp °C' : 'Inicializando...',
                                              style: GoogleFonts.poppins(
                                                color: color0,
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Row(
                                              children: [
                                                Text(
                                                  'Alerta máxima:',
                                                  style: GoogleFonts.poppins(
                                                    color: color0,
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(width: 5),
                                                alertMaxFlag
                                                    ? const Icon(
                                                        HugeIcons
                                                            .strokeRoundedAlert02,
                                                        color: color4,
                                                      )
                                                    : const ImageIcon(
                                                        AssetImage(CaldenIcons
                                                            .termometro),
                                                        color: Colors.green,
                                                      ),
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                Text(
                                                  'Alerta mínima:',
                                                  style: GoogleFonts.poppins(
                                                    color: color0,
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(width: 5),
                                                alertMinFlag
                                                    ? const Icon(
                                                        HugeIcons
                                                            .strokeRoundedAlert02,
                                                        color: color4,
                                                      )
                                                    : const Icon(
                                                        HugeIcons
                                                            .strokeRoundedTemperature,
                                                        color: Colors.green,
                                                      ),
                                              ],
                                            ),
                                          ],
                                        )
                                      : Padding(
                                          padding: const EdgeInsets.only(
                                              left: 8.0, bottom: 8.0),
                                          child: Text(
                                            'El equipo debe estar\nconectado para su uso',
                                            style: GoogleFonts.poppins(
                                              color: color3,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                    right: 8.0, bottom: 8.0),
                                child: IconButton(
                                  icon: const Icon(
                                    HugeIcons.strokeRoundedDelete02,
                                    color: color0,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    _confirmDelete(deviceName, productCode);
                                  },
                                ),
                              ),
                            ],
                          ),
                  ],
                ),
              ),
            ),
          );
        case '027345_IOT':
          bool estado = deviceDATA['w_status'] ?? false;
          bool heaterOn = deviceDATA['f_status'] ?? false;
          return RepaintBoundary(
            key: ValueKey(deviceName),
            child: Card(
              color: cardColor,
              margin: cardMargin,
              elevation: cardElevation,
              shape: cardShape,
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16.0),
                  iconColor: color4,
                  collapsedIconColor: color4,
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(HugeIcons.strokeRoundedMenu01,
                            color: Colors.grey),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nicknamesMap[deviceName] ?? deviceName,
                              style: GoogleFonts.poppins(
                                color: color0,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              spacing: 10,
                              children: [
                                Text(
                                  online ? '● CONECTADO' : '● DESCONECTADO',
                                  style: GoogleFonts.poppins(
                                    color: online ? Colors.green : color3,
                                    fontSize: 15,
                                  ),
                                ),
                                online
                                    ? ImageIcon(
                                        const AssetImage(CaldenIcons.cloud),
                                        color: online ? Colors.green : color3,
                                        size: 25,
                                      )
                                    : ImageIcon(
                                        const AssetImage(CaldenIcons.cloudOff),
                                        color: online ? Colors.green : color3,
                                        size: 15,
                                      ),
                              ],
                            ),
                            if (online && networkUnstable) ...[
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    HugeIcons.strokeRoundedAlert02,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Red inestable',
                                    style: GoogleFonts.poppins(
                                      color: Colors.orange,
                                      fontSize: 15,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    HugeIcons.strokeRoundedAlert02,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                ],
                              )
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  children: <Widget>[
                    isRestrictedAdmin
                        ? Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 5.0),
                                  child: Text(
                                    'El dueño del equipo restringió su uso por wifi.',
                                    style: GoogleFonts.poppins(
                                      color: color3,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 5.0),
                                  child: online
                                      ? Row(
                                          children: [
                                            estado
                                                ? Row(
                                                    children: [
                                                      if (heaterOn) ...[
                                                        Text(
                                                          'Calentando',
                                                          style: GoogleFonts
                                                              .poppins(
                                                            color: Colors
                                                                .amber[800],
                                                            fontSize: 15,
                                                          ),
                                                        ),
                                                        Icon(
                                                          HugeIcons
                                                              .strokeRoundedRainDrop,
                                                          size: 15,
                                                          color:
                                                              Colors.amber[800],
                                                        ),
                                                      ] else ...[
                                                        Text(
                                                          'Encendido',
                                                          style: GoogleFonts
                                                              .poppins(
                                                            color: Colors.green,
                                                            fontSize: 15,
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  )
                                                : Text(
                                                    'Apagado',
                                                    style: GoogleFonts.poppins(
                                                        color: color4,
                                                        fontSize: 15),
                                                  ),
                                            const SizedBox(width: 5),
                                            owner
                                                ? Switch(
                                                    activeThumbColor:
                                                        const Color(0xFF9C9D98),
                                                    activeTrackColor:
                                                        const Color(0xFFB2B5AE),
                                                    inactiveThumbColor:
                                                        const Color(0xFFB2B5AE),
                                                    inactiveTrackColor:
                                                        const Color(0xFF9C9D98),
                                                    value: estado,
                                                    onChanged: (newValue) {
                                                      toggleState(
                                                          deviceName, newValue);
                                                      setState(() {
                                                        estado = newValue;
                                                      });
                                                    },
                                                  )
                                                : const SizedBox(
                                                    height: 0, width: 0),
                                            if (!owner) ...[
                                              _buildNotOwnerWarning()
                                            ],
                                          ],
                                        )
                                      : Padding(
                                          padding: const EdgeInsets.only(
                                              left: 8.0, bottom: 8.0),
                                          child: Text(
                                            'El equipo debe estar\nconectado para su uso',
                                            style: GoogleFonts.poppins(
                                              color: color3,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                    right: 8.0, bottom: 8.0),
                                child: IconButton(
                                  icon: const Icon(
                                    HugeIcons.strokeRoundedDelete02,
                                    color: color0,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    _confirmDelete(deviceName, productCode);
                                  },
                                ),
                              ),
                            ],
                          ),
                  ],
                ),
              ),
            ),
          );
        case '024011_IOT':
          int actualPosition = deviceDATA['actual_position'] ?? -1;
          final dynamic rawWp = deviceDATA['working_position'];
          int workingPosition = rawWp is int
              ? rawWp
              : int.tryParse(rawWp.toString().replaceAll('%', '')) ?? -1;
          bool moving = deviceDATA['moving'] ?? false;
          bool isCalibrated = deviceDATA['is_calibrated'] ?? false;

          if (moving == false && actualPosition != workingPosition) {
            workingPosition = actualPosition;
          }

          // Está en movimiento mientras moving=true O mientras no llegó al destino
          bool isMoving = moving;

          // Label y color del estado
          String positionLabel;
          Color positionColor;
          if (isMoving) {
            positionLabel = actualPosition >= 0
                ? 'Moviendo... $actualPosition%'
                : 'Moviendo...';
            positionColor = Colors.grey;
          } else if (actualPosition == 0) {
            positionLabel = 'Abierto (0%)';
            positionColor = Colors.green;
          } else if (actualPosition == 100) {
            positionLabel = 'Cerrado (100%)';
            positionColor = color4;
          } else if (actualPosition > 0 && actualPosition < 100) {
            positionLabel = 'Parcial ($actualPosition%)';
            positionColor = Colors.orange;
          } else {
            positionLabel = 'Sin datos';
            positionColor = Colors.grey;
          }

          return RepaintBoundary(
            key: ValueKey(deviceName),
            child: Card(
              color: cardColor,
              margin: cardMargin,
              elevation: cardElevation,
              shape: cardShape,
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16.0),
                  iconColor: color4,
                  collapsedIconColor: color4,
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(HugeIcons.strokeRoundedMenu01,
                            color: Colors.grey),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nicknamesMap[deviceName] ?? deviceName,
                              style: GoogleFonts.poppins(
                                color: color0,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              spacing: 10,
                              children: [
                                Text(
                                  online ? '● CONECTADO' : '● DESCONECTADO',
                                  style: GoogleFonts.poppins(
                                    color: online ? Colors.green : color3,
                                    fontSize: 15,
                                  ),
                                ),
                                online
                                    ? const ImageIcon(
                                        AssetImage(CaldenIcons.cloud),
                                        color: Colors.green,
                                        size: 25,
                                      )
                                    : const ImageIcon(
                                        AssetImage(CaldenIcons.cloudOff),
                                        color: color3,
                                        size: 15,
                                      ),
                              ],
                            ),
                            if (online && networkUnstable) ...[
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(HugeIcons.strokeRoundedAlert02,
                                      color: Colors.orange, size: 18),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Red inestable',
                                    style: GoogleFonts.poppins(
                                        color: Colors.orange, fontSize: 15),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(HugeIcons.strokeRoundedAlert02,
                                      color: Colors.orange, size: 18),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  children: <Widget>[
                    isRestrictedAdmin
                        ? Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 5.0),
                                  child: Text(
                                    'El dueño del equipo restringió su uso por wifi.',
                                    style: GoogleFonts.poppins(
                                        color: color3, fontSize: 15),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: online
                                      ? (!isCalibrated
                                          ? Row(
                                              children: [
                                                const Icon(
                                                  HugeIcons.strokeRoundedRuler,
                                                  color: Colors.orange,
                                                  size: 18,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    'El equipo necesita calibración antes de usarse',
                                                    style: GoogleFonts.poppins(
                                                      color: Colors.orange,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            )
                                          : Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                // ── Estado / porcentaje ──
                                                Row(
                                                  children: [
                                                    Icon(
                                                      HugeIcons
                                                          .strokeRoundedOrbit01,
                                                      color: isMoving
                                                          ? Colors.grey
                                                          : positionColor,
                                                      size: 18,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      positionLabel,
                                                      style:
                                                          GoogleFonts.poppins(
                                                        color: isMoving
                                                            ? Colors.grey
                                                            : positionColor,
                                                        fontSize: 15,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    // Spinner mientras se mueve
                                                    if (isMoving) ...[
                                                      const SizedBox(width: 8),
                                                      const SizedBox(
                                                        width: 14,
                                                        height: 14,
                                                        child:
                                                            CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Colors.grey,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                const SizedBox(height: 10),

                                                if (owner) ...[
                                                  // ── Slider de posición ──
                                                  _RollerPositionSlider(
                                                    initialValue:
                                                        workingPosition,
                                                    isMoving: isMoving,
                                                    onChangeEnd: (v) =>
                                                        _sendRollerCommand(
                                                            deviceName, v),
                                                  ),
                                                ] else ...[
                                                  _buildNotOwnerWarning(),
                                                ],
                                              ],
                                            ))
                                      : Text(
                                          'El equipo debe estar\nconectado para su uso',
                                          style: GoogleFonts.poppins(
                                              color: color3, fontSize: 15),
                                        ),
                                ),
                                // ── Botón delete ──
                                IconButton(
                                  icon: const Icon(
                                    HugeIcons.strokeRoundedDelete02,
                                    color: color0,
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      _confirmDelete(deviceName, productCode),
                                ),
                              ],
                            ),
                          ),
                  ],
                ),
              ),
            ),
          );
        default:
          return Container(
            key: ValueKey(deviceName),
          );
      }
    } catch (e) {
      printLog.e('Error al procesar el equipo $deviceName: $e');
      return RepaintBoundary(
        key: ValueKey('${deviceName}_error'),
        child: Card(
          color: color1,
          margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
          elevation: 2,
          child: Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(
                      nicknamesMap[deviceName] ?? deviceName,
                      style: GoogleFonts.poppins(
                        color: color0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      'Por favor, verifica la conexión y actualice su equipo.',
                      style: GoogleFonts.poppins(
                        color: color0,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              )),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Escucha cambios en globalDataProvider para detectar cuando un device
    // pasa de cstate=true a cstate=false (desconexión). En ese momento
    // refrescamos el flag de "red inestable" SOLO para ese device.
    // Si no hay desconexiones, el cache no se toca → cero queries innecesarias.
    ref.listen(globalDataProvider, (previous, next) {
      for (final entry in next.entries) {
        final String key = entry.key; // formato "pc/sn"
        final dynamic newCstate = entry.value['cstate'];
        if (newCstate is! bool) continue;

        final bool prevCstate = _previousCstate[key] ?? newCstate;

        // Transición true → false: device se acaba de desconectar.
        if (prevCstate == true && newCstate == false) {
          final parts = key.split('/');
          if (parts.length == 2) {
            _refreshNetworkUnstableForDevice(parts[0], parts[1]);
          }
        }

        _previousCstate[key] = newCstate;
      }
    });

    final safeAreaBottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      extendBody: false,
      resizeToAvoidBottomInset: false,
      backgroundColor: color0,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('Mis equipos registrados',
            style: GoogleFonts.poppins(color: color0)),
        backgroundColor: color1,
        bottom: TabBar(
          controller: _tabController,
          labelColor: color0,
          unselectedLabelColor: color0.withValues(alpha: 0.6),
          indicatorColor: color4,
          dividerColor: Colors.transparent,
          labelStyle:
              GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 14),
          unselectedLabelStyle:
              GoogleFonts.poppins(fontWeight: FontWeight.normal, fontSize: 14),
          tabs: [
            Tab(text: 'Individuales ($_totalDispositivosReal)'),
            Tab(text: 'Eventos (${_listaEventos.length})'),
          ],
        ),
      ),
      body: Container(
        padding: const EdgeInsets.only(bottom: 100.0),
        color: color0,
        child: TabBarView(
          controller: _tabController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildDeviceList(_listaIndividuales, 'individual'),
            _buildDeviceList(_listaEventos, 'grupos',
                footerWidget: _buildConfigButton()),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _listaIndividuales.isNotEmpty &&
              _tabController.index == 0
          ? Padding(
              padding: EdgeInsets.only(bottom: 10 + safeAreaBottom),
              child: FloatingActionButton.extended(
                backgroundColor: color4,
                elevation: 5,
                onPressed: _showCreateFolderDialog,
                icon:
                    const Icon(HugeIcons.strokeRoundedFolderAdd, color: color0),
                label: Text('Agrupar',
                    style: GoogleFonts.poppins(
                        color: color0, fontWeight: FontWeight.bold)),
              ),
            )
          : null,
    );
  }

  Widget _buildConfigButton() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color1, color1.withValues(alpha: 0.8)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color1.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            final result = await Navigator.pushNamed(context, '/escenas');
            if (result == true && mounted) {
              _buildDeviceListFromLoadedData();
            }
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color0.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    HugeIcons.strokeRoundedPlusSign,
                    color: color0,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Configurar evento',
                  style: GoogleFonts.poppins(
                    color: color0,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotOwnerWarning() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          height: 10,
        ),
        SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          child: Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1), // Fondo sutil
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade700, width: 1),
            ),
            child: Row(
              children: [
                Icon(HugeIcons.strokeRoundedIdNotVerified,
                    color: Colors.amber[800]),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Ud. no está habilitado\npara controlar este dispositivo',
                    style: GoogleFonts.poppins(
                      color: Colors.amber[900],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(
          height: 10,
        ),
      ],
    );
  }

  Widget _buildDeviceList(
      List<MapEntry<String, String>> deviceList, String tipo,
      {Widget? footerWidget}) {
    if (deviceList.where((e) => e.value.trim().isNotEmpty).isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                tipo == 'individual'
                    ? HugeIcons.strokeRoundedSmartPhone01
                    : HugeIcons.strokeRoundedUserGroup,
                size: 80,
                color: color1.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 20),
              Text(
                tipo == 'individual'
                    ? 'No hay equipos individuales conectados'
                    : 'No hay eventos creados',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color1,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                tipo == 'individual'
                    ? 'Conecta tus primeros dispositivos para comenzar'
                    : 'Crea eventos para controlar múltiples dispositivos',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: color1.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 20),
              if (tipo != 'individual') ...[
                const SizedBox(height: 20),
                _buildConfigButton(),
              ],
            ],
          ),
        ),
      );
    }

    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      proxyDecorator: (Widget child, int index, Animation<double> animation) {
        return Theme(
          data: Theme.of(context).copyWith(
            cardTheme: Theme.of(context).cardTheme.copyWith(
                  surfaceTintColor: Colors.transparent,
                  color: color1,
                  shadowColor: Colors.transparent,
                ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: child,
          ),
        );
      },
      itemCount: deviceList.length,
      footer: Column(
        children: [
          if (footerWidget != null) ...[
            const SizedBox(height: 10),
            footerWidget,
          ],
          const SizedBox(height: 120),
        ],
      ),
      onReorder: (int oldIndex, int newIndex) {
        if (newIndex > oldIndex) newIndex -= 1;

        setState(() {
          if (tipo == 'individual') {
            final item = _listaIndividuales.removeAt(oldIndex);
            _listaIndividuales.insert(newIndex, item);
          } else {
            final item = _listaEventos.removeAt(oldIndex);
            _listaEventos.insert(newIndex, item);
          }

          todosLosDispositivos
            ..clear()
            ..addAll(_listaIndividuales)
            ..addAll(_listaEventos);
        });

        _saveOrder(immediate: false);
      },
      itemBuilder: (BuildContext context, int index) {
        final String key = deviceList[index].key;
        final String value = deviceList[index].value;

        if (key == 'folder') {
          return _buildFolderWidget(value, index);
        }

        final String grupo = key;
        final String deviceName = value;

        final bool esGrupo = grupo != 'individual';

        if (!esGrupo) {
          return _buildDeviceCard(deviceName, index, isInsideFolder: false);
        } else {
          // Detectar si es una cadena
          final eventoCadena = eventosCreados
                  .where(
                    (evento) =>
                        evento['evento'] == 'cadena' &&
                        evento['title'] == grupo &&
                        (evento['deviceGroup'] as List<dynamic>).join(',') ==
                            deviceName,
                  )
                  .isNotEmpty
              ? eventosCreados.firstWhere(
                  (evento) =>
                      evento['evento'] == 'cadena' &&
                      evento['title'] == grupo &&
                      (evento['deviceGroup'] as List<dynamic>).join(',') ==
                          deviceName,
                )
              : null;

          // Detectar si es un evento de riego
          final eventoRiego = eventosCreados
                  .where(
                    (evento) =>
                        evento['evento'] == 'riego' &&
                        evento['title'] == grupo &&
                        (evento['deviceGroup'] as List<dynamic>).join(',') ==
                            deviceName,
                  )
                  .isNotEmpty
              ? eventosCreados.firstWhere(
                  (evento) =>
                      evento['evento'] == 'riego' &&
                      evento['title'] == grupo &&
                      (evento['deviceGroup'] as List<dynamic>).join(',') ==
                          deviceName,
                )
              : null;

          // Detectar si es un evento de clima
          final eventoClima = eventosCreados
                  .where(
                    (evento) =>
                        evento['evento'] == 'clima' &&
                        evento['title'] == grupo &&
                        (evento['deviceGroup'] as List<dynamic>).join(',') ==
                            deviceName,
                  )
                  .isNotEmpty
              ? eventosCreados.firstWhere(
                  (evento) =>
                      evento['evento'] == 'clima' &&
                      evento['title'] == grupo &&
                      (evento['deviceGroup'] as List<dynamic>).join(',') ==
                          deviceName,
                )
              : null;

          // Detectar si es un evento de disparador
          final eventoDisparador = eventosCreados
                  .where(
                    (evento) =>
                        evento['evento'] == 'disparador' &&
                        evento['title'] == grupo &&
                        (evento['deviceGroup'] as List<dynamic>).join(',') ==
                            deviceName,
                  )
                  .isNotEmpty
              ? eventosCreados.firstWhere(
                  (evento) =>
                      evento['evento'] == 'disparador' &&
                      evento['title'] == grupo &&
                      (evento['deviceGroup'] as List<dynamic>).join(',') ==
                          deviceName,
                )
              : null;

          // Detectar si es un evento de horario
          final eventoHorario = eventosCreados
                  .where(
                    (evento) =>
                        evento['evento'] == 'horario' &&
                        evento['title'] == grupo &&
                        (evento['deviceGroup'] as List<dynamic>).join(',') ==
                            deviceName,
                  )
                  .isNotEmpty
              ? eventosCreados.firstWhere(
                  (evento) =>
                      evento['evento'] == 'horario' &&
                      evento['title'] == grupo &&
                      (evento['deviceGroup'] as List<dynamic>).join(',') ==
                          deviceName,
                )
              : null;

          if (eventoCadena != null) {
            try {
              // Verificar si todos los equipos de la cadena están online
              bool cadenaOnline =
                  isCadenaOnline(eventoCadena['deviceGroup'] as List<dynamic>);

              bool isRestricted =
                  _hasRestrictedDevicesInGroup(eventoCadena['deviceGroup']);

              return RepaintBoundary(
                key: ValueKey('cadena_$grupo'),
                child: Card(
                  color: color1,
                  margin:
                      const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                  elevation: 2,
                  child: Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16.0),
                      iconColor: color4,
                      collapsedIconColor: color4,
                      onExpansionChanged: (bool expanded) {
                        setState(() {
                          _expandedStates[deviceName] = expanded;
                        });
                      },
                      title: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: index,
                            child: const Icon(HugeIcons.strokeRoundedMenu01,
                                color: Colors.grey),
                          ),
                          const SizedBox(width: 8),
                          const Icon(HugeIcons.strokeRoundedLink01,
                              color: color4),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              grupo,
                              style: GoogleFonts.poppins(
                                color: color0,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: color0.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'CADENA',
                              style: GoogleFonts.poppins(
                                color: color0,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!cadenaOnline) ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.red.withValues(alpha: 0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        HugeIcons.strokeRoundedWifiOff02,
                                        color: Colors.red,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Todos los equipos deben estar conectados para activar la cadena',
                                          style: GoogleFonts.poppins(
                                            color: Colors.red,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],

                              // 🆕 BARRA DE PROGRESO Y ESTADO
                              Consumer(
                                builder: (context, ref, child) {
                                  final eventoEstado =
                                      ref.watch(eventosEstadoProvider)[
                                          'ControlPorCadena/$grupo'];

                                  if (eventoEstado != null &&
                                      (eventoEstado.isRunning ||
                                          eventoEstado.isPaused)) {
                                    return Column(
                                      children: [
                                        // Barra de progreso
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.blue
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: Colors.blue
                                                  .withValues(alpha: 0.3),
                                              width: 1,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(
                                                    eventoEstado.isPaused
                                                        ? HugeIcons
                                                            .strokeRoundedPauseCircle
                                                        : HugeIcons
                                                            .strokeRoundedPlayCircle,
                                                    color: eventoEstado.isPaused
                                                        ? Colors.orange
                                                        : Colors.blue,
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      eventoEstado.mensaje
                                                              .isNotEmpty
                                                          ? eventoEstado.mensaje
                                                          : eventoEstado
                                                                  .isPaused
                                                              ? 'Pausado'
                                                              : 'En ejecución',
                                                      style:
                                                          GoogleFonts.poppins(
                                                        color: color0,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    '${eventoEstado.progresoPortentaje.toStringAsFixed(0)}%',
                                                    style: GoogleFonts.poppins(
                                                      color: Colors.blue,
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                child: LinearProgressIndicator(
                                                  value: eventoEstado
                                                      .progresoDecimal,
                                                  minHeight: 8,
                                                  backgroundColor: Colors.grey
                                                      .withValues(alpha: 0.3),
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                          Color>(
                                                    eventoEstado.isPaused
                                                        ? Colors.orange
                                                        : Colors.blue,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                'Paso ${eventoEstado.pasoActual} de ${eventoEstado.totalPasos}',
                                                style: GoogleFonts.poppins(
                                                  color: color0.withValues(
                                                      alpha: 0.7),
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        // Botones de control
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            if (eventoEstado.isRunning) ...[
                                              ElevatedButton.icon(
                                                onPressed: () =>
                                                    pausarCadena(grupo),
                                                icon: const Icon(
                                                    HugeIcons
                                                        .strokeRoundedPause,
                                                    size: 18),
                                                label: Text(
                                                  'Pausar',
                                                  style: GoogleFonts.poppins(
                                                      fontSize: 13),
                                                ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      Colors.orange,
                                                  foregroundColor: color0,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 16,
                                                    vertical: 8,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                            ],
                                            if (eventoEstado.isPaused) ...[
                                              ElevatedButton.icon(
                                                onPressed: () =>
                                                    reanudarCadena(grupo),
                                                icon: const Icon(
                                                    HugeIcons.strokeRoundedPlay,
                                                    size: 18),
                                                label: Text(
                                                  'Reanudar',
                                                  style: GoogleFonts.poppins(
                                                      fontSize: 13),
                                                ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.green,
                                                  foregroundColor: color0,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 16,
                                                    vertical: 8,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                            ],
                                            ElevatedButton.icon(
                                              onPressed: () =>
                                                  cancelarCadena(grupo),
                                              icon: const Icon(
                                                  HugeIcons
                                                      .strokeRoundedCancel01,
                                                  size: 18),
                                              label: Text(
                                                'Cancelar',
                                                style: GoogleFonts.poppins(
                                                    fontSize: 13),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.red,
                                                foregroundColor: color0,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 8,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                      ],
                                    );
                                  }

                                  if (isRestricted) {
                                    return Column(
                                      children: [
                                        _buildNotOwnerWarning(),
                                        const SizedBox(height: 16),
                                      ],
                                    );
                                  }

                                  // Mostrar botón de iniciar solo si no está en ejecución
                                  final bool isExecuting =
                                      eventoEstado != null &&
                                          eventoEstado.isRunning;

                                  return Column(
                                    children: [
                                      Center(
                                        child: ElevatedButton.icon(
                                          onPressed:
                                              (cadenaOnline && !isExecuting)
                                                  ? () => controlarCadena(grupo)
                                                  : null,
                                          icon: isExecuting
                                              ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor:
                                                        AlwaysStoppedAnimation<
                                                            Color>(color0),
                                                  ),
                                                )
                                              : Icon(
                                                  HugeIcons.strokeRoundedPlay,
                                                  color: cadenaOnline
                                                      ? color0
                                                      : Colors.grey,
                                                  size: 20,
                                                ),
                                          label: Text(
                                            isExecuting
                                                ? 'Ejecutando Cadena...'
                                                : 'Activar Cadena',
                                            style: GoogleFonts.poppins(
                                              color:
                                                  (cadenaOnline || isExecuting)
                                                      ? color0
                                                      : Colors.grey,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                (cadenaOnline || isExecuting)
                                                    ? color4
                                                    : Colors.grey
                                                        .withValues(alpha: 0.3),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 24,
                                              vertical: 12,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            elevation:
                                                (cadenaOnline || isExecuting)
                                                    ? 3
                                                    : 0,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                  );
                                },
                              ),
                              Text(
                                'Pasos de la cadena:',
                                style: GoogleFonts.poppins(
                                  color: color0,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ...((eventoCadena['pasos'] ?? [])
                                      as List<dynamic>)
                                  .asMap()
                                  .entries
                                  .map((entry) {
                                final paso = entry.value;
                                final idx = entry.key + 1;

                                // Si paso es String, intentar parsearlo para compatibilidad
                                dynamic pasoProcessed = paso;
                                if (paso is String) {
                                  try {
                                    pasoProcessed = parseMapString(paso);
                                  } catch (e) {
                                    printLog.e(
                                        'Error parseando paso de cadena: $e');
                                    return const SizedBox.shrink();
                                  }
                                }

                                // Validar que los campos requeridos existan
                                if (pasoProcessed == null ||
                                    pasoProcessed['devices'] == null ||
                                    pasoProcessed['actions'] == null) {
                                  printLog.i(
                                      'Paso de cadena incompleto, saltando...');
                                  return const SizedBox.shrink();
                                }

                                final devices =
                                    pasoProcessed['devices'] as List<dynamic>;
                                if (pasoProcessed['actions'].runtimeType ==
                                    String) {
                                  pasoProcessed['actions'] =
                                      parseMapString(pasoProcessed['actions']);
                                }
                                final actions = pasoProcessed['actions'];
                                final stepDelay = pasoProcessed['stepDelay'];
                                final stepDelayUnit =
                                    pasoProcessed['stepDelayUnit'] as String? ??
                                        'seg';

                                // Formatear tiempo
                                String delayText = 'Instantáneo';
                                if (stepDelay != null) {
                                  if (stepDelay is Duration) {
                                    int totalSeconds = stepDelay.inSeconds;
                                    if (totalSeconds > 0) {
                                      int minutes = (totalSeconds / 60).floor();

                                      if (stepDelayUnit == 'min') {
                                        delayText =
                                            '$minutes ${minutes == 1 ? 'minuto' : 'minutos'}';
                                      } else {
                                        delayText =
                                            '$totalSeconds ${totalSeconds == 1 ? 'segundo' : 'segundos'}';
                                      }
                                    }
                                  }
                                }

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: color0.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: color4.withValues(alpha: 0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 24,
                                            height: 24,
                                            decoration: const BoxDecoration(
                                              color: color4,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Center(
                                              child: Text(
                                                '$idx',
                                                style: GoogleFonts.poppins(
                                                  color: color1,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Paso $idx',
                                            style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.bold,
                                              color: color4,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const Spacer(),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color:
                                                  color0.withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              delayText,
                                              style: GoogleFonts.poppins(
                                                color: color0,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      ...devices.map((device) {
                                        final deviceStr = device.toString();
                                        if (actions[deviceStr].runtimeType ==
                                            String) {
                                          actions[deviceStr] =
                                              actions[deviceStr] == 'true';
                                        }
                                        final action =
                                            actions[deviceStr] ?? false;

                                        // Formatear nombre del dispositivo igual que en grupos
                                        String displayName = '';
                                        if (deviceStr.contains('_')) {
                                          final parts = deviceStr.split('_');
                                          final String baseName = parts[0];
                                          final String idx = parts[1];
                                          final String dpc =
                                              DeviceManager.getProductCode(
                                                  baseName);
                                          final String dsn =
                                              DeviceManager.extractSerialNumber(
                                                  baseName);
                                          final Map<String, dynamic> dData =
                                              globalDATA['$dpc/$dsn'] ?? {};
                                          final bool hasEntry =
                                              dData['hasEntry'] ?? true;
                                          // Si no tiene entrada y es salida 0 → omitir sufijo
                                          if (idx == '0' && !hasEntry) {
                                            displayName =
                                                nicknamesMap[baseName] ??
                                                    baseName;
                                          } else {
                                            displayName = nicknamesMap[
                                                    deviceStr] ??
                                                '${nicknamesMap[baseName] ?? baseName} salida $idx';
                                          }
                                        } else {
                                          displayName =
                                              nicknamesMap[deviceStr] ??
                                                  deviceStr;
                                        }

                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 2),
                                          child: Row(
                                            children: [
                                              const SizedBox(width: 32),
                                              Expanded(
                                                child: Text(
                                                  displayName,
                                                  style: GoogleFonts.poppins(
                                                    color: color0,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: action
                                                      ? Colors.green.withValues(
                                                          alpha: 0.2)
                                                      : Colors.red.withValues(
                                                          alpha: 0.2),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  _isRollerDevice(deviceStr)
                                                      ? (action
                                                          ? 'ABRIR'
                                                          : 'CERRAR')
                                                      : (action ? 'ON' : 'OFF'),
                                                  style: GoogleFonts.poppins(
                                                    color: action
                                                        ? Colors.green
                                                        : Colors.red,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      })
                                    ],
                                  ),
                                );
                              }),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        HugeIcons.strokeRoundedPen01,
                                        color: color4,
                                      ),
                                      tooltip: 'Editar evento',
                                      onPressed: () async {
                                        final eventoAEditar =
                                            eventosCreados.firstWhere(
                                          (e) => e['title'] == grupo,
                                          orElse: () => <String, dynamic>{},
                                        );

                                        if (eventoAEditar.isNotEmpty) {
                                          final result =
                                              await Navigator.pushNamed(
                                            context,
                                            '/escenas',
                                            arguments: eventoAEditar,
                                          );
                                          if (result == true && mounted) {
                                            _buildDeviceListFromLoadedData();
                                          }
                                        }
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        HugeIcons.strokeRoundedDelete02,
                                        color: color0,
                                      ),
                                      tooltip: 'Eliminar evento de cadena',
                                      onPressed: () {
                                        showAlertDialog(
                                          context,
                                          false,
                                          const Text(
                                            '¿Eliminar este evento de cadena?',
                                            style: TextStyle(color: color0),
                                          ),
                                          const Text(
                                            'Esta acción no se puede deshacer.',
                                            style: TextStyle(color: color0),
                                          ),
                                          <Widget>[
                                            TextButton(
                                              style: ButtonStyle(
                                                foregroundColor:
                                                    WidgetStateProperty.all(
                                                        color0),
                                              ),
                                              child: const Text('Cancelar'),
                                              onPressed: () {
                                                Navigator.of(context).pop();
                                              },
                                            ),
                                            TextButton(
                                              style: ButtonStyle(
                                                foregroundColor:
                                                    WidgetStateProperty.all(
                                                        color0),
                                              ),
                                              child: const Text('Confirmar'),
                                              onPressed: () {
                                                setState(() {
                                                  eventosCreados.removeWhere(
                                                      (e) =>
                                                          e['title'] == grupo &&
                                                          e['evento'] ==
                                                              'cadena');
                                                  putEventos(currentUserEmail,
                                                      eventosCreados);
                                                  printLog.d(grupo,
                                                      color: 'naranja');
                                                  deleteEventoControlPorCadena(
                                                      currentUserEmail, grupo);
                                                  todosLosDispositivos
                                                      .removeWhere((entry) =>
                                                          entry.key == grupo);
                                                  savedOrder.removeWhere(
                                                      (item) =>
                                                          item['key'] == grupo);

                                                  _actualizarListasUI();
                                                });
                                                _saveOrder();
                                                Navigator.of(context).pop();
                                              },
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            } catch (e) {
              printLog.e('Error al procesar la cadena $grupo: $e');
              return RepaintBoundary(
                key: ValueKey('cadena_error_$grupo'),
                child: Card(
                  color: color1,
                  margin:
                      const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                  elevation: 2,
                  child: Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ListTile(
                      title: Text(
                        'Error al cargar la cadena $grupo',
                        style: GoogleFonts.poppins(
                          color: color0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        'Por favor, elimine el evento y vuelva a crearlo.',
                        style: GoogleFonts.poppins(
                          color: color0,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }
          }

          // Manejar evento de riego
          if (eventoRiego != null) {
            try {
              bool isRestricted =
                  _hasRestrictedDevicesInGroup(eventoRiego['deviceGroup']);

              // Verificar si el equipo creador del evento de riego está online
              String creatorDevice = eventoRiego['creator'] ?? '';
              String productCode = DeviceManager.getProductCode(creatorDevice);
              String serialNumber =
                  DeviceManager.extractSerialNumber(creatorDevice);

              Map<String, dynamic> deviceDATA =
                  globalDATA['$productCode/$serialNumber'] ?? {};
              bool riegoOnline = deviceDATA['cstate'] ?? false;

              List<String> allRiegoDevices = [creatorDevice];
              List<dynamic> rawExtensions = deviceDATA['riegoExtensions'] ?? [];
              List<String> sortedExtensions =
                  rawExtensions.map((e) => e.toString()).toList();
              sortedExtensions.sort();
              allRiegoDevices.addAll(sortedExtensions);

              Map<String, int> zonaMap = {};
              int globalZoneCounter = 1;

              for (String devName in allRiegoDevices) {
                String dPc = DeviceManager.getProductCode(devName);
                String dSn = DeviceManager.extractSerialNumber(devName);
                Map<String, dynamic> dData = globalDATA['$dPc/$dSn'] ?? {};

                List<String> ioKeys =
                    dData.keys.where((k) => k.startsWith('io')).toList();
                ioKeys.sort((a, b) {
                  int idxA = int.tryParse(a.substring(2)) ?? 0;
                  int idxB = int.tryParse(b.substring(2)) ?? 0;
                  return idxA.compareTo(idxB);
                });

                for (String key in ioKeys) {
                  if (devName == creatorDevice && key == 'io0') continue;

                  dynamic val = dData[key];
                  if (val is String) {
                    try {
                      var decoded = jsonDecode(val);
                      if (decoded['pinType'].toString() == '0') {
                        int ioIndex = int.parse(key.substring(2));
                        zonaMap['${devName}_$ioIndex'] = globalZoneCounter;
                        globalZoneCounter++;
                      }
                    } catch (e) {
                      continue;
                    }
                  }
                }
              }

              printLog.d(
                  'Mapa de zonas generado para evento ${eventoRiego['title']}: $zonaMap');

              return RepaintBoundary(
                key: ValueKey('riego_$grupo'),
                child: Card(
                  color: color1,
                  margin:
                      const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                  elevation: 2,
                  child: Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16.0),
                      iconColor: color4,
                      collapsedIconColor: color4,
                      onExpansionChanged: (bool expanded) {
                        setState(() {
                          _expandedStates[deviceName] = expanded;
                        });
                      },
                      title: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: index,
                            child: const Icon(HugeIcons.strokeRoundedMenu01,
                                color: Colors.grey),
                          ),
                          const SizedBox(width: 8),
                          const Icon(HugeIcons.strokeRoundedPlant03,
                              color: color4),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              grupo,
                              style: GoogleFonts.poppins(
                                color: color0,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: color0.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'RIEGO',
                              style: GoogleFonts.poppins(
                                color: color0,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!riegoOnline) ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.red.withValues(alpha: 0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        HugeIcons.strokeRoundedWifiOff02,
                                        color: Colors.red,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'El equipo de riego debe estar conectado para activar la rutina',
                                          style: GoogleFonts.poppins(
                                            color: Colors.red,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],

                              // 🆕 BARRA DE PROGRESO Y ESTADO
                              Consumer(
                                builder: (context, ref, child) {
                                  final eventoEstado =
                                      ref.watch(eventosEstadoProvider)[
                                          'ControlPorRiego/$grupo'];

                                  if (eventoEstado != null &&
                                      (eventoEstado.isRunning ||
                                          eventoEstado.isPaused)) {
                                    return Column(
                                      children: [
                                        // Barra de progreso
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.green
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: Colors.green
                                                  .withValues(alpha: 0.3),
                                              width: 1,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(
                                                    eventoEstado.isPaused
                                                        ? HugeIcons
                                                            .strokeRoundedPauseCircle
                                                        : HugeIcons
                                                            .strokeRoundedRainDrop,
                                                    color: eventoEstado.isPaused
                                                        ? Colors.orange
                                                        : Colors.green,
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      eventoEstado.mensaje
                                                              .isNotEmpty
                                                          ? eventoEstado.mensaje
                                                          : eventoEstado
                                                                  .isPaused
                                                              ? 'Pausado'
                                                              : 'Regando...',
                                                      style:
                                                          GoogleFonts.poppins(
                                                        color: color0,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    '${eventoEstado.progresoPortentaje.toStringAsFixed(0)}%',
                                                    style: GoogleFonts.poppins(
                                                      color: Colors.green,
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                child: LinearProgressIndicator(
                                                  value: eventoEstado
                                                      .progresoDecimal,
                                                  minHeight: 8,
                                                  backgroundColor: Colors.grey
                                                      .withValues(alpha: 0.3),
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                          Color>(
                                                    eventoEstado.isPaused
                                                        ? Colors.orange
                                                        : Colors.green,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                'Zona ${eventoEstado.pasoActual} de ${eventoEstado.totalPasos}',
                                                style: GoogleFonts.poppins(
                                                  color: color0.withValues(
                                                      alpha: 0.7),
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        // Botones de control
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            if (eventoEstado.isRunning) ...[
                                              ElevatedButton.icon(
                                                onPressed: () =>
                                                    pausarRiego(grupo),
                                                icon: const Icon(
                                                    HugeIcons
                                                        .strokeRoundedPause,
                                                    size: 18),
                                                label: Text(
                                                  'Pausar',
                                                  style: GoogleFonts.poppins(
                                                      fontSize: 13),
                                                ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      Colors.orange,
                                                  foregroundColor: color0,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 16,
                                                    vertical: 8,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                            ],
                                            if (eventoEstado.isPaused) ...[
                                              ElevatedButton.icon(
                                                onPressed: () =>
                                                    reanudarRiego(grupo),
                                                icon: const Icon(
                                                    HugeIcons.strokeRoundedPlay,
                                                    size: 18),
                                                label: Text(
                                                  'Reanudar',
                                                  style: GoogleFonts.poppins(
                                                      fontSize: 13),
                                                ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.green,
                                                  foregroundColor: color0,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 16,
                                                    vertical: 8,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                            ],
                                            ElevatedButton.icon(
                                              onPressed: () =>
                                                  cancelarRiego(grupo),
                                              icon: const Icon(
                                                  HugeIcons
                                                      .strokeRoundedCancel01,
                                                  size: 18),
                                              label: Text(
                                                'Cancelar',
                                                style: GoogleFonts.poppins(
                                                    fontSize: 13),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.red,
                                                foregroundColor: color0,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 8,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                      ],
                                    );
                                  }

                                  if (isRestricted) {
                                    return Column(
                                      children: [
                                        _buildNotOwnerWarning(),
                                        const SizedBox(height: 16),
                                      ],
                                    );
                                  }

                                  // Mostrar botón de iniciar solo si no está en ejecución
                                  final bool isExecuting =
                                      eventoEstado != null &&
                                          eventoEstado.isRunning;

                                  return Column(
                                    children: [
                                      Center(
                                        child: ElevatedButton.icon(
                                          onPressed:
                                              (riegoOnline && !isExecuting)
                                                  ? () => activarRutinaRiego(
                                                      eventoRiego)
                                                  : null,
                                          icon: isExecuting
                                              ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor:
                                                        AlwaysStoppedAnimation<
                                                            Color>(color0),
                                                  ),
                                                )
                                              : Icon(
                                                  HugeIcons.strokeRoundedPlay,
                                                  color: riegoOnline
                                                      ? color0
                                                      : Colors.grey,
                                                  size: 20,
                                                ),
                                          label: Text(
                                            isExecuting
                                                ? 'Ejecutando Rutina...'
                                                : 'Activar Rutina de Riego',
                                            style: GoogleFonts.poppins(
                                              color:
                                                  (riegoOnline || isExecuting)
                                                      ? color0
                                                      : Colors.grey,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                (riegoOnline || isExecuting)
                                                    ? color4
                                                    : Colors.grey
                                                        .withValues(alpha: 0.3),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 24,
                                              vertical: 12,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            elevation:
                                                (riegoOnline || isExecuting)
                                                    ? 3
                                                    : 0,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                  );
                                },
                              ),
                              Text(
                                'Zonas de riego:',
                                style: GoogleFonts.poppins(
                                  color: color0,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ...((eventoRiego['pasos'] ?? []) as List<dynamic>)
                                  .asMap()
                                  .entries
                                  .map((entry) {
                                final paso = entry.value;
                                final idx = entry.key;

                                if (paso == null || paso['device'] == null) {
                                  return const SizedBox.shrink();
                                }

                                final deviceString = paso['device'].toString();
                                final int minutes =
                                    paso['duration'] as int? ?? 5;
                                final int seconds =
                                    paso['duration_seg'] as int? ?? 0;

                                String displayName = '';
                                int zonaNumber = 0;

                                if (deviceString.contains('_')) {
                                  final parts = deviceString.split('_');
                                  String devName = parts[0];

                                  if (zonaMap.containsKey(deviceString)) {
                                    zonaNumber = zonaMap[deviceString]!;
                                  }

                                  displayName = nicknamesMap[deviceString] ??
                                      '${nicknamesMap[devName] ?? devName} Zona $zonaNumber';
                                } else {
                                  displayName = nicknamesMap[deviceString] ??
                                      deviceString;
                                }

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: color0.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: color4.withValues(alpha: 0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 70,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Container(
                                            width: 24,
                                            height: 24,
                                            decoration: const BoxDecoration(
                                              color: color4,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Center(
                                              child: Text(
                                                zonaNumber > 0
                                                    ? '$zonaNumber'
                                                    : '${idx + 1}',
                                                style: GoogleFonts.poppins(
                                                  color: color1,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          displayName,
                                          style: GoogleFonts.poppins(
                                            color: color0,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 70,
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.blue
                                                  .withValues(alpha: 0.2),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  '$minutes min',
                                                  style: GoogleFonts.poppins(
                                                    color: Colors.blue,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                if (seconds > 0)
                                                  Text(
                                                    '$seconds seg',
                                                    style: GoogleFonts.poppins(
                                                      color: Colors.blue,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              Align(
                                alignment: Alignment.centerRight,
                                child: IconButton(
                                  icon: const Icon(
                                    HugeIcons.strokeRoundedDelete02,
                                    color: color0,
                                  ),
                                  tooltip: 'Eliminar rutina de riego',
                                  onPressed: () {
                                    printLog.d('sexoooooooo $grupo');
                                    showAlertDialog(
                                      context,
                                      false,
                                      const Text(
                                        '¿Eliminar esta rutina de riego?',
                                        style: TextStyle(color: color0),
                                      ),
                                      const Text(
                                        'Esta acción no se puede deshacer.',
                                        style: TextStyle(color: color0),
                                      ),
                                      <Widget>[
                                        TextButton(
                                          style: ButtonStyle(
                                            foregroundColor:
                                                WidgetStateProperty.all(color0),
                                          ),
                                          child: const Text('Cancelar'),
                                          onPressed: () {
                                            Navigator.of(context).pop();
                                          },
                                        ),
                                        TextButton(
                                          style: ButtonStyle(
                                            foregroundColor:
                                                WidgetStateProperty.all(color0),
                                          ),
                                          child: const Text('Confirmar'),
                                          onPressed: () {
                                            setState(() {
                                              eventosCreados.removeWhere(
                                                  (evento) =>
                                                      evento['title'] ==
                                                          grupo &&
                                                      evento['evento'] ==
                                                          'riego');

                                              putEventos(currentUserEmail,
                                                  eventosCreados);
                                              deleteEventoControlDeRiego(
                                                  currentUserEmail, grupo);

                                              todosLosDispositivos.removeWhere(
                                                  (entry) =>
                                                      entry.key == grupo);

                                              savedOrder.removeWhere((item) =>
                                                  item['key'] == grupo);

                                              _actualizarListasUI();
                                            });
                                            _saveOrder();
                                            Navigator.of(context).pop();
                                            showToast('Rutina eliminada');
                                          },
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            } catch (e) {
              printLog.e('Error al procesar el evento de riego $grupo: $e');
              return RepaintBoundary(
                key: ValueKey('riego_error_$grupo'),
                child: Card(
                  color: color1,
                  margin:
                      const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                  elevation: 2,
                  child: Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ListTile(
                      title: Text(
                        'Error al cargar el evento de riego $grupo',
                        style: GoogleFonts.poppins(
                          color: color0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        'Por favor, elimine el evento y vuelva a crearlo.',
                        style: GoogleFonts.poppins(
                          color: color0,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }
          }

          // Manejar evento de clima
          if (eventoClima != null) {
            try {
              bool isRestricted =
                  _hasRestrictedDevicesInGroup(eventoClima['deviceGroup']);

              bool isEnabled = eventoClima['enabled'] ?? true;
              String condition = eventoClima['condition'] ?? '';

              Map<String, dynamic> devicesActions =
                  Map<String, dynamic>.from(eventoClima['deviceActions'] ?? {});

              String? windDirection = eventoClima['wind_direction'];

              String devicesInGroup = deviceName;
              List<String> deviceList = devicesInGroup
                  .replaceAll('[', '')
                  .replaceAll(']', '')
                  .split(',');
              List<String> climaNicksList = [];
              for (String equipo in deviceList) {
                String displayName = '';
                if (equipo.contains('_')) {
                  final parts = equipo.split('_');
                  String baseName = parts[0];
                  String index = parts[1];

                  String pc = DeviceManager.getProductCode(baseName);
                  String sn = DeviceManager.extractSerialNumber(baseName);
                  Map<String, dynamic> devData = globalDATA['$pc/$sn'] ?? {};

                  bool hasEntry = devData['hasEntry'] ?? true;

                  if (index == '0' && !hasEntry) {
                    displayName = nicknamesMap[baseName] ?? baseName;
                  } else {
                    displayName = nicknamesMap[equipo.trim()] ??
                        '${nicknamesMap[baseName] ?? baseName} salida $index';
                  }
                } else {
                  displayName = nicknamesMap[equipo.trim()] ?? equipo.trim();
                }
                climaNicksList.add(displayName);
              }

              IconData climaIcon;
              switch (condition) {
                case 'Lluvia':
                  climaIcon = HugeIcons.strokeRoundedCloudAngledRain;
                  break;
                case 'Nublado':
                  climaIcon = HugeIcons.strokeRoundedSunCloud02;
                  break;
                case 'Viento Fuerte':
                  climaIcon = HugeIcons.strokeRoundedFastWind;
                  break;
                case 'Soleado':
                  climaIcon = HugeIcons.strokeRoundedSun03;
                  break;
                default:
                  climaIcon = HugeIcons.strokeRoundedCloudSnow;
              }

              return RepaintBoundary(
                key: ValueKey('clima_$grupo'),
                child: Card(
                  color: isEnabled ? color1 : color1.withValues(alpha: 0.8),
                  margin:
                      const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                  elevation: 2,
                  child: Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16.0),
                      iconColor: isEnabled ? color4 : Colors.grey,
                      collapsedIconColor: isEnabled ? color4 : Colors.grey,
                      onExpansionChanged: (bool expanded) {
                        setState(() {
                          _expandedStates[deviceName] = expanded;
                        });
                      },
                      title: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: index,
                            child: const Icon(HugeIcons.strokeRoundedMenu01,
                                color: Colors.grey),
                          ),
                          const SizedBox(width: 8),
                          Icon(HugeIcons.strokeRoundedCloudAngledRainZap,
                              color: isEnabled ? color4 : Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              grupo,
                              style: GoogleFonts.poppins(
                                color: isEnabled
                                    ? color0
                                    : color0.withValues(alpha: 0.6),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                decoration: isEnabled
                                    ? TextDecoration.none
                                    : TextDecoration.lineThrough,
                                decorationColor: color4,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isEnabled
                                  ? color0.withValues(alpha: 0.2)
                                  : Colors.grey.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isEnabled ? 'CLIMA' : 'INACTIVO',
                              style: GoogleFonts.poppins(
                                color: isEnabled ? color0 : Colors.grey,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(climaIcon,
                                      color: isEnabled ? color4 : Colors.grey,
                                      size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Condición',
                                          style: GoogleFonts.poppins(
                                            color:
                                                color0.withValues(alpha: 0.7),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          (windDirection != null &&
                                                  windDirection.isNotEmpty)
                                              ? '$condition con origen $windDirection'
                                              : condition,
                                          style: GoogleFonts.poppins(
                                            color: isEnabled
                                                ? color0
                                                : color0.withValues(alpha: 0.5),
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Dispositivos afectados:',
                                style: GoogleFonts.poppins(
                                  color: isEnabled
                                      ? color0
                                      : color0.withValues(alpha: 0.5),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ...climaNicksList.asMap().entries.map((entry) {
                                final idx = entry.key + 1;
                                String deviceNick = entry.value;
                                final equipo = deviceList[entry.key].trim();

                                bool isEvento = false;
                                bool isCadena = false;
                                bool isRiego = false;
                                bool isGrupo = false;

                                final eventoEncontrado =
                                    eventosCreados.firstWhere(
                                  (evento) => evento['title'] == equipo,
                                  orElse: () => <String, dynamic>{},
                                );

                                if (eventoEncontrado.isNotEmpty) {
                                  final eventoType =
                                      eventoEncontrado['evento'] as String;
                                  deviceNick = equipo;
                                  isEvento = true;
                                  isCadena = eventoType == 'cadena';
                                  isRiego = eventoType == 'riego';
                                  isGrupo = eventoType == 'grupo';
                                }

                                String actionText = '';
                                IconData actionIcon =
                                    HugeIcons.strokeRoundedSettings02;
                                Color actionColor = color0;

                                if (isEvento) {
                                  if (isCadena) {
                                    actionText = 'Se ejecutará';
                                    actionIcon =
                                        HugeIcons.strokeRoundedPlayCircle;
                                    actionColor = Colors.orange;
                                  } else if (isRiego) {
                                    actionText = 'Se ejecutará';
                                    actionIcon = HugeIcons.strokeRoundedLeaf01;
                                    actionColor = Colors.blue;
                                  } else if (isGrupo) {
                                    final action =
                                        devicesActions['$equipo:grupo'] ??
                                            false;
                                    actionText =
                                        action ? "Encenderá" : "Apagará";
                                    actionIcon = (action
                                        ? HugeIcons.strokeRoundedPlug01
                                        : HugeIcons.strokeRoundedPlugSocket);
                                    actionColor =
                                        action ? Colors.green : Colors.red;
                                  } else {
                                    actionText = 'Se ejecutará';
                                    actionIcon =
                                        HugeIcons.strokeRoundedSettings02;
                                    actionColor = color4;
                                  }
                                } else {
                                  final action =
                                      devicesActions[equipo] ?? false;
                                  final bool isRollerEquipo = _isRollerDevice(
                                      equipo.trim().contains('_')
                                          ? equipo.trim().split('_')[0]
                                          : equipo.trim());
                                  actionText = isRollerEquipo
                                      ? (action ? "Abrirá" : "Cerrará")
                                      : (action ? "Encenderá" : "Apagará");
                                  actionIcon = (action
                                      ? HugeIcons.strokeRoundedPlug01
                                      : HugeIcons.strokeRoundedPlugSocket);
                                  actionColor =
                                      action ? Colors.green : Colors.red;
                                }

                                if (!isEnabled) {
                                  actionColor =
                                      actionColor.withValues(alpha: 0.4);
                                }

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: isEnabled
                                              ? color4
                                              : Colors.grey
                                                  .withValues(alpha: 0.3),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            '$idx',
                                            style: GoogleFonts.poppins(
                                              color: color1,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          deviceNick,
                                          style: GoogleFonts.poppins(
                                            color: isEnabled
                                                ? color0
                                                : color0.withValues(alpha: 0.5),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        actionIcon,
                                        color: actionColor,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        actionText,
                                        style: GoogleFonts.poppins(
                                          color: actionColor,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              const SizedBox(height: 10),
                              if (isRestricted) ...{
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(child: _buildNotOwnerWarning()),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // ✏️ Botón de Editar para Administrador Restringido
                                        IconButton(
                                          icon: const Icon(
                                            HugeIcons.strokeRoundedPen01,
                                            color: color4,
                                          ),
                                          tooltip: 'Editar evento',
                                          onPressed: () async {
                                            final eventoAEditar =
                                                eventosCreados.firstWhere(
                                              (e) => e['title'] == grupo,
                                              orElse: () => <String, dynamic>{},
                                            );

                                            if (eventoAEditar.isNotEmpty) {
                                              final result =
                                                  await Navigator.pushNamed(
                                                context,
                                                '/escenas',
                                                arguments: eventoAEditar,
                                              );
                                              if (result == true && mounted) {
                                                _buildDeviceListFromLoadedData();
                                              }
                                            }
                                          },
                                        ),
                                        // 🗑️ Botón de Eliminar original
                                        IconButton(
                                          icon: const Icon(
                                            HugeIcons.strokeRoundedDelete02,
                                            color: color0,
                                            size: 24,
                                          ),
                                          onPressed: () {
                                            showAlertDialog(
                                              context,
                                              false,
                                              const Text(
                                                '¿Eliminar este evento clima?',
                                                style: TextStyle(color: color0),
                                              ),
                                              const Text(
                                                'Esta acción no se puede deshacer.',
                                                style: TextStyle(color: color0),
                                              ),
                                              <Widget>[
                                                TextButton(
                                                  style: ButtonStyle(
                                                    foregroundColor:
                                                        WidgetStateProperty.all(
                                                            color0),
                                                  ),
                                                  child: const Text('Cancelar'),
                                                  onPressed: () =>
                                                      Navigator.of(context)
                                                          .pop(),
                                                ),
                                                TextButton(
                                                  style: ButtonStyle(
                                                    foregroundColor:
                                                        WidgetStateProperty.all(
                                                            color0),
                                                  ),
                                                  child:
                                                      const Text('Confirmar'),
                                                  onPressed: () {
                                                    setState(() {
                                                      eventosCreados
                                                          .removeWhere((e) =>
                                                              e['title'] ==
                                                                  grupo &&
                                                              e['evento'] ==
                                                                  'clima');
                                                      putEventos(
                                                          currentUserEmail,
                                                          eventosCreados);
                                                      deleteEventoControlPorClima(
                                                          currentUserEmail,
                                                          grupo);
                                                      todosLosDispositivos
                                                          .removeWhere(
                                                              (entry) =>
                                                                  entry.key ==
                                                                  grupo);
                                                      savedOrder.removeWhere(
                                                          (item) =>
                                                              item['key'] ==
                                                              grupo);
                                                      _actualizarListasUI();
                                                    });
                                                    _saveOrder();
                                                    Navigator.of(context).pop();
                                                  },
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                )
                              } else ...{
                                Row(
                                  children: [
                                    Switch(
                                      value: isEnabled,
                                      activeThumbColor: Colors.green,
                                      activeTrackColor:
                                          Colors.green.withValues(alpha: 0.3),
                                      inactiveThumbColor: Colors.grey,
                                      inactiveTrackColor:
                                          Colors.grey.withValues(alpha: 0.3),
                                      onChanged: (val) =>
                                          _toggleEventEnabled(eventoClima, val),
                                    ),
                                    Text(
                                      isEnabled ? 'Habilitado' : 'Inhabilitado',
                                      style: GoogleFonts.poppins(
                                        color: isEnabled
                                            ? color0
                                            : color0.withValues(alpha: 0.6),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Spacer(),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // ✏️ Botón de Editar para el Dueño
                                        IconButton(
                                          icon: const Icon(
                                            HugeIcons.strokeRoundedPen01,
                                            color: color4,
                                          ),
                                          tooltip: 'Editar evento',
                                          onPressed: () async {
                                            final eventoAEditar =
                                                eventosCreados.firstWhere(
                                              (e) => e['title'] == grupo,
                                              orElse: () => <String, dynamic>{},
                                            );

                                            if (eventoAEditar.isNotEmpty) {
                                              final result =
                                                  await Navigator.pushNamed(
                                                context,
                                                '/escenas',
                                                arguments: eventoAEditar,
                                              );
                                              if (result == true && mounted) {
                                                _buildDeviceListFromLoadedData();
                                              }
                                            }
                                          },
                                        ),
                                        // 🗑️ Botón de Eliminar original
                                        IconButton(
                                          onPressed: () {
                                            showAlertDialog(
                                              context,
                                              false,
                                              const Text(
                                                '¿Eliminar este evento clima?',
                                                style: TextStyle(color: color0),
                                              ),
                                              const Text(
                                                'Esta acción no se puede deshacer.',
                                                style: TextStyle(color: color0),
                                              ),
                                              <Widget>[
                                                TextButton(
                                                  style: ButtonStyle(
                                                    foregroundColor:
                                                        WidgetStateProperty.all(
                                                            color0),
                                                  ),
                                                  child: const Text('Cancelar'),
                                                  onPressed: () {
                                                    Navigator.of(context).pop();
                                                  },
                                                ),
                                                TextButton(
                                                  style: ButtonStyle(
                                                    foregroundColor:
                                                        WidgetStateProperty.all(
                                                            color0),
                                                  ),
                                                  child:
                                                      const Text('Confirmar'),
                                                  onPressed: () {
                                                    setState(() {
                                                      eventosCreados
                                                          .removeWhere((e) =>
                                                              e['title'] ==
                                                                  grupo &&
                                                              e['evento'] ==
                                                                  'clima');
                                                      putEventos(
                                                          currentUserEmail,
                                                          eventosCreados);
                                                      printLog.d(grupo,
                                                          color: 'naranja');
                                                      deleteEventoControlPorClima(
                                                          currentUserEmail,
                                                          grupo);
                                                      todosLosDispositivos
                                                          .removeWhere(
                                                              (entry) =>
                                                                  entry.key ==
                                                                  grupo);
                                                      savedOrder.removeWhere(
                                                          (item) =>
                                                              item['key'] ==
                                                              grupo);

                                                      _actualizarListasUI();
                                                    });
                                                    _saveOrder();
                                                    Navigator.of(context).pop();
                                                  },
                                                ),
                                              ],
                                            );
                                          },
                                          icon: const Icon(
                                            HugeIcons.strokeRoundedDelete02,
                                            color: Colors.redAccent,
                                            size: 20,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              }
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            } catch (e) {
              printLog.e('Error al procesar el evento de clima $grupo: $e');
              return RepaintBoundary(
                key: ValueKey('clima_error_$grupo'),
                child: Card(
                  color: color1,
                  margin:
                      const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                  elevation: 2,
                  child: Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ListTile(
                      title: Text(
                        'Error al cargar el evento de clima $grupo',
                        style: GoogleFonts.poppins(
                          color: color0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        'Por favor, elimine el evento y vuelva a crearlo.',
                        style: GoogleFonts.poppins(
                          color: color0,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }
          }

          // Manejar evento de disparador
          if (eventoDisparador != null) {
            try {
              bool isRestricted =
                  _hasRestrictedDevicesInGroup(eventoDisparador['deviceGroup']);

              bool isEnabled = eventoDisparador['enabled'] ?? true;
              List<dynamic> deviceGroup = eventoDisparador['deviceGroup'] ?? [];

              Map<String, dynamic> devicesActions = Map<String, dynamic>.from(
                  eventoDisparador['deviceActions'] ?? {});

              String devicesInGroup = deviceName;
              List<String> deviceList = devicesInGroup
                  .replaceAll('[', '')
                  .replaceAll(']', '')
                  .split(',');
              List<String> disparadorNicksList = [];
              for (String equipo in deviceList) {
                String displayName = '';
                if (equipo.contains('_')) {
                  final parts = equipo.split('_');
                  String baseName = parts[0];
                  String index = parts[1];

                  String pc = DeviceManager.getProductCode(baseName);
                  String sn = DeviceManager.extractSerialNumber(baseName);
                  Map<String, dynamic> devData = globalDATA['$pc/$sn'] ?? {};

                  // 2. Verificamos hasEntry
                  bool hasEntry = devData['hasEntry'] ?? true;

                  if (index == '0' && !hasEntry) {
                    displayName = nicknamesMap[baseName] ?? baseName;
                  } else {
                    displayName = nicknamesMap[equipo.trim()] ??
                        '${nicknamesMap[baseName] ?? baseName} salida $index';
                  }
                } else {
                  displayName = nicknamesMap[equipo.trim()] ?? equipo.trim();
                }
                disparadorNicksList.add(displayName);
              }

              String activador = disparadorNicksList.isNotEmpty
                  ? disparadorNicksList.first
                  : '';
              List<String> ejecutores = disparadorNicksList.length > 1
                  ? disparadorNicksList.sublist(1)
                  : [];

              bool isTermometro = deviceGroup.isNotEmpty &&
                  deviceGroup.first.toString().contains('Termometro');

              String? estadoAlerta =
                  eventoDisparador['estadoAlerta']?.toString();
              String? estadoTermometro =
                  eventoDisparador['estadoTermometro']?.toString();

              return RepaintBoundary(
                  key: ValueKey('disparador_$grupo'),
                  child: Card(
                    color: isEnabled ? color1 : color1.withValues(alpha: 0.8),
                    margin:
                        const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                    elevation: 2,
                    child: Theme(
                      data: Theme.of(context)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding:
                            const EdgeInsets.symmetric(horizontal: 16.0),
                        iconColor: isEnabled ? color4 : Colors.grey,
                        collapsedIconColor: isEnabled ? color4 : Colors.grey,
                        onExpansionChanged: (bool expanded) {
                          setState(() {
                            _expandedStates[deviceName] = expanded;
                          });
                        },
                        title: Row(
                          children: [
                            ReorderableDragStartListener(
                              index: index,
                              child: const Icon(HugeIcons.strokeRoundedMenu01,
                                  color: Colors.grey),
                            ),
                            const SizedBox(width: 8),
                            Icon(HugeIcons.strokeRoundedPlayCircle,
                                color: isEnabled ? color4 : Colors.grey),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                grupo,
                                style: GoogleFonts.poppins(
                                  color: isEnabled
                                      ? color0
                                      : color0.withValues(alpha: 0.6),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  decoration: isEnabled
                                      ? TextDecoration.none
                                      : TextDecoration.lineThrough,
                                  decorationColor: color4,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isEnabled
                                    ? color0.withValues(alpha: 0.2)
                                    : Colors.grey.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isEnabled ? 'DISPARADOR' : 'INACTIVO',
                                style: GoogleFonts.poppins(
                                  color: isEnabled ? color0 : Colors.grey,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(HugeIcons.strokeRoundedTap05,
                                        color: isEnabled ? color4 : Colors.grey,
                                        size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      'ACTIVADOR',
                                      style: GoogleFonts.poppins(
                                        color: isEnabled ? color4 : Colors.grey,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (activador.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isTermometro
                                              ? HugeIcons
                                                  .strokeRoundedTemperature
                                              : HugeIcons.strokeRoundedAlert02,
                                          color: isEnabled
                                              ? color4
                                              : Colors.grey
                                                  .withValues(alpha: 0.5),
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            activador,
                                            style: GoogleFonts.poppins(
                                              color: isEnabled
                                                  ? color0
                                                  : color0.withValues(
                                                      alpha: 0.5),
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                if (estadoAlerta != null)
                                  Card(
                                    color: Colors.transparent,
                                    elevation: 0,
                                    margin: const EdgeInsets.only(bottom: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: BorderSide(
                                        color: isEnabled
                                            ? (estadoAlerta == "1"
                                                    ? Colors.orange
                                                    : Colors.blueGrey)
                                                .withValues(alpha: 0.3)
                                            : Colors.grey
                                                .withValues(alpha: 0.2),
                                        width: 1,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            estadoAlerta == "1"
                                                ? HugeIcons.strokeRoundedAlert02
                                                : HugeIcons
                                                    .strokeRoundedCheckmarkCircle02,
                                            color: isEnabled
                                                ? (estadoAlerta == "1"
                                                    ? Colors.orange
                                                    : Colors.blueGrey)
                                                : Colors.grey,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text.rich(
                                              TextSpan(
                                                children: [
                                                  const TextSpan(
                                                      text:
                                                          "El evento se accionará cuando el activador esté en "),
                                                  TextSpan(
                                                    text: estadoAlerta == "1"
                                                        ? "ALERTA"
                                                        : "REPOSO",
                                                    style: GoogleFonts.poppins(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: isEnabled
                                                          ? (estadoAlerta == "1"
                                                              ? Colors.orange
                                                              : Colors.blueGrey)
                                                          : Colors.grey,
                                                      letterSpacing: 0.5,
                                                    ),
                                                  ),
                                                  const TextSpan(text: "."),
                                                ],
                                              ),
                                              style: GoogleFonts.poppins(
                                                fontSize: 13,
                                                color: isEnabled
                                                    ? color0.withValues(
                                                        alpha: 0.85)
                                                    : color0.withValues(
                                                        alpha: 0.5),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (isTermometro && estadoTermometro != null)
                                  Card(
                                    color: Colors.transparent,
                                    elevation: 0,
                                    margin: const EdgeInsets.only(bottom: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: BorderSide(
                                        color: isEnabled
                                            ? (estadoTermometro == "1"
                                                    ? Colors.red
                                                    : Colors.lightBlue)
                                                .withValues(alpha: 0.3)
                                            : Colors.grey
                                                .withValues(alpha: 0.2),
                                        width: 1,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          ImageIcon(
                                            const AssetImage(
                                                CaldenIcons.termometro),
                                            color: isEnabled
                                                ? (estadoTermometro == "1"
                                                    ? Colors.red
                                                    : Colors.lightBlue)
                                                : Colors.grey,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text.rich(
                                              TextSpan(
                                                children: [
                                                  const TextSpan(
                                                      text:
                                                          "Condición usada: Temperatura "),
                                                  TextSpan(
                                                    text:
                                                        estadoTermometro == "1"
                                                            ? "MÁXIMA"
                                                            : "MÍNIMA",
                                                    style: GoogleFonts.poppins(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: isEnabled
                                                          ? (estadoTermometro ==
                                                                  "1"
                                                              ? Colors.red
                                                              : Colors
                                                                  .lightBlue)
                                                          : Colors.grey,
                                                      letterSpacing: 0.5,
                                                    ),
                                                  ),
                                                  const TextSpan(
                                                      text: " del termómetro."),
                                                ],
                                              ),
                                              style: GoogleFonts.poppins(
                                                fontSize: 13,
                                                color: isEnabled
                                                    ? color0.withValues(
                                                        alpha: 0.85)
                                                    : color0.withValues(
                                                        alpha: 0.5),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 16),
                                if (ejecutores.isNotEmpty) ...[
                                  Row(
                                    children: [
                                      Icon(HugeIcons.strokeRoundedSettings02,
                                          color:
                                              isEnabled ? color4 : Colors.grey,
                                          size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        'EJECUTORES',
                                        style: GoogleFonts.poppins(
                                          color:
                                              isEnabled ? color4 : Colors.grey,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  ...ejecutores.asMap().entries.map((entry) {
                                    final idx = entry.key + 1;
                                    String ejecutorName = entry.value;
                                    final equipoOriginal =
                                        deviceList[entry.key + 1].trim();

                                    bool isEvento = false;
                                    bool isCadena = false;
                                    bool isRiego = false;
                                    bool isGrupo = false;

                                    final eventoEncontrado =
                                        eventosCreados.firstWhere(
                                      (evento) =>
                                          evento['title'] == equipoOriginal,
                                      orElse: () => <String, dynamic>{},
                                    );

                                    if (eventoEncontrado.isNotEmpty) {
                                      final eventoType =
                                          eventoEncontrado['evento'] as String;
                                      ejecutorName = equipoOriginal;
                                      isEvento = true;
                                      isCadena = eventoType == 'cadena';
                                      isRiego = eventoType == 'riego';
                                      isGrupo = eventoType == 'grupo';
                                    }

                                    String actionText = '';
                                    String fullActionText = '';
                                    IconData actionIcon =
                                        HugeIcons.strokeRoundedSettings02;
                                    Color actionColor = color0;

                                    if (isEvento) {
                                      if (isCadena) {
                                        actionText = 'ejecutará';
                                        fullActionText = 'Se ejecutará';
                                        actionIcon =
                                            HugeIcons.strokeRoundedPlayCircle;
                                        actionColor = Colors.orange;
                                      } else if (isRiego) {
                                        actionText = 'ejecutará';
                                        fullActionText = 'Se ejecutará';
                                        actionIcon =
                                            HugeIcons.strokeRoundedLeaf01;
                                        actionColor = Colors.blue;
                                      } else if (isGrupo) {
                                        final action = devicesActions[
                                                '$equipoOriginal:grupo'] ??
                                            false;
                                        actionText =
                                            action ? "Encenderá" : "Apagará";
                                        fullActionText = 'Se $actionText';
                                        actionIcon = (action
                                            ? HugeIcons.strokeRoundedPlug01
                                            : HugeIcons
                                                .strokeRoundedPlugSocket);
                                        actionColor =
                                            action ? Colors.green : Colors.red;
                                      } else {
                                        actionText = 'ejecutará';
                                        fullActionText = 'Se ejecutará';
                                        actionIcon =
                                            HugeIcons.strokeRoundedSettings02;
                                        actionColor = color4;
                                      }
                                    } else {
                                      final action =
                                          devicesActions[equipoOriginal] ??
                                              false;
                                      final bool isRollerEquipo =
                                          _isRollerDevice(equipoOriginal
                                                  .trim()
                                                  .contains('_')
                                              ? equipoOriginal
                                                  .trim()
                                                  .split('_')[0]
                                              : equipoOriginal.trim());
                                      actionText = isRollerEquipo
                                          ? (action ? "Abrirá" : "Cerrará")
                                          : (action ? "Encenderá" : "Apagará");
                                      fullActionText = 'Se $actionText';
                                      actionIcon = (action
                                          ? HugeIcons.strokeRoundedPlug01
                                          : HugeIcons.strokeRoundedPlugSocket);
                                      actionColor =
                                          action ? Colors.green : color4;
                                    }

                                    if (!isEnabled) {
                                      actionColor =
                                          actionColor.withValues(alpha: 0.4);
                                    }

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color:
                                            actionColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: actionColor.withValues(
                                              alpha: 0.3),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 24,
                                            height: 24,
                                            decoration: BoxDecoration(
                                              color: isEnabled
                                                  ? color4
                                                  : Colors.grey
                                                      .withValues(alpha: 0.3),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Center(
                                              child: Text(
                                                '$idx',
                                                style: GoogleFonts.poppins(
                                                  color: color1,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  ejecutorName,
                                                  style: GoogleFonts.poppins(
                                                    color: isEnabled
                                                        ? color0
                                                        : color0.withValues(
                                                            alpha: 0.5),
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Icon(
                                                      actionIcon,
                                                      color: actionColor,
                                                      size: 14,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      fullActionText,
                                                      style:
                                                          GoogleFonts.poppins(
                                                        color: actionColor,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(
                                            actionIcon,
                                            color: actionColor,
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                  const SizedBox(height: 10),
                                  const Divider(color: Colors.white24),
                                  if (isRestricted) ...[
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                            child: _buildNotOwnerWarning()),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // ✏️ Botón de Editar para Administrador Restringido
                                            IconButton(
                                              icon: const Icon(
                                                HugeIcons.strokeRoundedPen01,
                                                color: Colors.blueAccent,
                                              ),
                                              tooltip: 'Editar evento',
                                              onPressed: () async {
                                                final eventoAEditar =
                                                    eventosCreados.firstWhere(
                                                  (e) => e['title'] == grupo,
                                                  orElse: () =>
                                                      <String, dynamic>{},
                                                );

                                                if (eventoAEditar.isNotEmpty) {
                                                  final result =
                                                      await Navigator.pushNamed(
                                                    context,
                                                    '/escenas',
                                                    arguments: eventoAEditar,
                                                  );
                                                  if (result == true &&
                                                      mounted) {
                                                    _buildDeviceListFromLoadedData();
                                                  }
                                                }
                                              },
                                            ),
                                            // 🗑️ Botón de Eliminar original
                                            IconButton(
                                              icon: const Icon(
                                                HugeIcons.strokeRoundedDelete02,
                                                color: color0,
                                                size: 24,
                                              ),
                                              onPressed: () {
                                                showAlertDialog(
                                                  context,
                                                  false,
                                                  const Text(
                                                    '¿Eliminar este disparador?',
                                                    style: TextStyle(
                                                        color: color0),
                                                  ),
                                                  const Text(
                                                    'Esta acción no se puede deshacer.',
                                                    style: TextStyle(
                                                        color: color0),
                                                  ),
                                                  <Widget>[
                                                    TextButton(
                                                      style: ButtonStyle(
                                                        foregroundColor:
                                                            WidgetStateProperty
                                                                .all(color0),
                                                      ),
                                                      child: const Text(
                                                          'Cancelar'),
                                                      onPressed: () =>
                                                          Navigator.of(context)
                                                              .pop(),
                                                    ),
                                                    TextButton(
                                                      style: ButtonStyle(
                                                        foregroundColor:
                                                            WidgetStateProperty
                                                                .all(color0),
                                                      ),
                                                      child: const Text(
                                                          'Confirmar'),
                                                      onPressed: () {
                                                        setState(() {
                                                          eventosCreados
                                                              .removeWhere((e) =>
                                                                  e['title'] ==
                                                                      grupo &&
                                                                  e['evento'] ==
                                                                      'disparador');
                                                          putEventos(
                                                              currentUserEmail,
                                                              eventosCreados);
                                                          deleteEventoControlPorDisparadores(
                                                              activador,
                                                              currentUserEmail,
                                                              grupo);
                                                          todosLosDispositivos
                                                              .removeWhere(
                                                                  (entry) =>
                                                                      entry
                                                                          .key ==
                                                                      grupo);
                                                          savedOrder.removeWhere(
                                                              (item) =>
                                                                  item['key'] ==
                                                                  grupo);
                                                          _actualizarListasUI();
                                                        });
                                                        _saveOrder();
                                                        Navigator.of(context)
                                                            .pop();
                                                      },
                                                    ),
                                                  ],
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                    )
                                  ] else ...[
                                    Row(
                                      children: [
                                        Switch(
                                          value: isEnabled,
                                          activeThumbColor: Colors.green,
                                          activeTrackColor: Colors.green
                                              .withValues(alpha: 0.3),
                                          inactiveThumbColor: Colors.grey,
                                          inactiveTrackColor: Colors.grey
                                              .withValues(alpha: 0.3),
                                          onChanged: (val) =>
                                              _toggleEventEnabled(
                                                  eventoDisparador, val),
                                        ),
                                        Text(
                                          isEnabled
                                              ? 'Habilitado'
                                              : 'Inhabilitado',
                                          style: GoogleFonts.poppins(
                                            color: isEnabled
                                                ? color0
                                                : color0.withValues(alpha: 0.6),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const Spacer(),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // ✏️ Botón de Editar para el Dueño
                                            IconButton(
                                              icon: const Icon(
                                                HugeIcons.strokeRoundedPen01,
                                                color: color4,
                                              ),
                                              tooltip: 'Editar evento',
                                              onPressed: () async {
                                                final eventoAEditar =
                                                    eventosCreados.firstWhere(
                                                  (e) => e['title'] == grupo,
                                                  orElse: () =>
                                                      <String, dynamic>{},
                                                );

                                                if (eventoAEditar.isNotEmpty) {
                                                  final result =
                                                      await Navigator.pushNamed(
                                                    context,
                                                    '/escenas',
                                                    arguments: eventoAEditar,
                                                  );
                                                  if (result == true &&
                                                      mounted) {
                                                    _buildDeviceListFromLoadedData();
                                                  }
                                                }
                                              },
                                            ),
                                            // 🗑️ Botón de Eliminar original
                                            IconButton(
                                              onPressed: () {
                                                showAlertDialog(
                                                  context,
                                                  false,
                                                  const Text(
                                                    '¿Eliminar este evento de control por disparador?',
                                                    style: TextStyle(
                                                        color: color0),
                                                  ),
                                                  const Text(
                                                    'Esta acción no se puede deshacer.',
                                                    style: TextStyle(
                                                        color: color0),
                                                  ),
                                                  <Widget>[
                                                    TextButton(
                                                      style: ButtonStyle(
                                                        foregroundColor:
                                                            WidgetStateProperty
                                                                .all(color0),
                                                      ),
                                                      child: const Text(
                                                          'Cancelar'),
                                                      onPressed: () {
                                                        Navigator.of(context)
                                                            .pop();
                                                      },
                                                    ),
                                                    TextButton(
                                                      style: ButtonStyle(
                                                        foregroundColor:
                                                            WidgetStateProperty
                                                                .all(color0),
                                                      ),
                                                      child: const Text(
                                                          'Confirmar'),
                                                      onPressed: () {
                                                        setState(() {
                                                          eventosCreados
                                                              .removeWhere((e) =>
                                                                  e['title'] ==
                                                                      grupo &&
                                                                  e['evento'] ==
                                                                      'disparador');
                                                          putEventos(
                                                              currentUserEmail,
                                                              eventosCreados);

                                                          deleteEventoControlPorDisparadores(
                                                              activador,
                                                              currentUserEmail,
                                                              grupo);

                                                          todosLosDispositivos
                                                              .removeWhere(
                                                                  (entry) =>
                                                                      entry
                                                                          .key ==
                                                                      grupo);
                                                          savedOrder.removeWhere(
                                                              (item) =>
                                                                  item['key'] ==
                                                                  grupo);

                                                          _actualizarListasUI();
                                                        });
                                                        _saveOrder();
                                                        Navigator.of(context)
                                                            .pop();
                                                      },
                                                    ),
                                                  ],
                                                );
                                              },
                                              icon: const Icon(
                                                HugeIcons.strokeRoundedDelete02,
                                                color: Colors.redAccent,
                                                size: 20,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ]
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ));
            } catch (e) {
              printLog
                  .e('Error al procesar el evento de disparador $grupo: $e');
              return RepaintBoundary(
                key: ValueKey('disparador_error_$grupo'),
                child: Card(
                  color: color1,
                  margin:
                      const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                  elevation: 2,
                  child: Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ListTile(
                      title: Text(
                        'Error al cargar el evento de disparador $grupo',
                        style: GoogleFonts.poppins(
                          color: color0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        'Por favor, elimine el evento y vuelva a crearlo.',
                        style: GoogleFonts.poppins(
                          color: color0,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }
          }

          // Manejar evento de horario
          if (eventoHorario != null) {
            try {
              bool isRestricted =
                  _hasRestrictedDevicesInGroup(eventoHorario['deviceGroup']);

              bool isEnabled = eventoHorario['enabled'] ?? true;

              List<String> selectedDays =
                  List<String>.from(eventoHorario['selectedDays'] ?? []);
              String selectedTime = eventoHorario['selectedTime'] ?? '';

              Map<String, dynamic> devicesActions = Map<String, dynamic>.from(
                  eventoHorario['deviceActions'] ?? {});
              String devicesInGroup = deviceName;
              List<String> deviceList = devicesInGroup
                  .replaceAll('[', '')
                  .replaceAll(']', '')
                  .split(',');
              List<String> horarioNicksList = [];
              for (String equipo in deviceList) {
                String displayName = '';
                if (equipo.contains('_')) {
                  final parts = equipo.split('_');
                  String baseName = parts[0];
                  String index = parts[1];

                  String pc = DeviceManager.getProductCode(baseName);
                  String sn = DeviceManager.extractSerialNumber(baseName);
                  Map<String, dynamic> devData = globalDATA['$pc/$sn'] ?? {};

                  bool hasEntry = devData['hasEntry'] ?? true;

                  if (index == '0' && !hasEntry) {
                    displayName = nicknamesMap[baseName] ?? baseName;
                  } else {
                    displayName = nicknamesMap[equipo.trim()] ??
                        '${nicknamesMap[baseName] ?? baseName} salida $index';
                  }
                } else {
                  displayName = nicknamesMap[equipo.trim()] ?? equipo.trim();
                }
                horarioNicksList.add(displayName);
              }

              // Formatear días
              String formatDays(List<String> days) {
                if (days.isEmpty) return 'No hay días seleccionados';
                if (days.length == 1) return days.first;
                final primeros = days.sublist(0, days.length - 1);
                return '${primeros.join(', ')} y ${days.last}';
              }

              return RepaintBoundary(
                key: ValueKey('horario_$grupo'),
                child: Card(
                  color: isEnabled ? color1 : color1.withValues(alpha: 0.8),
                  margin:
                      const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                  elevation: 2,
                  child: Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16.0),
                      iconColor: isEnabled ? color4 : Colors.grey,
                      collapsedIconColor: isEnabled ? color4 : Colors.grey,
                      onExpansionChanged: (bool expanded) {
                        setState(() {
                          _expandedStates[deviceName] = expanded;
                        });
                      },
                      title: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: index,
                            child: const Icon(HugeIcons.strokeRoundedMenu01,
                                color: Colors.grey),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            HugeIcons.strokeRoundedClock01,
                            color: isEnabled ? color4 : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              grupo,
                              style: GoogleFonts.poppins(
                                color: isEnabled
                                    ? color0
                                    : color0.withValues(alpha: 0.6),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                decoration: isEnabled
                                    ? TextDecoration.none
                                    : TextDecoration.lineThrough,
                                decorationColor: color4,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isEnabled
                                  ? color0.withValues(alpha: 0.2)
                                  : Colors.grey.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isEnabled ? 'HORARIO' : 'INACTIVO',
                              style: GoogleFonts.poppins(
                                color: isEnabled ? color0 : Colors.grey,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    HugeIcons.strokeRoundedCalendar01,
                                    color: isEnabled
                                        ? color4
                                        : Colors.grey.withValues(alpha: 0.5),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Días',
                                          style: GoogleFonts.poppins(
                                            color:
                                                color0.withValues(alpha: 0.7),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          formatDays(selectedDays),
                                          style: GoogleFonts.poppins(
                                            color: isEnabled
                                                ? color0
                                                : color0.withValues(alpha: 0.5),
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Icon(
                                    HugeIcons.strokeRoundedClock01,
                                    color: isEnabled
                                        ? color4
                                        : Colors.grey.withValues(alpha: 0.5),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Hora',
                                          style: GoogleFonts.poppins(
                                            color:
                                                color0.withValues(alpha: 0.7),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          selectedTime.isNotEmpty
                                              ? selectedTime
                                              : 'No especificada',
                                          style: GoogleFonts.poppins(
                                            color: isEnabled
                                                ? color0
                                                : color0.withValues(alpha: 0.5),
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Dispositivos afectados:',
                                style: GoogleFonts.poppins(
                                  color: isEnabled
                                      ? color0
                                      : color0.withValues(alpha: 0.5),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ...horarioNicksList.asMap().entries.map((entry) {
                                final idx = entry.key + 1;
                                String deviceNick = entry.value;
                                final equipo = deviceList[entry.key].trim();

                                bool isEvento = false;
                                bool isCadena = false;
                                bool isRiego = false;
                                bool isGrupo = false;

                                final eventoEncontrado =
                                    eventosCreados.firstWhere(
                                  (evento) => evento['title'] == equipo,
                                  orElse: () => <String, dynamic>{},
                                );

                                if (eventoEncontrado.isNotEmpty) {
                                  final eventoType =
                                      eventoEncontrado['evento'] as String;
                                  deviceNick = equipo;
                                  isEvento = true;
                                  isCadena = eventoType == 'cadena';
                                  isRiego = eventoType == 'riego';
                                  isGrupo = eventoType == 'grupo';
                                }

                                String actionText = '';
                                IconData actionIcon =
                                    HugeIcons.strokeRoundedSettings02;
                                Color actionColor = color0;

                                if (isEvento) {
                                  if (isCadena) {
                                    actionText = 'Se ejecutará';
                                    actionIcon =
                                        HugeIcons.strokeRoundedPlayCircle;
                                    actionColor = Colors.orange;
                                  } else if (isRiego) {
                                    actionText = 'Se ejecutará';
                                    actionIcon = HugeIcons.strokeRoundedLeaf01;
                                    actionColor = Colors.blue;
                                  } else if (isGrupo) {
                                    final action =
                                        devicesActions['$equipo:grupo'] ??
                                            false;
                                    actionText =
                                        action ? "Encenderá" : "Apagará";
                                    actionIcon = (action
                                        ? HugeIcons.strokeRoundedPlug01
                                        : HugeIcons.strokeRoundedPlugSocket);
                                    actionColor =
                                        action ? Colors.green : Colors.red;
                                  } else {
                                    actionText = 'Se ejecutará';
                                    actionIcon =
                                        HugeIcons.strokeRoundedSettings02;
                                    actionColor = color4;
                                  }
                                } else {
                                  final action =
                                      devicesActions['$equipo:dispositivo'] ??
                                          false;
                                  final bool isRollerEquipo = _isRollerDevice(
                                      equipo.trim().contains('_')
                                          ? equipo.trim().split('_')[0]
                                          : equipo.trim());
                                  actionText = isRollerEquipo
                                      ? (action ? "Abrirá" : "Cerrará")
                                      : (action ? "Encenderá" : "Apagará");
                                  actionIcon = (action
                                      ? HugeIcons.strokeRoundedPlug01
                                      : HugeIcons.strokeRoundedPlugSocket);
                                  actionColor =
                                      action ? Colors.green : Colors.red;
                                }

                                if (!isEnabled) {
                                  actionColor =
                                      actionColor.withValues(alpha: 0.4);
                                }

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: isEnabled
                                              ? color4
                                              : Colors.grey
                                                  .withValues(alpha: 0.3),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            '$idx',
                                            style: GoogleFonts.poppins(
                                              color: color1,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          deviceNick,
                                          style: GoogleFonts.poppins(
                                            color: isEnabled
                                                ? color0
                                                : color0.withValues(alpha: 0.5),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        actionIcon,
                                        color: actionColor,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        actionText,
                                        style: GoogleFonts.poppins(
                                          color: actionColor,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              const SizedBox(height: 10),
                              const Divider(color: Colors.white24),
                              if (isRestricted) ...[
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(child: _buildNotOwnerWarning()),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            HugeIcons.strokeRoundedPen01,
                                            color: color4,
                                          ),
                                          tooltip: 'Editar evento',
                                          onPressed: () async {
                                            final eventoAEditar =
                                                eventosCreados.firstWhere(
                                              (e) => e['title'] == grupo,
                                              orElse: () => <String, dynamic>{},
                                            );

                                            if (eventoAEditar.isNotEmpty) {
                                              final result =
                                                  await Navigator.pushNamed(
                                                context,
                                                '/escenas',
                                                arguments: eventoAEditar,
                                              );
                                              if (result == true && mounted) {
                                                _buildDeviceListFromLoadedData();
                                              }
                                            }
                                          },
                                        ),
                                        // 🗑️ Botón de Eliminar original
                                        IconButton(
                                          icon: const Icon(
                                            HugeIcons.strokeRoundedDelete02,
                                            color: color0,
                                            size: 24,
                                          ),
                                          onPressed: () {
                                            showAlertDialog(
                                              context,
                                              false,
                                              const Text(
                                                  '¿Eliminar este horario?',
                                                  style:
                                                      TextStyle(color: color0)),
                                              const Text(
                                                  'Esta acción no se puede deshacer.',
                                                  style:
                                                      TextStyle(color: color0)),
                                              <Widget>[
                                                TextButton(
                                                  style: ButtonStyle(
                                                      foregroundColor:
                                                          WidgetStateProperty
                                                              .all(color0)),
                                                  child: const Text('Cancelar'),
                                                  onPressed: () =>
                                                      Navigator.of(context)
                                                          .pop(),
                                                ),
                                                TextButton(
                                                  style: ButtonStyle(
                                                      foregroundColor:
                                                          WidgetStateProperty
                                                              .all(color0)),
                                                  child:
                                                      const Text('Confirmar'),
                                                  onPressed: () {
                                                    setState(() {
                                                      eventosCreados
                                                          .removeWhere((e) =>
                                                              e['title'] ==
                                                                  grupo &&
                                                              e['evento'] ==
                                                                  'horario');
                                                      putEventos(
                                                          currentUserEmail,
                                                          eventosCreados);
                                                      deleteEventoControlPorHorarios(
                                                          selectedTime,
                                                          currentUserEmail,
                                                          grupo);
                                                      todosLosDispositivos
                                                          .removeWhere(
                                                              (entry) =>
                                                                  entry.key ==
                                                                  grupo);
                                                      savedOrder.removeWhere(
                                                          (item) =>
                                                              item['key'] ==
                                                              grupo);
                                                      _actualizarListasUI();
                                                    });
                                                    _saveOrder();
                                                    Navigator.of(context).pop();
                                                  },
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                )
                              ] else ...[
                                Row(
                                  children: [
                                    Switch(
                                      value: isEnabled,
                                      activeThumbColor: Colors.green,
                                      activeTrackColor:
                                          Colors.green.withValues(alpha: 0.3),
                                      inactiveThumbColor: Colors.grey,
                                      inactiveTrackColor:
                                          Colors.grey.withValues(alpha: 0.3),
                                      onChanged: (val) => _toggleEventEnabled(
                                          eventoHorario, val),
                                    ),
                                    Text(
                                      isEnabled ? 'Habilitado' : 'Inhabilitado',
                                      style: GoogleFonts.poppins(
                                        color: isEnabled
                                            ? color0
                                            : color0.withValues(alpha: 0.6),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Spacer(),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // ✏️ Botón de Editar para Dueño
                                        IconButton(
                                          icon: const Icon(
                                            HugeIcons.strokeRoundedPen01,
                                            color: color4,
                                          ),
                                          tooltip: 'Editar evento',
                                          onPressed: () async {
                                            final eventoAEditar =
                                                eventosCreados.firstWhere(
                                              (e) => e['title'] == grupo,
                                              orElse: () => <String, dynamic>{},
                                            );

                                            if (eventoAEditar.isNotEmpty) {
                                              final result =
                                                  await Navigator.pushNamed(
                                                context,
                                                '/escenas',
                                                arguments: eventoAEditar,
                                              );
                                              if (result == true && mounted) {
                                                _buildDeviceListFromLoadedData();
                                              }
                                            }
                                          },
                                        ),
                                        // 🗑️ Botón de Eliminar original
                                        IconButton(
                                          onPressed: () {
                                            showAlertDialog(
                                              context,
                                              false,
                                              const Text(
                                                '¿Eliminar este evento de control por horario?',
                                                style: TextStyle(color: color0),
                                              ),
                                              const Text(
                                                'Esta acción no se puede deshacer.',
                                                style: TextStyle(color: color0),
                                              ),
                                              <Widget>[
                                                TextButton(
                                                  style: ButtonStyle(
                                                    foregroundColor:
                                                        WidgetStateProperty.all(
                                                            color0),
                                                  ),
                                                  child: const Text('Cancelar'),
                                                  onPressed: () {
                                                    Navigator.of(context).pop();
                                                  },
                                                ),
                                                TextButton(
                                                  style: ButtonStyle(
                                                    foregroundColor:
                                                        WidgetStateProperty.all(
                                                            color0),
                                                  ),
                                                  child:
                                                      const Text('Confirmar'),
                                                  onPressed: () {
                                                    setState(() {
                                                      eventosCreados
                                                          .removeWhere((e) =>
                                                              e['title'] ==
                                                                  grupo &&
                                                              e['evento'] ==
                                                                  'horario');
                                                      putEventos(
                                                          currentUserEmail,
                                                          eventosCreados);
                                                      deleteEventoControlPorHorarios(
                                                          selectedTime,
                                                          currentUserEmail,
                                                          grupo);
                                                      todosLosDispositivos
                                                          .removeWhere(
                                                              (entry) =>
                                                                  entry.key ==
                                                                  grupo);
                                                      savedOrder.removeWhere(
                                                          (item) =>
                                                              item['key'] ==
                                                              grupo);
                                                      _actualizarListasUI();
                                                    });
                                                    _saveOrder();
                                                    Navigator.of(context).pop();
                                                  },
                                                ),
                                              ],
                                            );
                                          },
                                          icon: const Icon(
                                            HugeIcons.strokeRoundedDelete02,
                                            color: Colors.redAccent,
                                            size: 20,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            } catch (e) {
              printLog.e('Error al procesar el evento de horario $grupo: $e');
              return RepaintBoundary(
                key: ValueKey('horario_$grupo'),
                child: Card(
                  color: color1,
                  margin:
                      const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                  elevation: 2,
                  child: Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ListTile(
                      title: Text(
                        'Error al cargar el evento de horario $grupo',
                        style: GoogleFonts.poppins(
                          color: color0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        'Por favor, elimine el evento y vuelva a crearlo.',
                        style: GoogleFonts.poppins(
                          color: color0,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }
          }
          String devicesInGroup = deviceName;
          List<String> deviceList =
              devicesInGroup.replaceAll('[', '').replaceAll(']', '').split(',');
          List<String> nicksList = [];
          for (String equipo in deviceList) {
            String displayName = '';
            if (equipo.contains('_')) {
              final parts = equipo.split('_');
              final String baseName = parts[0];
              final String idx = parts[1];
              final String gpc = DeviceManager.getProductCode(baseName);
              final String gsn = DeviceManager.extractSerialNumber(baseName);
              final Map<String, dynamic> gData = globalDATA['$gpc/$gsn'] ?? {};
              final bool hasEntry = gData['hasEntry'] ?? true;
              if (idx == '0' && !hasEntry) {
                displayName = nicknamesMap[baseName] ?? baseName;
              } else {
                displayName = nicknamesMap[equipo.trim()] ??
                    '${nicknamesMap[baseName] ?? baseName} salida $idx';
              }
            } else {
              displayName = nicknamesMap[equipo.trim()] ?? equipo.trim();
            }

            nicksList.add(displayName);
          }

          for (String device in deviceList) {
            String equipo = DeviceManager.getProductCode(device);
            String serial = DeviceManager.extractSerialNumber(
              device,
            );

            final deviceSpecificData = ref.watch(
              globalDataProvider.select(
                (map) => map['$equipo/$serial'] ?? {},
              ),
            );

            globalDATA
                .putIfAbsent('$equipo/$serial', () => {})
                .addAll(deviceSpecificData);
          }

          bool online = isGroupOnline(devicesInGroup);
          bool estado = isGroupOn(devicesInGroup);
          bool owner = canControlGroup(devicesInGroup);

          bool isRestricted = _hasRestrictedDevicesInGroup(devicesInGroup);

          try {
            return RepaintBoundary(
              key: ValueKey('grupo_$grupo'),
              child: Card(
                color: color1,
                margin: const EdgeInsets.symmetric(
                  vertical: 5,
                  horizontal: 10,
                ),
                elevation: 2,
                child: Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                    ),
                    iconColor: color4,
                    collapsedIconColor: color4,
                    onExpansionChanged: (bool expanded) {
                      setState(() {
                        _expandedStates[deviceName] = expanded;
                      });
                    },
                    title: Row(
                      children: [
                        ReorderableDragStartListener(
                          index: index,
                          child: const Icon(HugeIcons.strokeRoundedMenu01,
                              color: Colors.grey),
                        ),
                        const SizedBox(width: 8),
                        const Icon(HugeIcons.strokeRoundedUserGroup,
                            color: color4),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            grupo[0].toUpperCase() + grupo.substring(1),
                            style: GoogleFonts.poppins(
                              color: color0,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: color0.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'GRUPO',
                            style: GoogleFonts.poppins(
                              color: color0,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!online) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.red.withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      HugeIcons.strokeRoundedWifiOff02,
                                      color: Colors.red,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Todos los equipos deben estar conectados para su uso',
                                        style: GoogleFonts.poppins(
                                          color: Colors.red,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                            ] else ...[
                              // Control del grupo cuando está online
                              if (isRestricted) ...[
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16.0),
                                  child: _buildNotOwnerWarning(),
                                )
                              ] else ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: estado
                                        ? color0.withValues(alpha: 0.1)
                                        : color0.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: color0,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        estado
                                            ? HugeIcons.strokeRoundedPlug01
                                            : HugeIcons.strokeRoundedPlugSocket,
                                        color:
                                            estado ? Colors.green : Colors.red,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          estado
                                              ? 'Grupo encendido'
                                              : 'Grupo apagado',
                                          style: GoogleFonts.poppins(
                                            color:
                                                estado ? Colors.green : color4,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if (owner)
                                        Switch(
                                          activeThumbColor: Colors.green,
                                          activeTrackColor: Colors.green
                                              .withValues(alpha: 0.3),
                                          inactiveThumbColor: color4,
                                          inactiveTrackColor:
                                              color4.withValues(alpha: 0.3),
                                          value: estado,
                                          onChanged: (newValue) {
                                            controlGroup(
                                              currentUserEmail,
                                              newValue,
                                              grupo,
                                            );
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              ],

                              const SizedBox(height: 16),
                            ],
                            Text(
                              'Dispositivos en el grupo:',
                              style: GoogleFonts.poppins(
                                color: color0,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ...nicksList.map((deviceDisplayName) {
                              return Container(
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: color1.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: color0.withValues(alpha: 0.1),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: Colors.green,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        deviceDisplayName,
                                        style: GoogleFonts.poppins(
                                          color: color0,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      HugeIcons.strokeRoundedPen01,
                                      color: color4,
                                    ),
                                    tooltip: 'Editar evento',
                                    onPressed: () async {
                                      final eventoAEditar =
                                          eventosCreados.firstWhere(
                                        (e) => e['title'] == grupo,
                                        orElse: () => <String, dynamic>{},
                                      );

                                      if (eventoAEditar.isNotEmpty) {
                                        final result =
                                            await Navigator.pushNamed(
                                          context,
                                          '/escenas',
                                          arguments: eventoAEditar,
                                        );
                                        if (result == true && mounted) {
                                          _buildDeviceListFromLoadedData();
                                        }
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      HugeIcons.strokeRoundedDelete02,
                                      color: color0,
                                    ),
                                    tooltip: 'Eliminar evento de grupos',
                                    onPressed: () {
                                      showAlertDialog(
                                        context,
                                        false,
                                        const Text(
                                          '¿Eliminar este evento de control por grupos?',
                                          style: TextStyle(color: color0),
                                        ),
                                        const Text(
                                          'Esta acción no se puede deshacer.',
                                          style: TextStyle(color: color0),
                                        ),
                                        <Widget>[
                                          TextButton(
                                            style: ButtonStyle(
                                              foregroundColor:
                                                  WidgetStateProperty.all(
                                                      color0),
                                            ),
                                            child: const Text('Cancelar'),
                                            onPressed: () {
                                              Navigator.of(context).pop();
                                            },
                                          ),
                                          TextButton(
                                            style: ButtonStyle(
                                              foregroundColor:
                                                  WidgetStateProperty.all(
                                                      color0),
                                            ),
                                            child: const Text('Confirmar'),
                                            onPressed: () {
                                              setState(() {
                                                eventosCreados.removeWhere(
                                                    (e) =>
                                                        e['title'] == grupo &&
                                                        e['evento'] == 'grupo');
                                                putEventos(currentUserEmail,
                                                    eventosCreados);
                                                printLog.d(grupo,
                                                    color: 'naranja');
                                                deleteEventoControlPorGrupos(
                                                    currentUserEmail, grupo);
                                                todosLosDispositivos
                                                    .removeWhere((entry) =>
                                                        entry.key == grupo);
                                                savedOrder.removeWhere((item) =>
                                                    item['key'] == grupo);
                                                _actualizarListasUI();
                                              });
                                              _saveOrder();
                                              Navigator.of(context).pop();
                                            },
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          } catch (e) {
            printLog.e('Error al procesar el grupo $grupo: $e');
            return RepaintBoundary(
              key: ValueKey('grupo_error_$grupo'),
              child: Card(
                color: color1,
                margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                elevation: 2,
                child: Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ListTile(
                    title: Text(
                      'Error al cargar el grupo $grupo',
                      style: GoogleFonts.poppins(
                        color: color0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      'Por favor, elimine el evento y vuelva a crearlo.',
                      style: GoogleFonts.poppins(
                        color: color0,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
        }
      },
    );
  }

  // Función para construir tarjeta de equipo de riego
  Widget _buildRiegoCard(
      String deviceName,
      String productCode,
      String serialNumber,
      Map<String, dynamic> deviceDATA,
      bool online,
      bool owner,
      int index,
      {bool isInsideFolder = false}) {
    bool isRiegoActive = deviceDATA['riegoActive'] == true;

    if (!isRiegoActive) {
      return SizedBox.shrink(key: ValueKey(deviceName));
    }

    // Obtener extensiones vinculadas
    List<String> extensionesVinculadas = [];
    globalDATA.forEach((key, value) {
      if (value['riegoMaster'] == deviceName &&
          (key.startsWith('020020_IOT/') ||
              key.startsWith('020010_IOT/') ||
              key.startsWith('027313_IOT/'))) {
        String pc = key.split('/')[0];
        String sn = key.split('/')[1];
        String extensionName = DeviceManager.recoverDeviceName(pc, sn);
        extensionesVinculadas.add(extensionName);
        extensionesVinculadas.sort();
      }
    });

    final cardColor = isInsideFolder ? color1.withValues(alpha: 0.9) : color1;
    final double cardElevation = isInsideFolder ? 0 : 2;
    final EdgeInsets cardMargin = isInsideFolder
        ? const EdgeInsets.symmetric(vertical: 8, horizontal: 4)
        : const EdgeInsets.symmetric(vertical: 5, horizontal: 10);

    final ShapeBorder cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(15),
      side: isInsideFolder
          ? const BorderSide(color: color3, width: 2.0)
          : BorderSide.none,
    );

    return RepaintBoundary(
      key: ValueKey(deviceName),
      child: Card(
        color: cardColor,
        margin: cardMargin,
        elevation: cardElevation,
        shape: cardShape,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16.0),
            iconColor: color4,
            collapsedIconColor: color4,
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                isInsideFolder
                    ? const Icon(HugeIcons.strokeRoundedPlant03,
                        color: color4, size: 20)
                    : ReorderableDragStartListener(
                        index: index,
                        child: const Icon(HugeIcons.strokeRoundedMenu01,
                            color: Colors.grey),
                      ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nicknamesMap[deviceName] ?? deviceName,
                        style: GoogleFonts.poppins(
                          color: color0,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        runSpacing: 5,
                        children: [
                          Text(
                            online ? '● CONECTADO' : '● DESCONECTADO',
                            style: GoogleFonts.poppins(
                              color: online ? Colors.green : color3,
                              fontSize: 15,
                            ),
                          ),
                          online
                              ? ImageIcon(
                                  const AssetImage(CaldenIcons.cloud),
                                  color: online ? Colors.green : color3,
                                  size: 25,
                                )
                              : ImageIcon(
                                  const AssetImage(CaldenIcons.cloudOff),
                                  color: online ? Colors.green : color3,
                                  size: 15,
                                ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50)
                                  .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'RIEGO',
                              style: GoogleFonts.poppins(
                                color: const Color(0xFF4CAF50),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            children: <Widget>[
              if (online) ...[
                ...(deviceDATA.keys
                        .where((key) =>
                            key.startsWith('io') &&
                            RegExp(r'^io\d+$').hasMatch(key))
                        .where((ioKey) {
                  if (deviceDATA[ioKey] == null) return false;
                  try {
                    var ioData = deviceDATA[ioKey] is String
                        ? jsonDecode(deviceDATA[ioKey])
                        : deviceDATA[ioKey];
                    // pinType puede ser '0', 0, "0"
                    var pinTypeStr = ioData['pinType'].toString();
                    bool isOutput = pinTypeStr == '0';
                    // printLog.i(
                    //     'Riego $deviceName - $ioKey: pinType=$pinTypeStr, isOutput=$isOutput');
                    return isOutput;
                  } catch (e) {
                    printLog.e('Error parseando $ioKey: $e');
                    return false;
                  }
                }).toList()
                      ..sort((a, b) {
                        int indexA = int.parse(a.substring(2));
                        int indexB = int.parse(b.substring(2));
                        return indexA.compareTo(indexB);
                      }))
                    .map((ioKey) => _buildRiegoOutput(deviceName, productCode,
                        serialNumber, ioKey, deviceDATA, owner)),

                // Mostrar extensiones si las hay
                if (extensionesVinculadas.isNotEmpty) ...[
                  const Divider(color: color0, thickness: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: Text(
                      'Extensiones Vinculadas',
                      style: GoogleFonts.poppins(
                        color: color0,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ...extensionesVinculadas.map((extension) =>
                      _buildExtensionCard(extension, deviceName, owner)),
                ],

                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0, bottom: 8.0),
                      child: IconButton(
                        icon: const Icon(
                          HugeIcons.strokeRoundedDelete02,
                          color: color0,
                          size: 20,
                        ),
                        onPressed: () {
                          _confirmDelete(deviceName, productCode);
                        },
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Padding(
                        padding:
                            const EdgeInsets.only(left: 20.0, bottom: 16.0),
                        child: !online
                            ? Text(
                                'El equipo debe estar\nconectado para su uso',
                                style: GoogleFonts.poppins(
                                  color: color3,
                                  fontSize: 15,
                                ),
                              )
                            : const SizedBox(height: 0),
                      ),
                    ),
                    if (!online) ...{
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0, bottom: 8.0),
                        child: IconButton(
                          icon: const Icon(
                            HugeIcons.strokeRoundedDelete02,
                            color: color0,
                            size: 20,
                          ),
                          onPressed: () {
                            _confirmDelete(deviceName, productCode);
                          },
                        ),
                      ),
                    }
                  ],
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }

  // Función para construir una salida de riego
  Widget _buildRiegoOutput(
      String deviceName,
      String productCode,
      String serialNumber,
      String ioKey,
      Map<String, dynamic> deviceDATA,
      bool owner) {
    int outputIndex = int.parse(ioKey.substring(2));
    Map<String, dynamic> outputData = jsonDecode(deviceDATA[ioKey]);

    String pinType = outputData['pinType'].toString();
    bool isOutput = pinType == '0';

    // En equipos de riego, solo mostrar salidas (ocultar entradas)
    if (!isOutput) {
      return const SizedBox.shrink();
    }

    bool currentStatus = outputData['w_status'] ?? false;
    String rState = (outputData['r_state'] ?? '0').toString();

    // Para la bomba (salida 0), usar lógica especial
    bool isBomb = outputIndex == 0 && isOutput;

    // Para las zonas, verificar lógica de riego
    String displayName;
    if (isBomb) {
      displayName = 'Bomba'; // La bomba siempre se llama "Bomba", sin nickname
    } else {
      displayName =
          nicknamesMap['${deviceName}_$outputIndex'] ?? 'Zona $outputIndex';
    }

    return ListTile(
      title: Text(
        displayName,
        style: GoogleFonts.poppins(
          color: color0,
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Text(
        _getRiegoStatusText(currentStatus, isOutput, isBomb, rState),
        style: GoogleFonts.poppins(
          color: _getRiegoStatusColor(currentStatus, isOutput, isBomb, rState),
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
      ),
      trailing: owner && isOutput
          ? Switch(
              activeThumbColor: const Color(0xFF9C9D98),
              activeTrackColor: const Color(0xFFB2B5AE),
              inactiveThumbColor: const Color(0xFFB2B5AE),
              inactiveTrackColor: const Color(0xFF9C9D98),
              value: currentStatus,
              onChanged: (value) => _controlRiegoOutput(deviceName, productCode,
                  serialNumber, outputIndex, value, isBomb),
            )
          : isOutput
              ? null
              : Icon(
                  HugeIcons.strokeRoundedInternetAntenna02,
                  color: _getRiegoStatusColor(
                      currentStatus, isOutput, isBomb, rState),
                ),
    );
  }

  // Función para construir tarjeta de extensión
  Widget _buildExtensionCard(
      String extension, String masterDevice, bool owner) {
    String extensionPc = DeviceManager.getProductCode(extension);
    String extensionSn = DeviceManager.extractSerialNumber(extension);
    String key = '$extensionPc/$extensionSn';

    Map<String, dynamic> extensionData = globalDATA[key] ?? {};
    bool isExtensionOnline = extensionData['cstate'] ?? false;

    // Obtener solo las salidas de la extensión
    List<MapEntry<String, dynamic>> outputs = [];
    extensionData.forEach((k, v) {
      if (k.startsWith('io') && v is String) {
        try {
          var decoded = jsonDecode(v);
          if (decoded['pinType'] == '0') {
            outputs.add(MapEntry(k, decoded));
          }
        } catch (e) {
          printLog.e('Error decodificando datos I/O: $e');
        }
      }
    });

    outputs.sort((a, b) {
      int indexA = int.tryParse(a.key.replaceAll('io', '')) ?? 0;
      int indexB = int.tryParse(b.key.replaceAll('io', '')) ?? 0;
      return indexA.compareTo(indexB);
    });

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      color: color0.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                isExtensionOnline
                    ? ImageIcon(
                        const AssetImage(CaldenIcons.cloud),
                        color: isExtensionOnline ? Colors.green : Colors.red,
                        size: 25,
                      )
                    : ImageIcon(
                        const AssetImage(CaldenIcons.cloudOff),
                        color: isExtensionOnline ? Colors.green : Colors.red,
                        size: 20,
                      ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    nicknamesMap[extension] ?? extension,
                    style: GoogleFonts.poppins(
                      color: color0,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            if (isExtensionOnline && outputs.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...outputs.map((output) {
                int outputIndex = int.parse(output.key.replaceAll('io', ''));
                bool isOn = output.value['w_status'] ?? false;
                String zoneLabel = nicknamesMap['${extension}_$outputIndex'] ??
                    'Zona ${_getZoneNumber(masterDevice, extension, outputIndex)}';

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          zoneLabel,
                          style: GoogleFonts.poppins(
                            color: color0,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Text(
                        isOn ? 'Encendido' : 'Apagado',
                        style: GoogleFonts.poppins(
                          color: isOn ? Colors.green : color4,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (owner)
                        Switch(
                          activeThumbColor: const Color(0xFF9C9D98),
                          activeTrackColor: const Color(0xFFB2B5AE),
                          inactiveThumbColor: const Color(0xFFB2B5AE),
                          inactiveTrackColor: const Color(0xFF9C9D98),
                          value: isOn,
                          onChanged: (value) => _controlExtensionOutput(
                              extension, outputIndex, value, masterDevice),
                        ),
                    ],
                  ),
                );
              }),
            ] else if (!isExtensionOnline) ...[
              const SizedBox(height: 8),
              Text(
                'Extensión desconectada',
                style: GoogleFonts.poppins(
                  color: color3,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Función auxiliar para obtener el número de zona consecutivo
  int _getZoneNumber(String masterDevice, String extension, int outputIndex) {
    int zoneCounter = 1;

    // Contar zonas del maestro primero
    String masterPc = DeviceManager.getProductCode(masterDevice);
    String masterSn = DeviceManager.extractSerialNumber(masterDevice);
    Map<String, dynamic> masterData = globalDATA['$masterPc/$masterSn'] ?? {};

    masterData.forEach((key, value) {
      if (key.startsWith('io') && key != 'io0' && value is String) {
        try {
          var decoded = jsonDecode(value);
          if (decoded['pinType'] == '0') {
            zoneCounter++;
          }
        } catch (e) {
          // Error handling
          printLog.e('Error al decodificar $key: $e');
        }
      }
    });

    // Luego contar zonas de extensiones anteriores a esta
    List<String> extensionesVinculadas = [];
    globalDATA.forEach((key, value) {
      if (value['riegoMaster'] == masterDevice &&
          key !=
              '${DeviceManager.getProductCode(extension)}/${DeviceManager.extractSerialNumber(extension)}') {
        String pc = key.split('/')[0];
        String sn = key.split('/')[1];
        String extensionName = DeviceManager.recoverDeviceName(pc, sn);
        extensionesVinculadas.add(extensionName);
      }
    });

    for (String ext in extensionesVinculadas) {
      if (ext == extension) break;

      String extPc = DeviceManager.getProductCode(ext);
      String extSn = DeviceManager.extractSerialNumber(ext);
      Map<String, dynamic> extData = globalDATA['$extPc/$extSn'] ?? {};

      extData.forEach((key, value) {
        if (key.startsWith('io') && value is String) {
          try {
            var decoded = jsonDecode(value);
            if (decoded['pinType'] == '0') {
              zoneCounter++;
            }
          } catch (e) {
            // Error handling
            printLog.e('Error al decodificar $key: $e');
          }
        }
      });
    }

    // Agregar el índice de salida actual
    String extPc = DeviceManager.getProductCode(extension);
    String extSn = DeviceManager.extractSerialNumber(extension);
    Map<String, dynamic> extData = globalDATA['$extPc/$extSn'] ?? {};

    List<int> outputs = [];
    extData.forEach((key, value) {
      if (key.startsWith('io') && value is String) {
        try {
          var decoded = jsonDecode(value);
          if (decoded['pinType'] == '0') {
            outputs.add(int.parse(key.replaceAll('io', '')));
          }
        } catch (e) {
          // Error handling
          printLog.e('Error al decodificar $key: $e');
        }
      }
    });

    outputs.sort();
    int indexInExtension = outputs.indexOf(outputIndex);

    return zoneCounter + indexInExtension;
  }

  // Funciones auxiliares para el estado de riego
  String _getRiegoStatusText(
      bool status, bool isOutput, bool isBomb, String rState) {
    if (isOutput) {
      if (isBomb) {
        return status ? 'Encendida' : 'Apagada';
      } else {
        return status ? 'Regando' : 'Apagada';
      }
    } else {
      return status
          ? (rState == '1' ? 'Cerrado' : 'Abierto')
          : (rState == '1' ? 'Abierto' : 'Cerrado');
    }
  }

  Color _getRiegoStatusColor(
      bool status, bool isOutput, bool isBomb, String rState) {
    if (isOutput) {
      return status ? Colors.green : color4;
    } else {
      bool isNormalClosed = rState == '1';
      return status == isNormalClosed ? Colors.green : color4;
    }
  }

  // Función para controlar salidas de riego individual
  void _controlRiegoOutput(String deviceName, String productCode,
      String serialNumber, int outputIndex, bool value, bool isBomb) {
    // Verificar si hay procesos en curso
    if (_isPumpShuttingDown) {
      showToast('Espere, la bomba se está apagando...');
      return;
    }

    if (_isAutoStarting) {
      showToast('Espere, se está iniciando automáticamente...');
      return;
    }

    // Aplicar lógica similar a riego.dart
    Map<String, dynamic> deviceDATA =
        globalDATA['$productCode/$serialNumber'] ?? {};
    bool freeBomb = deviceDATA['freeBomb'] ?? false;

    // Validación especial para control directo de bomba
    if (isBomb && !freeBomb) {
      if (value) {
        // Intentando ENCENDER la bomba - verificar si hay zonas activas
        int activeZones = _countActiveZonesForDevice(productCode, serialNumber);
        int activeExtensionZones =
            _countActiveZonesForAllExtensions(deviceName);
        int totalActiveZones = activeZones + activeExtensionZones;

        if (totalActiveZones == 0) {
          showToast('No se puede encender la bomba sin zonas activas.');
          return;
        }
      }
      // Si llegamos aquí, permitir el control directo de la bomba
      _sendRiegoCommand(productCode, serialNumber, outputIndex, value);
      return;
    }

    if (!freeBomb && !isBomb) {
      // Lógica para zonas con bomba automática
      if (value) {
        // ENCENDER: zona primero, luego bomba
        _sendRiegoCommand(productCode, serialNumber, outputIndex, value);

        // Verificar si la bomba está apagada
        if (deviceDATA['io0'] != null) {
          try {
            var bombData = jsonDecode(deviceDATA['io0']);
            bool bombStatus = bombData['w_status'] ?? false;

            if (!bombStatus) {
              setState(() {
                _isAutoStarting = true;
              });

              // Delay de 1 segundo antes de encender bomba
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted) {
                  _sendRiegoCommand(productCode, serialNumber, 0, true);
                  setState(() {
                    _isAutoStarting = false;
                  });
                }
              });
            }
          } catch (e) {
            // Error handling
            printLog.e('Error al decodificar datos de la bomba: $e');
          }
        }
        return;
      } else {
        // APAGAR ZONA: Verificar DIRECTAMENTE el estado de las zonas
        // Contar zonas activas en tiempo real (excluyendo la que vamos a apagar)
        Map<String, dynamic> currentDeviceData =
            globalDATA['$productCode/$serialNumber'] ?? {};

        int activeZonesCount = 0;

        // Verificar zonas del dispositivo principal (excluyendo io0 que es la bomba)
        currentDeviceData.forEach((key, value) {
          if (key.startsWith('io') && key != 'io0' && value is String) {
            try {
              var decoded = jsonDecode(value);
              int ioIndex = int.parse(key.substring(2));
              // Contar solo si: es salida, está encendida, y NO es la que vamos a apagar
              if (decoded['pinType'].toString() == '0' &&
                  decoded['w_status'] == true &&
                  ioIndex != outputIndex) {
                activeZonesCount++;
              }
            } catch (e) {
              printLog.e('Error verificando $key: $e');
            }
          }
        });

        // Verificar zonas de extensiones vinculadas
        globalDATA.forEach((key, value) {
          if (value['riegoMaster'] == deviceName) {
            // Esta es una extensión vinculada
            value.forEach((ioKey, ioValue) {
              if (ioKey.startsWith('io') && ioValue is String) {
                try {
                  var decoded = jsonDecode(ioValue);
                  // Contar zonas activas de extensiones
                  if (decoded['pinType'].toString() == '0' &&
                      decoded['w_status'] == true) {
                    activeZonesCount++;
                  }
                } catch (e) {
                  printLog.e('Error verificando extensión $ioKey: $e');
                }
              }
            });
          }
        });

        printLog.i('🔍 Verificación antes de apagar zona $outputIndex:');
        printLog
            .i('   - Zonas activas (excluyendo la actual): $activeZonesCount');

        // Verificar si la bomba está encendida
        bool bombIsOn = false;
        if (currentDeviceData['io0'] != null) {
          try {
            var bombData = jsonDecode(currentDeviceData['io0']);
            bombIsOn = bombData['w_status'] ?? false;
          } catch (e) {
            printLog.e('Error verificando bomba: $e');
          }
        }

        printLog.i('   - Bomba encendida: $bombIsOn');

        if (activeZonesCount == 0 && bombIsOn) {
          // Esta es la última zona activa Y la bomba está encendida
          // APAGAR BOMBA PRIMERO
          printLog.i('⚠️ Última zona activa - Apagando bomba primero');

          setState(() {
            _isPumpShuttingDown = true;
          });

          // 1. Apagar bomba primero
          _sendRiegoCommand(productCode, serialNumber, 0, false);

          // 2. Esperar 1 segundo
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) {
              // 3. Apagar zona
              _sendRiegoCommand(productCode, serialNumber, outputIndex, value);
              setState(() {
                _isPumpShuttingDown = false;
              });
              printLog.i('✅ Secuencia completada: Bomba → Zona $outputIndex');
            }
          });
          return;
        }

        // Si no es la última o la bomba ya está apagada, apagar normalmente
        printLog.i('➡️ Apagando zona $outputIndex normalmente');
        _sendRiegoCommand(productCode, serialNumber, outputIndex, value);
        return;
      }
    }

    // Envío normal
    _sendRiegoCommand(productCode, serialNumber, outputIndex, value);
  }

  // Función para controlar salidas de extensión
  void _controlExtensionOutput(
      String extension, int outputIndex, bool value, String masterDevice) {
    // Verificar si hay procesos en curso
    if (_isPumpShuttingDown) {
      showToast('Espere, la bomba se está apagando...');
      return;
    }

    if (_isAutoStarting) {
      showToast('Espere, se está iniciando automáticamente...');
      return;
    }

    String extensionPc = DeviceManager.getProductCode(extension);
    String extensionSn = DeviceManager.extractSerialNumber(extension);

    // Obtener datos del maestro para la lógica de bomba
    String masterPc = DeviceManager.getProductCode(masterDevice);
    String masterSn = DeviceManager.extractSerialNumber(masterDevice);
    Map<String, dynamic> masterData = globalDATA['$masterPc/$masterSn'] ?? {};
    bool freeBomb = masterData['freeBomb'] ?? false;

    if (!freeBomb) {
      // Aplicar lógica de bomba automática
      if (value) {
        // ENCENDER: extensión primero, luego bomba del maestro
        _sendRiegoCommand(extensionPc, extensionSn, outputIndex, value);

        // Verificar si la bomba del maestro está apagada
        if (masterData['io0'] != null) {
          try {
            var bombData = jsonDecode(masterData['io0']);
            bool bombStatus = bombData['w_status'] ?? false;

            if (!bombStatus) {
              setState(() {
                _isAutoStarting = true;
              });

              // Delay de 1 segundo antes de encender bomba
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted) {
                  _sendRiegoCommand(masterPc, masterSn, 0, true);
                  setState(() {
                    _isAutoStarting = false;
                  });
                }
              });
            }
          } catch (e) {
            // Error handling
            printLog.e('Error al decodificar datos de la bomba: $e');
          }
        }
        return;
      } else {
        // APAGAR ZONA DE EXTENSIÓN: Verificar DIRECTAMENTE el estado de todas las zonas
        Map<String, dynamic> masterData =
            globalDATA['$masterPc/$masterSn'] ?? {};

        int activeZonesCount = 0;

        // Verificar zonas del maestro (excluyendo io0 que es la bomba)
        masterData.forEach((key, value) {
          if (key.startsWith('io') && key != 'io0' && value is String) {
            try {
              var decoded = jsonDecode(value);
              // Contar solo salidas activas
              if (decoded['pinType'].toString() == '0' &&
                  decoded['w_status'] == true) {
                activeZonesCount++;
              }
            } catch (e) {
              printLog.e('Error verificando maestro $key: $e');
            }
          }
        });

        // Verificar zonas de TODAS las extensiones (incluyendo esta)
        globalDATA.forEach((key, value) {
          if (value['riegoMaster'] == masterDevice) {
            value.forEach((ioKey, ioValue) {
              if (ioKey.startsWith('io') && ioValue is String) {
                try {
                  var decoded = jsonDecode(ioValue);
                  // Obtener el índice de la salida
                  int ioIndex = int.parse(ioKey.substring(2));
                  bool isCurrentOutput = (key == '$extensionPc/$extensionSn' &&
                      ioIndex == outputIndex);

                  // Contar solo si: es salida, está encendida, y NO es la que vamos a apagar
                  if (decoded['pinType'].toString() == '0' &&
                      decoded['w_status'] == true &&
                      !isCurrentOutput) {
                    activeZonesCount++;
                  }
                } catch (e) {
                  printLog.e('Error verificando extensión $ioKey: $e');
                }
              }
            });
          }
        });

        printLog.i(
            '🔍 Verificación antes de apagar extensión $extension zona $outputIndex:');
        printLog
            .i('   - Zonas activas (excluyendo la actual): $activeZonesCount');

        // Verificar si la bomba del maestro está encendida
        bool bombIsOn = false;
        if (masterData['io0'] != null) {
          try {
            var bombData = jsonDecode(masterData['io0']);
            bombIsOn = bombData['w_status'] ?? false;
          } catch (e) {
            printLog.e('Error verificando bomba maestro: $e');
          }
        }

        printLog.i('   - Bomba maestro encendida: $bombIsOn');

        if (activeZonesCount == 0 && bombIsOn) {
          // Esta es la última zona activa Y la bomba está encendida
          // APAGAR BOMBA DEL MAESTRO PRIMERO
          printLog.i(
              '⚠️ Última zona de extensión activa - Apagando bomba maestro primero');

          setState(() {
            _isPumpShuttingDown = true;
          });

          // 1. Apagar bomba del maestro primero
          _sendRiegoCommand(masterPc, masterSn, 0, false);

          // 2. Esperar 1 segundo
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) {
              // 3. Apagar zona de extensión
              _sendRiegoCommand(extensionPc, extensionSn, outputIndex, value);
              setState(() {
                _isPumpShuttingDown = false;
              });
              printLog.i(
                  '✅ Secuencia completada: Bomba maestro → Extensión $extension zona $outputIndex');
            }
          });
          return;
        }

        // Si no es la última o la bomba ya está apagada, apagar normalmente
        printLog.i('➡️ Apagando zona $outputIndex de extensión normalmente');
        _sendRiegoCommand(extensionPc, extensionSn, outputIndex, value);
        return;
      }
    }

    // Envío normal para extensión
    _sendRiegoCommand(extensionPc, extensionSn, outputIndex, value);
  }

  // Función para enviar comando MQTT de riego
  void _sendRiegoCommand(String productCode, String serialNumber,
      int outputIndex, bool value) async {
    bool hasPermission = await checkAdminTimePermission(deviceName);
    if (!hasPermission) {
      showToast('No tiene permiso para controlar el riego ahora.');
      return;
    }
    String message = jsonEncode({
      'pinType': '0', // Siempre salida para riego
      'index': outputIndex,
      'w_status': value,
      'r_state': '0',
    });

    String topic = 'devices_rx/$productCode/$serialNumber';
    String topic2 = 'devices_tx/$productCode/$serialNumber';

    sendMessagemqtt(topic, message);
    sendMessagemqtt(topic2, message);

    // Actualizar datos locales
    globalDATA
        .putIfAbsent('$productCode/$serialNumber', () => {})
        .addAll({'io$outputIndex': message});

    setState(() {});
  }

  // Función para contar zonas activas de un dispositivo
  int _countActiveZonesForDevice(String productCode, String serialNumber) {
    Map<String, dynamic> deviceDATA =
        globalDATA['$productCode/$serialNumber'] ?? {};
    int count = 0;

    deviceDATA.forEach((key, value) {
      if (key.startsWith('io') && key != 'io0' && value is String) {
        try {
          var decoded = jsonDecode(value);
          if (decoded['pinType'] == '0' && decoded['w_status'] == true) {
            count++;
          }
        } catch (e) {
          // Error handling
          printLog.e('Error al decodificar $key: $e');
        }
      }
    });

    return count;
  }

  // Función para contar zonas activas de todas las extensiones
  int _countActiveZonesForAllExtensions(String masterDevice) {
    int count = 0;

    globalDATA.forEach((key, value) {
      if (value['riegoMaster'] == masterDevice) {
        Map<String, dynamic> extensionData = value;

        extensionData.forEach((ioKey, ioValue) {
          if (ioKey.startsWith('io') && ioValue is String) {
            try {
              var decoded = jsonDecode(ioValue);
              if (decoded['pinType'] == '0' && decoded['w_status'] == true) {
                count++;
              }
            } catch (e) {
              // Error handling
              printLog.e('Error al decodificar $ioKey: $e');
            }
          }
        });
      }
    });

    return count;
  }
}

// ── Slider de posición para roller (024011_IOT) ──
class _RollerPositionSlider extends StatefulWidget {
  final int initialValue;
  final bool isMoving;
  final void Function(int) onChangeEnd;

  const _RollerPositionSlider({
    required this.initialValue,
    required this.isMoving,
    required this.onChangeEnd,
  });

  @override
  State<_RollerPositionSlider> createState() => _RollerPositionSliderState();
}

class _RollerPositionSliderState extends State<_RollerPositionSlider> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue.clamp(0, 100).toDouble();
  }

  @override
  void didUpdateWidget(_RollerPositionSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sólo sincroniza si el usuario NO está arrastrando
    // (cuando isMoving pasa a false, actualiza la posición real)
    if (!widget.isMoving && oldWidget.isMoving) {
      setState(() => _value = widget.initialValue.clamp(0, 100).toDouble());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Posición',
              style: GoogleFonts.poppins(
                color: color0.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
            Text(
              '${_value.toInt()}%',
              style: GoogleFonts.poppins(
                color: color0,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: widget.isMoving ? Colors.grey.shade600 : color4,
            inactiveTrackColor: color0.withValues(alpha: 0.15),
            thumbColor: widget.isMoving ? Colors.grey.shade500 : color4,
            overlayColor: color4.withValues(alpha: 0.15),
            tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 3),
            activeTickMarkColor: color0.withValues(alpha: 0.5),
            inactiveTickMarkColor: color0.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: _value,
            min: 0,
            max: 100,
            divisions: 4,
            onChanged:
                widget.isMoving ? null : (v) => setState(() => _value = v),
            onChangeEnd:
                widget.isMoving ? null : (v) => widget.onChangeEnd(v.toInt()),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: ['0', '25', '50', '75', '100']
              .map((l) => Text(
                    l,
                    style: TextStyle(
                      fontSize: 10,
                      color: color0.withValues(alpha: 0.4),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}
