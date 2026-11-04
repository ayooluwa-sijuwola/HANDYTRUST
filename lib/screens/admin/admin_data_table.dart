import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'admin_palette.dart';

class AdminTableColumn {
  final String label;
  final int flex;
  final bool sortable;
  const AdminTableColumn(this.label, {this.flex = 1, this.sortable = false});
}

/// Professional, paginated, sortable data table shell used across every
/// admin browse section (Users, Artisans, Jobs, Reviews, Support Tickets).
/// Callers own filtering/sorting of [rows] and pass the already-prepared
/// list in; this widget only owns pagination + the header chrome + empty
/// state, so each section keeps its own search/filter logic untouched.
/// Below this content width, [AdminDataTable] drops the flex-column table
/// layout (built for the ≥4-column, hover-friendly desktop case) in favor
/// of stacked cards — real reflow, not a horizontal-scroll squeeze of the
/// same rigid columns onto a phone-width screen.
const double kAdminTableNarrowBreakpoint = 640;

class AdminDataTable<T> extends StatefulWidget {
  final AdminPalette palette;
  final List<AdminTableColumn> columns;
  final List<T> rows;
  final Widget Function(BuildContext context, T item, bool selected) rowBuilder;
  // Card-mode row renderer for narrow widths. Optional — callers that
  // haven't been given a card layout yet fall back to rowBuilder inside a
  // horizontally-scrollable row (still functional, just not reflowed),
  // so this can be adopted incrementally per table.
  final Widget Function(BuildContext context, T item, bool selected)? narrowRowBuilder;
  final void Function(T item)? onRowTap;
  final void Function(int columnIndex)? onSort;
  final int? sortColumnIndex;
  final bool sortAscending;
  final T? selected;
  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptySubtitle;
  final int pageSize;

  const AdminDataTable({
    super.key,
    required this.palette,
    required this.columns,
    required this.rows,
    required this.rowBuilder,
    this.narrowRowBuilder,
    this.onRowTap,
    this.onSort,
    this.sortColumnIndex,
    this.sortAscending = true,
    this.selected,
    this.emptyIcon = Icons.inbox_outlined,
    this.emptyTitle = 'No records found',
    this.emptySubtitle,
    this.pageSize = 10,
  });

  @override
  State<AdminDataTable<T>> createState() => _AdminDataTableState<T>();
}

class _AdminDataTableState<T> extends State<AdminDataTable<T>> {
  int _page = 0;

