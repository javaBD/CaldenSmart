import 'dart:convert';

import 'package:caldensmart/Global/manager_screen.dart';
import 'package:caldensmart/aws/dynamo/dynamo.dart';
import 'package:caldensmart/logger.dart';
import 'package:caldensmart/master.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hugeicons/hugeicons.dart';

class TermometroPage extends ConsumerStatefulWidget {
  const TermometroPage({super.key});
  @override
  ConsumerState<TermometroPage> createState() => TermometroPageState();
}

class TermometroPageState extends ConsumerState<TermometroPage> {
  final PageController _pageController = PageController();
  final String pc = DeviceManager.getProductCode(deviceName);
  final String sn = DeviceManager.extractSerialNumber(deviceName);
  int _selectedIndex = 0;
  bool _isAnimating = false;
  bool _isTutorialActive = false;
  List<TutorialItem> items = [];
  Map<String, double> _historicTemp = {};
  bool _loadingHistoric = true;

  void initItems() {
    items.addAll({
      TutorialItem(
        globalKey: keys['termometro:estado']!,
        borderRadius: const Radius.circular(30),
        shapeFocus: ShapeFocus.roundedSquare,
        fullBackground: true,
        contentPosition: ContentPosition.above,
        focusMargin: 15.0,
        pageIndex: 0,
        child: const TutorialItemContent(
          title: 'Termómetro',
          content:
              'En esta pantalla podrás ver los datos del termómetro a tiempo real',
        ),
      ),
      TutorialItem(
        globalKey: keys['termometro:temperaturaActual']!,
        borderRadius: const Radius.circular(30),
        shapeFocus: ShapeFocus.roundedSquare,
        contentPosition: ContentPosition.below,
        focusMargin: 15.0,
        pageIndex: 0,
        child: const TutorialItemContent(
          title: 'Temperatura Actual',
          content:
              'En este apartado podrás ver la temperatura actual del termómetro',
        ),
      ),
      TutorialItem(
        globalKey: keys['termometro:alertaMaxima']!,
        borderRadius: const Radius.circular(30),
        shapeFocus: ShapeFocus.roundedSquare,
        contentPosition: ContentPosition.above,
        focusMargin: 15.0,
        pageIndex: 0,
        contentOffsetY: -100,
        child: const TutorialItemContent(
          title: 'Alertas',
          content:
              'El termómetro en caso de estar por encima o por debajo de los valores establecidos, te enviará una alerta como la siguiente...',
        ),
      ),
      TutorialItem(
        globalKey: keys['termometro:ejemploAlerta']!,
        borderRadius: const Radius.circular(30),
        shapeFocus: ShapeFocus.roundedSquare,
        contentPosition: ContentPosition.below,
        focusMargin: 15.0,
        pageIndex: 0,
        fullBackground: true,
        onStepReached: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                showNotification(
                    '¡ALERTA DE TEMPERATURA EN ${nicknamesMap[deviceName] ?? deviceName}!',
                    'Se detectó temperatura MÍNIMA alcanzada.\nA las ${DateTime.now().hour >= 10 ? DateTime.now().hour : '0${DateTime.now().hour}'}:${DateTime.now().minute >= 10 ? DateTime.now().minute : '0${DateTime.now().minute}'} del ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                    soundOfNotification[
                            DeviceManager.getProductCode(deviceName)] ??
                        'alarm2');
              });
            }
          });
        },
        child: const TutorialItemContent(
          title: 'Ejemplo de alerta',
          content: '',
        ),
      ),
      TutorialItem(
        globalKey: keys['termometro:configAlertas']!,
        borderRadius: const Radius.circular(30),
        shapeFocus: ShapeFocus.roundedSquare,
        fullBackground: true,
        contentPosition: ContentPosition.above,
        focusMargin: 15.0,
        pageIndex: 1,
        child: const TutorialItemContent(
          title: 'Estado del equipo',
          content:
              'En esta pantalla podrás configurar las alertas del termómetro',
        ),
      ),
      TutorialItem(
        globalKey: keys['termometro:configMax']!,
        borderRadius: const Radius.circular(30),
        shapeFocus: ShapeFocus.roundedSquare,
        contentPosition: ContentPosition.below,
        focusMargin: 15.0,
        pageIndex: 1,
        child: const TutorialItemContent(
          title: 'Configuración máxima',
          content:
              'Configura la alerta máxima del termómetro, si se alcanza este valor, se enviará una alerta',
        ),
      ),
      TutorialItem(
        globalKey: keys['termometro:configMin']!,
        borderRadius: const Radius.circular(30),
        shapeFocus: ShapeFocus.roundedSquare,
        contentPosition: ContentPosition.above,
        contentOffsetY: -100,
        focusMargin: 15.0,
        pageIndex: 1,
        child: const TutorialItemContent(
          title: 'Configuración mínima',
          content:
              'Configura la alerta mínima del termómetro, si se alcanza este valor, se enviará una alerta como la siguiente',
        ),
      ),
      TutorialItem(
        globalKey: keys['termometro:historialTemperatura']!,
        borderRadius: const Radius.circular(30),
        shapeFocus: ShapeFocus.roundedSquare,
        contentPosition: ContentPosition.below,
        focusMargin: 15.0,
        pageIndex: 2,
        fullBackground: true,
        child: const TutorialItemContent(
          title: 'Historial de temperatura',
          content:
              'En esta pantalla se guardan los datos tomados por el equipo',
        ),
      ),
      TutorialItem(
        globalKey: keys['termometro:graficoTemperatura']!,
        borderRadius: const Radius.circular(30),
        shapeFocus: ShapeFocus.roundedSquare,
        contentPosition: ContentPosition.above,
        fullBackground: true,
        focusMargin: 15.0,
        pageIndex: 2,
        child: const TutorialItemContent(
          title: 'Grafico de temperatura',
          content:
              'Aquí podrás ver el gráfico con los datos históricos de temperatura',
        ),
      ),
      TutorialItem(
        globalKey: keys['termometro:ofrecerPremium']!,
        borderRadius: const Radius.circular(30),
        shapeFocus: ShapeFocus.roundedSquare,
        contentPosition: ContentPosition.below,
        focusMargin: 15.0,
        pageIndex: 2,
        fullBackground: true,
        buttonAction: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: color0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 17),
          ),
          onPressed: () {
            launchEmail(
              'comercial@caldensmart.com',
              'Habilitación para historial premium en $appName',
              '¡Hola! Me comunico porque busco habilitar la opción de "historial premium" en mi equipo ${DeviceManager.getComercialName(deviceName)}\nCódigo de Producto: ${DeviceManager.getProductCode(deviceName)}\nNúmero de Serie: ${DeviceManager.extractSerialNumber(deviceName)}\nDueño actual del equipo: $owner',
            );
          },
          child: const Text(
            'Enviar mail',
            style: TextStyle(color: color1),
          ),
        ),
        child: const TutorialItemContent(
          title: 'Historial premium',
          content:
              'En caso de querer tener el historial premium comuníquese con nuestro mail comercial@caldensmart.com',
        ),
      ),
      if (owner == currentUserEmail) ...{
        TutorialItem(
          globalKey: keys['managerScreen:agregarAdmin']!,
          borderRadius: const Radius.circular(15),
          shapeFocus: ShapeFocus.roundedSquare,
          pageIndex: 3,
          contentPosition: ContentPosition.below,
          buttonAction: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: color0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 17),
            ),
            onPressed: () {
              launchEmail(
                'comercial@caldensmart.com',
                'Habilitación Administradores secundarios extras en $appName',
                '¡Hola! Me comunico porque busco habilitar la opción de "Administradores secundarios extras" en mi equipo ${DeviceManager.getComercialName(deviceName)}\nCódigo de Producto: ${DeviceManager.getProductCode(deviceName)}\nNúmero de Serie: ${DeviceManager.extractSerialNumber(deviceName)}\nDueño actual del equipo: $owner',
              );
            },
            child: const Text(
              'Enviar mail',
              style: TextStyle(color: color1),
            ),
          ),
          child: const TutorialItemContent(
            title: 'Añadir administradores secundarios',
            content:
                'Podrás agregar correos secundarios hasta un límite de tres, en caso de querer extenderlo debes contactarte con comercial@caldensmart.com',
          ),
        ),
        TutorialItem(
          globalKey: keys['managerScreen:verAdmin']!,
          borderRadius: const Radius.circular(15),
          shapeFocus: ShapeFocus.roundedSquare,
          pageIndex: 3,
          contentPosition: ContentPosition.above,
          child: const TutorialItemContent(
            title: 'Ver administradores secundarios',
            content: 'Podrás ver o quitar los correos adicionales añadidos',
          ),
        ),
        TutorialItem(
          globalKey: keys['managerScreen:alquiler']!,
          borderRadius: const Radius.circular(15),
          shapeFocus: ShapeFocus.roundedSquare,
          pageIndex: 3,
          child: const TutorialItemContent(
            title: 'Alquiler temporario',
            content:
                'Puedes agregar el correo de tu inquilino al equipo y ajustarlo',
          ),
        ),
        if (adminDevices.isNotEmpty) ...{
          TutorialItem(
            globalKey: keys['managerScreen:historialAdmin']!,
            borderRadius: const Radius.circular(15),
            shapeFocus: ShapeFocus.roundedSquare,
            pageIndex: 3,
            child: const TutorialItemContent(
              title: 'Historial de administradores secundarios',
              content:
                  'Se veran las acciones ejecutadas por cada uno con su respectiva flecha',
            ),
          ),
          TutorialItem(
            globalKey: keys['managerScreen:horariosAdmin']!,
            borderRadius: const Radius.circular(15),
            shapeFocus: ShapeFocus.roundedSquare,
            pageIndex: 3,
            child: const TutorialItemContent(
              title: 'Horarios de administradores secundarios',
              content:
                  'Configura el rango de horarios y dias que podra accionar el equipo',
            ),
          ),
          TutorialItem(
            globalKey: keys['managerScreen:wifiAdmin']!,
            borderRadius: const Radius.circular(15),
            shapeFocus: ShapeFocus.roundedSquare,
            pageIndex: 3,
            child: const TutorialItemContent(
              title: 'Wifi de administradores secundarios',
              content:
                  'Podras restringirle a los administradores secundarios el uso del menu wifi',
            ),
          ),
        },
      },
      TutorialItem(
        globalKey: keys['managerScreen:desconexionNotificacion']!,
        borderRadius: const Radius.circular(20),
        shapeFocus: ShapeFocus.roundedSquare,
        pageIndex: 3,
        child: const TutorialItemContent(
          title: 'Notificación de desconexión',
          content:
              'Puedes establecer una alerta si el equipo se desconecta, en el siguiente paso verás un ejemplo de la misma',
        ),
      ),
      TutorialItem(
        globalKey: keys['managerScreen:ejemploNoti']!,
        borderRadius: const Radius.circular(20),
        shapeFocus: ShapeFocus.roundedSquare,
        pageIndex: 3,
        fullBackground: true,
        onStepReached: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                showNotification(
                    '¡El equipo ${nicknamesMap[deviceName] ?? deviceName} se desconecto!',
                    'Se detecto una desconexión a las ${DateTime.now().hour >= 10 ? DateTime.now().hour : '0${DateTime.now().hour}'}:${DateTime.now().minute >= 10 ? DateTime.now().minute : '0${DateTime.now().minute}'} del ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                    'noti');
              });
            }
          });
        },
        child: const TutorialItemContent(
          title: 'Ejemplo de notificación',
          content: '',
        ),
      ),
      TutorialItem(
        globalKey: keys['managerScreen:imagen']!,
        borderRadius: const Radius.circular(30),
        shapeFocus: ShapeFocus.roundedSquare,
        contentPosition: ContentPosition.below,
        focusMargin: 15.0,
        pageIndex: 3,
        child: const TutorialItemContent(
          title: 'Imagen del equipo',
          content:
              'Aquí podrás cambiar la imagen del equipo en el menú principal',
        ),
      ),
    });
  }

  @override
  void initState() {
    super.initState();

    nickname = nicknamesMap[deviceName] ?? deviceName;

    subscribeToWifiStatus();
    subscribeToVars();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      updateWifiValues(toolsValues);
      if (shouldUpdateDevice) {
        await showUpdateDialog(context);
      }
    });

    if (bluetoothManager.hasLoggerBle) getRecordedData(deviceName);

    _loadHistoricTemp();
  }

  Future<void> _loadHistoricTemp() async {
    try {
      final data = await getTemperatureHistory(pc, sn);
      if (mounted) {
        setState(() {
          _historicTemp = data;
          _loadingHistoric = false;
        });
      }
    } catch (e) {
      printLog.e('Error cargando histórico de temperatura: $e');
      if (mounted) {
        setState(() {
          _loadingHistoric = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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

  void updateWifiValues(List<int> data) {
    var fun = utf8.decode(data); //Wifi status | wifi ssid | ble status(users)
    fun = fun.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
    // printLog.i(fun);
    var parts = fun.split(':');
    final regex = RegExp(r'\((\d+)\)');
    final match = regex.firstMatch(parts[2]);
    int users = int.parse(match!.group(1).toString());
    // printLog.i('Hay $users conectados');
    userConnected = users > 1;

    final wifiNotifier = ref.read(wifiProvider.notifier);

    if (parts[0] == 'WCS_CONNECTED') {
      atemp = false;
      nameOfWifi = parts[1];
      isWifiConnected = true;
      // printLog.i('sis $isWifiConnected');
      errorMessage = '';
      errorSintax = '';
      werror = false;
      parts.length > 3
          ? signalPower = int.tryParse(parts[3]) ?? -30
          : signalPower = -30;
      parts.length > 4 ? wifiUnstable = parts[4] == '1' : wifiUnstable = false;

      wifiNotifier.updateStatus(
          'CONECTADO', Colors.green, wifiPower(signalPower));
    } else if (parts[0] == 'WCS_DISCONNECTED') {
      isWifiConnected = false;
      // printLog.i('non $isWifiConnected');

      nameOfWifi = '';

      wifiNotifier.updateStatus(
          'DESCONECTADO', Colors.red, HugeIcons.strokeRoundedWifiOff02);

      if (atemp) {
        setState(() {
          wifiNotifier.updateStatus(
              'DESCONECTADO', Colors.red, HugeIcons.strokeRoundedAlert02);
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
    // printLog.i('Se subscribio a wifi');
    await bluetoothManager.toolsUuid.setNotifyValue(true);

    final wifiSub =
        bluetoothManager.toolsUuid.onValueReceived.listen((List<int> status) {
      // printLog.i('Llegaron cositas wifi');
      updateWifiValues(status);
    });

    bluetoothManager.device.cancelWhenDisconnected(wifiSub);
  }

  void subscribeToVars() async {
    // printLog.i('Me subscribo a vars');
    await bluetoothManager.varsUuid.setNotifyValue(true);

    final trueStatusSub =
        bluetoothManager.varsUuid.onValueReceived.listen((List<int> status) {
      var parts = utf8.decode(status).split(':');

      setState(() {
        actualTemp = parts[0];
        // offsetTemp = parts[1];
        alertMaxFlag = parts[2] == '1';
        alertMinFlag = parts[3] == '1';
        termometroInitialized = parts[5] == '1';
      });
    });

    bluetoothManager.device.cancelWhenDisconnected(trueStatusSub);
  }

  void _showAlertDialog(String type) {
    String title =
        type == 'max' ? 'Configurar Alerta Máxima' : 'Configurar Alerta Mínima';
    String currentValue = type == 'max' ? alertMaxTemp : alertMinTemp;
    Color dialogColor = type == 'max' ? Colors.red : Colors.orange;

    TextEditingController tempController =
        TextEditingController(text: currentValue);

    showAlertDialog(
      context,
      false,
      Text(
        title,
        style: const TextStyle(color: color0),
      ),
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Introduce el valor de temperatura ${type == 'max' ? 'máxima' : 'mínima'} en grados Celsius',
            style:
                TextStyle(color: color0.withValues(alpha: 0.8), fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextField(
            style: const TextStyle(color: color0),
            cursorColor: dialogColor,
            controller: tempController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: "Ej: 25.5",
              hintStyle: TextStyle(color: color0.withValues(alpha: 0.5)),
              suffixText: "°C",
              suffixStyle: TextStyle(color: dialogColor),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: dialogColor),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: dialogColor, width: 2),
              ),
            ),
          ),
        ],
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
            foregroundColor: WidgetStateProperty.all(dialogColor),
          ),
          child: const Text('Guardar'),
          onPressed: () {
            String newValue = tempController.text.trim();

            // Validar que sea un número válido
            double? tempValue = double.tryParse(newValue);
            if (tempValue == null) {
              // Mostrar error si no es un número válido
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Por favor introduce un número válido'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }

            // Validar límites lógicos entre alertas
            if (type == 'max') {
              // Si existe alerta mínima, la máxima debe ser mayor
              if (alertMinTemp.isNotEmpty) {
                double? minTemp = double.tryParse(alertMinTemp);
                if (minTemp != null && tempValue <= minTemp) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'La alerta máxima debe ser mayor a la mínima ($alertMinTemp°C)'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
              }
            } else {
              // Si existe alerta máxima, la mínima debe ser menor
              if (alertMaxTemp.isNotEmpty) {
                double? maxTemp = double.tryParse(alertMaxTemp);
                if (maxTemp != null && tempValue >= maxTemp) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'La alerta mínima debe ser menor a la máxima ($alertMaxTemp°C)'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
              }
            }

            setState(() {
              if (type == 'max') {
                alertMaxTemp = newValue;
                String data = '$pc[7]($newValue)';
                //printLog.i('Enviando: $data');
                bluetoothManager.toolsUuid.write(data.codeUnits);
              } else {
                alertMinTemp = newValue;
                String data = '$pc[8]($newValue)';
                //printLog.i('Enviando: $data');
                bluetoothManager.toolsUuid.write(data.codeUnits);
              }
            });
            // printLog.i(
            //     'Nuevo valor de alerta ${type == 'max' ? 'máxima' : 'mínima'}: $newValue°C');

            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  Widget _buildHistorialPage() {
    final String pc = DeviceManager.getProductCode(deviceName);
    final String sn = DeviceManager.extractSerialNumber(deviceName);

    // historicTempPremium sigue viniendo en globalDATA — es un boolean chico
    // que NO migró a tabla aparte (no contribuía al costo y mantenerlo evita
    // un read extra).
    bool historicTempPremium =
        globalDATA['$pc/$sn']?['historicTempPremium'] ?? false;

    // Mientras se carga, mostrar un spinner.
    if (_loadingHistoric) {
      return Container(
        color: color0,
        child: const Center(
          child: CircularProgressIndicator(color: color1),
        ),
      );
    }

    // Convertir el mapa cargado a lista de puntos ordenados por timestamp.
    List<MapEntry<DateTime, double>> dataPoints = [];

    _historicTemp.forEach((key, value) {
      try {
        // Formato esperado: "2026-04-30 12:34:56" (UTC).
        // Convertir a hora de Argentina (UTC-3).
        DateTime timestampUTC = DateTime.parse(key);
        DateTime timestamp = timestampUTC.subtract(const Duration(hours: 3));

        dataPoints.add(MapEntry(timestamp, value));
      } catch (e) {
        printLog.e('Error parsing timestamp "$key": $e');
      }
    });

    // Ordenar por timestamp
    dataPoints.sort((a, b) => a.key.compareTo(b.key));

    // printLog.i('DataPoints count: ${dataPoints.length}');

    if (dataPoints.isEmpty) {
      return Container(
        color: color0,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(HugeIcons.strokeRoundedInformationCircle,
                  size: 80, color: color1.withValues(alpha: 0.5)),
              const SizedBox(height: 20),
              Text(
                'No hay datos de historial disponibles',
                style: TextStyle(
                  color: color1.withValues(alpha: 0.8),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Dispositivo: $pc/$sn',
                style: TextStyle(
                  color: color1.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _HistorialChart(
      dataPoints: dataPoints,
      isPremium: historicTempPremium,
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle poppinsStyle = GoogleFonts.poppins();
    final wifiState = ref.watch(wifiProvider);

    if (!canUseDevice) {
      return const NotAllowedScreen();
    }

    if (userConnected && lastUser > 1) {
      return const DeviceInUseScreen();
    }

    if (specialUser && !labProcessFinished) {
      return const LabProcessNotFinished();
    }

    final List<Widget> pages = [
      //*- Página 1 - Estado del dispositivo -*\\
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenHeight = constraints.maxHeight;
            final tempCardHeight = screenHeight * 0.45;

            return Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                // Temperatura Actual - Más grande
                AnimatedOpacity(
                  opacity: 1.0,
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeInOut,
                  child: SizedBox(
                    height: tempCardHeight,
                    child: Card(
                      color: color1,
                      elevation: 6,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                        side: const BorderSide(
                          color: color4,
                          width: 2,
                        ),
                      ),
                      child: Padding(
                        key: keys['termometro:temperaturaActual']!,
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const ImageIcon(AssetImage(CaldenIcons.termometro),
                                size: 80, color: color4),
                            const SizedBox(height: 16),
                            Text(
                              termometroInitialized
                                  ? 'Temperatura Actual'
                                  : 'Inicializando...',
                              style: const TextStyle(
                                color: color0,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Flexible(
                              key: keys['termometro:estado']!,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: termometroInitialized
                                    ? Text(
                                        actualTemp.isEmpty
                                            ? "-"
                                            : "$actualTemp°C",
                                        style: const TextStyle(
                                          color: color4,
                                          fontSize: 48,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      )
                                    : const CircularProgressIndicator(
                                        color: color4,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Alertas en una fila horizontal con tamaño fijo
                SizedBox(
                  key: keys['termometro:alertaMaxima']!,
                  height: screenHeight * 0.25,
                  child: Row(
                    children: [
                      // Alerta Mínima
                      Expanded(
                        child: AnimatedOpacity(
                          opacity: 1.0,
                          duration: const Duration(milliseconds: 800),
                          curve: Curves.easeInOut,
                          child: Card(
                            color: color1,
                            elevation: 6,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                              side: BorderSide(
                                color: alertMinFlag ? color4 : color0,
                                width: 2,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 500),
                                    transitionBuilder: (Widget child,
                                        Animation<double> animation) {
                                      return ScaleTransition(
                                          scale: animation, child: child);
                                    },
                                    child: alertMinFlag
                                        ? const Icon(
                                            HugeIcons.strokeRoundedAlert02,
                                            key: ValueKey('alert'),
                                            color: color4,
                                            size: 32,
                                          )
                                        : const ImageIcon(
                                            AssetImage(
                                                CaldenIcons.termometroMenos),
                                            key: ValueKey('termometro'),
                                            color: color0,
                                            size: 32,
                                          ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Flexible(
                                    child: Text(
                                      'Alerta Mínima',
                                      style: TextStyle(
                                        color: color0,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Flexible(
                                    child: Text(
                                      alertMinTemp.isEmpty
                                          ? "No configurado"
                                          : "$alertMinTemp°C",
                                      style: TextStyle(
                                        color: color0.withValues(alpha: 0.8),
                                        fontSize: 11,
                                      ),
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                          width: 12, key: keys['termometro:ejemploAlerta']!),
                      // Alerta Máxima
                      Expanded(
                        child: AnimatedOpacity(
                          opacity: 1.0,
                          duration: const Duration(milliseconds: 800),
                          curve: Curves.easeInOut,
                          child: Card(
                            color: color1,
                            elevation: 6,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                              side: BorderSide(
                                color: alertMaxFlag ? color3 : color0,
                                width: 2,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 500),
                                    transitionBuilder: (Widget child,
                                        Animation<double> animation) {
                                      return ScaleTransition(
                                          scale: animation, child: child);
                                    },
                                    child: alertMaxFlag
                                        ? const Icon(
                                            HugeIcons.strokeRoundedAlert02,
                                            key: ValueKey('alertMax'),
                                            color: color3,
                                            size: 32,
                                          )
                                        : const ImageIcon(
                                            AssetImage(
                                                CaldenIcons.termometroPlus),
                                            key: ValueKey('termometroPlus'),
                                            color: color0,
                                            size: 32,
                                          ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Flexible(
                                    child: Text(
                                      'Alerta Máxima',
                                      style: TextStyle(
                                        color: color0,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Flexible(
                                    child: Text(
                                      alertMaxTemp.isEmpty
                                          ? "No configurado"
                                          : "$alertMaxTemp°C",
                                      style: TextStyle(
                                        color: color0.withValues(alpha: 0.8),
                                        fontSize: 11,
                                      ),
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),

      //*- Página 2: Configuraciones -*\\
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenHeight = constraints.maxHeight;
            final cardHeight = screenHeight * 0.25;

            return Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Configuración Alerta Máxima
                AnimatedOpacity(
                  opacity: 1.0,
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeInOut,
                  child: GestureDetector(
                    onTap: () => _showAlertDialog('max'),
                    child: SizedBox(
                      height: cardHeight,
                      child: Card(
                        key: keys['termometro:configAlertas']!,
                        color: color1,
                        elevation: 6,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                          side: BorderSide(
                            color: alertMaxFlag ? color3 : color0,
                            width: 2,
                          ),
                        ),
                        child: Padding(
                          key: keys['termometro:configMax']!,
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 500),
                                transitionBuilder: (Widget child,
                                    Animation<double> animation) {
                                  return ScaleTransition(
                                      scale: animation, child: child);
                                },
                                child: alertMaxFlag
                                    ? Icon(
                                        HugeIcons.strokeRoundedAlert02,
                                        key: ValueKey<bool>(alertMaxFlag),
                                        color: color3,
                                        size: 50,
                                      )
                                    : ImageIcon(
                                        const AssetImage(
                                            CaldenIcons.termometroPlus),
                                        key: ValueKey<bool>(alertMaxFlag),
                                        color: color0,
                                        size: 50,
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            'Configurar Alerta Máxima',
                                            style: TextStyle(
                                              color: color0,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(
                                          HugeIcons.strokeRoundedPen01,
                                          color: color0.withValues(alpha: 0.6),
                                          size: 16,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      alertMaxFlag ? 'ACTIVADA' : 'Normal',
                                      style: TextStyle(
                                        color: alertMaxFlag ? color3 : color0,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Límite: ${alertMaxTemp.isEmpty ? "No configurado" : "$alertMaxTemp°C"}',
                                      style: TextStyle(
                                        color: color0.withValues(alpha: 0.8),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Configuración Alerta Mínima
                AnimatedOpacity(
                  opacity: 1.0,
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeInOut,
                  child: GestureDetector(
                    onTap: () => _showAlertDialog('min'),
                    child: SizedBox(
                      height: cardHeight,
                      child: Card(
                        color: color1,
                        elevation: 6,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                          side: BorderSide(
                            color: alertMinFlag ? color4 : color0,
                            width: 2,
                          ),
                        ),
                        child: Padding(
                          key: keys['termometro:configMin']!,
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 500),
                                transitionBuilder: (Widget child,
                                    Animation<double> animation) {
                                  return ScaleTransition(
                                      scale: animation, child: child);
                                },
                                child: alertMinFlag
                                    ? Icon(
                                        HugeIcons.strokeRoundedAlert02,
                                        key: ValueKey<bool>(alertMinFlag),
                                        color: color4,
                                        size: 50,
                                      )
                                    : ImageIcon(
                                        const AssetImage(
                                            CaldenIcons.termometroMenos),
                                        key: ValueKey<bool>(alertMinFlag),
                                        color: color0,
                                        size: 50,
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            'Configurar Alerta Mínima',
                                            style: TextStyle(
                                              color: color0,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(
                                          HugeIcons.strokeRoundedPen01,
                                          color: color0.withValues(alpha: 0.6),
                                          size: 16,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      alertMinFlag ? 'ACTIVADA' : 'Normal',
                                      style: TextStyle(
                                        color: alertMinFlag ? color4 : color0,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Límite: ${alertMinTemp.isEmpty ? "No configurado" : "$alertMinTemp°C"}',
                                      style: TextStyle(
                                        color: color0.withValues(alpha: 0.8),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 50),
              ],
            );
          },
        ),
      ),

      //*- Página 3: Historial de Temperatura -*\\
      _buildHistorialPage(),

      //*- Página 4: Gestión del Equipo -*\\
      ManagerScreen(deviceName: deviceName),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, A) {
        if (_isTutorialActive) return;
        showDisconnectDialog(context);
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
        appBar: AppBar(
          backgroundColor: color1,
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
                        putNicknames(currentUserEmail, nicknamesMap);
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
                  //key: keys['termometros:titulo']!,
                  child: SizedBox(
                    height: 30,
                    width: 2,
                    child: AutoScrollingText(
                      text: nickname,
                      style: poppinsStyle.copyWith(color: color0),
                      velocity: 50,
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                const Icon(HugeIcons.strokeRoundedPen01,
                    size: 20, color: color0)
              ],
            ),
          ),
          leading: IconButton(
            icon: const Icon(HugeIcons.strokeRoundedArrowLeft02),
            color: color0,
            onPressed: () {
              if (_isTutorialActive) return;
              showDisconnectDialog(context);
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
          actions: [
            globalDATA['$pc/$sn']?['cstate'] ?? false
                ? const ImageIcon(
                    AssetImage(CaldenIcons.cloud),
                    color: color0,
                    size: 35,
                  )
                : const ImageIcon(
                    AssetImage(CaldenIcons.cloudOff),
                    color: color0,
                    size: 25,
                  ),
            IconButton(
              //key: keys['termometros:wifi']!,
              icon: wifiState.wifiIcon is String
                  ? ImageIcon(AssetImage(wifiState.wifiIcon),
                      color: color0, size: 24)
                  : Icon(wifiState.wifiIcon, color: color0, size: 24),
              onPressed: () {
                if (_isTutorialActive) return;
                wifiText(context);
              },
            ),
          ],
        ),
        backgroundColor: color0,
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
                  child: SafeArea(
                    child: CurvedNavigationBar(
                      index: _selectedIndex,
                      height: 75.0,
                      items: const <Widget>[
                        ImageIcon(AssetImage(CaldenIcons.termometro),
                            size: 30, color: color0),
                        Icon(HugeIcons.strokeRoundedSlidersHorizontal,
                            size: 30, color: color0),
                        Icon(HugeIcons.strokeRoundedChartLineData01,
                            size: 30, color: color0),
                        Icon(HugeIcons.strokeRoundedSettings02,
                            size: 30, color: color0),
                      ],
                      color: color1,
                      buttonBackgroundColor: color1,
                      backgroundColor: Colors.transparent,
                      animationCurve: Curves.easeInOut,
                      animationDuration: const Duration(milliseconds: 600),
                      onTap: onItemTapped,
                      letIndexChange: (index) => true,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: MediaQuery.of(context).padding.bottom,
                  color: Colors.black,
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
                          //   printLog.i('Tutorial is complete!');
                        },
                      );
                    }
                  });
                },
                backgroundColor: color4,
                shape: const CircleBorder(),
                child: const Icon(HugeIcons.strokeRoundedHelpCircle,
                    size: 30, color: color0),
              ),
            ),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }
}

// Widget para mostrar el gráfico de historial de temperatura
class _HistorialChart extends StatefulWidget {
  final List<MapEntry<DateTime, double>> dataPoints;
  final bool isPremium;

  const _HistorialChart({
    required this.dataPoints,
    required this.isPremium,
  });

  @override
  State<_HistorialChart> createState() => _HistorialChartState();
}

class _HistorialChartState extends State<_HistorialChart> {
  String selectedPeriod = '24h'; // '24h', 'semanal', 'mensual'

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color0,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Título
            Text(
              key: keys['termometro:historialTemperatura']!,
              'Historial de Temperatura',
              style: const TextStyle(
                color: color1,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 0, key: keys['termometro:graficoTemperatura']!),
            SizedBox(height: 20, key: keys['termometro:ofrecerPremium']!),

            // Selector de período (solo si es premium)
            if (widget.isPremium) _buildPeriodSelector(),

            if (widget.isPremium) const SizedBox(height: 20),

            // Gráfico
            Expanded(
              child: _buildChart(),
            ),

            const SizedBox(height: 200),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      decoration: BoxDecoration(
        color: color1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color4, width: 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildPeriodButton('24h', '24 Horas'),
          _buildPeriodButton('semanal', 'Semanal'),
          _buildPeriodButton('mensual', 'Mensual'),
        ],
      ),
    );
  }

  Widget _buildPeriodButton(String period, String label) {
    final bool isSelected = selectedPeriod == period;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            selectedPeriod = period;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color4 : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? color1 : color0,
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChart() {
    // Filtrar datos según el período seleccionado
    List<MapEntry<DateTime, double>> filteredData = _filterDataByPeriod();

    if (filteredData.isEmpty) {
      return Center(
        child: Text(
          'No hay datos para el período seleccionado',
          style: TextStyle(
            color: color1.withValues(alpha: 0.8),
            fontSize: 16,
          ),
        ),
      );
    }

    // Calcular promedios si es semanal o mensual
    List<FlSpot> spots = [];
    List<MapEntry<DateTime, double>> dataForChart = [];

    if (widget.isPremium &&
        (selectedPeriod == 'semanal' || selectedPeriod == 'mensual')) {
      dataForChart = _calculateDailyAverages(filteredData);
      spots = dataForChart
          .asMap()
          .entries
          .map((entry) => FlSpot(entry.key.toDouble(), entry.value.value))
          .toList();
    } else {
      dataForChart = filteredData;
      spots = filteredData
          .asMap()
          .entries
          .map((entry) => FlSpot(entry.key.toDouble(), entry.value.value))
          .toList();
    }

    if (spots.isEmpty) {
      return Center(
        child: Text(
          'No hay suficientes datos',
          style: TextStyle(
            color: color1.withValues(alpha: 0.8),
            fontSize: 16,
          ),
        ),
      );
    }

    // Calcular rango Y (temperatura)
    double minTemp = spots.map((e) => e.y).reduce((a, b) => a < b ? a : b);
    double maxTemp = spots.map((e) => e.y).reduce((a, b) => a > b ? a : b);

    // Redondear hacia abajo para minY y hacia arriba para maxY
    double minY = (minTemp - 2).floorToDouble();
    double maxY = (maxTemp + 2).ceilToDouble();

    // Calcular intervalo para tener valores redondos
    double range = maxY - minY;
    double interval = (range / 5).ceilToDouble();
    if (interval < 1) interval = 1.0;

    return Card(
      color: color1,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: const BorderSide(color: color4, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: true,
              horizontalInterval: interval,
              getDrawingHorizontalLine: (value) {
                return FlLine(
                  color: color0.withValues(alpha: 0.2),
                  strokeWidth: 1,
                );
              },
              getDrawingVerticalLine: (value) {
                return FlLine(
                  color: color0.withValues(alpha: 0.2),
                  strokeWidth: 1,
                );
              },
            ),
            titlesData: FlTitlesData(
              show: true,
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  interval: (spots.length / 4).ceilToDouble(),
                  getTitlesWidget: (value, meta) {
                    if (value.toInt() >= 0 &&
                        value.toInt() < dataForChart.length) {
                      final date = dataForChart[value.toInt()].key;
                      String label = '';

                      if (selectedPeriod == '24h') {
                        label =
                            '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
                      } else if (selectedPeriod == 'semanal') {
                        label = '${date.day}/${date.month}';
                      } else {
                        label = '${date.day}/${date.month}';
                      }

                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: color0.withValues(alpha: 0.7),
                            fontSize: 10,
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: interval,
                  reservedSize: 42,
                  getTitlesWidget: (value, meta) {
                    return Text(
                      '${value.toInt()}°C',
                      style: TextStyle(
                        color: color0.withValues(alpha: 0.7),
                        fontSize: 10,
                      ),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(
              show: true,
              border: Border.all(color: color0.withValues(alpha: 0.3)),
            ),
            minX: 0,
            maxX: spots.length.toDouble() - 1,
            minY: minY,
            maxY: maxY,
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                gradient: const LinearGradient(
                  colors: [color4, color3],
                ),
                barWidth: 3,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: spots.length < 50,
                  getDotPainter: (spot, percent, barData, index) {
                    return FlDotCirclePainter(
                      radius: 3,
                      color: color4,
                      strokeWidth: 1,
                      strokeColor: color0,
                    );
                  },
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    colors: [
                      color4.withValues(alpha: 0.3),
                      color3.withValues(alpha: 0.1),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ],
            lineTouchData: LineTouchData(
              enabled: true,
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (touchedSpot) => color1,
                getTooltipItems: (List<LineBarSpot> touchedSpots) {
                  return touchedSpots.map((LineBarSpot touchedSpot) {
                    final index = touchedSpot.x.toInt();
                    if (index >= 0 && index < dataForChart.length) {
                      final date = dataForChart[index].key;
                      final temp = touchedSpot.y;

                      String dateText;
                      if (selectedPeriod == '24h') {
                        dateText =
                            '${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
                      } else {
                        dateText = '${date.day}/${date.month}/${date.year}';
                      }

                      return LineTooltipItem(
                        '$dateText\n${temp.toStringAsFixed(1)}°C',
                        const TextStyle(
                          color: color0,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      );
                    }
                    return null;
                  }).toList();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<MapEntry<DateTime, double>> _filterDataByPeriod() {
    final now = DateTime.now();
    DateTime cutoffTimestamp;

    switch (selectedPeriod) {
      case '24h':
        cutoffTimestamp = now.subtract(const Duration(hours: 24));
        break;
      case 'semanal':
        cutoffTimestamp = now.subtract(const Duration(days: 7));
        break;
      case 'mensual':
        cutoffTimestamp = now.subtract(const Duration(days: 30));
        break;
      default:
        cutoffTimestamp = now.subtract(const Duration(hours: 24));
    }

    return widget.dataPoints
        .where((entry) => entry.key.isAfter(cutoffTimestamp))
        .toList();
  }

  List<MapEntry<DateTime, double>> _calculateDailyAverages(
      List<MapEntry<DateTime, double>> data) {
    if (data.isEmpty) return [];

    // Tanto semanal como mensual usan promedios diarios
    Map<DateTime, List<double>> buckets = {};

    for (var entry in data) {
      // Agrupar por día (promedios diarios)
      DateTime bucketKey = DateTime(
        entry.key.year,
        entry.key.month,
        entry.key.day,
      );
      buckets.putIfAbsent(bucketKey, () => []).add(entry.value);
    }

    List<MapEntry<DateTime, double>> averages = buckets.entries.map((entry) {
      double avg = entry.value.reduce((a, b) => a + b) / entry.value.length;
      return MapEntry(entry.key, avg);
    }).toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return averages;
  }
}
