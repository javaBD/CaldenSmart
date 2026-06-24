import 'dart:convert';
import 'package:caldensmart/aws/dynamo/dynamo_certificates.dart';
import 'package:caldensmart/logger.dart';
import 'package:aws_dynamodb_api/dynamodb-2012-08-10.dart';
import 'package:caldensmart/aws/mqtt/mqtt.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/master.dart';

//*-Lee todos los datos de un equipo-*\\
Future<void> queryItems(String pc, String sn) async {
  try {
    // printLog.i('Buscare en el equipo: $pc/$sn');
    final response = await service.query(
      tableName: 'sime-domotica',
      keyConditionExpression: 'product_code = :pk AND device_id = :sk',
      expressionAttributeValues: {
        ':pk': AttributeValue(s: pc),
        ':sk': AttributeValue(s: sn),
      },
    );

    if (response.items != null) {
      // printLog.i('Items encontrados');
      // printLog.i(response.items);
      for (var item in response.items!) {
        printLog.i("-----------Inicio de un item-----------");
        for (var key in item.keys) {
          var value = item[key];
          var displayValue = value?.s ??
              value?.n ??
              value?.boolValue.toString() ??
              value?.ss ??
              value?.m?.toString() ??
              "Desconocido";
          if (value != null) {
            switch (key) {
              case 'alert':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.boolValue ?? false});
                break;
              case 'cstate':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.boolValue ?? false});
                break;
              case 'w_status':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.boolValue ?? false});
                break;
              case 'f_status':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.boolValue ?? false});
                break;
              case 'ppmco':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: int.parse(value.n ?? '0')});
                break;
              case 'ppmch4':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: int.parse(value.n ?? '0')});
                break;
              case 'distanceOn':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: double.parse(value.n ?? '3000')});
                break;
              case 'distanceOff':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: double.parse(value.n ?? '100')});
                break;
              case 'AT':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.boolValue ?? false});
                break;
              case 'tenant':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.s ?? ''});
                break;
              case 'owner':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.s ?? ''});
                break;
              case 'secondary_admin':
                List<String> secAdm = value.ss ?? [];
                if (secAdm.contains('') && secAdm.length == 1) {
                  globalDATA.putIfAbsent('$pc/$sn', () => {}).addAll({key: []});
                } else {
                  globalDATA
                      .putIfAbsent('$pc/$sn', () => {})
                      .addAll({key: secAdm});
                }
                break;
              case 'isNC':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.boolValue ?? false});
                break;
              case 'rollerSavedLength':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.s ?? ''});
                break;
              case 'io0' || 'io1' || 'io2' || 'io3':
                Map<String, AttributeValue> mapa = value.m ?? {};
                Map<String, dynamic> valores = {};
                for (String llave in mapa.keys) {
                  AttributeValue valor = mapa[llave]!;
                  valores.addAll({llave: valor.boolValue ?? valor.n});
                }
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: jsonEncode(valores)});
                break;
              case 'hasSpark':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.boolValue ?? false});
                break;
              case 'LabProcessFinished':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.boolValue ?? false});
                break;
              case 'hasEntry':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.boolValue ?? false});
                break;
              case 'HardwareVersion':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.s ?? ''});
                break;
              case 'SoftwareVersion':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.s ?? ''});
                break;
              case 'actualTemp':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: int.parse(value.n ?? '0')});
                break;
              case 'alert_minflag':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.boolValue ?? false});
                break;
              case 'alert_maxflag':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.boolValue ?? false});
                break;
              case 'distanceControlActive':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.boolValue ?? false});
                break;
              case 'deviceLocation':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.s ?? ''});
                break;
              case 'riegoActive':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.boolValue ?? false});
                break;
              case 'riegoExtensions':
                List<String> data = value.ss ?? [];
                if (data.contains('') && data.length == 1) {
                  globalDATA.putIfAbsent('$pc/$sn', () => {}).addAll({key: []});
                } else {
                  globalDATA
                      .putIfAbsent('$pc/$sn', () => {})
                      .addAll({key: data});
                }
                break;
              case 'freeBomb':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.boolValue ?? false});
                break;
              case 'riegoMaster':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.s ?? ''});
                break;
              case 'admin_time_restrictions':
                Map<String, AttributeValue> restrictionsMap = value.m ?? {};
                Map<String, dynamic> restrictions = {};
                for (String email in restrictionsMap.keys) {
                  try {
                    String configJson = restrictionsMap[email]!.s!;
                    restrictions[email] = jsonDecode(configJson);
                  } catch (e) {
                    printLog
                        .e('Error parsing admin restrictions for $email: $e');
                  }
                }
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: restrictions});
                break;
              case 'historicTempPremium':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.boolValue ?? false});
                break;
              case 'DateSecAdm':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.s ?? ''});
                break;
              case 'DateAT':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.s ?? ''});
                break;
              case 'working_position':
                final String rawWp = value.s ?? '0';
                final int parsedWp =
                    int.tryParse(rawWp.replaceAll('%', '')) ?? 0;
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: parsedWp});
                break;
              case 'actual_position':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: int.parse(value.n ?? '0')});
                break;
              case 'moving':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.boolValue ?? false});
                break;
              case 'is_calibrated':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.boolValue ?? false});
                break;
              case 'startup_evaluated':
                globalDATA
                    .putIfAbsent('$pc/$sn', () => {})
                    .addAll({key: value.boolValue ?? false});
                break;
            }
          }
          printLog.i("$key: $displayValue");
        }
        printLog.i("-----------Fin de un item-----------");
      }
    } else {
      printLog.e('Dispositivo no encontrado');
    }
  } catch (e) {
    printLog.e('Error durante la consulta: $e');
  }
}
//*-Lee todos los datos de un equipo-*\\

//*-Nueva lógica: Tokens en Alexa-Devices y ActiveUsers en sime-domotica-*\\

/// Guarda tokens del usuario en Alexa-Devices (nueva lógica)
Future<void> putTokensInAlexaDevices(String email, List<String> tokens) async {
  try {
    // Filtrar tokens vacíos y duplicados
    Set<String> uniqueTokens = {};
    List<String> cleanTokens = [];

    for (String token in tokens) {
      if (token.isNotEmpty && !uniqueTokens.contains(token)) {
        uniqueTokens.add(token);
        cleanTokens.add(token);
      }
    }

    // Si no hay tokens válidos, usar string vacío como placeholder
    if (cleanTokens.isEmpty) {
      cleanTokens.add('');
    }

    await service.updateItem(
      tableName: 'Alexa-Devices',
      key: {
        'email': AttributeValue(s: email),
      },
      attributeUpdates: {
        'tokens': AttributeValueUpdate(value: AttributeValue(ss: cleanTokens)),
      },
    );

    // printLog.i('Tokens guardados en Alexa-Devices para $email: $response');
  } catch (e) {
    printLog.e('Error guardando tokens en Alexa-Devices: $e');
  }
}

/// Obtiene tokens del usuario desde Alexa-Devices (nueva lógica)
Future<List<String>> getTokensFromAlexaDevices(String email) async {
  try {
    final response = await service.getItem(
      tableName: 'Alexa-Devices',
      key: {
        'email': AttributeValue(s: email),
      },
    );

    if (response.item != null) {
      var item = response.item!;
      List<String> tokens = item['tokens']?.ss ?? [];

      // printLog.i('Tokens encontrados en Alexa-Devices para $email: $tokens');

      if (tokens.contains('') && tokens.length == 1) {
        return [];
      } else {
        return tokens;
      }
    } else {
      printLog.e('Usuario no encontrado en Alexa-Devices: $email');
      return [];
    }
  } catch (e) {
    printLog.e('Error obteniendo tokens de Alexa-Devices: $e');
    return [];
  }
}

/// Guarda usuarios activos en sime-domotica (nueva lógica)
Future<void> putActiveUsers(
    String pc, String sn, List<String> activeUsers) async {
  try {
    // Filtrar emails vacíos y duplicados
    Set<String> uniqueEmails = {};
    List<String> cleanEmails = [];

    for (String email in activeUsers) {
      if (email.isNotEmpty && !uniqueEmails.contains(email)) {
        uniqueEmails.add(email);
        cleanEmails.add(email);
      }
    }

    // Si no hay emails válidos, usar string vacío como placeholder
    if (cleanEmails.isEmpty) {
      cleanEmails.add('');
    }

    await service.updateItem(
      tableName: 'sime-domotica',
      key: {
        'product_code': AttributeValue(s: pc),
        'device_id': AttributeValue(s: sn),
      },
      attributeUpdates: {
        'activeUsers':
            AttributeValueUpdate(value: AttributeValue(ss: cleanEmails)),
      },
    );

    // printLog.i('ActiveUsers guardados para $pc/$sn: $response');
  } catch (e) {
    printLog.e('Error guardando activeUsers: $e');
  }
}

/// Obtiene usuarios activos desde sime-domotica (nueva lógica)
Future<List<String>> getActiveUsers(String pc, String sn) async {
  try {
    final response = await service.getItem(
      tableName: 'sime-domotica',
      key: {
        'product_code': AttributeValue(s: pc),
        'device_id': AttributeValue(s: sn),
      },
    );

    if (response.item != null) {
      var item = response.item!;
      List<String> activeUsers = item['activeUsers']?.ss ?? [];

      // printLog.i('ActiveUsers encontrados para $pc/$sn: $activeUsers');

      if (activeUsers.contains('') && activeUsers.length == 1) {
        return [];
      } else {
        return activeUsers;
      }
    } else {
      printLog.e('Equipo no encontrado en sime-domotica: $pc/$sn');
      return [];
    }
  } catch (e) {
    printLog.e('Error obteniendo activeUsers: $e');
    return [];
  }
}

