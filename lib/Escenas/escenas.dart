// ignore_for_file: equal_elements_in_set

import 'package:caldensmart/Escenas/control_clima.dart';
import 'package:caldensmart/Escenas/control_disparadores.dart';
import 'package:caldensmart/Escenas/control_cadena.dart';
// import 'package:caldensmart/Escenas/control_clima.dart';
import 'package:caldensmart/Escenas/control_grupo.dart';
import 'package:caldensmart/Escenas/control_horario.dart';
// import 'package:caldensmart/Escenas/control_horario.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import '../master.dart';

class EscenasPage extends StatefulWidget {
  const EscenasPage({super.key});

  @override
  State<EscenasPage> createState() => EscenasPageState();
}

class EscenasPageState extends State<EscenasPage> {
  late VoidCallback _titleListener;
  final GlobalKey _configCardKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  TextEditingController delayController = TextEditingController();
  TextEditingController title = TextEditingController();
  bool isEditing = false; 

  @override
  void initState() {
    super.initState();
    // printLog(nicknamesMap);
    selectedWeatherCondition = weatherConditions.first;

    currentBuilder = buildMainOptions;
    _titleListener = () {
      if (mounted) setState(() {});
    };
    title.addListener(_titleListener);

    filterDevices = List.from(previusConnections);
    filterDevices.removeWhere((device) => device.contains('Detector'));
    setState(() {
      showCard = true;
      resetConfig();
      currentBuilder = buildMainOptions;
    });
  }

  @override
  void dispose() {
    super.dispose();
    _scrollController.dispose();

    title.removeListener(_titleListener);

    delayController.dispose();
    selectWeekDaysKey.currentState?.dispose();
  }

  //*-Reset Config Escenas-*\\
  void resetConfig() {
    setState(() {
      showCard = true;
      showHorarioStep = false;
      showHorarioStep2 = false;
      showGrupoStep = false;
      showCascadaStep = false;
      showCascadaStep2 = false;
      showClimaStep = false;
      showClimaStep2 = false;

      showDelay = false;

      deviceGroup.clear();
      title.clear();
    });
  }
  //*-Reset Config Escenas-*\\

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final args = ModalRoute.of(context)?.settings.arguments;

