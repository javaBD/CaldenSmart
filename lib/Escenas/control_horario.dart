import 'dart:convert';

import 'package:caldensmart/aws/dynamo/dynamo.dart';
import 'package:caldensmart/master.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';

class ControlHorarioWidget extends StatefulWidget {
  final VoidCallback? onBackToMain;
  final Map<String, dynamic>? eventoExistente;

  const ControlHorarioWidget(
      {super.key, this.onBackToMain, this.eventoExistente});

  @override
  ControlHorarioWidgetState createState() => ControlHorarioWidgetState();
}

class ControlHorarioWidgetState extends State<ControlHorarioWidget> {
  int currentStep = 0;
  List<String> selectedDevices = [];
  List<String> selectedDays = [];
  TimeOfDay? selectedTime;
  Map<String, bool> deviceActions = {};
  TextEditingController title = TextEditingController();
  String? nombreOriginal;
  String? horaOriginal;
  Map<String, bool> _wifiPermissions = {};
  bool _isLoadingPermissions = true;

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
      horaOriginal = widget.eventoExistente!['selectedTime'];

      selectedDevices =
          List<String>.from(widget.eventoExistente!['deviceGroup'] ?? []);
      selectedDays =
          List<String>.from(widget.eventoExistente!['selectedDays'] ?? []);

      String horaGuardada = widget.eventoExistente!['selectedTime'] ?? '12:00';
      List<String> partesHora = horaGuardada.split(':');
      if (partesHora.length == 2) {
        selectedTime = TimeOfDay(
            hour: int.tryParse(partesHora[0]) ?? 12,
            minute: int.tryParse(partesHora[1]) ?? 0);
      }

      Map<String, bool> savedActions = Map<String, bool>.from(
          widget.eventoExistente!['deviceActions'] ?? {});
      deviceActions.clear();
      savedActions.forEach((key, value) {
        String originalName = key.split(':').first;
        deviceActions[originalName] = value;
      });