  @override
  void didUpdateWidget(covariant AdminDataTable<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final maxPage = (widget.rows.length / widget.pageSize).ceil() - 1;
    if (_page > maxPage) _page = maxPage < 0 ? 0 : maxPage;
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;

    if (widget.rows.isEmpty) {
      return Container(
        decoration: palette.cardDecoration(),
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.emptyIcon, size: 48, color: palette.textTertiary),
              const SizedBox(height: 12),
              Text(widget.emptyTitle,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                      fontFamily: 'Inter')),
              if (widget.emptySubtitle != null) ...[
                const SizedBox(height: 4),
                Text(widget.emptySubtitle!,
                    style: TextStyle(
                        fontSize: 12,
                        color: palette.textTertiary,
                        fontFamily: 'Inter')),
              ],
            ],
          ),
        ),
      );
    }

    final totalPages = (widget.rows.length / widget.pageSize).ceil();
    final start = _page * widget.pageSize;
    final end = (start + widget.pageSize).clamp(0, widget.rows.length);
    final pageRows = widget.rows.sublist(start, end);

    final narrow = MediaQuery.of(context).size.width < kAdminTableNarrowBreakpoint;
    if (narrow && widget.narrowRowBuilder != null) {
      return Column(
        children: [
          ...pageRows.map((item) {
            final isSelected = widget.selected != null && widget.selected == item;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: palette.cardDecoration().copyWith(
                    border: isSelected
                        ? Border.all(color: AdminPalette.indigo, width: 1.5)
                        : null,
                  ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(item),
                  child: widget.narrowRowBuilder!(context, item, isSelected),
                ),
              ),
            );
          }),
          _pager(palette, start, end, totalPages),
        ],
      );
    }

    return Container(
      decoration: palette.cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: palette.bg2,
              border: Border(bottom: BorderSide(color: palette.border)),
            ),
            child: Row(
              children: widget.columns
                  .asMap()
                  .entries
                  .map((e) => Expanded(
                        flex: e.value.flex,
                        child: InkWell(
                          onTap: e.value.sortable && widget.onSort != null
                              ? () => widget.onSort!(e.key)
                              : null,
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  e.value.label.toUpperCase(),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6,
                                    color: palette.textTertiary,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ),
                              if (e.value.sortable &&
                                  widget.sortColumnIndex == e.key) ...[
                                const SizedBox(width: 3),
                                Icon(
                                  widget.sortAscending
                                      ? Icons.arrow_upward_rounded
                                      : Icons.arrow_downward_rounded,
                                  size: 12,
                                  color: AdminPalette.indigo,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
          ...pageRows.map((item) {
            final isSelected = widget.selected != null && widget.selected == item;
            return Material(
              color: isSelected
                  ? AdminPalette.indigo.withValues(alpha: 0.10)
                  : Colors.transparent,
              child: InkWell(
                onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(item),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: palette.border)),
                  ),
                  child: widget.rowBuilder(context, item, isSelected),
                ),
              ),
            );
          }),
          _pager(palette, start, end, totalPages),
        ],
      ),
    );
  }

  /// Shared "Showing X-Y of Z" + prev/next footer — used by both the wide
  /// table layout and the narrow card-stack layout so pagination behaves
  /// identically either way.
  Widget _pager(AdminPalette palette, int start, int end, int totalPages) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing ${start + 1}-$end of ${widget.rows.length}',
            style: TextStyle(
                fontSize: 11.5, color: palette.textTertiary, fontFamily: 'Inter'),
          ),
          Row(
            children: [
              IconButton(
                iconSize: 18,
                color: palette.textSecondary,
                onPressed: _page > 0 ? () => setState(() => _page--) : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text(
                '${_page + 1} / ${totalPages == 0 ? 1 : totalPages}',
                style: TextStyle(
                    fontSize: 12, color: palette.textSecondary, fontFamily: 'Inter'),
              ),
              IconButton(
                iconSize: 18,
                color: palette.textSecondary,
                onPressed: _page < totalPages - 1 ? () => setState(() => _page++) : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Master-detail layout: table on the left, a docked panel on the right
/// once a row is selected (desktop/tablet); on narrow screens the panel
/// becomes a full-screen modal instead of squeezing the table. Tracks
/// [detailKey] so the modal is only pushed once per selection change, not
/// on every rebuild (e.g. from a live Firestore stream tick).
class AdminMasterDetail extends StatefulWidget {
  final AdminPalette palette;
  final Widget table;
  final Widget? detail;
  final Object? detailKey;
  final String detailTitle;
  final VoidCallback onCloseDetail;

  const AdminMasterDetail({
    super.key,
    required this.palette,
    required this.table,
    required this.detail,
    required this.detailKey,
    required this.detailTitle,
    required this.onCloseDetail,
  });

  @override
  State<AdminMasterDetail> createState() => _AdminMasterDetailState();
}

class _AdminMasterDetailState extends State<AdminMasterDetail> {
  Object? _shownForKey;

  @override
  void didUpdateWidget(covariant AdminMasterDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wide = kIsWeb && MediaQuery.of(context).size.width >= 900;
    if (wide) return;
    if (widget.detail != null && widget.detailKey != _shownForKey) {
      _shownForKey = widget.detailKey;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showSheet());
    } else if (widget.detail == null) {
      _shownForKey = null;
    }
  }

  void _showSheet() {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, controller) => Container(
          decoration: BoxDecoration(
            color: widget.palette.bg1,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: _panelChrome(controller),
        ),
      ),
    ).whenComplete(() {
      _shownForKey = null;
      widget.onCloseDetail();
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = kIsWeb && MediaQuery.of(context).size.width >= 900;

    if (widget.detail == null) return widget.table;
    if (!wide) return widget.table;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: widget.table),
        const SizedBox(width: 14),
        SizedBox(
          width: 380,
          child: Container(
            decoration: widget.palette.cardDecoration(),
            clipBehavior: Clip.antiAlias,
            child: _panelChrome(null),
          ),
        ),
      ],
    );
  }

  Widget _panelChrome(ScrollController? controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: widget.palette.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.detailTitle,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: widget.palette.textPrimary,
                      fontFamily: 'Inter'),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded,
                    color: widget.palette.textTertiary, size: 20),
                onPressed: widget.onCloseDetail,
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            controller: controller,
            padding: const EdgeInsets.all(14),
            child: widget.detail,
          ),
        ),
      ],
    );
  }
}
