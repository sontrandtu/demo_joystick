import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:joystick_app/main.dart';
import 'package:sdl3/sdl3.dart';
import 'package:collection/collection.dart';

class SdlController {
  late ReceivePort receivePort;
  late Isolate eventIsolate;
  late SendPort isolateSendPort;

  late StreamController<List<JoystickModel>> _joyStream;
  // Stream<List<JoystickModel>> get joysStream => _joyStream.stream;

  List<JoystickModel> joysticks = [];

  initialize(
    ReceivePort receivePort,
    StreamController<List<JoystickModel>> stream,
  ) async {
    _joyStream = stream;
    try {
      if (sdlInit(SDL_INIT_JOYSTICK) == false) {
        throw Exception(sdlGetError());
      }
      eventIsolate = await Isolate.spawn(
        sdlEventListen,
        [receivePort.sendPort],
      );

      receivePort.listen((msg) {
        if (msg is SendPort) {
          isolateSendPort = msg;
        } else if (msg is Map) {
          if (msg['type'] == 'update') {
            updateJoysticks();
          } else if (msg['type'] == 'update_j_button') {
            final event = msg['data'];
            if (event is JBtnEvent) {
              updateJButtonEvent(event);
            }
          } else if (msg['type'] == 'update_j_axes') {
            final event = msg['data'];
            if (event is JAxisEvent) {
              updateJAxisEvent(event);
            }
          } else if (msg['type'] == 'update_j_hat') {
            final event = msg['data'];
            if (event is JHatEvent) {
              updateJHatEvent(event);
            }
          }
        }
      });
    } catch (e) {
      rethrow;
    }
  }

  static sdlEventListen(List<dynamic> args) {
    final SendPort sendPort = args.first;
    final ReceivePort receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);
    var event = calloc<SdlEvent>();
    sdlJoystickEventsEnabled();
    var running = true;
    receivePort.listen((msg) {
      if (msg == 'stop') {
        running = false;
      }
    });

    while (running) {
      while (event.poll()) {
        switch (event.type) {
          case SDL_EVENT_QUIT:
            running = false;
            break;
          case SDL_EVENT_JOYSTICK_ADDED:
            sendPort.send({'type': 'update'});

            break;

          case SDL_EVENT_JOYSTICK_REMOVED:
            sendPort.send({'type': 'update'});
            break;
          case SDL_EVENT_JOYSTICK_BUTTON_DOWN:
            sendPort.send(
              {
                'type': 'update_j_button',
                'data': JBtnEvent.fromSdl(event.jbutton.ref),
              },
            );
          case SDL_EVENT_JOYSTICK_BUTTON_UP:
            sendPort.send(
              {
                'type': 'update_j_button',
                'data': JBtnEvent.fromSdl(event.jbutton.ref),
              },
            );
          case SDL_EVENT_JOYSTICK_AXIS_MOTION:
            sendPort.send(
              {
                'type': 'update_j_axes',
                'data': JAxisEvent.fromSdl(event.jaxis.ref),
              },
            );
          case SDL_EVENT_JOYSTICK_HAT_MOTION:
            sendPort.send(
              {
                'type': 'update_j_hat',
                'data': JHatEvent.fromSdl(event.jhat.ref),
              },
            );
          default:
            break;
        }
      }
    }
    if (!running) {
      event.callocFree();
      sdlQuit();
      Isolate.exit();
    }
  }

  void updateJoysticks() {
    bool joystickExist = sdlHasJoystick();
    clearJoysticks();
    if (!joystickExist) {
      _joyStream.sink.add(joysticks);
      return;
    }
    final count = calloc<Int32>();
    final joysticksPtr = sdlGetJoysticks(count);
    for (int i = 0; i < count.value; i++) {
      final instanceId = joysticksPtr[i];
      final joystickPtr = sdlOpenJoystick(instanceId);
      final id = sdlGetJoystickId(joystickPtr);
      final joystickName = sdlGetJoystickName(joystickPtr);
      final serial = sdlGetJoystickSerial(joystickPtr);
      final vendor = sdlGetJoystickVendor(joystickPtr);
      final product = sdlGetJoystickProduct(joystickPtr);
      final joystick = JoystickModel(
        instanceID: instanceId,
        id: id,
        joystickPtr: joystickPtr,
        name: joystickName,
        serial: serial,
        vendor: vendor,
        product: product,
      );
      joysticks.add(joystick);
    }
    _joyStream.add(joysticks);
    sdlFree(count);
    sdlFree(joysticksPtr);
  }

  void clearJoysticks() {
    for (final j in joysticks) {
      j.dispose();
    }
    joysticks.clear();
  }

  void updateJButtonEvent(JBtnEvent event) {
    final which = event.which;
    final joy = joysticks.firstWhereOrNull((e) => e.instanceID == which);
    if (joy == null) return;
    joy.updateJButton(event);
  }

  void updateJAxisEvent(JAxisEvent event) {
    final which = event.which;
    final joy = joysticks.firstWhereOrNull((e) => e.instanceID == which);
    if (joy == null) return;
    joy.updateJAxis(event);
  }

  void updateJHatEvent(JHatEvent event) {
    final which = event.which;
    final joy = joysticks.firstWhereOrNull((e) => e.instanceID == which);
    if (joy == null) return;
    joy.updateJHat(event);
  }

  void addListener(
    List<AUXFunctionMacro> macros,
    Function(AUXFuncResponse? response) callback,
  ) {
    for (final j in joysticks) {
      j.addListener(macros, callback);
    }
  }

  void dispose() {
    isolateSendPort.send('stop');
    eventIsolate.kill(priority: Isolate.immediate);
    receivePort.close();
    _joyStream.close();
  }
}

