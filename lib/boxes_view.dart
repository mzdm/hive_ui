import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'boxes_list.dart';
import 'core/box_update_handler.dart';
import 'core/hive_view_state.dart';
import 'extensions.dart';
import 'widgets/add_dialog.dart';
import 'widgets/hive_boxes_details.dart';
import 'widgets/update_dialog.dart';

typedef FieldPressedCallback = void Function(
  String boxName,
  String fieldName,
  Map<String, dynamic> objectAsJson, {
  int? objectIndex,
});

typedef ErrorCallback = void Function(String errorMessage);

typedef FromJsonConverter = dynamic Function(dynamic json);
typedef ToJsonConverter = dynamic Function(dynamic object);
typedef ToMapConverter = Map<String, dynamic> Function(String str, String key);
typedef FromMapConverter = dynamic Function(Map<String, dynamic> map);

class BoxWithSerialization {
  BoxWithSerialization({
    required this.box,
    required this.toJson,
    required this.fromJson,
    required this.toMap,
    required this.fromMap,
  });

  final Box<dynamic> box;
  final ToJsonConverter toJson;
  final FromJsonConverter fromJson;
  final ToMapConverter toMap;
  final FromMapConverter fromMap;
}

class HiveBoxesView extends StatefulWidget {
  final Color? appBarColor;
  final TextStyle? columnTitleTextStyle;
  final TextStyle? rowTitleTextStyle;
  final List<BoxWithSerialization> hiveBoxes;

  final ErrorCallback onError;
  final String? dateFormat;
  final bool deleteEnabled;

  const HiveBoxesView({
    Key? key,
    this.appBarColor,
    this.columnTitleTextStyle,
    this.rowTitleTextStyle,
    required this.hiveBoxes,
    required this.onError,
    this.dateFormat,
    this.deleteEnabled = false,
  }) : super(key: key);

  @override
  State<HiveBoxesView> createState() => _HiveBoxesViewState();
}

class _HiveBoxesViewState extends State<HiveBoxesView> {
  late ValueNotifier<HiveViewState> _hiveViewState;
  late PageController _pageController;

  @override
  void initState() {
    final hiveState = HiveViewState(
      boxesMap: widget.hiveBoxes,
    );
    _hiveViewState = ValueNotifier<HiveViewState>(hiveState);
    _pageController = PageController();
    super.initState();
  }

