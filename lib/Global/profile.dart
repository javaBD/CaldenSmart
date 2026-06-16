import 'package:caldensmart/Global/manager_screen.dart';
import 'package:caldensmart/Global/menu.dart';
import 'package:caldensmart/Global/stored_data.dart';
import 'package:caldensmart/Global/qr_scanner_screen.dart';
import 'package:caldensmart/login/welcome.dart';
import 'package:flutter/material.dart';
import 'package:caldensmart/master.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:caldensmart/aws/mqtt/mqtt.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:caldensmart/logger.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:in_app_review/in_app_review.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  ProfilePageState createState() => ProfilePageState();
}

class ProfilePageState extends State<ProfilePage> {
  int counter = 0;
  final List<String> alarmSounds = [
    "Sonido 1",
    "Sonido 2",
    "Sonido 3",
    "Sonido 4",
    "Sonido 5",
    "Sin sonido",
  ];

  bool isAccountOpen = false;
  bool isTutorialOpen = false;
  bool isDevicesOpen = false;
  bool isDomoticaOpen = false;
  bool isDetectorOpen = false;
  bool isTermometroOpen = false;
  bool isContactOpen = false;
  bool isSocialOpen = false;
  bool isAssistantOpen = false;

  @override
  void dispose() {
    NativeService.stopNativeSound();
    counter = 0;
    super.dispose();
  }