/// Añade un email a la lista de usuarios activos
Future<void> addToActiveUsers(String pc, String sn, String email) async {
  try {
    List<String> currentUsers = await getActiveUsers(pc, sn);
    if (!currentUsers.contains(email)) {
      currentUsers.add(email);
      await putActiveUsers(pc, sn, currentUsers);
      // printLog.i('Email $email añadido a activeUsers de $pc/$sn');
    } else {
      // printLog.i('Email $email ya está en activeUsers de $pc/$sn');
    }
  } catch (e) {
    printLog.e('Error añadiendo email a activeUsers: $e');
  }
}

/// Remueve un email de la lista de usuarios activos
Future<void> removeFromActiveUsers(String pc, String sn, String email) async {
  try {
    List<String> currentUsers = await getActiveUsers(pc, sn);
    if (currentUsers.contains(email)) {
      currentUsers.remove(email);
      await putActiveUsers(pc, sn, currentUsers);
      // printLog.i('Email $email removido de activeUsers de $pc/$sn');
    } else {
      // printLog.i('Email $email no estaba en activeUsers de $pc/$sn');
    }
  } catch (e) {
    printLog.e('Error removiendo email de activeUsers: $e');
  }
}

/// Verifica si el usuario debe ser removido de activeUsers basado en previous connections
Future<void> checkAndRemoveFromActiveUsers(
    String pc, String sn, String userEmail, String deviceName) async {
  try {
    // Verificar si el usuario aún tiene conexiones previas con este dispositivo
    final response = await service.getItem(
      tableName: 'Alexa-Devices',
      key: {
        'email': AttributeValue(s: userEmail),
      },
    );

    if (response.item != null) {
      var item = response.item!;
      List<String> previousConnections = item['previusConnections']?.ss ?? [];

      if (previousConnections.contains('') && previousConnections.length == 1) {
        previousConnections = [];
      }

      // Si el dispositivo no está en previous connections, remover de activeUsers
      if (!previousConnections.contains(deviceName)) {
        await removeFromActiveUsers(pc, sn, userEmail);
        // printLog.i('Usuario $userEmail removido de activeUsers para $pc/$sn');
      } else {
        // printLog
        //     .i('Usuario $userEmail mantiene conexión previa con $deviceName');
      }
    }
  } catch (e, s) {
    printLog.e('Error verificando previous connections: $e');
    printLog.t('Stack trace: $s');
    // No relanzar el error para no afectar el flujo principal
  }
}
//*-Nueva lógica: Tokens en Alexa-Devices y ActiveUsers en sime-domotica-*\\

//*-Guarda el mail del owner de un equipo en dynamo-*\\
Future<void> putOwner(String pc, String sn, String data) async {
  try {
    await service.updateItem(tableName: 'sime-domotica', key: {
      'product_code': AttributeValue(s: pc),
      'device_id': AttributeValue(s: sn),
    }, attributeUpdates: {
      'owner': AttributeValueUpdate(value: AttributeValue(s: data)),
    });

    // printLog.i('Item escrito perfectamente $response');
  } catch (e) {
    printLog.e('Error inserting item: $e');
  }
}
//*-Guarda el mail del owner de un equipo en dynamo-*\\

//*-Guarda y lee los mails de los admins de un equipo en dynamo-*\\
Future<void> putSecondaryAdmins(String pc, String sn, List<String> data) async {
  if (data.isEmpty) {
    data.add('');
  }
  try {
    await service.updateItem(tableName: 'sime-domotica', key: {
      'product_code': AttributeValue(s: pc),
      'device_id': AttributeValue(s: sn),
    }, attributeUpdates: {
      'secondary_admin': AttributeValueUpdate(value: AttributeValue(ss: data)),
    });
  } catch (e) {
    printLog.e('Error inserting item: $e');
  }
}
//*-Guarda y lee los mails de los admins de un equipo en dynamo-*\\

//*-Escribe la distancia de encendido y apagado de el control por distancia de un equipo-*\\
Future<void> putDistanceOn(String pc, String sn, String data) async {
  try {
    await service.updateItem(tableName: 'sime-domotica', key: {
      'product_code': AttributeValue(s: pc),
      'device_id': AttributeValue(s: sn),
    }, attributeUpdates: {
      'distanceOn': AttributeValueUpdate(value: AttributeValue(n: data)),
    });

    // printLog.i('Item escrito perfectamente $response');
  } catch (e) {
    printLog.e('Error inserting item: $e');
  }
}

Future<void> putDistanceOff(String pc, String sn, String data) async {
  try {
    await service.updateItem(tableName: 'sime-domotica', key: {
      'product_code': AttributeValue(s: pc),
      'device_id': AttributeValue(s: sn),
    }, attributeUpdates: {
      'distanceOff': AttributeValueUpdate(value: AttributeValue(n: data)),
    });

    // printLog.i('Item escrito perfectamente $response');
  } catch (e) {
    printLog.e('Error inserting item: $e');
  }
}
//*-Escribe la distancia de encendido y apagado de el control por distancia de un equipo-*\\

//*-Guarda la data del alquiler temporario (airbnb) de un equipo-*\\
Future<void> saveATData(String pc, String sn, bool activate, String mail,
    String dOn, String dOff) async {
  try {
    await service.updateItem(tableName: 'sime-domotica', key: {
      'product_code': AttributeValue(s: pc),
      'device_id': AttributeValue(s: sn),
    }, attributeUpdates: {
      'AT': AttributeValueUpdate(value: AttributeValue(boolValue: activate)),
      'tenant': AttributeValueUpdate(value: AttributeValue(s: mail)),
      'distanceOn': AttributeValueUpdate(value: AttributeValue(n: dOn)),
      'distanceOff': AttributeValueUpdate(value: AttributeValue(n: dOff)),
    });

    activatedAT = activate;
    // printLog.i('Inquilino escrito perfectamente $response');
  } catch (e) {
    printLog.e('Error inserting item: $e');
  }
}
//*-Guarda la data del alquiler temporario (airbnb) de un equipo-*\\

//*-Guardar si un equipo es NA o NC-*\\
Future<void> saveNC(String pc, String sn, bool data) async {
  try {
    await service.updateItem(tableName: 'sime-domotica', key: {
      'product_code': AttributeValue(s: pc),
      'device_id': AttributeValue(s: sn),
    }, attributeUpdates: {
      'isNC': AttributeValueUpdate(value: AttributeValue(boolValue: data)),
    });

    // printLog.i('Item escrito perfectamente $response');
  } catch (e) {
    printLog.e('Error inserting item: $e');
  }
}
//*-Guardar si un equipo es NA o NC-*\\

///*-Guardar equipos en dynamo-*\\\
Future<void> putDevicesForAlexa(String email, List<String> data) async {
  if (data.isEmpty) {
    data.add('');
  }
  try {
    // Se actualiza el ítem, asignando 'devices' con la lista proporcionada (vacía o no).
    final response = await service.updateItem(
      tableName: 'Alexa-Devices',
      key: {
        'email': AttributeValue(s: email),
      },
      attributeUpdates: {
        'devices': AttributeValueUpdate(value: AttributeValue(ss: data)),
      },
    );
    printLog.i('Item actualizado correctamente: $response');
  } catch (e) {
    printLog.e('Error actualizando el ítem de Alexa: $e');
  }
}

Future<void> putPreviusConnections(String email, List<String> data,
    {bool isIntentionalClear = false}) async {
  // Si es un borrado intencional y la lista está vacía, usar el marcador fantasma
  if (data.isEmpty && isIntentionalClear) {
    data = [intentionallyEmptyMarker];
    // printLog.i('Lista vaciada intencionalmente, usando marcador fantasma');
  }
  // Si la lista está vacía sin ser intencional, bloquear solo si no es usuario nuevo
  else if (data.isEmpty && deviceLoadState != DeviceLoadState.newUser) {
    printLog.e(
        'Intento de sobrescritura con lista vacía bloqueado para usuario existente');
    throw Exception(
        'Operación bloqueada: intento de sobrescritura con lista vacía');
  }
  // Si la lista está vacía y es usuario nuevo, usar string vacío (comportamiento original)
  else if (data.isEmpty) {
    data.add('');
  }

  try {
    // Se actualiza el ítem, asignando 'devices' con la lista proporcionada
    await service.updateItem(
      tableName: 'Alexa-Devices',
      key: {
        'email': AttributeValue(s: email),
      },
      attributeUpdates: {
        'previusConnections':
            AttributeValueUpdate(value: AttributeValue(ss: data)),
      },
    );
  } catch (e) {
    printLog.e('Error actualizando la lista de dispositivos: $e');
    rethrow;
  }
}

///*-Guardar equipos en dynamo-*\\\