class JoystickModel {
  final int instanceID;
  final int id;
  final String? name;
  final String? serial;
  final int vendor;
  final int product;
  final Pointer<SdlJoystick> joystickPtr;
  late List<ValueNotifier<JBtnEvent>> listJBtnEvent;
  late List<ValueNotifier<JAxisEvent>> listJAxisEvent;
  late List<ValueNotifier<JHatEvent>> listJHatEvent;

  late Map<int, VoidCallback> _jBtnListener;
  late Map<int, VoidCallback> _jAxisListener;
  late Map<int, VoidCallback> _jHatListener;

  JoystickModel({
    required this.instanceID,
    required this.id,
    required this.vendor,
    required this.product,
    required this.joystickPtr,
    this.name,
    this.serial,
  }) {
    listJBtnEvent = _initJBtnEvent();
    listJAxisEvent = _initJAxesEvent();
    listJHatEvent = _initJHatEvent();

    _jBtnListener = {};
    _jAxisListener = {};
    _jHatListener = {};
  }

  List<ValueNotifier<JBtnEvent>> _initJBtnEvent() {
    int length = sdlGetNumJoystickButtons(joystickPtr);
    List<ValueNotifier<JBtnEvent>> result = [];
    if (length == 0) return result;

    for (int i = 0; i < length; i++) {
      final buttonValue = sdlGetJoystickButton(joystickPtr, i);
      final value = ValueNotifier(
        JBtnEvent(
          type: SDL_EVENT_JOYSTICK_BUTTON_DOWN,
          reserved: 0,
          timestamp: 0,
          which: instanceID,
          button: i,
          down: buttonValue ? 1 : 0,
          padding1: 0,
          padding2: 0,
        ),
      );
      result.add(value);
    }
    return result;
  }

  List<ValueNotifier<JAxisEvent>> _initJAxesEvent() {
    int length = sdlGetNumJoystickAxes(joystickPtr);
    List<ValueNotifier<JAxisEvent>> result = [];
    if (length == 0) return result;
    for (int i = 0; i < length; i++) {
      final axisValue = sdlGetJoystickAxis(joystickPtr, i);
      final value = ValueNotifier(
        JAxisEvent(
          type: SDL_EVENT_JOYSTICK_BUTTON_DOWN,
          reserved: 0,
          timestamp: 0,
          which: instanceID,
          axis: i,
          value: axisValue,
          padding1: 0,
          padding2: 0,
          padding3: 0,
          padding4: 0,
        ),
      );
      result.add(value);
    }
    return result;
  }

