import 'dart:convert';

import 'package:caldensmart/aws/dynamo/dynamo.dart';
import 'package:caldensmart/logger.dart';
import 'package:caldensmart/master.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';

class ControlClimaWidget extends StatefulWidget {
  final VoidCallback? onBackToMain;
  final Map<String, dynamic>? eventoExistente;

  const ControlClimaWidget(
      {super.key, this.onBackToMain, this.eventoExistente});

  @override
  ControlClimaWidgetState createState() => ControlClimaWidgetState();
}

class ControlClimaWidgetState extends State<ControlClimaWidget> {
  int currentStep = 0;
  TextEditingController title = TextEditingController();
  List<String> deviceGroup = [];
  Map<String, bool> deviceActions = {};
  String selectedWeatherCondition = '';
  String? nombreOriginal;
  Map<String, bool> _wifiPermissions = {};
  bool _isLoadingPermissions = true;

  String? windDirection;

  final List<String> windDirectionsList = [
    'Todos los origenes',
    'Norte',
    'Noreste',
    'Este',
    'Sureste',
    'Sur',
    'Suroeste',
    'Oeste',
    'Noroeste'
  ];

  @override
  void initState() {
    super.initState();
    _loadWifiPermissions();
    _initializeData();
  }

  void _initializeData() {
    if (widget.eventoExistente != null) {
      title.text = widget.eventoExistente!['title'] ?? '';
      nombreOriginal = title.text;

      selectedWeatherCondition =
          widget.eventoExistente!['condition'] ?? weatherConditions.first;
      windDirection = widget.eventoExistente!['wind_direction'];

      deviceGroup =
          List<String>.from(widget.eventoExistente!['deviceGroup'] ?? []);

      Map<String, bool> savedActions = Map<String, bool>.from(
          widget.eventoExistente!['deviceActions'] ?? {});
      deviceActions.clear();
      savedActions.forEach((key, value) {
        String originalName = key.split(':').first;
        deviceActions[originalName] = value;
      });

      currentStep = 0;
    } else {
      deviceGroup.clear();
      deviceActions.clear();
      currentStep = 0;
      selectedWeatherCondition = weatherConditions.first;
      windDirection = null;
    }
  }

  bool _isValidForClima(String equipo) {
    final displayName = nicknamesMap[equipo] ?? equipo;
    if (displayName.isEmpty) return false;

    final pc = DeviceManager.getProductCode(equipo);
    final sn = DeviceManager.extractSerialNumber(equipo);
    final key = '$pc/$sn';

    if (!_isLoadingPermissions && _wifiPermissions.containsKey(key)) {
      if (_wifiPermissions[key] == false) return false;
    }

    // Excluir detectores, Termometros y patitos
    if (equipo.contains('Detector') ||
        equipo.contains('Termometro') ||
        equipo.contains('Patito')) {
      return false;
    }

    // Para Domotica, Modulo y Rele, verificar que tengan salidas
    if (equipo.contains('Domotica') ||
        equipo.contains('Modulo') ||
        equipo.contains('Rele')) {
      final deviceKey =
          '${DeviceManager.getProductCode(equipo)}/${DeviceManager.extractSerialNumber(equipo)}';
      final deviceDATA = globalDATA[deviceKey] ?? {};

      // Si no tiene pines IO, es válido
      final hasPinsIO = deviceDATA.keys.any((k) => k.startsWith('io'));
      if (!hasPinsIO) return true;

      // Verificar que tenga al menos una salida (pinType = 0)
      final hasSalidas =
          deviceDATA.keys.where((k) => k.startsWith('io')).any((key) {
        final rawData = deviceDATA[key];
        final data = rawData is String ? jsonDecode(rawData) : rawData;
        final pinType = int.tryParse(data['pinType'].toString()) ?? -1;
        return pinType == 0;
      });

      return hasSalidas;
    }

    return true;
  }