    if (args != null && args is Map<String, dynamic>) {
      isEditing = true;
      if (currentBuilder == buildMainOptions) {
        setState(() {
          switch (args['evento']) {
            case 'grupo':
              currentBuilder = () => ControlPorGrupoWidget(
                    eventoExistente: args,
                    onBackToMain: () => Navigator.pop(context),
                  );
              break;
            case 'cadena':
              currentBuilder = () => ControlCadenaWidget(
                    eventoExistente: args,
                    onBackToMain: () => Navigator.pop(context),
                  );
              break;
            case 'horario':
              currentBuilder = () => ControlHorarioWidget(
                    eventoExistente: args,
                    onBackToMain: () => Navigator.pop(context),
                  );
              break;
            case 'clima':
              currentBuilder = () => ControlClimaWidget(
                    eventoExistente: args,
                    onBackToMain: () => Navigator.pop(context),
                  );
              break;
            case 'disparador':
              currentBuilder = () => ControlDisparadorWidget(
                    eventoExistente: args,
                    onBackToMain: () => Navigator.pop(context),
                  );
              break;
          }
        });
      }
    }
  }


  String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      return '${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
  }

  //*- Opción principal -*\\
  Widget buildMainOptions() {
    return Container(
      decoration: BoxDecoration(
        color: color1,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color1.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Header mejorado
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: color0.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: color0.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color4.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: color4.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      HugeIcons.strokeRoundedSettings02,
                      size: 24,
                      color: color4,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Selecciona un tipo de evento',
                      textAlign: TextAlign.left,
                      style: GoogleFonts.poppins(
                        color: color0,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Lista de opciones mejorada
            _buildOptionTile(
              icon: HugeIcons.strokeRoundedClock01,
              title: 'Control horario',
              subtitle: 'Programa eventos en días y horarios específicos',
              color: color0,
              onTap: () {
                // showToast("Próximamente");
                setState(() {
                  currentBuilder = () => ControlHorarioWidget(
                        onBackToMain: () =>
                            setState(() => currentBuilder = buildMainOptions),
                      );
                  deviceGroup.clear();
                });
                Future.delayed(const Duration(milliseconds: 350), () {
                  final context = _configCardKey.currentContext;
                  if (context != null && context.mounted) {
                    Scrollable.ensureVisible(
                      context,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                      alignment: 0.1,
                    );
                  }
                });
              },
            ),
            const SizedBox(height: 16),
            _buildOptionTile(
              icon: HugeIcons.strokeRoundedLink01,
              title: 'Control por cadena',
              subtitle: 'Ejecuta dispositivos en secuencia con retrasos',
              color: color0,
              onTap: () {
                // showToast("Próximamente");
                setState(() {
                  currentBuilder = () => ControlCadenaWidget(
                        onBackToMain: () =>
                            setState(() => currentBuilder = buildMainOptions),
                      );
                  deviceGroup.clear();
                });
                Future.delayed(const Duration(milliseconds: 350), () {
                  final context = _configCardKey.currentContext;
                  if (context != null && context.mounted) {
                    Scrollable.ensureVisible(
                      context,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                      alignment: 0.1,
                    );
                  }
                });
              },
            ),
            const SizedBox(height: 16),
            _buildOptionTile(
              icon: HugeIcons.strokeRoundedComputerPhoneSync,
              title: 'Control por grupos',
              subtitle: 'Controla múltiples dispositivos como una unidad',
              color: color0,
              onTap: () {
                setState(() {
                  currentBuilder = () => ControlPorGrupoWidget(
                        onBackToMain: () =>
                            setState(() => currentBuilder = buildMainOptions),
                      );
                  deviceGroup.clear();
                  selectedTime = null;
                });
                Future.delayed(const Duration(milliseconds: 350), () {
                  final context = _configCardKey.currentContext;
                  if (context != null && context.mounted) {
                    Scrollable.ensureVisible(
                      context,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                      alignment: 0.1,
                    );
                  }
                });
              },
            ),
            const SizedBox(height: 16),
            _buildOptionTile(
              icon: HugeIcons.strokeRoundedFastWind,
              title: 'Control por clima',
              subtitle: 'Activa eventos según condiciones meteorológicas',
              color: color0,
              onTap: () {
                // showToast("Próximamente");
                setState(() {
                  currentBuilder = () => ControlClimaWidget(
                        onBackToMain: () =>
                            setState(() => currentBuilder = buildMainOptions),
                      );
                  deviceGroup.clear();
                });
                Future.delayed(const Duration(milliseconds: 350), () {
                  final context = _configCardKey.currentContext;
                  if (context != null && context.mounted) {
                    Scrollable.ensureVisible(
                      context,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                      alignment: 0.1,
                    );
                  }
                });
              },
            ),
            const SizedBox(height: 16),
            _buildOptionTile(
              icon: HugeIcons.strokeRoundedPlayCircle,
              title: 'Control por disparadores',
              subtitle: 'Un dispositivo activa automáticamente otros',
              color: color0,
              onTap: () {
                setState(() {
                  currentBuilder = () => ControlDisparadorWidget(
                        onBackToMain: () =>
                            setState(() => currentBuilder = buildMainOptions),
                      );
                  deviceGroup.clear();
                });
                Future.delayed(const Duration(milliseconds: 350), () {
                  final context = _configCardKey.currentContext;
                  if (context != null && context.mounted) {
                    Scrollable.ensureVisible(
                      context,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                      alignment: 0.1,
                    );
                  }
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color0.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color0.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: color.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: 24,
                    color: color,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.poppins(
                          color: color0,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: GoogleFonts.poppins(
                          color: color0.withValues(alpha: 0.7),
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    HugeIcons.strokeRoundedArrowRight02,
                    size: 16,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  //*- Opción principal -*\\

  @override
  Widget build(BuildContext context) {
    bool isAtMainOptions = currentBuilder == buildMainOptions;

    return PopScope(
      canPop: isEditing ? true : isAtMainOptions,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        setState(() {
          currentBuilder = buildMainOptions;
          resetConfig();
        });
      },
      child: Scaffold(
        appBar: AppBar(
          title: AutoScrollingText(
            text: 'Programación de eventos',
            style: GoogleFonts.poppins(
                color: color0, fontWeight: FontWeight.bold, fontSize: 20),
            velocity: 50.0,
            pauseDuration: const Duration(seconds: 2),
          ),
          backgroundColor: color1,
          leading: IconButton(
            icon: const Icon(HugeIcons.strokeRoundedArrowLeft02, color: color0),
            onPressed: () => Navigator.pop(context, true),
          ),
        ),
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: Container(
            color: color0,
            width: double.infinity,
            height: double.infinity,
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeIn,
                    switchOutCurve: Curves.easeOut,
                    child: showCard
                        ? Container(
                            key: _configCardKey,
                            child: currentBuilder!(),
                          )
                        : const SizedBox.shrink(
                            key: ValueKey('noCard'),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            launchWebURL(linksOfApp('manuales_escenas'));
          },
          backgroundColor: color4,
          shape: const CircleBorder(),
          child: const Icon(HugeIcons.strokeRoundedHelpCircle,
              size: 30, color: color0),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }
}