  List<ValueNotifier<JHatEvent>> _initJHatEvent() {
    int length = sdlGetNumJoystickHats(joystickPtr);
    List<ValueNotifier<JHatEvent>> result = [];
    if (length == 0) return result;
    for (int i = 0; i < length; i++) {
      final hatValue = sdlGetJoystickHat(joystickPtr, i);
      final value = ValueNotifier(
        JHatEvent(
          type: SDL_EVENT_JOYSTICK_BUTTON_DOWN,
          reserved: 0,
          timestamp: 0,
          which: instanceID,
          hat: i,
          value: hatValue,
          padding1: 0,
          padding2: 0,
        ),
      );
      result.add(value);
    }
    return result;
  }

  String get hexVendor => vendor.toRadixString(16).padLeft(4, '0');
  String get hexProduct => product.toRadixString(16).padLeft(4, '0');

  void updateJButton(JBtnEvent event) {
    final v =
        listJBtnEvent.firstWhereOrNull((e) => e.value.button == event.button);
    if (v == null) {
      listJBtnEvent.add(ValueNotifier(event));
    } else {
      v.value = event;
    }
  }

  void updateJAxis(JAxisEvent event) {
    final v =
        listJAxisEvent.firstWhereOrNull((e) => e.value.axis == event.axis);
    if (v == null) {
      listJAxisEvent.add(ValueNotifier(event));
    } else {
      v.value = event;
    }
  }

  void updateJHat(JHatEvent event) {
    final v = listJHatEvent.firstWhereOrNull((e) => e.value.hat == event.hat);
    if (v == null) {
      listJHatEvent.add(ValueNotifier(event));
    } else {
      v.value = event;
    }
  }

  void addListener(
    List<AUXFunctionMacro> macros,
    Function(AUXFuncResponse? response) callback,
  ) {
    for (final macro in macros) {
      switch (macro.type) {
        case ActionType.button:
          addJButtonListener(macro, macros, callback);
        case ActionType.axis:
          addJAxisListener(macro, macros, callback);
        case ActionType.hat:
          addJHatListener(macro, macros, callback);
      }
    }
  }

  void addJButtonListener(
    AUXFunctionMacro macro,
    List<AUXFunctionMacro> allMacro,
    Function(AUXFuncResponse? response) callback,
  ) {
    final event =
        listJBtnEvent.firstWhereOrNull((b) => b.value.button == macro.id);
    if (event != null) {
      if (_jBtnListener[macro.id] != null) {
        event.removeListener(_jBtnListener[macro.id]!);
      }

      listener() {
        print(
            'Button ${event.value.button} Macro: ${macro.auxFuncType} - value: ${event.value.down}');

        final auxFuncType = macro.auxFuncType ?? macro.auxFuncType2;
        if (auxFuncType == null) return;
        final resultValue = _getResult(
          auxFuncType: auxFuncType,
          macro: macro,
          allMacro: allMacro,
        );

        if (resultValue == null) return;

        callback.call(resultValue);
      }

      _jBtnListener[macro.id] = listener;

      event.addListener(listener);
    }
  }

  void addJAxisListener(
    AUXFunctionMacro macro,
    List<AUXFunctionMacro> allMacro,
    Function(AUXFuncResponse? response) callback,
  ) {
    final event =
        listJAxisEvent.firstWhereOrNull((b) => b.value.axis == macro.id);
    if (event != null) {
      if (_jAxisListener[macro.id] != null) {
        event.removeListener(_jAxisListener[macro.id]!);
      }

      listener() {
        final auxFuncType = macro.auxFuncType ?? macro.auxFuncType2;
        print('aux type: $auxFuncType --- ID: ${macro.id}');

        if (auxFuncType == null) return;
        final resultValue = _getResult(
          auxFuncType: auxFuncType,
          macro: macro,
          allMacro: allMacro,
        );

        if (resultValue == null) return;

        callback.call(resultValue);
      }

      _jAxisListener[macro.id] = listener;

      event.addListener(listener);
    }
  }

