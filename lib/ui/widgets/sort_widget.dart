import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/l10n/l10n.dart';
import 'package:harmonymusic/app/providers/repository_providers.dart';
import 'package:harmonymusic/ui/screens/Library/library_controller.dart';

import 'additional_operation_dialog.dart';
import 'awaitable_button.dart';
import 'modified_text_field.dart';

enum OperationMode { arrange, delete, addToPlaylist, none }

enum SortType { name, date, duration, recentlyPlayed }

Set<SortType> buildSortTypeSet([
  bool dateRequired = false,
  bool durationRequired = false,
  bool recentlyPlayedRequired = false,
]) {
  Set<SortType> requiredSortTypes = {};
  if (dateRequired) {
    requiredSortTypes.add(SortType.date);
  }
  if (durationRequired) {
    requiredSortTypes.add(SortType.duration);
  }
  if (recentlyPlayedRequired) {
    requiredSortTypes.add(SortType.recentlyPlayed);
  }
  return requiredSortTypes;
}

class SortWidget extends StatefulWidget {
  /// Additional operations - Delete Multiple songs, Rearrange offline playlist, Add Multiple songs to playlist
  const SortWidget({
    super.key,
    required this.tag,
    this.itemCountTitle = '',
    this.titleLeftPadding = 18,
    this.isAdditionalOperationRequired = true,
    this.requiredSortTypes = const <SortType>{SortType.name},
    this.isSearchFeatureRequired = false,
    this.isPlaylistRearrangeFeatureRequired = false,
    this.isSongDeletionFeatureRequired = false,
    required this.screenController,
    this.onSearchStart,
    this.onSearch,
    this.onSearchClose,
    this.itemIcon,
    this.startAdditionalOperation,
    this.selectAll,
    this.performAdditionalOperation,
    this.cancelAdditionalOperation,
    this.isImportFeatureRequired = false,
    this.initialSortType = SortType.name,
    this.initialIsAscending = true,
    required this.onSort,
    this.onMounted,
    this.filterOptions,
  });

  /// Optional filter switches shown behind a funnel icon. Only the Songs tab
  /// uses them; every other screen passes null and is unchanged.
  final List<SortFilterOption>? filterOptions;

  /// unique identifier for each sort-widget
  final String tag;
  final String itemCountTitle;
  final IconData? itemIcon;
  final bool isAdditionalOperationRequired;
  final double titleLeftPadding;
  final Set<SortType> requiredSortTypes;
  final bool isSearchFeatureRequired;
  final bool isSongDeletionFeatureRequired;
  final bool isPlaylistRearrangeFeatureRequired;
  final dynamic screenController;
  final Function(SortWidgetController, OperationMode)? startAdditionalOperation;
  final Function(bool)? selectAll;
  final Function()? performAdditionalOperation;
  final Function()? cancelAdditionalOperation;
  final Function(String?)? onSearchStart;
  final Function(String, String?)? onSearch;
  final Function(String?)? onSearchClose;
  final Function(SortType, bool) onSort;
  final bool isImportFeatureRequired;
  final SortType initialSortType;
  final bool initialIsAscending;

  /// Fired once after this sort widget attaches. A freshly mounted sort
  /// widget always starts with the search bar closed and empty, so screens
  /// whose controller outlives the widget (the library tabs) use this to
  /// drop a filter left over from a previous visit — otherwise the list
  /// stays filtered with no visible search text.
  final VoidCallback? onMounted;

  @override
  State<SortWidget> createState() => _SortWidgetState();
}

class _SortWidgetState extends State<SortWidget> {
  late final SortWidgetController controller;

