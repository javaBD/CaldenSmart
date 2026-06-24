import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../aws/dynamo/dynamo.dart';
import '../aws/mqtt/mqtt.dart';
import '../master.dart';
import 'package:caldensmart/logger.dart';

class LoadingPage extends StatefulWidget {
  const LoadingPage({super.key});
  @override
  LoadState createState() => LoadState();
}

class LoadState extends State<LoadingPage> {
  BluetoothManager bluetoothManager = BluetoothManager();
  String _dots = '';
  int dot = 0;
  late Timer _dotTimer;
  final pc = DeviceManager.getProductCode(deviceName);
  final sn = DeviceManager.extractSerialNumber(deviceName);
  bool riego = false;

  @override
  void initState() {
    super.initState();
    printLog.i('HOSTIAAAAAAAAAAAAAAAAAAAAAAAA');

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

    precharge().then((precharge) {
      if (precharge == true) {
        showToast('Dispositivo conectado exitosamente');
        if (riego) {
          navigatorKey.currentState?.pushReplacementNamed('/riego');
          return;
        }

        switch (pc) {
          case '022000_IOT' || '027000_IOT':
            navigatorKey.currentState?.pushReplacementNamed('/calefactor');
            break;
          case '015773_IOT':
            navigatorKey.currentState?.pushReplacementNamed('/detector');
            break;
          case '020010_IOT':
            navigatorKey.currentState?.pushReplacementNamed('/domotica');
            break;
          case '020020_IOT':
            navigatorKey.currentState?.pushReplacementNamed('/modulo');
            break;
          case '024011_IOT':
            navigatorKey.currentState?.pushReplacementNamed('/roller');
            break;
          case '027313_IOT':
            navigatorKey.currentState?.pushReplacementNamed('/rele1i1o');
            break;
          case '028000_IOT':
            navigatorKey.currentState?.pushReplacementNamed('/heladera');
            break;
          case '023430_IOT':
            navigatorKey.currentState?.pushReplacementNamed('/termometro');
            break;
          case '027345_IOT':
            navigatorKey.currentState?.pushReplacementNamed('/termotanque');
            break;
        }
      } else {
        showToast('Error en el dispositivo, intente nuevamente');
        bluetoothManager.device.disconnect();
      }
    });
  }

  @override
  void dispose() {
    _dotTimer.cancel();
    super.dispose();
  }