  int getAlarmDelay(String alarmName) {
    switch (alarmName) {
      case 'alarm1':
        return 2300;
      case 'alarm2':
        return 2000;
      case 'alarm3':
        return 1200;
      case 'alarm4':
        return 1000;
      case 'alarm5':
        return 2300;
      default:
        return 2000;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: color0,
      appBar: AppBar(
        backgroundColor: color1,
        leading: IconButton(
          icon: const Icon(HugeIcons.strokeRoundedArrowLeft02),
          color: color0,
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: AutoScrollingText(
          text: 'Configuraciones del perfil',
          style: GoogleFonts.poppins(
              color: color0, fontWeight: FontWeight.bold, fontSize: 20),
          velocity: 50.0,
          pauseDuration: const Duration(seconds: 2),
        ),
      ),
      body: Container(
        color: color0,
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    leading:
                        const Icon(HugeIcons.strokeRoundedUser, color: color1),
                    title: Text(
                      "Cuenta",
                      style: GoogleFonts.poppins(
                        color: color1,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      "Ver cuenta conectada",
                      style: GoogleFonts.poppins(
                        color: color1,
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        isAccountOpen = !isAccountOpen;
                      });
                    },
                    trailing: Icon(
                      isAccountOpen
                          ? HugeIcons.strokeRoundedArrowUp01
                          : HugeIcons.strokeRoundedArrowDown01,
                      color: color1,
                    ),
                  ),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 300),
                    firstChild: const SizedBox.shrink(),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(left: 16.0),
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: () {
                              if (counter < 20) {
                                counter++;
                              } else {
                                navigatorKey.currentState?.pushNamed('/eg');
                              }
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: color1,
                                borderRadius: BorderRadius.circular(8.0),
                                border: Border.all(color: color0),
                              ),
                              padding: const EdgeInsets.all(16.0),
                              child: Text(
                                currentUserEmail,
                                style: GoogleFonts.poppins(
                                  color: color0,
                                ),
                              ),
                            ),
                          ),
                          const Divider(color: Colors.transparent),
                          TextButton(
                            onPressed: () {
                              showAlertDialog(
                                context,
                                false,
                                const Text(
                                  '¿Está seguro que quiere eliminar la cuenta?',
                                ),
                                const Text(
                                  'Al presionar aceptar su cuenta será eliminada, está acción no puede revertirse',
                                ),
                                [
                                  TextButton(
                                    style: const ButtonStyle(
                                      foregroundColor: WidgetStatePropertyAll(
                                        color0,
                                      ),
                                    ),
                                    child: const Text('Cancelar'),
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                    },
                                  ),
                                  TextButton(
                                    style: const ButtonStyle(
                                      foregroundColor: WidgetStatePropertyAll(
                                        color0,
                                      ),
                                    ),
                                    child: const Text('Aceptar'),
                                    onPressed: () async {
                                      try {
                                        Navigator.of(context).pop();
                                        await Amplify.Auth.deleteUser();

                                        currentUserEmail = '';

                                        if (context.mounted) {
                                          Navigator.pushAndRemoveUntil(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  const WelcomePage(),
                                            ),
                                            (route) => false,
                                          );
                                        }
                                      } catch (e) {
                                        printLog
                                            .e('Error deleting account: $e');
                                        if (context.mounted) {
                                          showToast(
                                              'Error al eliminar la cuenta');
                                        }
                                      }

                                      // launchWebURL(
                                      //     linksOfApp(app, 'Borrar Cuenta'));
                                    },
                                  ),
                                ],
                              );
                            },
                            child: Text(
                              'Borrar cuenta',
                              style: GoogleFonts.poppins(
                                color: color1,
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                    crossFadeState: isAccountOpen
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                  ),
                  const Divider(color: color1),
                  ListTile(
                    leading: const Icon(
                        HugeIcons.strokeRoundedComputerPhoneSync,
                        color: color1),
                    title: Text(
                      "Dispositivos",
                      style: GoogleFonts.poppins(
                        color: color1,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      "Ver dispositivos registrados",
                      style: GoogleFonts.poppins(
                        color: color1,
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        isDevicesOpen = !isDevicesOpen;
                      });
                    },
                    trailing: Icon(
                      isDevicesOpen
                          ? HugeIcons.strokeRoundedArrowUp01
                          : HugeIcons.strokeRoundedArrowDown01,
                      color: color1,
                    ),
                  ),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 300),
                    firstChild: const SizedBox.shrink(),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(left: 16.0),
                      child: Column(
                        children: [
                          // Lista de dispositivos existentes
                          ...previusConnections.isEmpty
                              ? [
                                  Center(
                                    child: Text(
                                      "No hay dispositivos registrados",
                                      style: GoogleFonts.poppins(
                                        color: color1,
                                      ),
                                    ),
                                  )
                                ]
                              : previusConnections
                                  .map((device) => Center(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 8.0),
                                          child: Container(
                                              decoration: BoxDecoration(
                                                color: color1,
                                                borderRadius:
                                                    BorderRadius.circular(8.0),
                                                border:
                                                    Border.all(color: color0),
                                              ),
                                              padding:
                                                  const EdgeInsets.all(16.0),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      nicknamesMap[device] ??
                                                          device,
                                                      style:
                                                          GoogleFonts.poppins(
                                                        color: color0,
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                  ),
                                                  if (globalDATA['${DeviceManager.getProductCode(device)}/${DeviceManager.extractSerialNumber(device)}']
                                                              ?['owner'] ==
                                                          currentUserEmail ||
                                                      globalDATA['${DeviceManager.getProductCode(device)}/${DeviceManager.extractSerialNumber(device)}']
                                                              ?['owner'] ==
                                                          '' ||
                                                      globalDATA['${DeviceManager.getProductCode(device)}/${DeviceManager.extractSerialNumber(device)}']
                                                              ?['owner'] ==
                                                          null) ...[
                                                    IconButton(
                                                      onPressed: () {
                                                        Navigator.of(context)
                                                            .push(
                                                          MaterialPageRoute(
                                                            builder: (context) =>
                                                                ManagerScreen(
                                                              deviceName:
                                                                  device,
                                                              needsAppbar: true,
                                                            ),
                                                          ),
                                                        )
                                                            .then((_) {
                                                          setState(() {});
                                                        });
                                                      },
                                                      icon: const Icon(
                                                        HugeIcons
                                                            .strokeRoundedSettings01,
                                                        color: color0,
                                                        size: 24,
                                                      ),
                                                    )
                                                  ]
                                                ],
                                              )),
                                        ),
                                      ))
                                  .toList(),
                          // Botón Agregar dispositivo
                          const SizedBox(height: 16),
                          Center(
                            child: ElevatedButton.icon(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const QRScannerScreen(),
                                ),
                              ),
                              icon: const Icon(
                                HugeIcons.strokeRoundedAdd01,
                                color: color0,
                                size: 20,
                              ),
                              label: Text(
                                'Agregar dispositivo',
                                style: GoogleFonts.poppins(
                                  color: color0,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: color1,
                                side: const BorderSide(color: color0, width: 2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    crossFadeState: isDevicesOpen
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                  ),
                  const Divider(color: color1),
                  ListTile(
                    leading: const Icon(HugeIcons.strokeRoundedHome11,
                        color: color1),
                    title: Text(
                      "Domótica",
                      style: GoogleFonts.poppins(
                        color: color1,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      "Alarma para domótica",
                      style: GoogleFonts.poppins(
                        color: color1,
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        isDomoticaOpen = !isDomoticaOpen;
                      });
                    },
                    trailing: Icon(
                      isDomoticaOpen
                          ? HugeIcons.strokeRoundedArrowUp01
                          : HugeIcons.strokeRoundedArrowDown01,
                      color: color1,
                    ),
                  ),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 300),
                    firstChild: const SizedBox.shrink(),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(left: 16.0),
                      // 1. Se envuelve la Column con el widget RadioGroup.
                      child: RadioGroup<int>(
                        // 2. La propiedad 'groupValue' se mueve aquí.
                        groupValue: selectedSoundDomotica,
                        // 3. La lógica completa de 'onChanged' se mueve aquí.
                        onChanged: (int? value) {
                          setState(() {
                            if (selectedSoundDomotica == value) {
                              selectedSoundDomotica = null;
                            } else {
                              selectedSoundDomotica = value!;
                              soundOfNotification['020010_IOT'] =
                                  'alarm${value + 1}';
                              soundOfNotification['020020_IOT'] =
                                  'alarm${value + 1}';
                              soundOfNotification['027313_IOT'] =
                                  'alarm${value + 1}';
                              saveSounds(soundOfNotification);
                              NativeService().playNativeSound(
                                  'alarm${value + 1}',
                                  getAlarmDelay('alarm${value + 1}'));
                            }
                          });
                        },
                        child: Column(
                          children: List.generate(alarmSounds.length, (index) {
                            // 4. El RadioListTile ahora es más simple, sin la lógica de estado.
                            return RadioListTile<int>(
                              title: Row(
                                children: [
                                  const Icon(HugeIcons.strokeRoundedVolumeHigh,
                                      color: color1),
                                  const SizedBox(width: 10),
                                  Text(
                                    alarmSounds[index],
                                    style: GoogleFonts.poppins(
                                      color: color1,
                                    ),
                                  ),
                                ],
                              ),
                              activeColor: color1,
                              value: index,
                            );
                          }),
                        ),
                      ),
                    ),
                    crossFadeState: isDomoticaOpen
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                  ),
                  const Divider(color: color1),
                  ListTile(
                    leading: const Icon(
                      HugeIcons.strokeRoundedHotspot,
                      color: color1,
                    ),
                    title: Text(
                      "Detector",
                      style: GoogleFonts.poppins(
                        color: color1,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      "Alarma para detectores",
                      style: GoogleFonts.poppins(
                        color: color1,
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        isDetectorOpen = !isDetectorOpen;
                      });
                    },
                    trailing: Icon(
                      isDetectorOpen
                          ? HugeIcons.strokeRoundedArrowUp01
                          : HugeIcons.strokeRoundedArrowDown01,
                      color: color1,
                    ),
                  ),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 300),
                    firstChild: const SizedBox.shrink(),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(left: 16.0),
                      // 1. Se envuelve la Column con el widget RadioGroup.
                      child: RadioGroup<int>(
                        // 2. La propiedad 'groupValue' se mueve al RadioGroup.
                        groupValue: selectedSoundDetector,
                        // 3. La lógica 'onChanged' completa se mueve aquí.
                        onChanged: (int? value) {
                          setState(() {
                            if (selectedSoundDetector == value) {
                              selectedSoundDetector = null;
                            } else {
                              selectedSoundDetector = value!;
                              // printLog.i('Elegí alarma${value! + 1}');
                              soundOfNotification['015773_IOT'] =
                                  'alarm${value + 1}';
                              saveSounds(soundOfNotification);
                              NativeService().playNativeSound(
                                  'alarm${value + 1}',
                                  getAlarmDelay('alarm${value + 1}'));
                            }
                          });
                        },
                        child: Column(
                          children: List.generate(alarmSounds.length, (index) {
                            // 4. El RadioListTile queda simplificado, sin la lógica de estado.
                            return RadioListTile<int>(
                              title: Row(
                                children: [
                                  const Icon(HugeIcons.strokeRoundedVolumeHigh,
                                      color: color1),
                                  const SizedBox(width: 10),
                                  Text(
                                    alarmSounds[index],
                                    style: GoogleFonts.poppins(
                                      color: color1,
                                    ),
                                  ),
                                ],
                              ),
                              activeColor: color1,
                              value: index,
                            );
                          }),
                        ),
                      ),
                    ),
                    crossFadeState: isDetectorOpen
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                  ),
                  const Divider(color: color1),
                  ListTile(
                    leading: const ImageIcon(AssetImage(CaldenIcons.termometro),
                        color: color1),
                    title: Text(
                      "Termómetro",
                      style: GoogleFonts.poppins(
                        color: color1,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      "Alarma para termómetros",
                      style: GoogleFonts.poppins(
                        color: color1,
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        isTermometroOpen = !isTermometroOpen;
                      });
                    },
                    trailing: Icon(
                      isTermometroOpen
                          ? HugeIcons.strokeRoundedArrowUp01
                          : HugeIcons.strokeRoundedArrowDown01,
                      color: color1,
                    ),
                  ),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 300),
                    firstChild: const SizedBox.shrink(),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(left: 16.0),
                      // 1. Se envuelve la Column con el widget RadioGroup.
                      child: RadioGroup<int>(
                        // 2. La propiedad 'groupValue' se mueve al RadioGroup.
                        groupValue: selectedSoundTermometro,
                        // 3. La lógica 'onChanged' completa se mueve aquí.
                        onChanged: (int? value) {
                          setState(() {
                            if (selectedSoundTermometro == value) {
                              selectedSoundTermometro = null;
                            } else {
                              selectedSoundTermometro = value!;
                              // printLog.i('Elegí alarma${value! + 1}');
                              soundOfNotification['023430_IOT'] =
                                  'alarm${value + 1}';
                              saveSounds(soundOfNotification);
                              NativeService().playNativeSound(
                                  'alarm${value + 1}',
                                  getAlarmDelay('alarm${value + 1}'));
                            }
                          });
                        },
                        child: Column(
                          children: List.generate(alarmSounds.length, (index) {
                            // 4. El RadioListTile queda simplificado, sin la lógica de estado.
                            return RadioListTile<int>(
                              title: Row(
                                children: [
                                  const Icon(HugeIcons.strokeRoundedVolumeHigh,
                                      color: color1),
                                  const SizedBox(width: 10),
                                  Text(
                                    alarmSounds[index],
                                    style: GoogleFonts.poppins(
                                      color: color1,
                                    ),
                                  ),
                                ],
                              ),
                              activeColor: color1,
                              value: index,
                            );
                          }),
                        ),
                      ),
                    ),
                    crossFadeState: isTermometroOpen
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                  ),
                  const Divider(color: color1),
                  ListTile(
                    leading: const Icon(
                        HugeIcons.strokeRoundedBubbleChatQuestion,
                        color: color1),
                    title: Text(
                      "Tutorial",
                      style: GoogleFonts.poppins(
                        color: color1,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      "Activar o desactivar tutoriales",
                      style: GoogleFonts.poppins(
                        color: color1,
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        isTutorialOpen = !isTutorialOpen;
                      });
                    },
                    trailing: Icon(
                      isTutorialOpen
                          ? HugeIcons.strokeRoundedArrowUp01
                          : HugeIcons.strokeRoundedArrowDown01,
                      color: color1,
                    ),
                  ),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 300),
                    firstChild: const SizedBox.shrink(),
                    secondChild: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: color1,
                          borderRadius: BorderRadius.circular(10.0),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 4.0),
                        child: Row(
                          spacing: 10,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                child: Text(
                                  tutorial
                                      ? "Tutorial Activado"
                                      : "Tutorial Desactivado",
                                  style: GoogleFonts.poppins(
                                    color: color0,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  softWrap: true,
                                ),
                              ),
                            ),
                            Switch(
                              value: tutorial,
                              activeThumbColor: color0,
                              activeTrackColor: color0.withValues(alpha: 0.5),
                              onChanged: (bool value) {
                                setState(() {
                                  tutorial = value;
                                });
                                saveTutorial(tutorial);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    crossFadeState: isTutorialOpen
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                  ),
                  const Divider(color: color1),
                  ListTile(
                    leading: const Icon(
                      HugeIcons.strokeRoundedContactBook,
                      color: color1,
                    ),
                    title: Text(
                      "Contáctanos",
                      style: GoogleFonts.poppins(
                        color: color1,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      "Ver información de contacto",
                      style: GoogleFonts.poppins(
                        color: color1,
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        isContactOpen = !isContactOpen;
                      });
                    },
                    trailing: Icon(
                      isContactOpen
                          ? HugeIcons.strokeRoundedArrowUp01
                          : HugeIcons.strokeRoundedArrowDown01,
                      color: color1,
                    ),
                  ),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 300),
                    firstChild: const SizedBox.shrink(),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(left: 16.0),
                      child: contactInfo(app),
                    ),
                    crossFadeState: isContactOpen
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                  ),
                  const Divider(color: color1),
                  ListTile(
                    leading: const Icon(HugeIcons.strokeRoundedShare01,
                        color: color1),
                    title: Text(
                      "Nuestras redes",
                      style: GoogleFonts.poppins(
                        color: color1,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      "Ver nuestras redes sociales",
                      style: GoogleFonts.poppins(
                        color: color1,
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        isSocialOpen = !isSocialOpen;
                      });
                    },
                    trailing: Icon(
                      isSocialOpen
                          ? HugeIcons.strokeRoundedArrowUp01
                          : HugeIcons.strokeRoundedArrowDown01,
                      color: color1,
                    ),
                  ),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 300),
                    firstChild: const SizedBox.shrink(),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(left: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            leading: const Icon(
                                HugeIcons.strokeRoundedInstagram,
                                color: color1),
                            title: Text(
                              'Instagram',
                              style: GoogleFonts.poppins(
                                color: color1,
                              ),
                            ),
                            onTap: () {
                              launchWebURL(linksOfApp('Instagram'));
                            },
                          ),
                          ListTile(
                            leading: const Icon(
                                HugeIcons.strokeRoundedFacebook01,
                                color: color1),
                            title: Text(
                              'Facebook',
                              style: GoogleFonts.poppins(
                                color: color1,
                              ),
                            ),
                            onTap: () {
                              launchWebURL(linksOfApp('Facebook'));
                            },
                          ),
                          ListTile(
                            leading: const Icon(HugeIcons.strokeRoundedInternet,
                                color: color1),
                            title: Text(
                              'Sitio web',
                              style: GoogleFonts.poppins(
                                color: color1,
                              ),
                            ),
                            onTap: () {
                              launchWebURL(linksOfApp('Web'));
                            },
                          ),
                        ],
                      ),
                    ),
                    crossFadeState: isSocialOpen
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                  ),
                  const Divider(color: color1),
                                    ListTile(
                    leading:
                        const Icon(HugeIcons.strokeRoundedStar, color: color1),
                    title: Text(
                      "Puntúa la app",
                      style: GoogleFonts.poppins(
                        color: color1,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      "Déjanos tu opinión en la tienda",
                      style: GoogleFonts.poppins(
                        color: color1,
                      ),
                    ),
                    trailing: const Icon(
                      HugeIcons.strokeRoundedShare01,
                      color: color1,
                      size: 20,
                    ),
                    onTap: () async {
                      try {
                        final InAppReview inAppReview = InAppReview.instance;
                        await inAppReview.openStoreListing(
                            appStoreId: '6737855207');
                      } catch (e) {
                        printLog.e('Error al abrir la tienda: $e');
                        showToast('No se pudo abrir la tienda de aplicaciones');
                      }
                    },
                  ),
                  const Divider(color: color1),
                ],
              ),
            ),
            SafeArea(
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: color1,
                    side: const BorderSide(color: color1),
                    padding: const EdgeInsets.symmetric(vertical: 15.0),
                  ),
                  onPressed: () async {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ClosingSessionScreen(),
                      ),
                    );

                    await Future.delayed(const Duration(milliseconds: 500));

                    previusConnections.clear();
                    nicknamesMap.clear();
                    globalDATA.clear();
                    alexaDevices.clear();
                    currentUserEmail = '';
                    MenuPageState.hasInitialized = false;

                    for (int i = 0; i < topicsToSub.length; i++) {
                      unSubToTopicMQTT(topicsToSub[i]);
                    }

                    topicsToSub.clear();
                    backTimerDS?.cancel();

                    await Amplify.Auth.signOut();
                    await Future.delayed(const Duration(seconds: 2));

                    if (context.mounted) {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const WelcomePage(),
                        ),
                        (route) => false,
                      );
                    }
                  },
                  child: Text(
                    "Cerrar sesión",
                    style: GoogleFonts.poppins(
                      color: color0,
                      fontSize: 18.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