  void addJHatListener(
    AUXFunctionMacro macro,
    List<AUXFunctionMacro> allMacro,
    Function(AUXFuncResponse? response) callback,
  ) {
    final event =
        listJHatEvent.firstWhereOrNull((b) => b.value.hat == macro.id);
    if (event != null) {
      if (_jHatListener[macro.id] != null) {
        event.removeListener(_jHatListener[macro.id]!);
      }
      listener() {
        final auxFuncType = macro.auxFuncType ?? macro.auxFuncType2;
        print('aux type: $auxFuncType');

        if (auxFuncType == null) return;

        // int value1 = 65535;
        // int value2 = 65535;
        //
        // if (auxFuncType.isMultiValue) {
        //   if (macro.auxFuncType != null) {
        //     value1 = hatValue.value;
        //     final macro2 = allMacro
        //         .where((e) => e.auxFuncType2 == auxFuncType)
        //         .firstOrNull;
        //
        //     if (macro2 != null) {
        //       value2 = sdlGetJoystickHat(joystickPtr, macro2.id);
        //     }
        //   } else {
        //     value2 = hatValue.value;
        //     final macro1 =
        //         allMacro.where((e) => e.auxFuncType == auxFuncType).firstOrNull;
        //
        //     if (macro1 != null) {
        //       value1 = sdlGetJoystickHat(joystickPtr, macro1.id);
        //     }
        //   }
        // } else {
        //   value1 = hatValue.value;
        //   //TODO: VALUE 2
        //   // value2
        // }
        final resultValue = _getResult(
          auxFuncType: auxFuncType,
          macro: macro,
          allMacro: allMacro,
        );

        if (resultValue == null) return;

        callback.call(resultValue);
      }

      _jHatListener[macro.id] = listener;

      event.addListener(listener);
    }
  }

  AUXFuncResponse? _getResult({
    required AUXFunctionEnum auxFuncType,
    required AUXFunctionMacro macro,
    required List<AUXFunctionMacro> allMacro,
  }) {
    int value1 = 65535;
    int value2 = 65535;

    if (auxFuncType.isMultiValue) {
      if (macro.auxFuncType != null) {
        value1 = _getValueFromMacro(macro);
        final macro2 =
            allMacro.where((e) => e.auxFuncType2 == auxFuncType).firstOrNull;

        if (macro2 != null) {
          value2 = _getValueFromMacro(macro2);
        }
      } else {
        value2 = _getValueFromMacro(macro);
        final macro1 =
            allMacro.where((e) => e.auxFuncType == auxFuncType).firstOrNull;

        if (macro1 != null) {
          value1 = _getValueFromMacro(macro1);
        }
      }
      print('multi macro');
    } else {
      value1 = _getValueFromMacro(macro);
      //TODO: VALUE 2
      // value2
    }

    print('value1: $value1 ------- value2; $value2');

    final resultValue = auxFuncType.getValue(value1, value2);

    if (resultValue.$1 == null || resultValue.$2 == null) return null;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final camTimestamp = DateTime.now().millisecondsSinceEpoch;
    final auxSerialNumber = product.toRadixString(16);
    final id = macro.id;

    return AUXFuncResponse(
      timestamp: timestamp,
      camTimestamp: camTimestamp,
      allInputs: 0,
      auxInputs: [
        AuxInput(
          auxSerialNumber: auxSerialNumber,
          id: id,
          functionTypeID: auxFuncType.id,
          value1: resultValue.$1!,
          value2: resultValue.$2!,
        )
      ],
    );
  }