  Future<bool> precharge() async {
    try {
      printLog.i('Estoy precargando');

      // ── WAVE 0: BLE setup (secuencial — protocolo lo exige) ──────────────────
      android ? await bluetoothManager.device.requestMtu(255) : null;
      toolsValues = await bluetoothManager.toolsUuid.read();
      printLog.i('Valores tools: $toolsValues');
      printLog.i('Valores info: $infoValues');

      // ── WAVE 1: Todas independientes entre sí → paralelo total ───────────────
      // safeAddDevice lee Alexa-Devices (distinta tabla que queryItems)
      // addToActiveUsers escribe un campo distinto en sime-domotica
      final addF = safeAddDevice(currentUserEmail, deviceName);
      final activeF = addToActiveUsers(pc, sn, currentUserEmail);
      final posF = Geolocator.getCurrentPosition();
      final specialF = isSpecialUser(currentUserEmail);
      final firmwareF = _safeFetchFirmware(pc, hardwareVersion);

      await Future.wait([
        queryItems(pc, sn), // void — popula globalDATA
        addF,
        activeF, // void — no result needed
        posF,
        specialF,
        firmwareF,
      ]);

      // Resultados de Wave 1 (todos ya resueltos, await es instantáneo)
      final String addResult = await addF;
      final Position position = await posF;
      specialUser = await specialF;
      final String? firmwareFile = await firmwareF;

      // ── Campos sincrónicos — globalDATA ya populado ──────────────────────────
      riego = globalDATA['$pc/$sn']?['riegoActive'] ?? false;
      labProcessFinished =
          globalDATA['$pc/$sn']?['LabProcessFinished'] ?? false;
      discNotfActivated = configNotiDsc.keys.toList().contains(deviceName);
      quickAccesActivated = quickAccess.contains(deviceName);
      printLog.i('Riego activo: $riego', color: 'Naranja');
      printLog.i('Usuario especial: $specialUser');

      // Parse toolsValues (sincrónico)
      var parts3 = utf8.decode(toolsValues).split(':');
      final match = RegExp(r'\((\d+)\)').firstMatch(parts3[2]);
      int users = int.parse(match!.group(1).toString());
      lastUser = users;
      userConnected = users > 1;
      printLog.i('Hay $users conectados');

      // Resultado safeAddDevice
      switch (addResult) {
        case 'added':
          todosLosDispositivos.add(MapEntry('individual', deviceName));
          topicsToSub.add('devices_tx/$pc/$sn');
          subToTopicMQTT('devices_tx/$pc/$sn');
          printLog.i('Dispositivo $deviceName agregado exitosamente');
        case 'exists':
          printLog.i('Dispositivo $deviceName ya estaba registrado');
        case 'error':
          printLog.e(
              'No se pudo agregar el dispositivo $deviceName de forma segura');
      }

      // Firmware
      if (firmwareFile != null) {
        lastSV = Versioner.extractSV(firmwareFile, hardwareVersion);
        printLog.i('Ultimo firmware: $lastSV', color: 'Naranja');
        if (lastSV != null) {
          shouldUpdateDevice =
              (lastSV != softwareVersion) || softwareVersion.contains('_F');
        }
      } else {
        lastSV = null;
        shouldUpdateDevice = false;
      }

      // ── WAVE 2: Escrituras post-globalDATA + GPS ──────────────────────────────
      final needsVersionUpdate =
          softwareVersion != globalDATA['$pc/$sn']?['SoftwareVersion'] ||
              hardwareVersion != globalDATA['$pc/$sn']?['HardwareVersion'];

      final adminF = checkAdminTimePermission(deviceName);

      final location = extractCoordinates(
          globalDATA['$pc/$sn']?['deviceLocation'] ?? 'unknown');

      final shouldUpdateLocation = location == null ||
          Geolocator.distanceBetween(
                position.latitude,
                position.longitude,
                location['lat']!,
                location['lon']!,
              ) >
              50;

      await Future.wait([
        if (shouldUpdateLocation) saveLocation(pc, sn, position.toString()),
        adminF,
        if (needsVersionUpdate)
          putVersions(pc, sn, hardwareVersion, softwareVersion)
        else
          Future.value(),
      ]);

      canUseDevice = await adminF;

      if (needsVersionUpdate) {
        globalDATA.putIfAbsent('$pc/$sn', () => {}).addAll({
          'SoftwareVersion': softwareVersion,
          'HardwareVersion': hardwareVersion
        });
      }

      // ── WAVE 3: Lecturas BLE por tipo (secuencial — stack BLE) ───────────────
      switch (pc) {
        case '022000_IOT' || '027000_IOT' || '027345_IOT':
          varsValues = await bluetoothManager.varsUuid.read();
          var parts2 = utf8.decode(varsValues).split(':');
          printLog.i('Valores Vars: $parts2', color: 'Naranja');

          if (parts2[0] == '0' || parts2[0] == '1') {
            distanceControlActive =
                globalDATA['$pc/$sn']?['distanceControlActive'] ?? false;
            tempValue = double.parse(parts2[1]);
            turnOn = parts2[2] == '1';
            trueStatus = parts2[4] == '1';
            nightMode = parts2[5] == '1';
            actualTemp = parts2[6];
            printLog.i('Estado: $turnOn');
          } else {
            distanceControlActive =
                globalDATA['$pc/$sn']?['distanceControlActive'] ?? false;
            tempValue = double.parse(parts2[0]);
            turnOn = parts2[1] == '1';
            trueStatus = parts2[3] == '1';
            nightMode = parts2[4] == '1';
            actualTemp = parts2[5];
            printLog.i('Estado: $turnOn');
          }

          owner = globalDATA['$pc/$sn']!['owner'] ?? '';
          printLog.i('Owner actual: $owner');
          adminDevices =
              (globalDATA['$pc/$sn']?['secondary_admin'] as List<dynamic>?)
                      ?.cast<String>() ??
                  [];
          printLog.i('Administradores: $adminDevices');

          if (owner != '') {
            if (owner == currentUserEmail) {
              deviceOwner = true;
            } else {
              deviceOwner = false;
              secondaryAdmin = adminDevices.contains(currentUserEmail);
            }
          } else {
            deviceOwner = true;
          }

          if (payAT) {
            activatedAT = globalDATA['$pc/$sn']?['AT'] ?? false;
            tenant = globalDATA['$pc/$sn']?['tenant'] == currentUserEmail;
          } else {
            activatedAT = false;
            tenant = false;
          }

          distOffValue = globalDATA['$pc/$sn']!['distanceOff'] ?? 100.0;
          distOnValue = globalDATA['$pc/$sn']!['distanceOn'] ?? 3000.0;

          globalDATA
              .putIfAbsent('$pc/$sn', () => {})
              .addAll({'w_status': turnOn, 'f_status': trueStatus});

        case '015773_IOT':
          workValues = await bluetoothManager.workUuid.read();
          printLog.i('Valores work: $workValues');

          ppmCO = workValues[5] + (workValues[6] << 8);
          ppmCH4 = workValues[7] + (workValues[8] << 8);
          picoMaxppmCO = workValues[9] + (workValues[10] << 8);
          picoMaxppmCH4 = workValues[11] + (workValues[12] << 8);
          promedioppmCO = workValues[17] + (workValues[18] << 8);
          promedioppmCH4 = workValues[19] + (workValues[20] << 8);
          daysToExpire = workValues[21] + (workValues[22] << 8);

          globalDATA.putIfAbsent('$pc/$sn', () => {}).addAll({
            'ppmCO': ppmCO,
            'ppmCH4': ppmCH4,
            'alert': workValues[4] == 1,
          });

        case '020010_IOT':
          ioValues = await bluetoothManager.ioUuid.read();
          printLog.i('Valores IO: $ioValues || ${utf8.decode(ioValues)}');
          varsValues = await bluetoothManager.varsUuid.read();
          printLog.i('Valores VARS: $varsValues || ${utf8.decode(varsValues)}');

          distanceControlActive =
              globalDATA['$pc/$sn']?['distanceControlActive'] ?? false;

          owner = globalDATA['$pc/$sn']!['owner'] ?? '';
          printLog.i('Owner actual: $owner');
          adminDevices =
              (globalDATA['$pc/$sn']?['secondary_admin'] as List<dynamic>?)
                      ?.cast<String>() ??
                  [];
          printLog.i('Administradores: $adminDevices');

          if (owner != '') {
            if (owner == currentUserEmail) {
              deviceOwner = true;
            } else {
              deviceOwner = false;
              secondaryAdmin = adminDevices.contains(currentUserEmail);
            }
          } else {
            deviceOwner = true;
          }

          if (payAT) {
            activatedAT = globalDATA['$pc/$sn']?['AT'] ?? false;
            tenant = globalDATA['$pc/$sn']?['tenant'] == currentUserEmail;
          } else {
            activatedAT = false;
            tenant = false;
          }

          distOffValue = globalDATA['$pc/$sn']!['distanceOff'] ?? 100.0;
          distOnValue = globalDATA['$pc/$sn']!['distanceOn'] ?? 3000.0;

        case '020020_IOT':
          ioValues = await bluetoothManager.ioUuid.read();
          printLog.i('Valores IO: $ioValues || ${utf8.decode(ioValues)}');
          varsValues = await bluetoothManager.varsUuid.read();
          printLog.i('Valores VARS: $varsValues || ${utf8.decode(varsValues)}');

          distanceControlActive =
              globalDATA['$pc/$sn']?['distanceControlActive'] ?? false;

          owner = globalDATA['$pc/$sn']!['owner'] ?? '';
          printLog.i('Owner actual: $owner');
          adminDevices =
              (globalDATA['$pc/$sn']?['secondary_admin'] as List<dynamic>?)
                      ?.cast<String>() ??
                  [];
          printLog.i('Administradores: $adminDevices');

          if (owner != '') {
            if (owner == currentUserEmail) {
              deviceOwner = true;
            } else {
              deviceOwner = false;
              secondaryAdmin = adminDevices.contains(currentUserEmail);
            }
          } else {
            deviceOwner = true;
          }

          if (payAT) {
            activatedAT = globalDATA['$pc/$sn']?['AT'] ?? false;
            tenant = globalDATA['$pc/$sn']?['tenant'] == currentUserEmail;
          } else {
            activatedAT = false;
            tenant = false;
          }

          distOffValue = globalDATA['$pc/$sn']!['distanceOff'] ?? 100.0;
          distOnValue = globalDATA['$pc/$sn']!['distanceOn'] ?? 3000.0;

        case '027313_IOT':
          ioValues = await bluetoothManager.ioUuid.read();
          printLog.i('Valores IO: $ioValues || ${utf8.decode(ioValues)}');
          varsValues = await bluetoothManager.varsUuid.read();
          printLog.i('Valores VARS: $varsValues || ${utf8.decode(varsValues)}');

          distanceControlActive =
              globalDATA['$pc/$sn']?['distanceControlActive'] ?? false;
          distOffValue = globalDATA['$pc/$sn']!['distanceOff'] ?? 100.0;
          distOnValue = globalDATA['$pc/$sn']!['distanceOn'] ?? 3000.0;
          isNC = globalDATA['$pc/$sn']!['isNC'] ?? false;

          owner = globalDATA['$pc/$sn']!['owner'] ?? '';
          printLog.i('Owner actual: $owner');
          adminDevices =
              (globalDATA['$pc/$sn']?['secondary_admin'] as List<dynamic>?)
                      ?.cast<String>() ??
                  [];
          printLog.i('Administradores: $adminDevices');

          if (owner != '') {
            if (owner == currentUserEmail) {
              deviceOwner = true;
            } else {
              deviceOwner = false;
              secondaryAdmin = adminDevices.contains(currentUserEmail);
            }
          } else {
            deviceOwner = true;
          }

          if (payAT) {
            activatedAT = globalDATA['$pc/$sn']?['AT'] ?? false;
            tenant = globalDATA['$pc/$sn']?['tenant'] == currentUserEmail;
          } else {
            activatedAT = false;
            tenant = false;
          }

        case '024011_IOT':
          varsValues = await bluetoothManager.varsUuid.read();
          printLog.i('Valores VARS: $varsValues || ${utf8.decode(varsValues)}');

          distanceControlActive =
              globalDATA['$pc/$sn']?['distanceControlActive'] ?? false;

          owner = globalDATA['$pc/$sn']!['owner'] ?? '';
          printLog.i('Owner actual: $owner');
          adminDevices =
              (globalDATA['$pc/$sn']?['secondary_admin'] as List<dynamic>?)
                      ?.cast<String>() ??
                  [];
          printLog.i('Administradores: $adminDevices');

          if (owner != '') {
            if (owner == currentUserEmail) {
              deviceOwner = true;
            } else {
              deviceOwner = false;
              secondaryAdmin = adminDevices.contains(currentUserEmail);
            }
          } else {
            deviceOwner = true;
          }

          if (payAT) {
            activatedAT = globalDATA['$pc/$sn']?['AT'] ?? false;
            tenant = globalDATA['$pc/$sn']?['tenant'] == currentUserEmail;
          } else {
            activatedAT = false;
            tenant = false;
          }

          rollerSavedLength = globalDATA['$pc/$sn']!['rollerSavedLength'] ?? '';

        case '028000_IOT':
          varsValues = await bluetoothManager.varsUuid.read();
          var parts2 = utf8.decode(varsValues).split(':');
          printLog.i('Valores Vars: $parts2');

          distanceControlActive =
              globalDATA['$pc/$sn']?['distanceControlActive'] ?? false;
          turnOn = parts2[2] == '1';
          trueStatus = parts2[4] == '1';
          actualTemp = parts2[5];
          printLog.i('Estado: $turnOn');

          owner = globalDATA['$pc/$sn']!['owner'] ?? '';
          printLog.i('Owner actual: $owner');
          adminDevices =
              (globalDATA['$pc/$sn']?['secondary_admin'] as List<dynamic>?)
                      ?.cast<String>() ??
                  [];
          printLog.i('Administradores: $adminDevices');

          if (owner != '') {
            if (owner == currentUserEmail) {
              deviceOwner = true;
            } else {
              deviceOwner = false;
              secondaryAdmin = adminDevices.contains(currentUserEmail);
            }
          } else {
            deviceOwner = true;
          }

          if (payAT) {
            activatedAT = globalDATA['$pc/$sn']?['AT'] ?? false;
            tenant = globalDATA['$pc/$sn']?['tenant'] == currentUserEmail;
          } else {
            activatedAT = false;
            tenant = false;
          }

          distOffValue = globalDATA['$pc/$sn']!['distanceOff'] ?? 100.0;
          distOnValue = globalDATA['$pc/$sn']!['distanceOn'] ?? 3000.0;

          globalDATA
              .putIfAbsent('$pc/$sn', () => {})
              .addAll({'w_status': turnOn, 'f_status': trueStatus});

        case '023430_IOT':
          varsValues = await bluetoothManager.varsUuid.read();
          var partes = utf8.decode(varsValues).split(':');
          printLog.i('Valores VARS: $varsValues || ${utf8.decode(varsValues)}');
          actualTemp = partes[0];
          awsInit = partes[2] == '1';
          alertMaxFlag = partes[3] == '1';
          alertMinFlag = partes[4] == '1';
          alertMaxTemp = partes[5];
          alertMinTemp = partes[6];
          termometroInitialized = partes[8] == '1';

        default:
          printLog.i('Dispositivo no reconocido');
          return false;
      }

      analizePayment(pc, sn); // fire-and-forget

      return true;
    } catch (e, stackTrace) {
      printLog.e('Error en la precarga $e $stackTrace');
      showToast('Error en la precarga');
      return false;
    }
  }

// ── Helper privado: firmware fetch con error handling propio ─────────────────
  Future<String?> _safeFetchFirmware(String pc, String hv) async {
    try {
      return await Versioner.fetchLatestFirmwareFile(pc, hv);
    } catch (e) {
      printLog.e('No se pudo verificar la versión de firmware desde GitHub: $e',
          color: 'Amarillo');
      printLog.i('Continuando sin verificación de actualizaciones...',
          color: 'Verde');
      return null;
    }
  }

//!Visual
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
                const SizedBox(height: 20),
                RichText(
                  text: TextSpan(
                    text: 'Cargando',
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
                  ),
                ),
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
