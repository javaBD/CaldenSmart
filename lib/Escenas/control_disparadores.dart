import 'dart:convert';

import 'package:caldensmart/aws/dynamo/dynamo.dart';
import 'package:caldensmart/logger.dart';
import 'package:caldensmart/master.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';

class ControlDisparadorWidget extends StatefulWidget {
  final VoidCallback? onBackToMain;
  final Map<String, dynamic>? eventoExistente;

  const ControlDisparadorWidget(
      {super.key, this.onBackToMain, this.eventoExistente});

  @override
  ControlDisparadorWidgetState createState() => ControlDisparadorWidgetState();
}

class ControlDisparadorWidgetState extends State<ControlDisparadorWidget> {
  int currentStep = 0;
  List<String> activadores = [];
  List<String> ejecutores = [];
  Map<String, bool> deviceActions = {};
  TextEditingController title = TextEditingController();
  String estadoAlerta = "1";
  String estadoTermometro = "1";
  Map<String, bool> _wifiPermissions = {};
  bool _isLoadingPermissions = true;
  String? nombreOriginal;
  String? activadorOriginal;
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

      activadores =
          List<String>.from(widget.eventoExistente!['activadores'] ?? []);
      if (activadores.isNotEmpty) activadorOriginal = activadores.first;

      ejecutores =
          List<String>.from(widget.eventoExistente!['ejecutores'] ?? []);

      Map<String, bool> savedActions = Map<String, bool>.from(
          widget.eventoExistente!['deviceActions'] ?? {});
      deviceActions.clear();
      savedActions.forEach((key, value) {
        String originalName = key.split(':').first;
        deviceActions[originalName] = value;
      });

      estadoAlerta = widget.eventoExistente!['estadoAlerta']?.toString() ?? "1";
      estadoTermometro =
          widget.eventoExistente!['estadoTermometro']?.toString() ?? "1";