///*-Guardar y obtener folders de equipos -*\\\
Future<Map<String, List<String>>> getFolders(String email) async {
  Map<String, List<String>> foldersResult = {};

  try {
    final response = await service.getItem(
      tableName: 'Alexa-Devices',
      key: {'email': AttributeValue(s: email)},
    );

    folders.clear();

    if (response.item != null) {
      final dynamic foldersAttr = response.item!['folders'];

      if (foldersAttr != null && foldersAttr.m != null) {
        Map<String, AttributeValue> mapaRaw = foldersAttr.m!;

        mapaRaw.forEach((key, value) {
          foldersResult[key] =
              value.ss ?? value.l?.map((e) => e.s ?? "").toList() ?? [];
        });
      }
      printLog.d('Folders obtenidos para $email: $foldersResult');
      return foldersResult;
    } else {
      printLog.e('Item no encontrado para el email: $email');
      return {};
    }
  } catch (e) {
    printLog.e('Error al obtener folders: $e');
    return {};
  }
}

Future<void> putFolders(
    String email, Map<String, List<String>> foldersToSave) async {
  try {
    Map<String, AttributeValue> folderAttribute =
        foldersToSave.map((key, value) {
      return MapEntry(
        key,
        AttributeValue(
          l: value.map((deviceId) => AttributeValue(s: deviceId)).toList(),
        ),
      );
    });

    await service.updateItem(
      tableName: 'Alexa-Devices',
      key: {'email': AttributeValue(s: email)},
      attributeUpdates: {
        'folders': AttributeValueUpdate(
          value: AttributeValue(m: folderAttribute),
          action: AttributeAction.put,
        ),
      },
    );

    printLog.i('Sincronización completa: Map > List > String guardado.');
  } catch (e) {
    printLog.e('Error al guardar en Dynamo: $e');
  }
}

///*-Guardar y obtener folders de equipos -*\\\

///*-Guardar y obtener Nicknames de los equipo-*\\\
Future<void> putNicknames(String email, Map<String, String> data) async {
  try {
    await service.updateItem(tableName: 'Alexa-Devices', key: {
      'email': AttributeValue(s: email),
    }, attributeUpdates: {
      'nicknames': AttributeValueUpdate(
        value: AttributeValue(
          m: {
            for (final entry in data.entries)
              entry.key: AttributeValue(s: entry.value),
          },
        ),
      ),
    });

    // printLog.i('Item escrito perfectamente $response');
  } catch (e) {
    printLog.e('Error guardando alexa item: $e');
  }
}

Future<Map<String, String>> getNicknames(String email) async {
  Map<String, String> nicks = {};
  try {
    final response = await service.getItem(
      tableName: 'Alexa-Devices',
      key: {'email': AttributeValue(s: email)},
    );
    if (response.item != null) {
      // Convertir AttributeValue a String
      var item = response.item!;

      Map<String, AttributeValue> mapa = item['nicknames']?.m ?? {};
      mapa.forEach((key, value) {
        nicks.addAll({key: value.s ?? ''});
      });
      // printLog.i('Nicknames encontrados: $nicks');
      return nicks;
    } else {
      printLog.e('Item no encontrado. No está el mail en la database');
      return nicks;
    }
  } catch (e) {
    printLog.e('Error al obtener el item: $e');
    return nicks;
  }
}

Future<List<String>> getPreviusConnections(String email) async {
  try {
    final response = await service.getItem(
      tableName: 'Alexa-Devices',
      key: {'email': AttributeValue(s: email)},
    );
    if (response.item != null) {
      // Convertir AttributeValue a String
      var item = response.item!;

      List<String> equipos = item['previusConnections']?.ss ?? [];

      // Filtrar marcadores fantasma y strings vacíos
      equipos = equipos
          .where((device) =>
              device.isNotEmpty && device != intentionallyEmptyMarker)
          .toList();

      return equipos;
    } else {
      printLog.e('Item no encontrado. No está el mail en la database');
      return [];
    }
  } catch (e) {
    printLog.e('Error al obtener el item: $e');
    return [];
  }
}

///*-Guardar y obtener Nicknames de los equipo-*\\\

///*-Guardar el largo del Roller-*\\\
Future<void> putRollerLength(String pc, String sn, String data) async {
  try {
    await service.updateItem(tableName: 'sime-domotica', key: {
      'product_code': AttributeValue(s: pc),
      'device_id': AttributeValue(s: sn),
    }, attributeUpdates: {
      'rollerSavedLength': AttributeValueUpdate(value: AttributeValue(s: data)),
    });

    // printLog.i('Item escrito perfectamente $response');
  } catch (e) {
    printLog.e('Error inserting item: $e');
  }
}

///*-Guardar el largo del Roller-*\\\

///*-Leer las conexiones previas-*\\\
///Está función lee los equipos de la base de datos de DynamoDB
///y los guarda en las variables previusConnections.
///También lee los dispositivos de Asistentes por voz y los guarda en la variable alexaDevices.
///A su vez, guarda los topics a los que se va a suscribir el cliente MQTT en la variable topicsToSub.
///Por último, guarda los nicknames de los dispositivos en la variable nicknamesMap.
Future<void> getDevices(String email) async {
  deviceLoadState = DeviceLoadState.loading;

  try {
    final response = await service.getItem(
      tableName: 'Alexa-Devices',
      key: {'email': AttributeValue(s: email)},
    );

    if (response.item != null) {
      // Usuario existe en la base de datos
      var item = response.item!;
      List<String> equipos = item['previusConnections']?.ss ?? [];

      // Filtrar marcadores fantasma y strings vacíos
      equipos = equipos
          .where((device) =>
              device.isNotEmpty && device != intentionallyEmptyMarker)
          .toList();

      // Sin validaciones de formato - permitir cualquier formato de nombre de dispositivo

      previusConnections = equipos;
      deviceLoadState = DeviceLoadState.existingUserLoaded;
      lastSuccessfulLoad = DateTime.now();
      loadRetryCount = 0;

      for (String equipo in previusConnections) {
        String pc = DeviceManager.getProductCode(equipo);
        String sn = DeviceManager.extractSerialNumber(equipo);
        topicsToSub.add('devices_tx/$pc/$sn');
        subToTopicMQTT('devices_tx/$pc/$sn');
      }

      // printLog.i('Se encontro el siguiente item: $equipos');

      alexaDevices = item['devices']?.ss ?? [];
      if (alexaDevices.contains('') && alexaDevices.length == 1) {
        alexaDevices = [];
      }
      // printLog.i('Equipos de asistentes por voz: $alexaDevices');

      await DeviceManager.init();

      for (String device in previusConnections) {
        await queryItems(DeviceManager.getProductCode(device),
            DeviceManager.extractSerialNumber(device));
      }
    } else {
      // Usuario NO existe en la base de datos = Usuario nuevo
      // printLog.i('Item no encontrado. Usuario nuevo detectado');
      deviceLoadState = DeviceLoadState.newUser;
      previusConnections = [];
      lastSuccessfulLoad = DateTime.now();
      loadRetryCount = 0;
    }
  } catch (e) {
    printLog.e('Error al obtener dispositivos del usuario: $e');
    deviceLoadState = DeviceLoadState.loadError;
    loadRetryCount++;
  }
}

/// Agrega un dispositivo de forma segura, con protecciones contra sobrescritura accidental
/// Retorna:
/// - 'added': Dispositivo agregado exitosamente
/// - 'exists': Dispositivo ya existía en la lista
/// - 'error': Error al agregar el dispositivo
Future<String> safeAddDevice(String email, String deviceName) async {
  // Verificar el estado de carga antes de proceder
  switch (deviceLoadState) {
    case DeviceLoadState.unknown:
    case DeviceLoadState.loading:
      // printLog
      //     .i('Estado de carga incierto, reintentando cargar dispositivos...');
      await getDevices(email);
      if (deviceLoadState == DeviceLoadState.loadError) {
        return 'error';
      }
      break;

    case DeviceLoadState.loadError:
      printLog.e(
          'Error de carga detectado. No se agregará dispositivo para evitar sobrescritura');
      if (loadRetryCount < maxRetryAttempts) {
        // printLog.i(
        //     'Reintentando carga de dispositivos (intento ${loadRetryCount + 1}/$maxRetryAttempts)');
        await getDevices(email);
        if (deviceLoadState == DeviceLoadState.loadError) {
          return 'error';
        }
      } else {
        return 'error';
      }
      break;

    case DeviceLoadState.newUser:
    case DeviceLoadState.existingUserLoaded:
      // Estados seguros para proceder
      break;
  }

  // Validar que el dispositivo no esté ya en la lista
  if (previusConnections.contains(deviceName)) {
    // printLog.i('Dispositivo $deviceName ya está en la lista');
    return 'exists';
  }

  // Sin validación de formato - permitir cualquier nombre de dispositivo

  // Crear backup de la lista actual
  List<String> backupList = List<String>.from(previusConnections);

  try {
    // Agregar el nuevo dispositivo
    previusConnections.add(deviceName);

    // Intentar guardar en DynamoDB
    await putPreviusConnections(email, previusConnections);

    // printLog.i('Dispositivo $deviceName agregado exitosamente');
    return 'added';
  } catch (e) {
    // En caso de error, restaurar la lista anterior
    printLog.e('Error al guardar dispositivo, restaurando lista anterior: $e');
    previusConnections.clear();
    previusConnections.addAll(backupList);
    return 'error';
  }
}

//*-Leer las conexiones previas-*\\\

