import 'dart:async';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:joystick_app/sdl_controller.dart';
import 'package:collection/collection.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gamepads Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late ReceivePort receivePort;
  Isolate? eventIsolate;
  SendPort? isolateSendPort;
  final List<AUXFunctionMacro> _auxFuncMacros = [];

  final SdlController sdlController = SdlController();

  bool isShowData = false;

  String? _jsonData;

  @override
  void initState() {
    _joyStream = StreamController<List<JoystickModel>>.broadcast();
    receivePort = ReceivePort();
    sdlController.initialize(receivePort, _joyStream);
    super.initState();
  }

  late StreamController<List<JoystickModel>> _joyStream;

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _stop() {
    sdlController.dispose();
  }

  void _getAuxResponse(AUXFuncResponse? response) {
    print('response: \n${response?.toJson()}');
    setState(() {
      _jsonData = response?.toJson().toString();
    });
  }

  void _updateMacro({
    required AUXFunctionEnum auxType,
    required ActionType type,
    required int id,
    required int joystickID,
    required bool isValue1,
  }) {
    final exist =
        _auxFuncMacros.firstWhereOrNull((e) => e.type == type && e.id == id);
    if (exist == null) {
      final macro = AUXFunctionMacro(
        joystickID: joystickID,
        id: id,
        type: type,
        auxFuncType: isValue1 ? auxType : null,
        auxFuncType2: !isValue1 ? auxType : null,
      );
      _auxFuncMacros.add(macro);
    } else {
      if (isValue1) {
        exist.auxFuncType = auxType;
        exist.auxFuncType2 = null;
      } else {
        exist.auxFuncType = null;
        exist.auxFuncType2 = auxType;
      }
    }
    setState(() {
      _auxFuncMacros;
    });
  }

  void _revert() {
    setState(() {
      isShowData = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gamepads Example'),
        actions: [
          IconButton(
            onPressed: () {
              sdlController.addListener(_auxFuncMacros, _getAuxResponse);
              setState(() {
                isShowData = true;
              });
            },
            icon: const Icon(Icons.save_as_outlined),
          ),
          IconButton(
            onPressed: _revert,
            icon: const Icon(Icons.settings_backup_restore),
          )
        ],
      ),
      body: StreamBuilder<List<JoystickModel>>(
        stream: _joyStream.stream,
        builder: (context, snapshot) {
          final data = snapshot.data ?? [];
          if (data.isEmpty) {
            return const Center(
              child: Text('No Have Data'),
            );
          }

          final joy = data.first;
          return _buildContent(joy);
        },
      ),
    );
  }

  Widget _buildContent(JoystickModel joy) {
    if (isShowData) {
      return Text(_jsonData ?? 'No Data');
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${joy.name.toString()} (ID: ${joy.instanceID}, Serial: ${joy.serial}, Vendor: ${joy.hexVendor}, Product: ${joy.hexProduct})',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 16),
            Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Buttons:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    ...joy.listJBtnEvent.map(
                      (e) => _buildMacroItem(
                        joy.instanceID,
                        e,
                        ActionType.button,
                      ),
                    ),
                  ],
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Axes:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    ...joy.listJAxisEvent.map(
                      (e) => _buildMacroItem(
                        joy.instanceID,
                        e,
                        ActionType.axis,
                      ),
                    )
                  ],
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Hats:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    ...joy.listJHatEvent.map(
                      (e) => _buildMacroItem(
                        joy.instanceID,
                        e,
                        ActionType.hat,
                      ),
                    )
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  ValueListenableBuilder<dynamic> _buildMacroItem(
    int joystickIdD,
    ValueNotifier<dynamic> value,
    ActionType type,
  ) {
    return ValueListenableBuilder(
      valueListenable: value,
      builder: (_, event, __) {
        late int id;
        late int value;
        late String name;
        switch (type) {
          case ActionType.button:
            event as JBtnEvent;
            id = event.button;
            value = event.down;
            name = 'Button';
          case ActionType.axis:
            event as JAxisEvent;
            id = event.axis;
            value = event.value;
            name = 'Axis';
          case ActionType.hat:
            event as JHatEvent;
            id = event.hat;
            value = event.value;
            name = 'Hat';
        }
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.5),
                offset: const Offset(0, 1),
                blurRadius: 1,
              )
            ],
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 6,
          ),
          margin: const EdgeInsets.only(bottom: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$name ${id + 1} (ID = $id) '),
                  const SizedBox(width: 10),
                  Row(
                    children: [
                      _SliderAnimation(
                        value: value,
                        type: type,
                      ),
                      Container(
                        width: 60,
                        alignment: Alignment.center,
                        child: Text('$value'),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                width: 200,
                child: CustomDropdownMenu(
                  auxFuncSelect: _auxFuncMacros
                          .firstWhereOrNull((e) => e.type == type && e.id == id)
                          ?.auxFuncType ??
                      _auxFuncMacros
                          .firstWhereOrNull((e) => e.type == type && e.id == id)
                          ?.auxFuncType2,
                  onSelected: (auxType, isValue1) {
                    _updateMacro(
                      joystickID: joystickIdD,
                      id: id,
                      auxType: auxType,
                      type: type,
                      isValue1: isValue1,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class CustomDropdownMenu extends StatefulWidget {
  final AUXFunctionEnum? auxFuncSelect;
  final void Function(AUXFunctionEnum, bool)? onSelected;
  const CustomDropdownMenu({
    super.key,
    this.auxFuncSelect,
    this.onSelected,
  });

  @override
  State<CustomDropdownMenu> createState() => _CustomDropdownMenuState();
}

class _CustomDropdownMenuState extends State<CustomDropdownMenu> {
  AUXFunctionEnum? _auxFuncSelect;

  @override
  void initState() {
    _auxFuncSelect = widget.auxFuncSelect;
    super.initState();
  }

  void _onSelect(AUXFunctionEnum? value) async {
    if (value == null) return;
    if (value.isMultiValue) {
      bool isValue1 = true;
      final isChange = await showDialog(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: Text('Confirm'),
            content: Text('What value do you want to assign?'),
            actions: [
              ElevatedButton(
                onPressed: () {
                  isValue1 = true;
                  Navigator.of(context).pop(true);
                },
                child: Text('Value 1'),
              ),
              ElevatedButton(
                onPressed: () {
                  isValue1 = false;
                  Navigator.of(context).pop(true);
                },
                child: Text('Value 2'),
              ),
            ],
          );
        },
      );
      if (isChange == null || !isChange) {
        return;
      }
      setState(() {
        _auxFuncSelect = value;
        widget.onSelected?.call(value, isValue1);
      });
    } else if (value != _auxFuncSelect) {
      setState(() {
        _auxFuncSelect = value;
        widget.onSelected?.call(value, true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 40,
      decoration: BoxDecoration(border: Border.all(color: Colors.black)),
      child: DropdownButton<AUXFunctionEnum>(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        underline: const SizedBox(),
        isExpanded: true,
        value: _auxFuncSelect,
        items: AUXFunctionEnum.values
            .map<DropdownMenuItem<AUXFunctionEnum>>(
              (e) => DropdownMenuItem<AUXFunctionEnum>(
                value: e,
                child: Tooltip(
                  preferBelow: false,
                  message: e.name,
                  child: Text(
                    e.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            )
            .toList(),
        onChanged: _onSelect,
      ),
    );
  }
}

enum ActionType { button, axis, hat }

class _SliderAnimation extends StatelessWidget {
  final int value;
  final ActionType type;
  const _SliderAnimation({
    required this.value,
    required this.type,
  });

  double _getRatio() {
    final ratio = (value / (65535 / 2)) * 100;
    if (ratio > 100) {
      return 100;
    }
    if (ratio < -100) {
      return -100;
    }
    return ratio;
  }

  Widget _buildButton() {
    return Container(
      width: 200.1,
      height: 10,
      decoration: BoxDecoration(
        color: (value == 0) ? Colors.grey.withOpacity(0.5) : Colors.green,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }

  Widget _buildHat() {
    return Container(
      width: 200.1,
      height: 10,
      decoration: BoxDecoration(
        color: (value == 0) ? Colors.grey.withOpacity(0.5) : Colors.green,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }

  Widget _buildAxis() {
    return Container(
      width: 200.1,
      height: 10,
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Stack(
              children: [
                Positioned(
                  right: 0,
                  child: AnimatedContainer(
                    width: value == 0
                        ? 0
                        : _getRatio() > 0
                            ? 0
                            : (_getRatio() * -1),
                    height: 10,
                    duration: const Duration(microseconds: 200),
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(6),
                        bottomLeft: Radius.circular(6),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 100,
            child: Stack(
              children: [
                AnimatedContainer(
                  width: value == 0
                      ? 0
                      : _getRatio() < 0
                          ? 0
                          : (_getRatio()),
                  height: 10,
                  duration: const Duration(microseconds: 200),
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(6),
                      bottomRight: Radius.circular(6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case ActionType.button:
        return _buildButton();
      case ActionType.axis:
        return _buildAxis();
      case ActionType.hat:
        return _buildHat();
    }
  }
}

enum AUXFunctionEnum {
  none(name: "None", id: -1),
  booleanLatching(name: "Boolean ― Latching (maintains position)", id: 0),
  analogue(name: "Analogue (maintains position setting)", id: 1),
  booleanNonLatching(name: "Boolean ― Non-Latching (momentary)", id: 2),
  analogue50(name: "Analogue ― return to 50%", id: 3),
  analogue0(name: "Analogue ― return to 0%", id: 4),
  dualBooleanBothLatching(
    name: "Dual Boolean ― Both Latching (Maintain positions)",
    id: 5,
  ),
  dualBooleanBothNonLatching(
    name: "Dual Boolean ― Both Non-Latching (Momentary) ",
    id: 6,
  ),
  dualBooleanLatchingUp(
    name: "Dual Boolean ― Latching (Up) (Momentary down)",
    id: 7,
  ),
  dualBooleanLatchingDown(
    name: "Dual Boolean ― Latching (Down) (Momentary up)",
    id: 8,
  ),
  combinedAnalogue(
    name: "Combined Analogue ― return to 50% with Dual Boolean Latching",
    id: 9,
  ),
  combinedAnalogueMaintain(
    name:
        "Combined Analogue ― maintains position setting with Dual Boolean Latching",
    id: 10,
  ),
  quadratureBoolean(name: "Quadrature Boolean ― Non-Latching", id: 11),
  quadratureAnalogue(
    name: "Quadrature Analogue (maintains position setting)",
    id: 12,
  ),
  quadratureAnalogue50(name: "Quadrature Analogue return to 50%", id: 13),
  bidirectionalEncoder(name: "Bidirectional Encoder", id: 14);

  const AUXFunctionEnum({required this.id, required this.name});
  final String name;
  final int id;
}

extension AUXFunctionExt on AUXFunctionEnum {
  bool _checkRange(int min, int max, int value) {
    return value >= min && value <= max;
  }

  int convertToPercent(int value) => (value / 65535 * 100).round() + 50;

  (int?, int?) getValue(int value1, int value2) {
    int? result1;
    int? result2;
    switch (this) {
      case AUXFunctionEnum.none:
        break;
      case AUXFunctionEnum.booleanLatching:
        if (value1 == 0 || value1 == 1) {
          result1 = value1;
        }
        if (_checkRange(0, 65535, value2)) {
          result2 = value2;
        }
      case AUXFunctionEnum.analogue:
        if (_checkRange(0, 100, value1)) {
          result1 = value1;
        }
        result2 = 65535;

      case AUXFunctionEnum.booleanNonLatching:
        const values = [0, 1, 2];
        if (values.contains(value1)) {
          result1 = value1;
        }
        if (_checkRange(0, 65535, value2)) {
          result2 = value2;
        }
      case AUXFunctionEnum.analogue50:
        final perCent = convertToPercent(value1);

        if (_checkRange(0, 100, perCent)) {
          result1 = perCent;
        }
        result2 = 65535;
      case AUXFunctionEnum.analogue0:
        final perCent = convertToPercent(value1);
        if (_checkRange(0, 100, perCent)) {
          result1 = perCent;
        }
        result2 = 65535;
      case AUXFunctionEnum.dualBooleanBothLatching:
        const values = [0, 1, 4];
        if (values.contains(value1)) {
          result1 = value1;
        }
        if (_checkRange(0, 65535, value2)) {
          result2 = value2;
        }
      case AUXFunctionEnum.dualBooleanBothNonLatching:
        const values = [0, 1, 2, 4, 8];
        if (values.contains(value1)) {
          result1 = value1;
        }
        if (_checkRange(0, 65535, value2)) {
          result2 = value2;
        }
      case AUXFunctionEnum.dualBooleanLatchingUp:
        const values = [0, 1, 4, 8];
        if (values.contains(value1)) {
          result1 = value1;
        }
        if (_checkRange(0, 65535, value2)) {
          result2 = value2;
        }
      case AUXFunctionEnum.dualBooleanLatchingDown:
        const values = [0, 1, 2, 4];
        if (values.contains(value1)) {
          result1 = value1;
        }
        if (_checkRange(0, 65535, value2)) {
          result2 = value2;
        }
      case AUXFunctionEnum.combinedAnalogue:
        const values = [0xFB00, 0xFB01];
        final perCent = convertToPercent(value1);
        if (values.contains(value1)) {
          result1 = value1;
        } else if (_checkRange(0, 100, value1)) {
          result1 = perCent;
        }
        if (_checkRange(0, 65535, value2)) {
          result2 = value2;
        }
      case AUXFunctionEnum.combinedAnalogueMaintain:
        const values = [0xFB00, 0xFB01];
        final perCent = convertToPercent(value1);
        if (values.contains(value1)) {
          result1 = value1;
        } else if (_checkRange(0, 100, perCent)) {
          result1 = perCent;
        }
        if (_checkRange(0, 65535, value2)) {
          result2 = value2;
        }
      case AUXFunctionEnum.quadratureBoolean:
        if (_checkRange(0, 65535, value1)) {
          result1 = value1;
        }
        if (_checkRange(0, 65535, value2)) {
          result2 = value2;
        }
      case AUXFunctionEnum.quadratureAnalogue:
        final percent1 = convertToPercent(value1);
        final percent2 = convertToPercent(value2);
        if (_checkRange(0, 100, percent1.round())) {
          result1 = percent1.round();
        }
        if (_checkRange(0, 100, percent2.round())) {
          result2 = percent2.round();
        }
      case AUXFunctionEnum.quadratureAnalogue50:
        final percent1 = convertToPercent(value1);
        final percent2 = convertToPercent(value2);
        if (_checkRange(0, 100, percent1)) {
          result1 = percent1;
        }
        if (_checkRange(0, 100, percent2)) {
          result2 = percent2;
        }
      case AUXFunctionEnum.bidirectionalEncoder:
        if (_checkRange(0, 65535, value1)) {
          result1 = value1;
        }
        if (_checkRange(1, 65535, value2)) {
          result2 = value2;
        }
    }
    return (result1, result2);
  }

  bool get isMultiValue =>
      this == AUXFunctionEnum.quadratureAnalogue ||
      this == AUXFunctionEnum.quadratureAnalogue50;
}

class AUXFunctionMacro {
  final int joystickID;
  final int id;
  final ActionType type;
  AUXFunctionEnum? auxFuncType;
  AUXFunctionEnum? auxFuncType2; // for value2

  AUXFunctionMacro({
    required this.joystickID,
    required this.id,
    required this.type,
    this.auxFuncType,
    this.auxFuncType2,
  });
}