  /// The method is used to navigate back to the previous page
  /// It uses the PageController's previousPage method, and sets the duration and curve of the transition
  void _toPreviousPage() => _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );

  /// The method is used to clear the current opened box
  /// It creates an instance of BoxUpdateHandler and calls its clearBox method
  /// If the box is cleared successfully, the state is updated and the previous page is navigated to
  void _onClearBox() async {
    final boxHandler = BoxUpdateHandler(_hiveViewState.value, widget.onError);
    final isCleared = await boxHandler.clearBox();
    if (isCleared) {
      _hiveViewState.value = _hiveViewState.value.clearState();
      _toPreviousPage();
    }
  }

  /// The method is used to delete all fields of an object
  /// It creates an instance of BoxUpdateHandler and calls its deleteFieldOfObject method
  /// If the fields are deleted successfully, the state is updated and the previous page is navigated to
  void _onDeleteAllFields() async {
    final boxHandler = BoxUpdateHandler(_hiveViewState.value, widget.onError);
    final isDeleted = await boxHandler.deleteFieldOfObject();
    if (isDeleted) {
      final newNestedObjects = _hiveViewState.value.nestedObjectList!;
      newNestedObjects.removeLast();
      _hiveViewState.value = _hiveViewState.value.copyWith(nestedObjectList: newNestedObjects);
    }
  }

  /// The method is used to add a new row to the current opened box
  /// It uses the AddNewDialog widget to update the new object's properties
  /// If the object is updated successfully, it creates an instance of BoxUpdateHandler and calls its addObject method
  /// If the object is added successfully, the previous page is navigated to
  void _onAddRow(
    Map<String, dynamic> objectAsJson,
    List<String> boxColumns,
  ) async {
    final updatedObject = await showDialog(
      context: context,
      builder: (_) => AddNewDialog(
        objectAsJson: objectAsJson,
        allColumns: boxColumns,
      ),
    );
    if (updatedObject != null) {
      final boxHandler = BoxUpdateHandler(
        _hiveViewState.value,
        widget.onError,
      );
      setState(() {});
      final isAdded = await boxHandler.addObject(objectAsJson);
      if (isAdded) {
        _toPreviousPage();
      }
    }
  }

  void _onDeleteRows(List<int> rowsIndices) async {
    final boxHandler = BoxUpdateHandler(_hiveViewState.value, widget.onError);
    final isDeleted = await boxHandler.deleteRowObject(rowsIndices);
    if (isDeleted) {
      _toPreviousPage();
    }
  }

  void onFieldPressed(
    String boxName,
    String fieldName,
    Map<String, dynamic> objectAsJson, {
    int pageIndex = 1,
    int? objectIndex,
  }) async {
    dynamic fieldValue = objectAsJson[fieldName];
    if (fieldValue.runtimeType == List<Object?>) {
      fieldValue = [
        for (var i = 0; i < fieldValue.length; i++)
          fieldValue[i] is String
              ? {
                  "": "$i: ${fieldValue[i]}"
                }
              : fieldValue[i] as Map<String, dynamic>
      ];
    }

    if ((fieldValue.runtimeType == List<Map<String, dynamic>>) || isMap(fieldValue)) {
      if (fieldValue.isEmpty) {
        widget.onError('Field is Empty');
        return;
      }
      var nestedObjectList = _hiveViewState.value.nestedObjectList ?? [];
      var objectNestedIndices = _hiveViewState.value.objectNestedIndices ?? [];
      if (isMap(fieldValue)) {
        nestedObjectList.add([fieldValue]);
        objectNestedIndices.add({objectNestedIndices.isNotEmpty ? -1 : objectIndex!: fieldName});
      } else {
        nestedObjectList.add(fieldValue);
        objectNestedIndices.add({objectIndex!: fieldName});
      }

      _hiveViewState.value = _hiveViewState.value.copyWith(
        nestedObjectList: nestedObjectList,
        objectNestedIndices: objectNestedIndices,
      );
      _pageController.jumpToPage(pageIndex + 1);
    } else if (fieldValue.runtimeType == List<String>) {
    } else {
      return; // update dialog not fully implemented
      final updatedObject = await showDialog(
        context: context,
        builder: (_) => UpdateDialog(
          objectAsJson: objectAsJson,
          fieldName: fieldName,
          dateFormat: widget.dateFormat,
        ),
      );
      final indexOfUpdatedObject = _hiveViewState.value.selectedBoxValue!.indexOf(
        updatedObject ?? {},
      );
      if (updatedObject != null) {
        final boxHandler = BoxUpdateHandler(
          _hiveViewState.value,
          widget.onError,
          objectIndex: indexOfUpdatedObject,
        );

        setState(() {});
        boxHandler.updateObject();
      }
    }
  }

  void _onBoxSelected(String boxName, List<BoxWithSerialization> boxesList) {
    final selectedBoxWithSerialization = boxesList.singleWhere(
      (element) => element.box.name == boxName,
    );
    if (selectedBoxWithSerialization.box.values.isEmpty) {
      widget.onError('Box is Empty');
    } else {
      _hiveViewState.value = _hiveViewState.value.copyWith(
        currentOpenedBox: selectedBoxWithSerialization.box,
        selectedBoxValue:
            selectedBoxWithSerialization.box.toMap().entries.map<Map<String, dynamic>>((entry) {
          // print(entry.toString());
          final val = entry.value.toString();
          return selectedBoxWithSerialization.toMap(val, entry.key.toString());
        }).toList(),
        objectNestedIndices: [],
      );
      _pageController.jumpToPage(1);
    }
  }

  void _onExitBoxView() {
    _hiveViewState.value = _hiveViewState.value.clearState();
    _pageController.jumpToPage(0);
  }

  void _onExitNestedObjectView(int index) {
    final newNestedObjectList = _hiveViewState.value.nestedObjectList!;
    final newObjectIndices = _hiveViewState.value.objectNestedIndices!;
    if (newObjectIndices.isNotEmpty) {
      newObjectIndices.removeLast();
    }

    newNestedObjectList.removeAt(index - 2);
    debugPrint(newObjectIndices.toString());
    _hiveViewState.value = _hiveViewState.value.copyWith(
      nestedObjectList: newNestedObjectList,
      objectNestedIndices: newObjectIndices,
    );
    _pageController.jumpToPage(index - 1);
  }

  bool boxIsNotEmpty(List<String>? columns, List<Map<String, dynamic>>? rows) {
    if (columns == null || rows == null) {
      return false;
    } else if (columns.isEmpty || rows.isEmpty) {
      return false;
    } else {
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<HiveViewState>(
      valueListenable: _hiveViewState,
      builder: (_, viewState, __) {
        int maximumKeys = 0;
        viewState.selectedBoxValue?.forEach((element) {
          if (maximumKeys < element.keys.length) {
            maximumKeys = element.keys.length;
          }
        });
        final selectedBox = viewState.currentOpenedBox;

        final boxesList = viewState.boxesMap.map((e) => e.box).toList();

        final boxColumns = viewState.selectedBoxValue
            ?.firstWhere((element) => element.keys.length == maximumKeys)
            .keys
            .toList();
// final boxColumns= column.first;

        final boxRows = viewState.selectedBoxValue;

        return Scaffold(
            appBar: AppBar(
              backgroundColor: widget.appBarColor,
              title: Text(
                selectedBox?.name ?? "",
              ),
            ),
            body: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                HiveBoxesList(
                  boxes: boxesList.toList(),
                  onBoxNameSelected: (boxName) => _onBoxSelected(
                    boxName,
                    viewState.boxesMap,
                  ),
                ),
                if (boxIsNotEmpty(boxColumns, boxRows))
                  HiveBoxesDetails(
                    deleteEnabled: widget.deleteEnabled,
                    onDeleteRows: (objectIndices) {
                      _onDeleteRows(objectIndices);
                    },
                    onDeleteAll: _onClearBox,
                    onFieldPressed: onFieldPressed,
                    onBackPressed: _onExitBoxView,
                    onAddRow: (map, boxColumns) {
                      _onAddRow(map, boxColumns);
                    },
                    rowTitleTextStyle: widget.rowTitleTextStyle,
                    columnTitleTextStyle: widget.columnTitleTextStyle,
                    columns: boxColumns!,
                    rows: boxRows!,
                  ),
                if (viewState.nestedObjectList != null && viewState.nestedObjectList!.isNotEmpty)
                  ...viewState.nestedObjectList!.map<HiveBoxesDetails>((nestedObject) {
                    final index = viewState.nestedObjectList!.indexOf(nestedObject);
                    final objectColumns = nestedObject.first.keys.toList();
                    final objectRows = nestedObject;
                    return HiveBoxesDetails(
                      deleteEnabled: widget.deleteEnabled,
                      onDeleteRows: (objectIndices) {
                        _onDeleteRows(objectIndices);
                      },
                      onDeleteAll: _onDeleteAllFields,
                      onFieldPressed: (
                        boxName,
                        fieldName,
                        objectAsJson, {
                        objectIndex,
                      }) {
                        onFieldPressed(
                          boxName,
                          fieldName,
                          objectAsJson,
                          pageIndex: 2 + index,
                          objectIndex: objectIndex,
                        );
                      },
                      onBackPressed: () => _onExitNestedObjectView(2 + index),
                      onAddRow: (objectAsJson, columns) => _onAddRow(objectAsJson, columns),
                      columnTitleTextStyle: widget.columnTitleTextStyle,
                      rowTitleTextStyle: widget.rowTitleTextStyle,
                      columns: objectColumns,
                      rows: objectRows,
                    );
                  })
              ],
            ));
      },
    );
  }
}