/// Guarda la lista [eventosCreados] (List<Map<String, dynamic>>) bajo la clave primaria [email]
void putEventos(
  String email,
  List<Map<String, dynamic>> eventosCreados,
) async {
  try {
    // Convertir cada Map a AttributeValue(M)
    final attributeList = eventosCreados.map((evento) {
      final m = <String, AttributeValue>{};
      evento.forEach((key, value) {
        if (value is String) {
          m[key] = AttributeValue(s: value);
        } else if (value is num) {
          m[key] = AttributeValue(n: value.toString());
        } else if (value is bool) {
          m[key] = AttributeValue(boolValue: value);
        } else if (value is Duration) {
          // Guardar Duration como microsegundos con un marcador especial
          m[key] = AttributeValue(s: 'DURATION:${value.inMicroseconds}');
        } else if (value is List) {
          m[key] = AttributeValue(
              l: value.map((e) {
            if (e is String) return AttributeValue(s: e);
            if (e is num) return AttributeValue(n: e.toString());
            if (e is bool) return AttributeValue(boolValue: e);
            if (e is Duration) {
              return AttributeValue(n: e.inMicroseconds.toString());
            }
            if (e is Map<String, dynamic>) {
              // Manejar Maps dentro de listas (como pasos de cadena)
              final nestedMap = <String, AttributeValue>{};
              e.forEach((k, v) {
                if (v is String) {
                  nestedMap[k] = AttributeValue(s: v);
                } else if (v is num) {
                  nestedMap[k] = AttributeValue(n: v.toString());
                } else if (v is bool) {
                  nestedMap[k] = AttributeValue(boolValue: v);
                } else if (v is Duration) {
                  nestedMap[k] =
                      AttributeValue(s: 'DURATION:${v.inMicroseconds}');
                } else if (v is List) {
                  // Manejar listas anidadas
                  nestedMap[k] = AttributeValue(
                    l: v.map((item) {
                      if (item is String) return AttributeValue(s: item);
                      if (item is num) {
                        return AttributeValue(n: item.toString());
                      }
                      if (item is bool) return AttributeValue(boolValue: item);
                      return AttributeValue(s: item.toString());
                    }).toList(),
                  );
                } else {
                  nestedMap[k] = AttributeValue(s: v.toString());
                }
              });
              return AttributeValue(m: nestedMap);
            }
            return AttributeValue(s: e.toString());
          }).toList());
        } else if (value is Map<String, dynamic>) {
          final nested = <String, AttributeValue>{};
          value.forEach((k, v) {
            if (v is String) {
              nested[k] = AttributeValue(s: v);
            } else if (v is num) {
              nested[k] = AttributeValue(n: v.toString());
            } else if (v is bool) {
              nested[k] = AttributeValue(boolValue: v);
            } else if (v is Duration) {
              // Guardar Duration como microsegundos
              nested[k] = AttributeValue(n: v.inMicroseconds.toString());
            } else {
              nested[k] = AttributeValue(s: v.toString());
            }
          });
          m[key] = AttributeValue(m: nested);
        } else {
          m[key] = AttributeValue(s: value.toString());
        }
      });
      return AttributeValue(m: m);
    }).toList();

    // Actualizar el item en DynamoDB
    await service.updateItem(
      tableName: 'Alexa-Devices',
      key: {'email': AttributeValue(s: email)},
      attributeUpdates: {
        'events': AttributeValueUpdate(value: AttributeValue(l: attributeList)),
      },
    );
    // printLog.i('Eventos guardados correctamente');
  } catch (e) {
    printLog.e('Error al guardar eventos: $e');
  }
}

/// Carga y convierte de vuelta a List<Map<String, dynamic>> desde DynamoDB
Future<List<Map<String, dynamic>>> getEventos(
  String email,
) async {
  try {
    final response = await service.getItem(
      tableName: 'Alexa-Devices',
      key: {'email': AttributeValue(s: email)},
    );

    final listAttr = response.item?['events']?.l;
    if (listAttr == null) return [];

    final result = listAttr.map((av) {
      final map = <String, dynamic>{};
      av.m?.forEach((key, val) {
        if (val.s != null) {
          // Verificar si es un Duration codificado
          if (val.s!.startsWith('DURATION:')) {
            final microseconds = int.tryParse(val.s!.substring(9));
            map[key] = microseconds != null
                ? Duration(microseconds: microseconds)
                : Duration.zero;
          } else {
            map[key] = val.s;
          }
        } else if (val.n != null) {
          map[key] = num.parse(val.n!);
        } else if (val.boolValue != null) {
          map[key] = val.boolValue;
        } else if (val.l != null) {
          map[key] = val.l!.map((e) {
            if (e.s != null) {
              return e.s;
            } else if (e.n != null) {
              return num.parse(e.n!);
            } else if (e.boolValue != null) {
              return e.boolValue;
            } else if (e.m != null) {
              // Procesar Map anidado correctamente
              final nestedMap = <String, dynamic>{};
              e.m!.forEach((k, v) {
                if (v.s != null) {
                  // Verificar si es un Duration codificado
                  if (v.s!.startsWith('DURATION:')) {
                    final microseconds = int.tryParse(v.s!.substring(9));
                    nestedMap[k] = microseconds != null
                        ? Duration(microseconds: microseconds)
                        : Duration.zero;
                  } else {
                    nestedMap[k] = v.s;
                  }
                } else if (v.n != null) {
                  nestedMap[k] = num.parse(v.n!);
                } else if (v.boolValue != null) {
                  nestedMap[k] = v.boolValue;
                } else if (v.l != null) {
                  // Manejar listas anidadas dentro de maps
                  nestedMap[k] = v.l!.map((listItem) {
                    if (listItem.s != null) {
                      return listItem.s;
                    } else if (listItem.n != null) {
                      return num.parse(listItem.n!);
                    } else if (listItem.boolValue != null) {
                      return listItem.boolValue;
                    } else {
                      return null;
                    }
                  }).toList();
                } else {
                  nestedMap[k] = null;
                }
              });
              return nestedMap;
            } else {
              return null;
            }
          }).toList();
        } else if (val.m != null) {
          final nested = <String, dynamic>{};
          val.m!.forEach((k, v) {
            if (v.s != null) {
              // Verificar si es un Duration codificado
              if (v.s!.startsWith('DURATION:')) {
                final microseconds = int.tryParse(v.s!.substring(9));
                nested[k] = microseconds != null
                    ? Duration(microseconds: microseconds)
                    : Duration.zero;
              } else {
                nested[k] = v.s;
              }
            } else if (v.n != null) {
              nested[k] = num.parse(v.n!);
            } else if (v.boolValue != null) {
              nested[k] = v.boolValue;
            } else {
              nested[k] = null;
            }
          });
          map[key] = nested;
        } else {
          map[key] = null;
        }
      });

      return map;
    }).toList();

    // printLog.i('Eventos procesados: ${result.length}');
    return result;
  } catch (e) {
    printLog.e('Error al cargar eventos: $e');
    return [];
  }
}

///Guarda la ubicación del equipo en la base de datos
Future<void> saveLocation(String pc, String sn, String data) async {
  try {
    await service.updateItem(tableName: 'sime-domotica', key: {
      'product_code': AttributeValue(s: pc),
      'device_id': AttributeValue(s: sn),
    }, attributeUpdates: {
      'deviceLocation': AttributeValueUpdate(value: AttributeValue(s: data)),
    });

    // printLog.i('Item escrito perfectamente $response');
  } catch (e) {
    printLog.e('Error inserting item: $e');
  }
}

///Guarda las versiones de Hardware y Software
Future<void> putVersions(String pc, String sn, String hard, String soft) async {
  try {
    await service.updateItem(tableName: 'sime-domotica', key: {
      'product_code': AttributeValue(s: pc),
      'device_id': AttributeValue(s: sn),
    }, attributeUpdates: {
      'HardwareVersion': AttributeValueUpdate(value: AttributeValue(s: hard)),
      'SoftwareVersion': AttributeValueUpdate(value: AttributeValue(s: soft)),
    });

    // printLog.i('Item escrito perfectamente $response');
  } catch (e) {
    printLog.e('Error inserting item: $e');
  }
}

//*-Obtener datos generales de la aplicación desde GENERALDATA-*\\
Future<Map<String, dynamic>> getGeneralData() async {
  try {
    // printLog.i('Obteniendo datos generales de GENERALDATA...');
    final response = await service.getItem(
      tableName: 'GENERALDATA',
      key: {
        'App': AttributeValue(s: 'Caldén Smart'),
      },
    );

    if (response.item != null) {
      Map<String, dynamic> generalData = {};
      var item = response.item!;

      for (var key in item.keys) {
        if (key == 'App') continue; // Saltear la clave principal

        var value = item[key];
        if (value?.m != null) {
          // Es un mapa (Map)
          Map<String, dynamic> mapValue = {};
          for (var mapKey in value!.m!.keys) {
            var mapVal = value.m![mapKey];
            mapValue[mapKey] = mapVal?.s ??
                mapVal?.n ??
                mapVal?.boolValue ??
                mapVal?.ss ??
                mapVal?.toString();
          }
          generalData[key] = mapValue;
        } else if (value?.l != null) {
          // Es una lista (List)
          List<dynamic> listValue = [];
          for (var listItem in value!.l!) {
            listValue.add(listItem.s ??
                listItem.n ??
                listItem.boolValue ??
                listItem.toString());
          }
          generalData[key] = listValue;
        } else if (value?.ss != null) {
          // Es un conjunto de strings (StringSet)
          generalData[key] = value!.ss!;
        } else {
          // Es un valor simple
          generalData[key] =
              value?.s ?? value?.n ?? value?.boolValue ?? value?.toString();
        }
      }

      // printLog.i('Datos generales obtenidos correctamente');
      return generalData;
    } else {
      printLog.e('No se encontraron datos generales en GENERALDATA');
      return {};
    }
  } catch (e) {
    printLog.e('Error al obtener datos generales de GENERALDATA: $e');
    return {};
  }
}
//*-Obtener datos generales de la aplicación desde GENERALDATA-*\\