  Future<void> _loadWifiPermissions() async {
    Map<String, bool> permissions = {};
    for (var device in filterDevices) {
      String pc = DeviceManager.getProductCode(device);
      String sn = DeviceManager.extractSerialNumber(device);
      String key = '$pc/$sn';
      bool hasPermission = await checkAdminWifiPermission(device);
      permissions[key] = hasPermission;
    }
    if (mounted) {
      setState(() {
        _wifiPermissions = permissions;
        _isLoadingPermissions = false;
      });
    }
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

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color1,
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header con título y navegación
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                children: [
                  Opacity(
                    opacity: currentStep == 0 ? 1.0 : 0.0,
                    child: IconButton(
                      icon: const Icon(HugeIcons.strokeRoundedArrowLeft02),
                      color: color0,
                      onPressed: currentStep == 0
                          ? () {
                              if (widget.onBackToMain != null) {
                                widget.onBackToMain!();
                              }
                            }
                          : null,
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Control por clima',
                        style: GoogleFonts.poppins(
                          color: color0,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // Indicador de pasos
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildStepIndicator(0, 'Condición', currentStep >= 0),
                  Container(
                      width: 30,
                      height: 2,
                      color: currentStep >= 1 ? color4 : color0),
                  _buildStepIndicator(1, 'Dispositivos', currentStep >= 1),
                  Container(
                      width: 30,
                      height: 2,
                      color: currentStep >= 2 ? color4 : color0),
                  _buildStepIndicator(2, 'Acciones', currentStep >= 2),
                  Container(
                      width: 30,
                      height: 2,
                      color: currentStep >= 3 ? color4 : color0),
                  _buildStepIndicator(3, 'Nombre', currentStep >= 3),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Contenido del paso actual
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
                minHeight: 0,
              ),
              child: _buildCurrentStepContent(),
            ),
            const SizedBox(height: 8),

            // Botones de navegación
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (currentStep > 0)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ElevatedButton(
                          onPressed: () => setState(() => currentStep--),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: color0,
                            foregroundColor: color1,
                            padding: const EdgeInsets.symmetric(vertical: 12.0),
                          ),
                          child: const Text('Anterior'),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: currentStep > 0 ? 8.0 : 0),
                      child: ElevatedButton.icon(
                        icon: Icon(currentStep == 3
                            ? HugeIcons.strokeRoundedTick02
                            : HugeIcons.strokeRoundedArrowRight02),
                        label:
                            Text(currentStep == 3 ? 'Confirmar' : 'Continuar'),
                        onPressed:
                            _canContinue() ? () => _handleContinue() : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color0,
                          foregroundColor: color1,
                          disabledForegroundColor:
                              color1.withValues(alpha: 0.5),
                          disabledBackgroundColor: color0,
                          padding: const EdgeInsets.symmetric(vertical: 12.0),
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
    );
  }

  Widget _buildStepIndicator(int step, String label, bool isActive) {
    return Column(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isActive ? color4 : color0,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '${step + 1}',
              style: GoogleFonts.poppins(
                color: color1,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.poppins(
            color: color0,
            fontSize: 9,
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentStepContent() {
    switch (currentStep) {
      case 0:
        return _buildWeatherConditionStep();
      case 1:
        return _buildDeviceSelectionStep();
      case 2:
        return _buildActionConfigurationStep();
      case 3:
        return _buildNameInputStep();
      default:
        return const SizedBox();
    }
  }

  Widget _buildWeatherConditionStep() {
    bool isWindCondition =
        selectedWeatherCondition.toLowerCase().contains('viento') &&
            !selectedWeatherCondition.toLowerCase().contains('sin');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Text(
            'Selecciona la condición climática',
            style: GoogleFonts.poppins(color: color0, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 20),
        Theme(
          data: Theme.of(context).copyWith(
            canvasColor: Colors.white,
          ),
          child: DropdownButtonHideUnderline(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.6,
              decoration: BoxDecoration(
                color: color0.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: color0, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButton<String>(
                  value: selectedWeatherCondition,
                  isExpanded: true,
                  icon: const Icon(
                    HugeIcons.strokeRoundedArrowDown01,
                    color: color0,
                  ),
                  dropdownColor: color1,
                  borderRadius: BorderRadius.circular(15),
                  elevation: 4,
                  style: GoogleFonts.poppins(
                    color: color0,
                    fontSize: 18,
                  ),
                  onChanged: (String? value) {
                    setState(() {
                      selectedWeatherCondition = value!;

                      if (!value.toLowerCase().contains('viento') ||
                          value.toLowerCase().contains('sin')) {
                        windDirection = null;
                      }
                    });
                  },
                  items: weatherConditions
                      .map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            value,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(color: color0),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
        if (isWindCondition) ...[
          const SizedBox(height: 20),
          Center(
            child: Text(
              'Selecciona el origen del viento',
              style: GoogleFonts.poppins(color: color0, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 10),
          Theme(
            data: Theme.of(context).copyWith(canvasColor: Colors.white),
            child: DropdownButtonHideUnderline(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.6,
                decoration: BoxDecoration(
                  color: color0.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: color0, width: 2),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButton<String>(
                    value: windDirection,
                    hint: Center(
                      child: Text("Dirección",
                          style: GoogleFonts.poppins(
                              color: color0.withValues(alpha: 0.5))),
                    ),
                    isExpanded: true,
                    icon: const Icon(HugeIcons.strokeRoundedNavigation04,
                        color: color0),
                    dropdownColor: color1,
                    borderRadius: BorderRadius.circular(15),
                    elevation: 4,
                    style: GoogleFonts.poppins(color: color0, fontSize: 18),
                    onChanged: (String? value) {
                      setState(() {
                        windDirection = value;
                      });
                    },
                    items: windDirectionsList
                        .map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              value,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(color: color0),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildDeviceSelectionStep() {
    if (_isLoadingPermissions) {
      return const Center(child: CircularProgressIndicator(color: color4));
    }
    final validDevices = filterDevices.where((equipo) {
      if (!_isValidForClima(equipo)) return false;
      final deviceKey =
          '${DeviceManager.getProductCode(equipo)}/${DeviceManager.extractSerialNumber(equipo)}';
      final deviceDATA = globalDATA[deviceKey] ?? {};
      final owner = deviceDATA['owner'] ?? '';
      return owner == '' || owner == currentUserEmail;
    }).toList();

    final eventosDisponibles = eventosCreados.where((evento) {
      final eventoType = evento['evento'] as String;
      return eventoType == 'grupo' || eventoType == 'cadena';
    }).toList();

    if (validDevices.isEmpty && eventosDisponibles.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Text(
              'Selecciona al menos un dispositivo o evento',
              style: GoogleFonts.poppins(color: color0, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'No hay dispositivos o eventos válidos disponibles.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: Colors.red,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Text(
            'Selecciona al menos un dispositivo',
            style: GoogleFonts.poppins(color: color0, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: _buildDeviceList(),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildDeviceList() {
    // Filtrar equipos válidos
    final validDevices = filterDevices.where((equipo) {
      if (!_isValidForClima(equipo)) return false;
      final deviceKey =
          '${DeviceManager.getProductCode(equipo)}/${DeviceManager.extractSerialNumber(equipo)}';
      final deviceDATA = globalDATA[deviceKey] ?? {};
      final owner = deviceDATA['owner'] ?? '';
      final admin = deviceDATA['secondary_admin'] ?? [];
      final isnotRiego = deviceDATA['riegoActive'] != true;

      return (owner == '' ||
              owner == currentUserEmail ||
              admin.contains(currentUserEmail)) &&
          isnotRiego;
    }).toList();

    final eventosDisponibles = eventosCreados.where((evento) {
      final eventoType = evento['evento'] as String;
      if (_hasRestrictedDevicesInGroup(evento['deviceGroup'])) return false;
      return eventoType == 'grupo' ||
          eventoType == 'cadena' ||
          eventoType == 'riego';
    }).toList();

    if (validDevices.isEmpty && eventosDisponibles.isEmpty) {
      return [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'No hay dispositivos o eventos válidos disponibles.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: Colors.red,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ];
    }

    List<Widget> widgets = [];

    if (eventosDisponibles.isNotEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Text(
            'EVENTOS DISPONIBLES',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color0.withValues(alpha: 0.9),
              letterSpacing: 1,
            ),
          ),
        ),
      );

      for (final evento in eventosDisponibles) {
        final eventoType = evento['evento'] as String;
        final eventoTitle = evento['title'] as String;
        final isSelected = deviceGroup.contains(eventoTitle);

        widgets.add(
          Container(
            margin: const EdgeInsets.only(bottom: 8.0),
            decoration: BoxDecoration(
              color: isSelected
                  ? color4.withValues(alpha: 0.1)
                  : color0.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(
                color: isSelected ? color4 : color0,
                width: 1.0,
              ),
            ),
            child: ListTile(
              leading: Icon(
                eventoType == 'grupo'
                    ? HugeIcons.strokeRoundedSmartPhone01
                    : eventoType == 'riego'
                        ? HugeIcons.strokeRoundedPlant03
                        : HugeIcons.strokeRoundedLink05,
                color: eventoType == 'grupo'
                    ? color4
                    : eventoType == 'riego'
                        ? Colors.green
                        : Colors.orange,
              ),
              title: Text(
                eventoTitle,
                style: GoogleFonts.poppins(color: color0),
              ),
              subtitle: Text(
                'Evento $eventoType',
                style: GoogleFonts.poppins(
                  color: color0.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
              trailing: Checkbox(
                value: isSelected,
                activeColor: color4,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      deviceGroup.add(eventoTitle);
                    } else {
                      deviceGroup.remove(eventoTitle);
                    }
                  });
                },
              ),
              onTap: () {
                setState(() {
                  if (isSelected) {
                    deviceGroup.remove(eventoTitle);
                  } else {
                    deviceGroup.add(eventoTitle);
                  }
                });
              },
            ),
          ),
        );
      }

      if (validDevices.isNotEmpty) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Text(
              'DISPOSITIVOS INDIVIDUALES',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color0.withValues(alpha: 0.9),
                letterSpacing: 1,
              ),
            ),
          ),
        );
      }
    }

    widgets.addAll(validDevices.map((equipo) {
      final displayName = nicknamesMap[equipo] ?? equipo;
      final deviceKey =
          '${DeviceManager.getProductCode(equipo)}/${DeviceManager.extractSerialNumber(equipo)}';
      final deviceDATA = globalDATA[deviceKey] ?? {};

      final salidaKeys =
          deviceDATA.keys.where((k) => k.startsWith('io')).toList()
            ..sort((a, b) {
              final numA = int.tryParse(a.substring(2)) ?? 0;
              final numB = int.tryParse(b.substring(2)) ?? 0;
              return numA.compareTo(numB);
            });

      final hasSelectedSalida = salidaKeys.any((key) {
        final rawData = deviceDATA[key];
        final data = rawData is String ? jsonDecode(rawData) : rawData;
        final pinType = int.tryParse(data['pinType'].toString()) ?? -1;
        if (pinType != 0) return false;
        final salidaId = '${equipo}_${key.replaceAll("io", "")}';
        return deviceGroup.contains(salidaId);
      });

      final isEquipoSelected =
          deviceGroup.contains(equipo) || hasSelectedSalida;

      return Container(
        margin: const EdgeInsets.only(bottom: 8.0),
        decoration: BoxDecoration(
          color: isEquipoSelected
              ? color4.withValues(alpha: 0.1)
              : color0.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(
            color: isEquipoSelected ? color4 : color0,
            width: 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (equipo.contains('Domotica') ||
                equipo.contains('Modulo') ||
                equipo.contains('Rele')) ...[
              if (deviceDATA.keys.any((k) => k.startsWith('io'))) ...[
                ListTile(
                  title: Text(displayName,
                      style: GoogleFonts.poppins(color: color0)),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 32.0, bottom: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: salidaKeys.map((key) {
                      if (!deviceDATA.containsKey(key)) {
                        return ListTile(
                          title: Text(
                            'Error en el equipo',
                            style: GoogleFonts.poppins(
                              color: color0,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            'Se solucionará automáticamente en poco tiempo...',
                            style: GoogleFonts.poppins(color: color0),
                          ),
                        );
                      }
                      final raw = deviceDATA[key];
                      final data = raw is String ? jsonDecode(raw) : raw;
                      final pinType =
                          int.tryParse(data['pinType'].toString()) ?? -1;

                      // Solo mostrar salidas (pinType = 0)
                      if (pinType != 0) return const SizedBox.shrink();

                      final salidaIndex = key.replaceAll('io', '');
                      final salidaId = '${equipo}_$salidaIndex';
                      final isChecked = deviceGroup.contains(salidaId);

                      return CheckboxListTile(
                        title: Text(
                          nicknamesMap[salidaId] ?? 'Salida $salidaIndex',
                          style: GoogleFonts.poppins(color: color0),
                        ),
                        value: isChecked,
                        activeColor: color4,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              deviceGroup.add(salidaId);
                            } else {
                              deviceGroup.remove(salidaId);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              ] else ...[
                CheckboxListTile(
                  title: Text(displayName,
                      style: GoogleFonts.poppins(color: color0)),
                  value: deviceGroup.contains(equipo),
                  activeColor: color4,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        deviceGroup.add(equipo);
                      } else {
                        deviceGroup.remove(equipo);
                      }
                    });
                  },
                ),
              ],
            ] else ...[
              CheckboxListTile(
                title: Text(displayName,
                    style: GoogleFonts.poppins(color: color0)),
                value: deviceGroup.contains(equipo),
                activeColor: color4,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      deviceGroup.add(equipo);
                    } else {
                      deviceGroup.remove(equipo);
                    }
                  });
                },
              ),
            ],
          ],
        ),
      );
    }));

    return widgets;
  }

  Widget _buildActionConfigurationStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Text(
            'Configura la acción para cada dispositivo/evento',
            style: GoogleFonts.poppins(color: color0, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: deviceGroup.length,
            itemBuilder: (context, index) {
              final device = deviceGroup[index];
              final isOn = deviceActions[device] ?? false;
              final bool isRollerDev = _isRoller(device);

              String displayName = device;
              String deviceType = 'Dispositivo';
              IconData iconData = HugeIcons.strokeRoundedLaptopPhoneSync;
              bool isCadena = false;
              bool isRiego = false;

              final eventoEncontrado = eventosCreados.firstWhere(
                (evento) => evento['title'] == device,
                orElse: () => <String, dynamic>{},
              );

              if (eventoEncontrado.isNotEmpty) {
                final eventoType = eventoEncontrado['evento'] as String;
                displayName = device;
                deviceType = eventoType == 'grupo'
                    ? 'Grupo'
                    : eventoType == 'riego'
                        ? 'Riego'
                        : 'Cadena';
                iconData = (eventoType == 'grupo'
                    ? HugeIcons.strokeRoundedSmartPhone01
                    : eventoType == 'riego'
                        ? HugeIcons.strokeRoundedPlant03
                        : HugeIcons.strokeRoundedLink05);
                isCadena = eventoType == 'cadena';
                isRiego = eventoType == 'riego';
              } else {
                displayName = nicknamesMap[device] ?? device;
              }

              final finalDisplayName =
                  displayName.isEmpty ? device : displayName;

              return Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                color: color0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(iconData, color: color1, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              finalDisplayName,
                              style: GoogleFonts.poppins(
                                color: color1,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (deviceType != 'Dispositivo') ...{
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: deviceType == 'Grupo'
                                    ? color4.withValues(alpha: 0.2)
                                    : Colors.orange.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                deviceType,
                                style: GoogleFonts.poppins(
                                  color: deviceType == 'Grupo'
                                      ? color4
                                      : Colors.orange,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          },
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (isCadena || isRiego) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange, width: 1),
                          ),
                          child: Row(
                            children: [
                              const Icon(HugeIcons.strokeRoundedPlay,
                                  color: Colors.orange, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Se ejecutará automáticamente',
                                style: GoogleFonts.poppins(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        SizedBox(
                          width: double.infinity,
                          child: ToggleButtons(
                            isSelected: [isOn == true, isOn == false],
                            onPressed: (i) => setState(() {
                              deviceActions[device] = i == 0 ? true : false;
                            }),
                            borderRadius: BorderRadius.circular(12),
                            selectedColor: color0,
                            fillColor: isOn
                                ? Colors.green.withValues(alpha: 0.8)
                                : color3.withValues(alpha: 0.8),
                            color: color1,
                            borderColor: color1,
                            selectedBorderColor: isOn
                                ? Colors.green.withValues(alpha: 0.8)
                                : color3.withValues(alpha: 0.8),
                            constraints: BoxConstraints(
                              minHeight: 36,
                              minWidth:
                                  MediaQuery.of(context).size.width * 0.25,
                            ),
                            children: [
                              Text(isRollerDev ? 'Abrir' : 'Encender',
                                  style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12)),
                              Text(isRollerDev ? 'Cerrar' : 'Apagar',
                                  style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNameInputStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Text(
            'Escribe el nombre del control climático',
            style: GoogleFonts.poppins(color: color0, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: title,
          decoration: InputDecoration(
            hintText: 'Ej: Control lluvia',
            hintStyle: GoogleFonts.poppins(color: color1),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16.0),
              borderSide: const BorderSide(color: color4),
            ),
            filled: true,
            fillColor: color0,
            errorText: title.text.contains(':')
                ? 'No se permiten dos puntos (:)'
                : _nombreDuplicado(title.text)
                    ? 'Ya existe un evento con ese nombre'
                    : null,
          ),
          style: GoogleFonts.poppins(color: color1),
          onChanged: (value) {
            setState(() {});
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // Detecta si un device es un roller (024011_IOT)
  bool _isRoller(String device) {
    final cleanName = device.contains('_') ? device.split('_')[0] : device;
    return DeviceManager.getProductCode(cleanName) == '024011_IOT';
  }

  bool _nombreDuplicado(String nombre) {
    if (nombre.trim().isEmpty) return false;
    if (nombreOriginal != null &&
        nombre.toLowerCase().trim() == nombreOriginal!.toLowerCase().trim()) {
      return false;
    }
    return eventosCreados.any(
      (e) =>
          (e['title'] as String?)?.toLowerCase().trim() ==
          nombre.toLowerCase().trim(),
    );
  }

  bool _canContinue() {
    switch (currentStep) {
      case 0:
        return selectedWeatherCondition.isNotEmpty;
      case 1:
        return deviceGroup.isNotEmpty;
      case 2:
        int requiredActions = deviceGroup.where((device) {
          final eventoEncontrado = eventosCreados.firstWhere(
            (evento) => evento['title'] == device,
            orElse: () => <String, dynamic>{},
          );
          return !(eventoEncontrado.isNotEmpty &&
              eventoEncontrado['evento'] == 'cadena');
        }).length;

        int configuredActions = deviceActions.entries.where((entry) {
          final eventoEncontrado = eventosCreados.firstWhere(
            (evento) => evento['title'] == entry.key,
            orElse: () => <String, dynamic>{},
          );
          return !(eventoEncontrado.isNotEmpty &&
              eventoEncontrado['evento'] == 'cadena');
        }).length;

        return deviceActions.isNotEmpty && configuredActions >= requiredActions;
      case 3:
        return title.text.isNotEmpty &&
            !title.text.contains(':') &&
            !_nombreDuplicado(title.text);
      default:
        return false;
    }
  }

  void _handleContinue() {
    if (currentStep < 3) {
      setState(() {
        currentStep++;
        // Inicializar valores por defecto para nuevos dispositivos en el paso 2
        if (currentStep == 2) {
          for (String device in deviceGroup) {
            final eventoEncontrado = eventosCreados.firstWhere(
              (evento) => evento['title'] == device,
              orElse: () => <String, dynamic>{},
            );

            if (eventoEncontrado.isNotEmpty &&
                eventoEncontrado['evento'] == 'cadena') {
              deviceActions[device] = true;
            } else {
              deviceActions[device] ??= false;
            }
          }
        }
      });
    } else {
      _confirmarClima();
    }
  }

  void _confirmarClima() {
    printLog.d("=== CONTROL POR CLIMA GUARDADO ===");
    String? directionToSave;
    if (windDirection != null && windDirection != 'Todos los origenes') {
      directionToSave = windDirection;
    }

    Map<String, dynamic> eventoData = {
      'evento': 'clima',
      'title': title.text.trim(),
      'condition': selectedWeatherCondition,
      if (directionToSave != null) 'wind_direction': directionToSave,
      'deviceGroup': List<String>.from(deviceGroup),
      'deviceActions': Map<String, bool>.from(deviceActions),
    };

    Map<String, Map<String, bool>> ejecutores = {};
    for (String item in deviceGroup) {
      final eventoEncontrado = eventosCreados.firstWhere(
        (evento) => evento['title'] == item,
        orElse: () => <String, dynamic>{},
      );

      String finalKey;
      if (eventoEncontrado.isNotEmpty) {
        final eventoType = eventoEncontrado['evento'] as String;
        finalKey = '$item:$eventoType';
      } else {
        finalKey = '$item:dispositivo';
      }

      final name = item.contains('_') ? item.split('_')[0] : item;
      final pc = DeviceManager.getProductCode(name);
      final sn = DeviceManager.extractSerialNumber(name);
      final map = globalDATA['$pc/$sn'] ?? {};
      String ubi = map['deviceLocation'] ?? '';

      ejecutores[ubi] = {finalKey: deviceActions[item] ?? false};
    }

    setState(() {
      if (widget.eventoExistente != null) {
        if (nombreOriginal != null && nombreOriginal != title.text) {
          deleteEventoControlPorClima(currentUserEmail, nombreOriginal!);
          todosLosDispositivos.removeWhere((e) => e.key == nombreOriginal);
          savedOrder.removeWhere((e) => e['key'] == nombreOriginal);
        }
        eventosCreados.removeWhere(
            (e) => e['title'] == nombreOriginal && e['evento'] == 'clima');
      }

      eventosCreados.add(eventoData);

      int indexDisp = todosLosDispositivos
          .indexWhere((e) => e.key == (nombreOriginal ?? title.text));
      if (indexDisp != -1) {
        todosLosDispositivos[indexDisp] =
            MapEntry(title.text.trim(), deviceGroup.join(','));
      } else {
        todosLosDispositivos
            .add(MapEntry(title.text.trim(), deviceGroup.join(',')));
      }

      putEventos(currentUserEmail, eventosCreados);
      putEventoControlPorClima(currentUserEmail, title.text.trim(),
          selectedWeatherCondition, ejecutores, directionToSave);

      showToast(widget.eventoExistente != null
          ? "Control climático actualizado"
          : "Control climático creado");

      if (widget.eventoExistente == null) {
        _initializeData();
        title.clear();
      }
    });

    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }
}