  @override
  void initState() {
    super.initState();
    controller = SortWidgetController(
      initialSortType: widget.initialSortType,
      initialIsAscending: widget.initialIsAscending,
    );
    SortWidgetRegistry.register(widget.tag, controller);
    if (widget.onMounted != null) {
      // Deferred past the first frame: the callback may notify listeners,
      // which is not allowed while the surrounding build is still running.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onMounted!();
      });
    }
  }

  @override
  void didUpdateWidget(covariant SortWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tag != widget.tag) {
      SortWidgetRegistry.unregister(oldWidget.tag, controller);
      SortWidgetRegistry.register(widget.tag, controller);
    }
  }

  @override
  void dispose() {
    SortWidgetRegistry.unregister(widget.tag, controller);
    controller.dispose();
    super.dispose();
  }

  Future<void> _showImportDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          context.l10n.importPlaylist,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.importPlaylistDesc,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.importLargeFileNote,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: AwaitableButton.elevated(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Theme.of(context).colorScheme.onSecondary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.file_open),
                label: Text(context.l10n.selectFile),
                onPressed: () async {
                  await LibraryPlaylistsControllerRegistry.current
                      ?.importPlaylistFromJson(context);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.secondary,
            ),
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSaveLibrarySearch = widget.tag == "LibSongSort";
    return Padding(
      padding: const EdgeInsets.only(top: 10.0),
      child: SizedBox(
        height: 40,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => Stack(
            children: [
              if (!controller.isSearchingEnabled)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(left: widget.titleLeftPadding),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(widget.itemCountTitle),
                          if (widget.itemIcon != null)
                            Icon(
                              Icons.music_note,
                              size: 15,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                        ],
                      ),
                    ),
                    if (widget.filterOptions?.isNotEmpty ?? false)
                      _filterMenu(context, widget.filterOptions!),
                    _customIconButton(
                      context,
                      isSelected: controller.sortType == SortType.name,
                      icon: Icons.sort_by_alpha,
                      tooltip: context.l10n.sortByName,
                      onPressed: () {
                        controller.onSortByName(widget.onSort);
                      },
                    ),
                    widget.requiredSortTypes.contains(SortType.date)
                        ? _customIconButton(
                            context,
                            isSelected: controller.sortType == SortType.date,
                            icon: Icons.calendar_month,
                            tooltip: context.l10n.sortByDate,
                            onPressed: () {
                              controller.onSortByDate(widget.onSort);
                            },
                          )
                        : const SizedBox.shrink(),
                    widget.requiredSortTypes.contains(SortType.duration)
                        ? _customIconButton(
                            context,
                            isSelected:
                                controller.sortType == SortType.duration,
                            tooltip: context.l10n.sortByDuration,
                            icon: Icons.timer,
                            onPressed: () {
                              controller.onSortByDuration(widget.onSort);
                            },
                          )
                        : const SizedBox.shrink(),
                    const Expanded(child: SizedBox()),
                    _customIconButton(
                      context,
                      icon: controller.isAscending
                          ? Icons.arrow_downward
                          : Icons.arrow_upward,
                      tooltip: context.l10n.sortAscendNDescend,
                      onPressed: () {
                        controller.onAscendNDescend(widget.onSort);
                      },
                    ),
                    if (widget.isImportFeatureRequired)
                      _customIconButton(
                        context,
                        icon: Icons.import_contacts,
                        tooltip: context.l10n.importPlaylist,
                        onPressed: () async {
                          await _showImportDialog(context);
                        },
                      ),
                    if (widget.isSearchFeatureRequired)
                      _customIconButton(
                        context,
                        icon: Icons.search,
                        tooltip: context.l10n.search,
                        onPressed: () {
                          widget.onSearchStart!(widget.tag);
                          controller.toggleSearch();
                        },
                      ),
                    if (widget.isAdditionalOperationRequired)
                      PopupMenuButton(
                        child: const Icon(Icons.more_vert, size: 20),
                        // Callback that sets the selected popup menu item.
                        onSelected: (mode) async {
                          await showDialog(
                            context: context,
                            builder: (context) => AdditionalOperationDialog(
                              operationMode: mode,
                              screenController: widget.screenController,
                              controller: controller,
                            ),
                          );

                          controller.setActiveMode(mode);
                          widget.startAdditionalOperation!(controller, mode);
                        },
                        itemBuilder: (BuildContext context) => <PopupMenuEntry>[
                          if (widget.isPlaylistRearrangeFeatureRequired)
                            PopupMenuItem(
                              value: OperationMode.arrange,
                              child: Text(context.l10n.reArrangePlaylist),
                            ),
                          if (widget.isSongDeletionFeatureRequired)
                            PopupMenuItem(
                              value: OperationMode.delete,
                              child: Text(context.l10n.removeMultiple),
                            ),
                          PopupMenuItem(
                            value: OperationMode.addToPlaylist,
                            child: Text(context.l10n.addMultipleSongs),
                          ),
                        ],
                      ),
                    const SizedBox(width: 15),
                  ],
                ),
              if (controller.isSearchingEnabled)
                Container(
                  height: 40,
                  padding: const EdgeInsets.only(left: 5, right: 20),
                  // color:
                  //     Theme.of(context).scaffoldBackgroundColor.withAlpha(125),
                  child: ColoredBox(
                    color: Theme.of(
                      context,
                    ).scaffoldBackgroundColor.withAlpha(125),
                    child: ModifiedTextField(
                      controller: controller.textEditingController,
                      textAlignVertical: TextAlignVertical.center,
                      autofocus: true,
                      onChanged: (value) {
                        widget.onSearch!(value, widget.tag);
                      },
                      cursorColor: Theme.of(
                        context,
                      ).textTheme.titleSmall!.color,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.all(8),
                        filled: true,
                        border: const OutlineInputBorder(),
                        hintText: widget.tag.startsWith("Lib")
                            ? context.l10n.searchHint
                            : context.l10n.search,
                        suffixIconColor: Theme.of(
                          context,
                        ).colorScheme.secondary,
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (canSaveLibrarySearch)
                              AwaitableIconButton(
                                splashRadius: 10,
                                iconSize: 20,
                                icon: const Icon(Icons.save),
                                onPressed: () async {
                                  final query = controller
                                      .textEditingController
                                      .text
                                      .trim();
                                  if (query.isEmpty) return;
                                  await ProviderScope.containerOf(
                                        context,
                                        listen: false,
                                      )
                                      .read(libraryRepositoryProvider)
                                      .addSearch(query);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        "${context.l10n.searchSaved}: $query",
                                      ),
                                    ),
                                  );
                                },
                              ),
                            IconButton(
                              splashRadius: 10,
                              iconSize: 20,
                              icon: const Icon(Icons.cancel),
                              onPressed: () {
                                widget.onSearchClose!(widget.tag);
                                controller.toggleSearch();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Filter switches behind a funnel, matching the sort buttons' size and
  /// colour so the toolbar stays one row of controls. Highlighted whenever a
  /// filter is on, so a narrowed list is never a mystery.
  Widget _filterMenu(BuildContext context, List<SortFilterOption> options) {
    final anyActive = options.any((option) => option.value);
    return PopupMenuButton<void>(
      icon: Icon(
        anyActive ? Icons.filter_alt : Icons.filter_alt_outlined,
        size: 20,
        color: anyActive
            ? Theme.of(context).colorScheme.secondary
            : Theme.of(context).textTheme.bodySmall!.color,
      ),
      padding: EdgeInsets.zero,
      splashRadius: 20,
      tooltip: context.l10n.filter,
      color: Theme.of(context).cardColor,
      itemBuilder: (context) => [
        for (final option in options)
          // Keeps the menu open so several filters can be flipped at once.
          PopupMenuItem<void>(child: _FilterSwitchTile(option: option)),
      ],
    );
  }

  Widget _customIconButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    bool? isSelected,
    Function()? onPressed,
  }) {
    return IconButton(
      icon: Icon(icon),
      padding: const EdgeInsets.all(0),
      color: isSelected == null || isSelected == true
          ? Theme.of(context).textTheme.bodySmall!.color
          : Theme.of(context).colorScheme.secondary,
      iconSize: 20,
      splashRadius: 20,
      visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
      onPressed: onPressed,
      tooltip: tooltip,
    );
  }
}