//*- Guarda evento: Control por disparadores (NUEVA LÓGICA) -*\\
/// Guarda un evento de control por disparadores en la nueva tabla
/// [activador] es el nombre del dispositivo que activa el disparador
/// [email] es el email del usuario
/// [nombreEvento] es el nombre del evento
/// [nuevosEjecutores] son los ejecutores a guardar con sus estados (true/false)
/// [tipoAlerta] especifica el tipo de alerta:
///   - Para alertas simples: 'ejecutoresAlert_true' o 'ejecutoresAlert_false'
///   - Para termómetros: 'ejecutoresMAX_true', 'ejecutoresMAX_false', 'ejecutoresMIN_true', 'ejecutoresMIN_false'
Future<void> putEventoControlPorDisparadores(
  String activador,
  String email,
  String nombreEvento,
  Map<String, bool> nuevosEjecutores, {
  String tipoAlerta = 'ejecutoresAlert_true',
}) async {
  try {
    String sortKey = '$email:$nombreEvento';

    await service.putItem(
      tableName: 'Eventos_ControlPorDisparadores',
      item: {
        'deviceName': AttributeValue(s: activador),
        'email:nombreEvento': AttributeValue(s: sortKey),
        tipoAlerta: AttributeValue(
          m: {
            for (final entry in nuevosEjecutores.entries)
              entry.key: AttributeValue(boolValue: entry.value),
          },
        ),
      },
    );

    // printLog.i(
    //     'Evento de control por disparadores guardado (nueva lógica): $response');
  } catch (e) {
    printLog.e('Error guardando evento de control por disparadores: $e');
  }
}

void deleteEventoControlPorDisparadores(
    String activador, String email, String nombreEvento) async {
  try {
    String sortKey = '$email:$nombreEvento';

    await service.deleteItem(
      tableName: 'Eventos_ControlPorDisparadores',
      key: {
        'deviceName': AttributeValue(s: activador),
        'email:nombreEvento': AttributeValue(s: sortKey),
      },
    );
  } catch (e) {
    printLog.e('Error eliminando evento de control por disparadores: $e');
  }
}
//*- Guarda evento: Control por disparadores -*\\

//*- Guarda evento: Control por horarios -*\\
/// Guarda un evento de control por horarios
/// [horario] es la hora en formato string (PK)
/// [email] es el email del usuario
/// [nombreEvento] es el nombre del evento
/// [ejecutores] mapa de ejecutores con sus estados (true/false)
///   - Las claves deben estar en formato "nombre:tipo" donde:
///   - tipo = 'dispositivo' para dispositivos individuales
///   - tipo = 'grupo' para eventos de tipo grupo
///   - tipo = 'cadena' para eventos de tipo cadena
/// [days] lista de días como números (0=Domingo, 1=Lunes, etc.)
/// [timezoneOffset] offset del timezone en horas desde UTC
/// [timezoneName] nombre del timezone (ej: "GMT-03:00")
Future<void> putEventoControlPorHorarios(
    String horario,
    String email,
    String nombreEvento,
    Map<String, bool> ejecutores,
    List<int> days,
    int timezoneOffset,
    String timezoneName) async {
  try {
    String sortKey = '$email:$nombreEvento';

    await service.putItem(
      tableName: 'Eventos_ControlPorHorarios',
      item: {
        'horario': AttributeValue(s: horario),
        'email:nombreEvento': AttributeValue(s: sortKey),
        'ejecutores': AttributeValue(
          m: {
            for (final entry in ejecutores.entries)
              entry.key: AttributeValue(boolValue: entry.value),
          },
        ),
        'days': AttributeValue(
          l: days.map((day) => AttributeValue(n: day.toString())).toList(),
        ),
        'timezoneOffset': AttributeValue(n: timezoneOffset.toString()),
        'timezoneName': AttributeValue(s: timezoneName),
      },
    );

    // printLog.i('Evento de control por horarios guardado: $response');
    // printLog
    //     .i('Ejecutores con formato nombre:tipo: ${ejecutores.keys.toList()}');
    // printLog.i('Días guardados como números: $days');
    // printLog.i(
    //     'Timezone: $timezoneName (UTC${timezoneOffset >= 0 ? '+' : ''}$timezoneOffset)');
  } catch (e) {
    printLog.e('Error guardando evento de control por horarios: $e');
  }
}

/// Elimina un evento de control por horarios
/// [horario] es la hora en formato string (PK)
/// [email] es el email del usuario
/// [nombreEvento] es el nombre del evento
void deleteEventoControlPorHorarios(
    String horario, String email, String nombreEvento) async {
  try {
    String sortKey = '$email:$nombreEvento';
    await service.deleteItem(
      tableName: 'Eventos_ControlPorHorarios',
      key: {
        'horario': AttributeValue(s: horario),
        'email:nombreEvento': AttributeValue(s: sortKey),
      },
    );

    // printLog.i('Evento de control por horarios eliminado: $response');
  } catch (e) {
    printLog.e('Error eliminando evento de control por horarios: $e');
  }
}

//*- Guarda evento: Control por horarios -*\\

//*- Dispositivos control por distancia -*\\
Future<void> putDevicesInDistanceControl(
    String email, List<String> data) async {
  if (data.isEmpty) {
    data.add('');
  }
  try {
    await service.updateItem(tableName: 'Alexa-Devices', key: {
      'email': AttributeValue(s: email)
    }, attributeUpdates: {
      'DevicesInDistanceControl':
          AttributeValueUpdate(value: AttributeValue(ss: data)),
    });

    // printLog.i('Item escrito perfectamente $response');
  } catch (e) {
    printLog.e('Error inserting item: $e');
  }
}

Future<List<String>> getDevicesInDistanceControl(String email) async {
  try {
    final response = await service.getItem(
      tableName: 'Alexa-Devices',
      key: {'email': AttributeValue(s: email)},
    );
    if (response.item != null) {
      // Convertir AttributeValue a String
      var item = response.item!;
      List<String> dsControl = item['DevicesInDistanceControl']?.ss ?? [];

      // printLog.i('Se encontro el siguiente item: $dsControl');

      if (dsControl.contains('') && dsControl.length == 1) {
        return [];
      } else {
        return dsControl;
      }
    } else {
      printLog.e('Item no encontrado.');
      return [];
    }
  } catch (e) {
    printLog.e('Error al obtener el item: $e');
    return [];
  }
}

Future<void> putDistanceControl(String pc, String sn, bool status) async {
  try {
    await service.updateItem(tableName: 'sime-domotica', key: {
      'product_code': AttributeValue(s: pc),
      'device_id': AttributeValue(s: sn),
    }, attributeUpdates: {
      'distanceControlActive':
          AttributeValueUpdate(value: AttributeValue(boolValue: status)),
    });

    // printLog.i('Item escrito perfectamente $response');
  } catch (e) {
    printLog.e('Error inserting item: $e');
  }
}
//*- Dispositivos control por distancia -*\\

//*- Guarda evento: Control por cadena -*\\
void putEventoControlPorCadena(
    String email, String nombreEvento, List<Map<String, dynamic>> pasos) async {
  try {
    final response = await service.putItem(
      tableName: 'Eventos_ControlPorCadena',
      item: {
        'email': AttributeValue(s: email),
        'nombreEvento': AttributeValue(s: nombreEvento),
        'pasos': AttributeValue(
          l: pasos.map((paso) {
            return AttributeValue(m: {
              'paso_index': AttributeValue(n: paso['paso_index'].toString()),
              'ejecutores': AttributeValue(
                m: {
                  for (final entry in paso['ejecutores'].entries)
                    entry.key: AttributeValue(boolValue: entry.value),
                },
              ),
              'delay': AttributeValue(n: paso['delay'].toString()),
            });
          }).toList(),
        ),
      },
    );

    printLog.i('Evento de control por cadena guardado: $response');
  } catch (e) {
    printLog.e('Error guardando evento de control por cadena: $e');
  }
}

void deleteEventoControlPorCadena(String email, String nombreEvento) async {
  try {
    await service.deleteItem(
      tableName: 'Eventos_ControlPorCadena',
      key: {
        'email': AttributeValue(s: email),
        'nombreEvento': AttributeValue(s: nombreEvento),
      },
    );

    // printLog.i('Evento de control por cadena eliminado: $response');
  } catch (e) {
    printLog.e('Error eliminando evento de control por cadena: $e');
  }
}