      currentStep = 0;
    } else {
      activadores.clear();
      ejecutores.clear();
      deviceActions.clear();
      currentStep = 0;
      estadoAlerta = "1";
      estadoTermometro = "1";
    }
  }

  Future<void> _loadWifiPermissions() async {
    Map<String, bool> permissions = {};
    for (var device in previusConnections) {
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

  bool _isActivador(String equipo) {
    final displayName = nicknamesMap[equipo] ?? equipo;
    if (displayName.isEmpty) return false;

    final pc = DeviceManager.getProductCode(equipo);
    final sn = DeviceManager.extractSerialNumber(equipo);
    final key = '$pc/$sn';

    if (!_isLoadingPermissions && _wifiPermissions.containsKey(key)) {
      if (_wifiPermissions[key] == false) return false;
    }

    if (equipo.contains('Detector') ||
        equipo.contains('Termometro') ||
        equipo.contains('Patito')) {
      return true;
    }

    if (equipo.contains('Domotica') ||
        equipo.contains('Modulo') ||
        equipo.contains('Rele')) {
      final deviceKey =
          '${DeviceManager.getProductCode(equipo)}/${DeviceManager.extractSerialNumber(equipo)}';
      final deviceDATA = globalDATA[deviceKey] ?? {};

      final hasEntradas =
          deviceDATA.keys.where((k) => k.startsWith('io')).any((key) {
        final rawData = deviceDATA[key];
        final data = rawData is String ? jsonDecode(rawData) : rawData;
        final pinType = int.tryParse(data['pinType'].toString()) ?? -1;
        return pinType != 0;
      });

      return hasEntradas;
    }

    return false;
  }

  bool _isEjecutor(String equipo) {
    final displayName = nicknamesMap[equipo] ?? equipo;
    if (displayName.isEmpty) return false;

    final pc = DeviceManager.getProductCode(equipo);
    final sn = DeviceManager.extractSerialNumber(equipo);
    final key = '$pc/$sn';

    if (!_isLoadingPermissions && _wifiPermissions.containsKey(key)) {
      if (_wifiPermissions[key] == false) return false;
    }

    if (equipo.contains('Domotica') ||
        equipo.contains('Modulo') ||
        equipo.contains('Rele')) {
      final deviceKey =
          '${DeviceManager.getProductCode(equipo)}/${DeviceManager.extractSerialNumber(equipo)}';
      final deviceDATA = globalDATA[deviceKey] ?? {};

      final hasPinsIO = deviceDATA.keys.any((k) => k.startsWith('io'));
      if (!hasPinsIO) return true;

      final hasSalidas =
          deviceDATA.keys.where((k) => k.startsWith('io')).any((key) {
        final rawData = deviceDATA[key];
        final data = rawData is String ? jsonDecode(rawData) : rawData;
        final pinType = int.tryParse(data['pinType'].toString()) ?? -1;
        return pinType == 0;
      });

      return hasSalidas;
    }

    if (equipo.contains('Detector') ||
        equipo.contains('Termometro') ||
        equipo.contains('Patito')) {
      return false;
    }

    return true;
  }

  List<Widget> _buildActivadoresSelection() {
    List<Widget> widgets = [];

    for (String equipo in previusConnections) {
      if (!_isActivador(equipo)) continue;

      final displayName = nicknamesMap[equipo] ?? equipo;
      final deviceKey =
          '${DeviceManager.getProductCode(equipo)}/${DeviceManager.extractSerialNumber(equipo)}';
      final deviceDATA = globalDATA[deviceKey] ?? {};
      final owner = deviceDATA['owner'] ?? '';
      final admin = deviceDATA['secondary_admin'] ?? [];
      final isnotRiego = deviceDATA['riegoActive'] != true;

      if ((owner != '' &&
              owner != currentUserEmail &&
              !admin.contains(currentUserEmail)) ||
          !isnotRiego) {
        continue;
      }
      // Verificar si este equipo tiene entradas seleccionadas
      final hasSelectedEntrada =
          deviceDATA.keys.where((k) => k.startsWith('io')).any((key) {
        final rawData = deviceDATA[key];
        final data = rawData is String ? jsonDecode(rawData) : rawData;
        final pinType = int.tryParse(data['pinType'].toString()) ?? -1;
        if (pinType == 0) return false; // Solo entradas (pinType != 0)
        final entradaIndex = key.replaceAll('io', '');
        final entradaId = '${equipo}_$entradaIndex';
        return activadores.contains(entradaId);
      });

      final isEquipoSelected =
          activadores.contains(equipo) || hasSelectedEntrada;

      widgets.add(
        Container(
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
                ListTile(
                  title: Text(
                    displayName,
                    style: GoogleFonts.poppins(color: color0),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 32.0, bottom: 8.0),
                  child: RadioGroup<String>(
                    groupValue:
                        activadores.isNotEmpty ? activadores.first : null,
                    onChanged: (value) {
                      setState(() {
                        activadores.clear();
                        if (value != null) {
                          activadores.add(value);
                        }
                      });
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: deviceDATA.keys
                          .where((k) => k.startsWith('io'))
                          .map((key) {
                        final rawData = deviceDATA[key];
                        final data =
                            rawData is String ? jsonDecode(rawData) : rawData;
                        final pinType =
                            int.tryParse(data['pinType'].toString()) ?? -1;

                        if (pinType == 0) return const SizedBox.shrink();

                        final entradaIndex = key.replaceAll('io', '');
                        final entradaId = '${equipo}_$entradaIndex';

                        return RadioListTile<String>(
                          title: Text(
                            nicknamesMap[entradaId] ?? 'Entrada $entradaIndex',
                            style: GoogleFonts.poppins(color: color0),
                          ),
                          value: entradaId,
                          activeColor: color4,
                        );
                      }).toList(),
                    ),
                  ),
                )
              ] else ...[
                RadioGroup<String>(
                  groupValue: activadores.isNotEmpty ? activadores.first : null,
                  onChanged: (value) {
                    setState(() {
                      activadores.clear();
                      if (value != null) {
                        activadores.add(value);
                      }
                    });
                  },
                  child: RadioListTile<String>(
                    title: Text(displayName.isEmpty ? equipo : displayName,
                        style: GoogleFonts.poppins(color: color0)),
                    value: equipo,
                    activeColor: color4,
                  ),
                )
              ],
            ],
          ),
        ),
      );
    }

    if (widgets.isEmpty) {
      return [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'No hay dispositivos válidos para control horario.',
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

    return widgets;
  }

  List<Widget> _buildEjecutoresSelection() {
    final validDevices = previusConnections.where((equipo) {
      if (!_isEjecutor(equipo)) return false;
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
              'No hay dispositivos o eventos válidos para control por disparadores.',
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
        final isSelected = ejecutores.contains(eventoTitle);

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
                      ejecutores.add(eventoTitle);
                    } else {
                      ejecutores.remove(eventoTitle);
                    }
                  });
                },
              ),
              onTap: () {
                setState(() {
                  if (isSelected) {
                    ejecutores.remove(eventoTitle);
                  } else {
                    ejecutores.add(eventoTitle);
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

    for (String equipo in validDevices) {
      if (!_isEjecutor(equipo)) continue;

      final displayName = nicknamesMap[equipo] ?? equipo;
      final deviceKey =
          '${DeviceManager.getProductCode(equipo)}/${DeviceManager.extractSerialNumber(equipo)}';
      final deviceDATA = globalDATA[deviceKey] ?? {};
      final owner = deviceDATA['owner'] ?? '';
      final admin = deviceDATA['secondary_admin'] ?? [];

      if (owner != '' &&
          owner != currentUserEmail &&
          !admin.contains(currentUserEmail)) {
        continue;
      }

      // Verificar si este equipo tiene salidas seleccionadas
      final hasSelectedSalida =
          deviceDATA.keys.where((k) => k.startsWith('io')).any((key) {
        final rawData = deviceDATA[key];
        final data = rawData is String ? jsonDecode(rawData) : rawData;
        final pinType = int.tryParse(data['pinType'].toString()) ?? -1;
        if (pinType != 0) return false; // Solo salidas (pinType = 0)
        final salidaIndex = key.replaceAll('io', '');
        final salidaId = '${equipo}_$salidaIndex';
        return ejecutores.contains(salidaId);
      });

      final isEquipoSelected = ejecutores.contains(equipo) || hasSelectedSalida;

      widgets.add(
        Container(
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
                      children: deviceDATA.keys
                          .where((k) => k.startsWith('io'))
                          .map((key) {
                        final rawData = deviceDATA[key];
                        final data =
                            rawData is String ? jsonDecode(rawData) : rawData;
                        final pinType =
                            int.tryParse(data['pinType'].toString()) ?? -1;

                        if (pinType != 0) return const SizedBox.shrink();

                        final salidaIndex = key.replaceAll('io', '');
                        final salidaId = '${equipo}_$salidaIndex';
                        final isChecked = ejecutores.contains(salidaId);

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
                                ejecutores.add(salidaId);
                              } else {
                                ejecutores.remove(salidaId);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ] else ...[
                  CheckboxListTile(
                    title: Text(displayName.isEmpty ? equipo : displayName,
                        style: GoogleFonts.poppins(color: color0)),
                    value: ejecutores.contains(equipo),
                    activeColor: color4,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          ejecutores.add(equipo);
                        } else {
                          ejecutores.remove(equipo);
                        }
                      });
                    },
                  ),
                ],
              ] else ...[
                CheckboxListTile(
                  title: Text(displayName.isEmpty ? equipo : displayName,
                      style: GoogleFonts.poppins(color: color0)),
                  value: ejecutores.contains(equipo),
                  activeColor: color4,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        ejecutores.add(equipo);
                      } else {
                        ejecutores.remove(equipo);
                      }
                    });
                  },
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (widgets.isEmpty) {
      return [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'No hay dispositivos válidos para control horario.',
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

    return widgets;
  }

  Widget _buildAccionesSelection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Text(
            'Configura la acción para cada ejecutor/evento',
            style: GoogleFonts.poppins(color: color0, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: ejecutores.length,
            itemBuilder: (context, index) {
              final device = ejecutores[index];
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
                      const SizedBox(height: 12),
                      if (isCadena || isRiego) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                HugeIcons.strokeRoundedPlay,
                                color: Colors.orange,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Se ejecutará la secuencia completa',
                                  style: GoogleFonts.poppins(
                                    color: Colors.orange,
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
                                  //  printLog.i('$deviceActions', color: 'verde');
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
                                  minWidth: 80,
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    child: Text(
                                        isRollerDev ? 'Abrir' : 'Encender',
                                        style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.w500)),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    child: Text(
                                        isRollerDev ? 'Cerrar' : 'Apagar',
                                        style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.w500)),
                                  ),
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
                        'Control por disparadores',
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
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildStepIndicator(0, 'Activadores', currentStep >= 0),
                  Container(
                      width: 30,
                      height: 2,
                      color: currentStep >= 1 ? color4 : color0),
                  _buildStepIndicator(1, 'Alerta', currentStep >= 1),
                  Container(
                      width: 30,
                      height: 2,
                      color: currentStep >= 2 ? color4 : color0),
                  _buildStepIndicator(2, 'Ejecutores', currentStep >= 2),
                  Container(
                      width: 30,
                      height: 2,
                      color: currentStep >= 3 ? color4 : color0),
                  _buildStepIndicator(3, 'Acciones', currentStep >= 3),
                  Container(
                      width: 30,
                      height: 2,
                      color: currentStep >= 4 ? color4 : color0),
                  _buildStepIndicator(4, 'Nombre', currentStep >= 4),
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
                        child: ElevatedButton(
                          onPressed: () => setState(() => currentStep--),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: color0,
                            foregroundColor: color1,
                            disabledForegroundColor:
                                color1.withValues(alpha: 0.5),
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
                        icon: Icon(currentStep == 4
                            ? HugeIcons.strokeRoundedTick02
                            : HugeIcons.strokeRoundedArrowRight02),
                        label:
                            Text(currentStep == 4 ? 'Confirmar' : 'Continuar'),
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
        if (_isLoadingPermissions) {
          return const Center(child: CircularProgressIndicator(color: color4));
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Text(
                'Selecciona el equipo activador',
                style: GoogleFonts.poppins(color: color0, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: _buildActivadoresSelection(),
              ),
            ),
          ],
        );
      case 1:
        final bool isTermometro = activadores.isNotEmpty &&
            (activadores.first.contains('Termometro'));
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Elige en que estado debe estar el activador para accionar los ejecutores',
                style: GoogleFonts.poppins(color: color0, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: ToggleButtons(
                isSelected: [estadoAlerta == "1", estadoAlerta == "0"],
                onPressed: (index) {
                  setState(() {
                    estadoAlerta = index == 0 ? "1" : "0";
                  });
                },
                borderRadius: BorderRadius.circular(12),
                selectedColor: color1,
                fillColor: color4.withValues(alpha: 0.8),
                color: color0,
                borderColor: color4,
                selectedBorderColor: color4,
                constraints: const BoxConstraints(
                  minHeight: 40,
                  minWidth: 120,
                ),
                children: [
                  Text(
                    'Estado de\n alerta',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'Estado de\n reposo',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (isTermometro) ...{
              const Divider(
                color: color0,
                thickness: 1.0,
                height: 24,
              ),
              Center(
                child: Text(
                  'Elige con que alerta ejecutarse',
                  style: GoogleFonts.poppins(color: color0, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: ToggleButtons(
                  isSelected: [
                    estadoTermometro == "1",
                    estadoTermometro == "0"
                  ],
                  onPressed: (index) {
                    setState(() {
                      estadoTermometro = index == 0 ? "1" : "0";
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  selectedColor: color1,
                  fillColor: color4.withValues(alpha: 0.8),
                  color: color0,
                  borderColor: color4,
                  selectedBorderColor: color4,
                  constraints: const BoxConstraints(
                    minHeight: 40,
                    minWidth: 120,
                  ),
                  children: [
                    Text(
                      'Alerta Máxima',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      'Alerta Mínima',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 15),
            },
          ],
        );
      case 2:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Text(
                'Selecciona los equipos ejecutores',
                style: GoogleFonts.poppins(color: color0, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: _buildEjecutoresSelection(),
              ),
            ),
          ],
        );
      case 3:
        return _buildAccionesSelection();
      case 4:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Text(
                'Nombre del grupo en cadena',
                style: GoogleFonts.poppins(color: color0, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: title,
              decoration: InputDecoration(
                hintText: 'Ej: Cadena de seguridad',
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
      default:
        return const SizedBox();
    }
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
        return activadores.length == 1;
      case 1:
        final bool isTermometro = activadores.isNotEmpty &&
            (activadores.first.contains('Termometro'));
        final bool estadoSeleccionado =
            estadoAlerta == "1" || estadoAlerta == "0";
        if (isTermometro) {
          return estadoSeleccionado &&
              (estadoTermometro == "1" || estadoTermometro == "0");
        }
        return estadoSeleccionado;
      case 2:
        return ejecutores.isNotEmpty;
      case 3:
        int requiredActions = ejecutores.where((device) {
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
      case 4:
        return title.text.isNotEmpty &&
            !title.text.contains(':') &&
            !_nombreDuplicado(title.text);
      default:
        return false;
    }
  }

  void _handleContinue() {
    if (currentStep < 4) {
      setState(() {
        currentStep++;
        if (currentStep == 3) {
          for (String device in ejecutores) {
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
      _confirmarDisparador();
    }
  }

  void _confirmarDisparador() async {
    printLog.i("=== CONTROL POR DISPARADOR GUARDADO ===");
    List<String> deviceGroup = [];
    Map<String, bool> finalDeviceActions = {};

    deviceGroup.addAll(activadores);
    deviceGroup.addAll(ejecutores);

    for (String item in ejecutores) {
      finalDeviceActions[item] = deviceActions[item] ?? false;
    }

    Map<String, dynamic> eventoData = {
      'evento': 'disparador',
      'title': title.text.trim(),
      'activadores': List<String>.from(activadores),
      'ejecutores': List<String>.from(ejecutores),
      'deviceGroup': List<String>.from(deviceGroup),
      'deviceActions': Map<String, bool>.from(finalDeviceActions),
      'estadoAlerta': estadoAlerta,
      'estadoTermometro': estadoTermometro,
    };

    Map<String, bool> ejecutoresMap = {};
    for (String item in ejecutores) {
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
      ejecutoresMap[finalKey] = finalDeviceActions[item] ?? false;
    }

    String tipoAlerta;
    String activador = activadores.first;
    bool isTermometro = activador.contains('Termometro');

    if (isTermometro) {
      if (estadoTermometro == "1") {
        tipoAlerta =
            estadoAlerta == "1" ? 'ejecutoresMAX_true' : 'ejecutoresMAX_false';
      } else {
        tipoAlerta =
            estadoAlerta == "1" ? 'ejecutoresMIN_true' : 'ejecutoresMIN_false';
      }
    } else {
      tipoAlerta = estadoAlerta == "1"
          ? 'ejecutoresAlert_true'
          : 'ejecutoresAlert_false';
    }

    setState(() {
      if (widget.eventoExistente != null) {
        if (nombreOriginal != null &&
            activadorOriginal != null &&
            (nombreOriginal != title.text || activadorOriginal != activador)) {
          deleteEventoControlPorDisparadores(
              activadorOriginal!, currentUserEmail, nombreOriginal!);
          todosLosDispositivos.removeWhere((e) => e.key == nombreOriginal);
          savedOrder.removeWhere((e) => e['key'] == nombreOriginal);
        }
        eventosCreados.removeWhere(
            (e) => e['title'] == nombreOriginal && e['evento'] == 'disparador');
      }

      eventosCreados.add(eventoData);

      int indexDisp = todosLosDispositivos
          .indexWhere((e) => e.key == (nombreOriginal ?? title.text));
      if (indexDisp != -1) {
        todosLosDispositivos[indexDisp] =
            MapEntry(title.text, deviceGroup.join(','));
      } else {
        todosLosDispositivos
            .add(MapEntry(title.text.trim(), deviceGroup.join(',')));
      }

      putEventos(currentUserEmail, eventosCreados);
      if (ejecutores.isNotEmpty) {
        putEventoControlPorDisparadores(
          activador,
          currentUserEmail,
          title.text.trim(),
          ejecutoresMap,
          tipoAlerta: tipoAlerta,
        );
      }

      showToast(widget.eventoExistente != null
          ? "Disparador actualizado"
          : "Disparador creado");

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
