import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart' as native;

import 'tray_menu.dart';

/// Shows the tray icon and turns [TrayEntry] lists into its native menu.
class TrayPresenter {
  TrayPresenter({required this.onCommand});

  final void Function(TrayCommand command) onCommand;

  native.TrayIcon? _icon;
  _NativeMenu? _menu;

  /// nativeapi frees a native image when its Dart wrapper is collected,
  /// so the images the icon shows are kept here.
  final Map<String, native.Image> _images = {};

  /// False when the desktop has no tray (StatusNotifierItem) support.
  bool start() {
    if (!native.TrayManager.instance.isSupported()) return false;
    final icon = native.TrayIcon.create();
    if (icon == null) return false;
    icon.setVisible(true);
    _icon = icon;
    return true;
  }

  void update({
    required String iconAsset,
    required String tooltip,
    required List<TrayEntry> entries,
  }) {
    final icon = _icon;
    if (icon == null) return;

    final image = _images[iconAsset] ?? _loadImage(iconAsset);
    if (image != null) {
      _images[iconAsset] = image;
      icon.icon = image;
    }
    icon.setTooltip(tooltip);

    final menu = _NativeMenu(entries, onCommand);
    icon.setContextMenu(menu.menu);
    // On Linux the panel opens the exported menu itself, and a menu is only
    // exported once a trigger is set.
    icon.setContextMenuTrigger(native.ContextMenuTrigger.rightClicked);

    // The old menu may be the one whose click callback is running right now.
    final old = _menu;
    _menu = menu;
    if (old != null) Timer.run(old.dispose);
  }

  native.Image? _loadImage(String asset) {
    final image = native.ImageAsset.fromAsset(asset);
    if (image == null) debugPrint('tray: cannot load $asset');
    return image;
  }
}

/// A native menu tree and every wrapper that must stay alive with it.
class _NativeMenu {
  _NativeMenu(List<TrayEntry> entries, this._onCommand) {
    menu = _build(entries);
  }

  final void Function(TrayCommand command) _onCommand;
  late final native.Menu menu;
  final List<native.Menu> _menus = [];
  final List<native.MenuItem> _items = [];
  final List<(native.MenuItem, native.ListenerId)> _listeners = [];

  native.Menu _build(List<TrayEntry> entries) {
    final menu = native.Menu.create()!;
    _menus.add(menu);
    for (final entry in entries) {
      switch (entry) {
        case TraySeparator():
          menu.addSeparator();
        case TraySubmenu(:final label, :final children):
          final item = _createItem(label, native.MenuItemType.submenu);
          item.submenu = _build(children);
          menu.addItem(item);
        case TrayItem(:final label, :final command, :final checked):
          final item = _createItem(
            label,
            checked == null
                ? native.MenuItemType.normal
                : native.MenuItemType.checkbox,
          );
          item.isEnabled = command != null;
          if (checked != null) item.state = _state(checked);
          if (command != null) {
            final id = item.addListener((event) {
              if (event is! native.MenuItemClickedEvent) return;
              // Some platforms tick a checkbox on click by themselves; the
              // menu should only change once the state really changes.
              if (checked != null) item.state = _state(checked);
              _onCommand(command);
            });
            _listeners.add((item, id));
          }
          menu.addItem(item);
      }
    }
    return menu;
  }

  native.MenuItem _createItem(String label, native.MenuItemType type) {
    final item = native.MenuItem.createWithLabelAndType(label, type)!;
    _items.add(item);
    return item;
  }

  static native.MenuItemState _state(bool checked) =>
      checked ? native.MenuItemState.checked : native.MenuItemState.unchecked;

  void dispose() {
    for (final (item, id) in _listeners) {
      item.removeListener(id);
    }
    for (final item in _items) {
      item.dispose();
    }
    for (final menu in _menus) {
      menu.dispose();
    }
  }
}