// Consultar todos los eventos de control por cadena del usuario
Future<List<Map<String, dynamic>>> queryEventosControlPorCadena(
    String email) async {
  try {
    final response = await service.query(
      tableName: 'Eventos_ControlPorCadena',
      keyConditionExpression: 'email = :email',
      expressionAttributeValues: {
        ':email': AttributeValue(s: email),
      },
    );

    List<Map<String, dynamic>> eventos = [];

    if (response.items != null) {
      for (var item in response.items!) {
        eventos.add({
          'nombreEvento': item['nombreEvento']?.s ?? '',
          'estado_ejecucion': item['estado_ejecucion']?.m != null
              ? {
                  'status': item['estado_ejecucion']!.m!['status']?.s ?? 'idle',
                  'paso_actual': int.tryParse(
                          item['estado_ejecucion']!.m!['paso_actual']?.n ??
                              '0') ??
                      0,
                  'total_pasos': int.tryParse(
                          item['estado_ejecucion']!.m!['total_pasos']?.n ??
                              '0') ??
                      0,
                  'pasos_completados': item['estado_ejecucion']!
                          .m!['pasos_completados']
                          ?.l
                          ?.map((e) => int.tryParse(e.n ?? '0') ?? 0)
                          .toList() ??
                      [],
                }
              : null,
        });
      }
    }

    // printLog.i('Eventos de control por cadena consultados: ${eventos.length}');
    return eventos;
  } catch (e) {
    printLog.e('Error consultando eventos de control por cadena: $e');
    return [];
  }
}

// 🆕 Query eventos de Control de Riego con estado de ejecución
Future<List<Map<String, dynamic>>> queryEventosControlDeRiego(
    String email) async {
  try {
    final response = await service.query(
      tableName: 'Eventos_ControlDeRiego',
      keyConditionExpression: 'email = :email',
      expressionAttributeValues: {
        ':email': AttributeValue(s: email),
      },
    );

    List<Map<String, dynamic>> eventos = [];

    if (response.items != null) {
      for (var item in response.items!) {
        eventos.add({
          'nombreEvento': item['nombreEvento']?.s ?? '',
          'estado_ejecucion': item['estado_ejecucion']?.m != null
              ? {
                  'status': item['estado_ejecucion']!.m!['status']?.s ?? 'idle',
                  'paso_actual': int.tryParse(
                          item['estado_ejecucion']!.m!['paso_actual']?.n ??
                              '0') ??
                      0,
                  'total_pasos': int.tryParse(
                          item['estado_ejecucion']!.m!['total_pasos']?.n ??
                              '0') ??
                      0,
                  'pasos_completados': item['estado_ejecucion']!
                          .m!['pasos_completados']
                          ?.l
                          ?.map((e) => int.tryParse(e.n ?? '0') ?? 0)
                          .toList() ??
                      [],
                  'zonas_canceladas_por_lluvia': item['estado_ejecucion']!
                          .m!['zonas_canceladas_por_lluvia']
                          ?.l
                          ?.map((e) => e.s ?? '')
                          .toList() ??
                      [],
                }
              : null,
        });
      }
    }

    // printLog.i('Eventos de control de riego consultados: ${eventos.length}');
    return eventos;
  } catch (e) {
    printLog.e('Error consultando eventos de control de riego: $e');
    return [];
  }
}
//*- Guarda evento: Control por cadena -*\\

//*- Guarda evento: Control por grupos -*\\
void putEventoControlPorGrupos(
    String email, String nombreEvento, List<String> grupo) async {
  try {
    await service.putItem(
      tableName: 'Eventos_ControlPorGrupos',
      item: {
        'email': AttributeValue(s: email),
        'nombreEvento': AttributeValue(s: nombreEvento),
        'grupo': AttributeValue(ss: grupo),
      },
    );

    // printLog.i('Evento de control por grupos guardado: $response');
  } catch (e) {
    printLog.e('Error guardando evento de control por grupos: $e');
  }
}

void deleteEventoControlPorGrupos(String email, String nombreEvento) async {
  try {
    await service.deleteItem(
      tableName: 'Eventos_ControlPorGrupos',
      key: {
        'email': AttributeValue(s: email),
        'nombreEvento': AttributeValue(s: nombreEvento),
      },
    );

    // printLog.i('Evento de control por grupos eliminado: $response');
  } catch (e) {
    printLog.e('Error eliminando evento de control por grupos: $e');
  }
}
//*- Guarda evento: Control por grupos -*\\

//*- Guarda evento: Control por clima -*\\
void putEventoControlPorClima(String email, String nombreEvento, String clima,
    Map<String, Map<String, bool>> ejecutores, String? windDirection) async {
  try {
    await service.putItem(
      tableName: 'Eventos_ControlPorClima',
      item: {
        'email': AttributeValue(s: email),
        'nombreEvento': AttributeValue(s: nombreEvento),
        'clima': AttributeValue(s: clima),
        'ejecutores': AttributeValue(
          m: {
            for (final entry in ejecutores.entries) ...{
              entry.key: AttributeValue(m: {
                for (final subEntry in entry.value.entries) ...{
                  subEntry.key: AttributeValue(boolValue: subEntry.value),
                }
              }),
            }
          },
        ),
        if (windDirection != null) ...{
          'wind_direction': AttributeValue(s: windDirection),
        },
      },
    );

    // printLog.i('Evento de control por clima guardado: $response');
  } catch (e) {
    printLog.e('Error guardando evento de control por clima: $e');
  }
}

void deleteEventoControlPorClima(String email, String nombreEvento) async {
  try {
    await service.deleteItem(
      tableName: 'Eventos_ControlPorClima',
      key: {
        'email': AttributeValue(s: email),
        'nombreEvento': AttributeValue(s: nombreEvento),
      },
    );

    // printLog.i('Evento de control por clima eliminado: $response');
  } catch (e) {
    printLog.e('Error eliminando evento de control por clima: $e');
  }
}
//*- Guarda evento: Control por clima -*\\

//*- Guarda las extensiones de riego -*\\
Future<void> putRiegoExtensions(String pc, String sn, List<String> data) async {
  if (data.isEmpty) {
    data.add('');
  }
  try {
    await service.updateItem(tableName: 'sime-domotica', key: {
      'product_code': AttributeValue(s: pc),
      'device_id': AttributeValue(s: sn),
    }, attributeUpdates: {
      'riegoExtensions': AttributeValueUpdate(value: AttributeValue(ss: data)),
    });

    // printLog.i('Item escrito perfectamente $response');
  } catch (e) {
    printLog.e('Error inserting item: $e');
  }
}

//*- Guarda el estado de freeBomb -*\\
Future<void> putFreeBomb(String pc, String sn, bool status) async {
  try {
    await service.updateItem(tableName: 'sime-domotica', key: {
      'product_code': AttributeValue(s: pc),
      'device_id': AttributeValue(s: sn),
    }, attributeUpdates: {
      'freeBomb':
          AttributeValueUpdate(value: AttributeValue(boolValue: status)),
    });

    // printLog.i('Item freeBomb escrito perfectamente $response');
  } catch (e) {
    printLog.e('Error insertando freeBomb: $e');
  }
}

//*- Guarda el maestro de riego para extensiones -*\\
Future<void> putRiegoMaster(
    String pc, String sn, String masterDeviceName) async {
  try {
    await service.updateItem(tableName: 'sime-domotica', key: {
      'product_code': AttributeValue(s: pc),
      'device_id': AttributeValue(s: sn),
    }, attributeUpdates: {
      'riegoMaster':
          AttributeValueUpdate(value: AttributeValue(s: masterDeviceName)),
    });

    // printLog.i('Item riegoMaster escrito perfectamente $response');
  } catch (e) {
    printLog.e('Error insertando riegoMaster: $e');
  }
}
//*- Guarda el maestro de riego para extensiones -*\\

//*- Guarda evento: Control de riego -*\\
void putEventoControlDeRiego(String email, String nombreEvento,
    bool cancelIfRain, String bomba, List<Map<String, dynamic>> pasos) async {
  try {
    await service.putItem(
      tableName: 'Eventos_ControlDeRiego',
      item: {
        'email': AttributeValue(s: email),
        'nombreEvento': AttributeValue(s: nombreEvento),
        'cancelIfRain': AttributeValue(boolValue: cancelIfRain),
        'bomba': AttributeValue(s: bomba),
        'pasos': AttributeValue(
          l: pasos.map((paso) {
            return AttributeValue(m: {
              'device': AttributeValue(s: paso['device']),
              'duration': AttributeValue(n: paso['duration'].toString()),
              'duration_seg':
                  AttributeValue(n: paso['duration_seg'].toString()),
            });
          }).toList(),
        ),
      },
    );

    // printLog.i('Evento de control de riego guardado: $response');
  } catch (e) {
    printLog.e('Error guardando evento de control de riego: $e');
  }
}

void deleteEventoControlDeRiego(String email, String nombreEvento) async {
  try {
    await service.deleteItem(
      tableName: 'Eventos_ControlDeRiego',
      key: {
        'email': AttributeValue(s: email),
        'nombreEvento': AttributeValue(s: nombreEvento),
      },
    );

    // printLog.i('Evento de control de riego eliminado: $response');
  } catch (e) {
    printLog.e('Error eliminando evento de control de riego: $e');
  }
}

//*- Funciones para restricciones horarias de administradores secundarios -*\\