/// One switch in the [SortWidget] filter menu.
class SortFilterOption {
  const SortFilterOption({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final void Function(bool value) onChanged;
}

/// One switch in the filter menu, holding its own position.
///
/// The menu is a separate route: its items are built once when it opens and
/// keep the [SortFilterOption] instances captured at that moment, so a parent
/// rebuild after `onChanged` never reaches them and re-reading `option.value`
/// always returns the pre-tap answer. The switch stayed visually stuck until
/// the menu was closed and reopened, even though the list behind it had
/// already re-filtered. Tracking the position locally is what makes the toggle
/// respond on the tap that caused it.
class _FilterSwitchTile extends StatefulWidget {
  const _FilterSwitchTile({required this.option});

  final SortFilterOption option;

  @override
  State<_FilterSwitchTile> createState() => _FilterSwitchTileState();
}

class _FilterSwitchTileState extends State<_FilterSwitchTile> {
  late bool _value = widget.option.value;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: _value,
      title: Text(widget.option.label),
      onChanged: (value) {
        setState(() => _value = value);
        widget.option.onChanged(value);
      },
    );
  }
}

class SortWidgetRegistry {
  static final _controllers = <String, SortWidgetController>{};

  static void register(String tag, SortWidgetController controller) {
    _controllers[tag] = controller;
  }

  static void unregister(String tag, SortWidgetController controller) {
    if (_controllers[tag] == controller) {
      _controllers.remove(tag);
    }
  }

  static SortWidgetController? maybeOf(String? tag) =>
      tag == null ? null : _controllers[tag];
}

class SortWidgetController extends ChangeNotifier {
  SortWidgetController({
    SortType initialSortType = SortType.name,
    bool initialIsAscending = true,
  }) : sortType = initialSortType,
       isAscending = initialIsAscending;

  SortType sortType;
  bool isAscending;
  bool isSearchingEnabled = false;
  bool isRearrangingEnabled = false;
  bool isDeletionEnabled = false;
  bool isAddToPlaylistEnabled = false;
  bool isAllSelected = false;
  final TextEditingController textEditingController = TextEditingController();

  void setActiveMode(OperationMode mode) {
    isAddToPlaylistEnabled = OperationMode.addToPlaylist == mode;
    isDeletionEnabled = OperationMode.delete == mode;
    isRearrangingEnabled = OperationMode.arrange == mode;
    notifyListeners();
  }

  void toggleSelectAll(bool val) {
    isAllSelected = val;
    notifyListeners();
  }

  void onSortByName(Function onSort) {
    sortType = SortType.name;
    notifyListeners();
    onSort(sortType, isAscending);
  }

  void onSortByDuration(Function onSort) {
    sortType = SortType.duration;
    notifyListeners();
    onSort(sortType, isAscending);
  }

  void onSortByDate(Function onSort) {
    sortType = SortType.date;
    notifyListeners();
    onSort(sortType, isAscending);
  }

  void onAscendNDescend(Function onSort) {
    isAscending = !isAscending;
    notifyListeners();
    onSort(sortType, isAscending);
  }

  void toggleSearch() {
    isSearchingEnabled = !isSearchingEnabled;
    notifyListeners();
  }

  @override
  void dispose() {
    textEditingController.dispose();
    super.dispose();
  }
}