      currentStep = 0;
    } else {
      selectedDevices.clear();
      selectedDays.clear();
      selectedTime = null;
      deviceActions.clear();
      currentStep = 0;
    }
  }

  bool _isRoller(String device) {
    final cleanName = device.contains('_') ? device.split('_')[0] : device;
    return DeviceManager.getProductCode(cleanName) == '024011_IOT';
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

  bool _isValidForHorario(String equipo) {
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

  List<Widget> _buildDeviceSelection() {
    // Filtrar equipos válidos
    final validDevices = filterDevices.where((equipo) {
      if (!_isValidForHorario(equipo)) return false;
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
              'No hay dispositivos o eventos válidos para control horario.',
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
        final isSelected = selectedDevices.contains(eventoTitle);

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
                      selectedDevices.add(eventoTitle);
                    } else {
                      selectedDevices.remove(eventoTitle);
                    }
                  });
                },
              ),
              onTap: () {
                setState(() {
                  if (isSelected) {
                    selectedDevices.remove(eventoTitle);
                  } else {
                    selectedDevices.add(eventoTitle);
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

    if (validDevices.isEmpty && eventosDisponibles.isNotEmpty) {
      return widgets;
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
        return selectedDevices.contains(salidaId);
      });

      return Container(
        margin: const EdgeInsets.only(bottom: 8.0),
        decoration: BoxDecoration(
          color: (selectedDevices.contains(equipo) || hasSelectedSalida)
              ? color4.withValues(alpha: 0.1)
              : color0.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(
            color: (selectedDevices.contains(equipo) || hasSelectedSalida)
                ? color4
                : color0,
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
                      final rawData = deviceDATA[key];
                      final data =
                          rawData is String ? jsonDecode(rawData) : rawData;
                      final pinType =
                          int.tryParse(data['pinType'].toString()) ?? -1;

                      // Solo mostrar salidas (pinType = 0)
                      if (pinType != 0) return const SizedBox.shrink();

                      final salidaIndex = key.replaceAll('io', '');
                      final salidaId = '${equipo}_$salidaIndex';
                      final isChecked = selectedDevices.contains(salidaId);

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
                              selectedDevices.add(salidaId);
                            } else {
                              selectedDevices.remove(salidaId);
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
                  value: selectedDevices.contains(equipo),
                  activeColor: color4,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        selectedDevices.add(equipo);
                      } else {
                        selectedDevices.remove(equipo);
                      }
                    });
                  },
                ),
              ],
            ] else ...[
              CheckboxListTile(
                title: Text(displayName,
                    style: GoogleFonts.poppins(color: color0)),
                value: selectedDevices.contains(equipo),
                activeColor: color4,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      selectedDevices.add(equipo);
                    } else {
                      selectedDevices.remove(equipo);
                    }
                  });
                },
              ),
            ],
          ],
        ),
      );
    }).toList());

    return widgets;
  }

  Widget _buildTimeAndDaySelection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Text(
            'Selecciona los días del evento',
            style: GoogleFonts.poppins(color: color0, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            child: SelectWeekDays(
              key: selectWeekDaysKey,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              days: [
                DayInWeek("L",
                    dayKey: "Lunes",
                    isSelected: selectedDays.contains("Lunes")),
                DayInWeek("M",
                    dayKey: "Martes",
                    isSelected: selectedDays.contains("Martes")),
                DayInWeek("X",
                    dayKey: "Miércoles",
                    isSelected: selectedDays.contains("Miércoles") ||
                        selectedDays.contains("Miercoles")),
                DayInWeek("J",
                    dayKey: "Jueves",
                    isSelected: selectedDays.contains("Jueves")),
                DayInWeek("V",
                    dayKey: "Viernes",
                    isSelected: selectedDays.contains("Viernes")),
                DayInWeek("S",
                    dayKey: "Sábado",
                    isSelected: selectedDays.contains("Sábado") ||
                        selectedDays.contains("Sabado")),
                DayInWeek("D",
                    dayKey: "Domingo",
                    isSelected: selectedDays.contains("Domingo")),
              ],
              unSelectedDayTextColor: color1,
              selectedDayTextColor: color1,
              selectedDaysFillColor: color4,
              unselectedDaysFillColor: color0,
              border: false,
              width: MediaQuery.of(context).size.width * 0.9,
              boxDecoration: BoxDecoration(
                color: color0,
                borderRadius: BorderRadius.circular(20.0),
              ),
              onSelect: (values) {
                setState(() {
                  selectedDays = values;
                });
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Selecciona la hora del evento',
            style: GoogleFonts.poppins(color: color0, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
        const Divider(
          color: color4,
          thickness: 1,
          height: 24,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: 120,
              maxHeight: 180,
            ),
            child: TimeSelector(
              onTimeChanged: (TimeOfDay time) {
                setState(() {
                  selectedTime = time;
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionsSelection() {
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
        const SizedBox(height: 12),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: selectedDevices.length,
            itemBuilder: (context, index) {
              final device = selectedDevices[index];
              final isOn = deviceActions[device] ?? false;
              final bool isRoller = _isRoller(device);
              String displayName = device;
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
              return Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
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
                              displayName,
                              style: GoogleFonts.poppins(
                                color: color1,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (isCadena || isRiego) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.blue.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                HugeIcons.strokeRoundedPlay,
                                color: Colors.blue,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Se ejecutará la secuencia completa',
                                  style: GoogleFonts.poppins(
                                    color: Colors.blue,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        Row(
                          children: [
                            Expanded(
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
                                constraints: const BoxConstraints(
                                  minHeight: 36,
                                  minWidth: 100,
                                ),
                                children: [
                                  Text(isRoller ? 'Abrir' : 'Encender',
                                      style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w500)),
                                  Text(isRoller ? 'Cerrar' : 'Apagar',
                                      style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                          ],
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

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color1,
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                        'Control por Horario',
                        style: GoogleFonts.poppins(
                          color: color0,
                          fontSize: 20,
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
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildStepIndicator(0, 'Dispositivos', currentStep >= 0),
                  Container(
                      width: 30,
                      height: 2,
                      color: currentStep >= 1 ? color4 : color0),
                  _buildStepIndicator(1, 'Horario', currentStep >= 1),
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
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
                minHeight: 0,
              ),
              child: _buildCurrentStepContent(),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (currentStep > 0)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ElevatedButton.icon(
                          icon: const Icon(HugeIcons.strokeRoundedArrowLeft02),
                          label: const Text('Atrás'),
                          onPressed: () {
                            setState(() {
                              currentStep--;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: color0,
                            foregroundColor: color1,
                            elevation: 2,
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: currentStep > 0 ? 8.0 : 0),
                      child: ElevatedButton.icon(
                        icon: Icon(currentStep < 3
                            ? HugeIcons.strokeRoundedArrowRight02
                            : HugeIcons.strokeRoundedTick02),
                        label:
                            Text(currentStep < 3 ? 'Continuar' : 'Confirmar'),
                        onPressed: _canContinue() ? _handleContinue : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color0,
                          foregroundColor: color1,
                          disabledBackgroundColor:
                              color1.withValues(alpha: 0.5),
                          disabledForegroundColor: color0,
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
        if (_isLoadingPermissions) {
          return const Center(child: CircularProgressIndicator(color: color4));
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Text(
                'Selecciona los dispositivos',
                style: GoogleFonts.poppins(color: color0, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: _buildDeviceSelection(),
              ),
            ),
          ],
        );
      case 1:
        return _buildTimeAndDaySelection();
      case 2:
        return _buildActionsSelection();
      case 3:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Text(
                'Nombre del control horario',
                style: GoogleFonts.poppins(color: color0, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: title,
              decoration: InputDecoration(
                hintText: 'Ej: Luces del jardín',
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
                setState(() {
                  // Actualizar el estado para mostrar/ocultar el error
                });
              },
            ),
            const SizedBox(height: 16),
          ],
        );
      default:
        return const SizedBox();
    }
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
        return selectedDevices.isNotEmpty;
      case 1:
        return selectedDays.isNotEmpty && selectedTime != null;
      case 2:
        int requiredActions = selectedDevices.where((device) {
          final eventoEncontrado = eventosCreados.firstWhere(
            (evento) => evento['title'] == device,
            orElse: () => <String, dynamic>{},
          );
          // Excluir cadenas de los requerimientos
          return !(eventoEncontrado.isNotEmpty &&
              eventoEncontrado['evento'] == 'cadena');
        }).length;

        int configuredActions = deviceActions.entries.where((entry) {
          final eventoEncontrado = eventosCreados.firstWhere(
            (evento) => evento['title'] == entry.key,
            orElse: () => <String, dynamic>{},
          );
          // Excluir cadenas del conteo
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
        if (currentStep == 2) {
          for (String device in selectedDevices) {
            // Verificar si es una cadena buscando en eventosCreados
            final eventoEncontrado = eventosCreados.firstWhere(
              (evento) => evento['title'] == device,
              orElse: () => <String, dynamic>{},
            );

            if (eventoEncontrado.isNotEmpty &&
                eventoEncontrado['evento'] == 'cadena') {
              // Para cadenas, configurar automáticamente como 'ejecutar' (true)
              deviceActions[device] = true;
            } else {
              // Para dispositivos y grupos, valor por defecto false
              deviceActions[device] ??= false;
            }
          }
        }
      });
    } else {
      _confirmarHorario();
    }
  }

  void _confirmarHorario() {
    String horario =
        '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}';

    List<int> daysAsNumbers = selectedDays
        .map((day) {
          switch (day.toLowerCase()) {
            case 'domingo':
              return 0;
            case 'lunes':
              return 1;
            case 'martes':
              return 2;
            case 'miercoles' || 'miércoles':
              return 3;
            case 'jueves':
              return 4;
            case 'viernes':
              return 5;
            case 'sabado' || 'sábado':
              return 6;
            default:
              return -1;
          }
        })
        .where((day) => day != -1)
        .toList();

    DateTime now = DateTime.now();
    int timezoneOffset = now.timeZoneOffset.inHours;
    String timezoneName = now.timeZoneName;

    Map<String, bool> finalDeviceActions = {};

    for (String item in selectedDevices) {
      final eventoEncontrado = eventosCreados.firstWhere(
        (evento) => evento['title'] == item,
        orElse: () => <String, dynamic>{},
      );

      String finalKey = eventoEncontrado.isNotEmpty
          ? '$item:${eventoEncontrado['evento']}'
          : '$item:dispositivo';

      finalDeviceActions[finalKey] = deviceActions[item] ?? false;
    }

    setState(() {
      if (widget.eventoExistente != null) {
        if (nombreOriginal != null &&
            horaOriginal != null &&
            (nombreOriginal != title.text || horaOriginal != horario)) {
          deleteEventoControlPorHorarios(
              horaOriginal!, currentUserEmail, nombreOriginal!);
          todosLosDispositivos.removeWhere((e) => e.key == nombreOriginal);
          savedOrder.removeWhere((e) => e['key'] == nombreOriginal);
        }
        eventosCreados.removeWhere(
            (e) => e['title'] == nombreOriginal && e['evento'] == 'horario');
      }

      Map<String, dynamic> eventoData = {
        'evento': 'horario',
        'title': title.text,
        'selectedDays': List<String>.from(selectedDays),
        'selectedTime': horario,
        'deviceActions': Map<String, bool>.from(finalDeviceActions),
        'deviceGroup': List<String>.from(selectedDevices),
      };

      eventosCreados.add(eventoData);

      int indexDisp = todosLosDispositivos
          .indexWhere((e) => e.key == (nombreOriginal ?? title.text));
      if (indexDisp != -1) {
        todosLosDispositivos[indexDisp] =
            MapEntry(title.text, selectedDevices.join(','));
      } else {
        todosLosDispositivos
            .add(MapEntry(title.text.trim(), selectedDevices.join(',')));
      }

      putEventos(currentUserEmail, eventosCreados);

      if (selectedDevices.isNotEmpty) {
        putEventoControlPorHorarios(horario, currentUserEmail, title.text,
            finalDeviceActions, daysAsNumbers, timezoneOffset, timezoneName);
      }

      showToast(widget.eventoExistente != null
          ? "Horario actualizado"
          : "Control horario creado");

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