/// Guarda las restricciones horarias para un administrador secundario
Future<void> putAdminTimeRestrictions(String pc, String sn,
    Map<String, Map<String, dynamic>> restrictions) async {
  try {
    // Convertir el map a formato compatible con DynamoDB
    Map<String, AttributeValue> dynamoMap = {};

    restrictions.forEach((email, config) {
      dynamoMap[email] = AttributeValue(
        s: jsonEncode({
          'enabled': config['enabled'] ?? false,
          'startHour': config['startHour'] ?? 0,
          'startMinute': config['startMinute'] ?? 0,
          'endHour': config['endHour'] ?? 23,
          'endMinute': config['endMinute'] ?? 59,
          'weekdays':
              config['weekdays'] ?? [1, 2, 3, 4, 5, 6, 7], // 1=Lunes, 7=Domingo
        }),
      );
    });

    final response = await service.updateItem(
      tableName: 'sime-domotica',
      key: {
        'product_code': AttributeValue(s: pc),
        'device_id': AttributeValue(s: sn),
      },
      attributeUpdates: {
        'admin_time_restrictions': AttributeValueUpdate(
          value: AttributeValue(m: dynamoMap),
        ),
      },
    );

    printLog.i('Restricciones horarias guardadas: $response');
  } catch (e) {
    printLog.e('Error guardando restricciones horarias: $e');
  }
}

/// Obtiene las restricciones horarias de administradores secundarios
Future<Map<String, Map<String, dynamic>>> getAdminTimeRestrictions(
    String pc, String sn) async {
  try {
    final response = await service.getItem(
      tableName: 'sime-domotica',
      key: {
        'product_code': AttributeValue(s: pc),
        'device_id': AttributeValue(s: sn),
      },
    );

    if (response.item != null &&
        response.item!['admin_time_restrictions'] != null) {
      Map<String, AttributeValue> dynamoMap =
          response.item!['admin_time_restrictions']!.m!;
      Map<String, Map<String, dynamic>> restrictions = {};

      dynamoMap.forEach((email, value) {
        try {
          Map<String, dynamic> config = jsonDecode(value.s!);
          restrictions[email] = config;
        } catch (e) {
          printLog.e('Error parseando restricción para $email: $e');
        }
      });

      return restrictions;
    }
    return {};
  } catch (e) {
    printLog.e('Error obteniendo restricciones horarias: $e');
    return {};
  }
}

/// Verifica si un administrador secundario puede usar el dispositivo en el horario actual
Future<bool> isAdminAllowedAtCurrentTime(
    String pc, String sn, String adminEmail) async {
  try {
    Map<String, Map<String, dynamic>> restrictions =
        await getAdminTimeRestrictions(pc, sn);

    if (!restrictions.containsKey(adminEmail)) {
      return true; // Sin restricciones = permitido
    }

    Map<String, dynamic> config = restrictions[adminEmail]!;

    if (!(config['enabled'] ?? false)) {
      return true; // Restricciones deshabilitadas = permitido
    }

    DateTime now = DateTime.now();
    int currentWeekday = now.weekday; // 1=Lunes, 7=Domingo
    List<dynamic> allowedWeekdays = config['weekdays'] ?? [1, 2, 3, 4, 5, 6, 7];

    // Verificar si hoy está permitido
    if (!allowedWeekdays.contains(currentWeekday)) {
      return false;
    }

    // Verificar horario
    int startHour = config['startHour'] ?? 0;
    int startMinute = config['startMinute'] ?? 0;
    int endHour = config['endHour'] ?? 23;
    int endMinute = config['endMinute'] ?? 59;

    int currentMinutes = now.hour * 60 + now.minute;
    int startMinutes = startHour * 60 + startMinute;
    int endMinutes = endHour * 60 + endMinute;

    return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
  } catch (e) {
    printLog.e('Error verificando permisos horarios: $e');
    return true; // En caso de error, permitir acceso
  }
}

//*- Funciones para restricciones de WiFi de administradores secundarios -*\\

/// Guarda las restricciones de WiFi para un administrador secundario
Future<void> saveAdminWifiRestrictions(String pc, String sn, String adminEmail,
    Map<String, dynamic> config) async {
  try {
    // Obtener restricciones existentes
    Map<String, Map<String, dynamic>> currentRestrictions =
        await getAdminWifiRestrictions(pc, sn);

    // Actualizar o agregar la configuración del administrador
    currentRestrictions[adminEmail] = config;

    // Convertir a formato DynamoDB
    Map<String, AttributeValue> restrictionsMap = {};
    currentRestrictions.forEach((email, cfg) {
      restrictionsMap[email] = AttributeValue(s: jsonEncode(cfg));
    });

    await service.updateItem(
      tableName: 'sime-domotica',
      key: {
        'product_code': AttributeValue(s: pc),
        'device_id': AttributeValue(s: sn),
      },
      updateExpression: 'SET admin_wifi_restrictions = :restrictions',
      expressionAttributeValues: {
        ':restrictions': AttributeValue(m: restrictionsMap),
      },
    );

    printLog.i('Restricciones de WiFi guardadas para $adminEmail');
  } catch (e) {
    printLog.e('Error guardando restricciones de WiFi: $e');
    rethrow;
  }
}

/// Obtiene las restricciones de WiFi de administradores secundarios
Future<Map<String, Map<String, dynamic>>> getAdminWifiRestrictions(
    String pc, String sn) async {
  try {
    final response = await service.getItem(
      tableName: 'sime-domotica',
      key: {
        'product_code': AttributeValue(s: pc),
        'device_id': AttributeValue(s: sn),
      },
    );

    if (response.item != null &&
        response.item!['admin_wifi_restrictions'] != null) {
      Map<String, AttributeValue> dynamoMap =
          response.item!['admin_wifi_restrictions']!.m!;
      Map<String, Map<String, dynamic>> restrictions = {};

      dynamoMap.forEach((email, value) {
        try {
          Map<String, dynamic> config = jsonDecode(value.s!);
          restrictions[email] = config;
        } catch (e) {
          printLog.e('Error parseando restricción de WiFi para $email: $e');
        }
      });

      return restrictions;
    }
    return {};
  } catch (e) {
    printLog.e('Error obteniendo restricciones de WiFi: $e');
    return {};
  }
}

/// Verifica si un administrador secundario puede usar el WiFi
Future<bool> isAdminAllowedToUseWifi(
    String pc, String sn, String adminEmail) async {
  try {
    Map<String, Map<String, dynamic>> restrictions =
        await getAdminWifiRestrictions(pc, sn);

    if (!restrictions.containsKey(adminEmail)) {
      return true; // Sin restricciones = permitido
    }

    Map<String, dynamic> config = restrictions[adminEmail]!;

    // Si las restricciones de WiFi están habilitadas, no permitir acceso
    if (config['enabled'] ?? false) {
      return false;
    }

    return true; // Restricciones deshabilitadas = permitido
  } catch (e) {
    printLog.e('Error verificando permisos de WiFi: $e');
    return true; // En caso de error, permitir acceso
  }
}

/// Guarda un log de impresión en la tabla PrintLogHistorial
void savePrintLog(String email, String log) async {
  try {
    final response =
        await service.updateItem(tableName: 'PrintLogHistorial', key: {
      'email': AttributeValue(s: email),
      'key': AttributeValue(n: printLogHistorialKey.toString()),
    }, attributeUpdates: {
      'logs': AttributeValueUpdate(
          value: AttributeValue(ss: [log]), action: AttributeAction.add),
    });

    printLog.i('Log guardado perfectamente $response');
  } catch (e) {
    printLog.e('Error insertando log: $e');
  }
}

/// Guarda registros de logs del dispositivo en la tabla sime-domotica
/// Los logs se guardan bajo el atributo 'device_register_ble' como un mapa
/// donde la clave es el timestamp de sesión y el valor es una lista de logs
Future<void> saveDeviceRegisterLog(String pc, String sn, int sessionTimestamp,
    List<Map<String, dynamic>> logs) async {
  try {
    // Usar el timestamp de sesión como claveq
    String sessionKey = sessionTimestamp.toString();

    // Obtener los logs existentes
    final getResponse = await service.getItem(
      tableName: 'sime-domotica',
      key: {
        'product_code': AttributeValue(s: pc),
        'device_id': AttributeValue(s: sn),
      },
    );

    Map<String, AttributeValue> existingLogs = {};
    if (getResponse.item != null &&
        getResponse.item!['device_register_ble'] != null) {
      existingLogs = getResponse.item!['device_register_ble']!.m ?? {};
    }

    // Si ya existe una entrada para este timestamp de sesión, agregar a la lista existente
    List<AttributeValue> currentSessionLogs = [];
    if (existingLogs.containsKey(sessionKey) &&
        existingLogs[sessionKey]!.l != null) {
      currentSessionLogs = existingLogs[sessionKey]!.l!;
    }

    // Agregar los nuevos logs a la lista de esta sesión
    for (var log in logs) {
      currentSessionLogs.add(
        AttributeValue(m: {
          'content': AttributeValue(s: log['content']),
          'level': AttributeValue(s: log['level']),
          'timestamp': AttributeValue(n: log['timestamp'].toString()),
        }),
      );
    }

    // Actualizar la entrada de esta sesión
    existingLogs[sessionKey] = AttributeValue(l: currentSessionLogs);

    // Limitar a las últimas 50 sesiones (mantener solo las más recientes)
    if (existingLogs.length > 50) {
      // Ordenar por timestamp de sesión y mantener solo las 50 más recientes
      var sortedKeys = existingLogs.keys.toList()
        ..sort((a, b) => int.parse(b).compareTo(int.parse(a)));
      existingLogs = Map.fromEntries(
        sortedKeys.take(50).map((key) => MapEntry(key, existingLogs[key]!)),
      );
    }

    // Actualizar en DynamoDB
    await service.updateItem(
      tableName: 'sime-domotica',
      key: {
        'product_code': AttributeValue(s: pc),
        'device_id': AttributeValue(s: sn),
      },
      attributeUpdates: {
        'device_register_ble': AttributeValueUpdate(
          value: AttributeValue(m: existingLogs),
        ),
      },
    );

    printLog.i('Registros BLE guardados para $pc/$sn bajo sesión $sessionKey');
  } catch (e) {
    printLog.e('Error guardando registros BLE: $e');
  }
}

