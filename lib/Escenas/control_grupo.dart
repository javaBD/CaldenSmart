import 'dart:convert';

import 'package:caldensmart/aws/dynamo/dynamo.dart';
import 'package:caldensmart/logger.dart';
import 'package:caldensmart/master.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';

class ControlPorGrupoWidget extends StatefulWidget {
  final VoidCallback? onBackToMain;
  final Map<String, dynamic>? eventoExistente;
  const ControlPorGrupoWidget(
      {super.key, this.onBackToMain, this.eventoExistente});

  @override
  ControlPorGrupoWidgetState createState() => ControlPorGrupoWidgetState();
}

class ControlPorGrupoWidgetState extends State<ControlPorGrupoWidget> {
  int currentStep = 0;
  TextEditingController title = TextEditingController();

  Map<String, bool> _wifiPermissions = {};
  bool _isLoadingPermissions = true;
  String? nombreOriginal;
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

      final devices = widget.eventoExistente!['deviceGroup'];
      if (devices != null) {
        deviceGroup = List<String>.from(devices);
      }
      currentStep = 0;
    } else {
      deviceGroup.clear();
      currentStep = 0;
    }
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

  bool _isValidForGroup(String equipo) {
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
      if (!_isValidForGroup(equipo)) return false;
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

    if (validDevices.length < 2) {
      return [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Se necesitan al menos 2 equipos para formar un grupo.',
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

    return validDevices.map((equipo) {
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
    }).toList();
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
                        'Control por Grupo',
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
                  _buildStepIndicator(0, 'Dispositivos', currentStep >= 0),
                  Container(
                      width: 30,
                      height: 2,
                      color: currentStep >= 1 ? color4 : color0),
                  _buildStepIndicator(1, 'Nombre', currentStep >= 1),
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
                        icon: Icon(currentStep == 1
                            ? HugeIcons.strokeRoundedTick02
                            : HugeIcons.strokeRoundedArrowRight02),
                        label:
                            Text(currentStep == 1 ? 'Confirmar' : 'Continuar'),
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
                'Selecciona al menos dos equipos',
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
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Text(
                'Escribe el nombre del grupo',
                style: GoogleFonts.poppins(color: color0, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: title,
              decoration: InputDecoration(
                hintText: 'Ej: Grupo de luces',
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
        return deviceGroup.length >= 2;
      case 1:
        return title.text.isNotEmpty &&
            !title.text.contains(':') &&
            !_nombreDuplicado(title.text);
      default:
        return false;
    }
  }

  void _handleContinue() {
    if (currentStep < 1) {
      setState(() {
        currentStep++;
      });
    } else {
      _confirmarGrupo();
    }
  }

  void _confirmarGrupo() {
    printLog.i("=== CONTROL POR GRUPO GUARDADO ===");
    final nuevoNombre = title.text.trim();
    printLog.i("Nombre: $nuevoNombre");
    printLog.i("Equipos seleccionados: $deviceGroup");

    setState(() {
      if (widget.eventoExistente != null) {
        if (nombreOriginal != null && nombreOriginal != nuevoNombre) {
          deleteEventoControlPorGrupos(currentUserEmail, nombreOriginal!);
          todosLosDispositivos.removeWhere((e) => e.key == nombreOriginal);
          savedOrder.removeWhere((e) => e['key'] == nombreOriginal);
        }
        eventosCreados.removeWhere(
            (e) => e['title'] == nombreOriginal && e['evento'] == 'grupo');
      }

      eventosCreados.add({
        'evento': 'grupo',
        'title': nuevoNombre,
        'deviceGroup': List<String>.from(deviceGroup),
      });

      putEventos(currentUserEmail, eventosCreados);

      int indexDisp = todosLosDispositivos
          .indexWhere((e) => e.key == (nombreOriginal ?? nuevoNombre));
      if (indexDisp != -1) {
        todosLosDispositivos[indexDisp] =
            MapEntry(nuevoNombre, deviceGroup.toString());
      } else {
        todosLosDispositivos.add(MapEntry(nuevoNombre, deviceGroup.toString()));
      }

      putEventoControlPorGrupos(currentUserEmail, nuevoNombre, deviceGroup);

      showToast(widget.eventoExistente != null
          ? "Grupo actualizado"
          : "Grupo confirmado");

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