  int _getValueFromMacro(AUXFunctionMacro otherMacro) {
    switch (otherMacro.type) {
      case ActionType.button:
        return sdlGetJoystickButton(joystickPtr, otherMacro.id) ? 1 : 0;
      case ActionType.axis:
        return sdlGetJoystickAxis(joystickPtr, otherMacro.id);
      case ActionType.hat:
        return sdlGetJoystickHat(joystickPtr, otherMacro.id);
    }
  }

  void dispose() {
    for (var v in listJBtnEvent) {
      v.dispose();
    }
    for (var v in listJAxisEvent) {
      v.dispose();
    }
    for (var v in listJHatEvent) {
      v.dispose();
    }
  }
}

// SDL_JoyButtonEvent
class JBtnEvent {
  final int type;
  final int reserved;
  final int timestamp;
  final int which;
  final int button;
  final int down;
  final int padding1;
  final int padding2;

  JBtnEvent({
    required this.type,
    required this.reserved,
    required this.timestamp,
    required this.which,
    required this.button,
    required this.down,
    required this.padding1,
    required this.padding2,
  });

  factory JBtnEvent.fromSdl(SdlJoyButtonEvent event) {
    return JBtnEvent(
      type: event.type,
      reserved: event.reserved,
      timestamp: event.timestamp,
      which: event.which,
      button: event.button,
      down: event.down,
      padding1: event.padding1,
      padding2: event.padding2,
    );
  }
}

// SDL_JoyAxisEvent
class JAxisEvent {
  final int type;
  final int reserved;
  final int timestamp;
  final int which;
  final int axis;
  final int value;
  final int padding1;
  final int padding2;
  final int padding3;
  final int padding4;

  JAxisEvent({
    required this.type,
    required this.reserved,
    required this.timestamp,
    required this.which,
    required this.axis,
    required this.value,
    required this.padding1,
    required this.padding2,
    required this.padding3,
    required this.padding4,
  });

  factory JAxisEvent.fromSdl(SdlJoyAxisEvent event) {
    return JAxisEvent(
      type: event.type,
      reserved: event.reserved,
      timestamp: event.timestamp,
      which: event.which,
      axis: event.axis,
      value: event.value,
      padding1: event.padding1,
      padding2: event.padding2,
      padding3: event.padding3,
      padding4: event.padding4,
    );
  }
}

// SDL_JoyHatEvent
class JHatEvent {
  final int type;
  final int reserved;
  final int timestamp;
  final int which;
  final int hat;
  final int value;
  final int padding1;
  final int padding2;

  JHatEvent({
    required this.type,
    required this.reserved,
    required this.timestamp,
    required this.which,
    required this.hat,
    required this.value,
    required this.padding1,
    required this.padding2,
  });

  factory JHatEvent.fromSdl(SdlJoyHatEvent event) {
    return JHatEvent(
      type: event.type,
      reserved: event.reserved,
      timestamp: event.timestamp,
      which: event.which,
      hat: event.hat,
      value: event.value,
      padding1: event.padding1,
      padding2: event.padding2,
    );
  }
}

class AUXFuncResponse {
  final int timestamp;
  final int camTimestamp;
  final int allInputs;
  final List<AuxInput> auxInputs;

  AUXFuncResponse({
    required this.timestamp,
    required this.camTimestamp,
    required this.allInputs,
    required this.auxInputs,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'camTimestamp': camTimestamp,
        'allInputs': allInputs,
        'auxInputs': auxInputs.map<Map<String, dynamic>>((e) => e.toJson()),
      };
}

class AuxInput {
  final String auxSerialNumber;
  final int id;
  final int functionTypeID;
  final int value1;
  final int value2;

  AuxInput({
    required this.auxSerialNumber,
    required this.id,
    required this.functionTypeID,
    required this.value1,
    required this.value2,
  });

  Map<String, dynamic> toJson() => {
        'auxSerialNumber': auxSerialNumber,
        'id': id,
        'functionTypeID': functionTypeID,
        'value1': value1,
        'value2': value2,
      };
}