///Inhabilita o habilita un evento
void setEventEnabled(
    String nombreEvento, String email, bool habilitado, String tipoEvento,
    [String? activador, String? horario]) async {
  try {
    String tableName = '';
    Map<String, AttributeValue> key = {};

    switch (tipoEvento) {
      case 'disparadores':
        tableName = 'Eventos_ControlPorDisparadores';
        key = {
          'deviceName': AttributeValue(s: activador!),
          'email:nombreEvento': AttributeValue(s: '$email:$nombreEvento'),
        };
        break;
      case 'horario':
        tableName = 'Eventos_ControlPorHorarios';
        key = {
          'horario': AttributeValue(s: horario!),
          'email:nombreEvento': AttributeValue(s: '$email:$nombreEvento'),
        };
        break;
      case 'clima':
        tableName = 'Eventos_ControlPorClima';
        key = {
          'email': AttributeValue(s: email),
          'nombreEvento': AttributeValue(s: nombreEvento),
        };
        break;
      default:
        printLog.e('Tipo de evento desconocido: $tipoEvento');
        return;
    }

    final response = await service.updateItem(
      tableName: tableName,
      key: key,
      attributeUpdates: {
        'enabled': AttributeValueUpdate(
          value: AttributeValue(boolValue: habilitado),
        ),
      },
    );

    printLog.i('Evento actualizado correctamente: $response');
  } catch (e) {
    printLog.e('Error actualizando evento habilitado: $e');
  }
}

const _kLastToken = 'token_guard_last_token';
const _kLastTokenTime = 'token_guard_last_time';
const _kTokenCooldownHours = 24;

/// Retorna true si hay que escribir en Dynamo, false si se puede saltear.
Future<bool> _shouldWriteToken(String newToken) async {
  final prefs = await SharedPreferences.getInstance();
  final savedToken = prefs.getString(_kLastToken);
  final savedTimeMs = prefs.getInt(_kLastTokenTime);

  // Token distinto → siempre escribir
  if (savedToken != newToken) return true;

  // Mismo token, pero pasaron más de 24h → re-validar
  if (savedTimeMs != null) {
    final savedTime = DateTime.fromMillisecondsSinceEpoch(savedTimeMs);
    if (DateTime.now().difference(savedTime).inHours >= _kTokenCooldownHours) {
      return true;
    }
  }

  // Mismo token, dentro del cooldown → skip
  return false;
}

Future<void> _markTokenWritten(String token) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kLastToken, token);
  await prefs.setInt(_kLastTokenTime, DateTime.now().millisecondsSinceEpoch);
}

/// Versión protegida de putTokensInAlexaDevices con guard local.
/// Usar esta función en lugar de putTokensInAlexaDevices en TokenManager
/// y en el listener onTokenRefresh de menu.dart.
Future<void> putTokensInAlexaDevicesGuarded(
  String email,
  List<String> tokens,
  String currentToken,
) async {
  final shouldWrite = await _shouldWriteToken(currentToken);

  if (!shouldWrite) {
    printLog.i(
        'Token guard: skip — mismo token subido hace menos de $_kTokenCooldownHours hs');
    return;
  }

  await putTokensInAlexaDevices(email, tokens);
  await _markTokenWritten(currentToken);
  printLog.i('Token guard: token escrito y guardado localmente');
}

// ───────────────────────────────────────────────────────────────────────────
// 1. ADMIN USAGE HISTORY — append-only en device-admin-usage-history
// ───────────────────────────────────────────────────────────────────────────

/// Registra una entrada de uso de admin secundario.
/// Reemplaza la antigua `putAdminUsageHistory` que reescribía la lista entera
/// dentro de sime-domotica (~15 KB por write). Ahora es 1 PutItem ≈ 1 WRU.
Future<void> putAdminUsageHistory(
    String pc, String sn, String adminEmail, String action) async {
  try {
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final int ttl = (nowMs ~/ 1000) + (90 * 24 * 3600); // 90 días

    await service.putItem(
      tableName: 'device-admin-usage-history',
      item: {
        'device_key': AttributeValue(s: '$pc#$sn'),
        'timestamp': AttributeValue(n: nowMs.toString()),
        'email': AttributeValue(s: adminEmail),
        'action': AttributeValue(s: action),
        'ttl': AttributeValue(n: ttl.toString()),
      },
    );
  } catch (e) {
    printLog.e('Error guardando admin usage: $e');
  }
}

/// Devuelve los últimos [limit] registros de uso para un device, más nuevos
/// primero. Cada registro es un Map con `email`, `action`, `timestamp`.
Future<List<Map<String, dynamic>>> getParsedAdminUsageHistory(
    String pc, String sn,
    {int limit = 100}) async {
  try {
    final response = await service.query(
      tableName: 'device-admin-usage-history',
      keyConditionExpression: 'device_key = :pk',
      expressionAttributeValues: {
        ':pk': AttributeValue(s: '$pc#$sn'),
      },
      scanIndexForward: false, // descendente: más nuevo primero
      limit: limit,
    );

    final items = response.items ?? [];
    return items.map((item) {
      final tsString = item['timestamp']?.n ?? '0';
      final tsMs = int.tryParse(tsString) ?? 0;
      return <String, dynamic>{
        'email': item['email']?.s ?? '',
        'action': item['action']?.s ?? '',
        // Mantengo el formato ISO8601 para no romper el código consumidor en
        // manager_screen.dart, que parsea la fecha como string.
        'timestamp':
            DateTime.fromMillisecondsSinceEpoch(tsMs).toIso8601String(),
      };
    }).toList();
  } catch (e) {
    printLog.e('Error leyendo admin usage history: $e');
    return [];
  }
}

// ───────────────────────────────────────────────────────────────────────────
// 2. CONNECTION EVENTS — reader para isWifiNetworkUnstable
// ───────────────────────────────────────────────────────────────────────────

/// Lee los eventos de desconexión de la última hora desde
/// device-connection-events. La firma devuelve los timestamps en segundos
/// (epoch) como strings para mantener la compatibilidad con el consumidor
/// existente (`isWifiNetworkUnstable` en master.dart).
Future<List<String>> getRecentDisconnectTimes(String pc, String sn,
    {Duration window = const Duration(hours: 1)}) async {
  try {
    final int nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final int fromSec = nowSec - window.inSeconds;

    final response = await service.query(
      tableName: 'device-connection-events',
      keyConditionExpression: 'device_key = :pk AND #ts >= :from',
      expressionAttributeNames: {'#ts': 'timestamp'},
      filterExpression: 'event_type = :etype',
      expressionAttributeValues: {
        ':pk': AttributeValue(s: '$pc#$sn'),
        ':from': AttributeValue(n: fromSec.toString()),
        ':etype': AttributeValue(s: 'disconnect'),
      },
    );

    final items = response.items ?? [];
    return items.map((it) => it['timestamp']?.n ?? '0').toList();
  } catch (e) {
    printLog.e('Error leyendo connection events: $e');
    return [];
  }
}

// ───────────────────────────────────────────────────────────────────────────
// 3. TEMPERATURE HISTORY — reader para la página de termómetro
// ───────────────────────────────────────────────────────────────────────────

/// Lee el historial de temperatura de los últimos [days] días.
/// Devuelve un Map<String iso8601 timestamp, double temp> para mantener
/// compatibilidad con el consumidor existente en termometro.dart.
Future<Map<String, double>> getTemperatureHistory(String pc, String sn,
    {int days = 30}) async {
  try {
    final int nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final int fromSec = nowSec - (days * 24 * 3600);

    final Map<String, double> history = {};
    Map<String, AttributeValue>? lastKey;

    do {
      final response = await service.query(
        tableName: 'device-temperature-history',
        keyConditionExpression: 'device_key = :pk AND #ts >= :from',
        expressionAttributeNames: {'#ts': 'timestamp'},
        expressionAttributeValues: {
          ':pk': AttributeValue(s: '$pc#$sn'),
          ':from': AttributeValue(n: fromSec.toString()),
        },
        scanIndexForward: true,
        exclusiveStartKey: lastKey,
      );

      for (final item in response.items ?? []) {
        final ts = int.tryParse(item['timestamp']?.n ?? '0') ?? 0;
        final temp = double.tryParse(item['temp']?.n ?? '0') ?? 0.0;
        if (ts > 0) {
          // termometro.dart parsea con DateTime.parse(key), formato
          // "2026-04-30 12:34:56" (sin TZ). Lo emulamos.
          final dt =
              DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true);
          final key =
              dt.toIso8601String().replaceFirst('T', ' ').substring(0, 19);
          history[key] = temp;
        }
      }
      lastKey = response.lastEvaluatedKey;
    } while (lastKey != null && lastKey.isNotEmpty);

    return history;
  } catch (e) {
    printLog.e('Error leyendo temperature history: $e');
    return {};
  }
}
