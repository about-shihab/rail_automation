import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/language_service.dart';
import '../utils/app_theme.dart';
import '../utils/railway_stations.dart';

class StationAutocomplete extends StatefulWidget {
  const StationAutocomplete({
    super.key,
    required this.label,
    required this.value,
    required this.otherValue,
    required this.stations,
    required this.icon,
    required this.onSelected,
  });

  final String label, value, otherValue;
  final List<String> stations;
  final IconData icon;
  final ValueChanged<String> onSelected;

  @override
  State<StationAutocomplete> createState() => _StationAutocompleteState();
}

class _StationAutocompleteState extends State<StationAutocomplete> {
  late final _controller = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void didUpdateWidget(StationAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        _controller.text != widget.value &&
        !(_focus.hasFocus && widget.value.isEmpty)) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Iterable<String> _options(TextEditingValue value) {
    final query = value.text.trim().toLowerCase();
    final matches = widget.stations
        .where(
          (station) =>
              station.toLowerCase() != widget.otherValue.toLowerCase() &&
              (query.isEmpty || station.toLowerCase().contains(query)),
        )
        .toList();
    matches.sort((a, b) {
      if (query.isEmpty) {
        final aPopular = popularStations.contains(a),
            bPopular = popularStations.contains(b);
        if (aPopular != bPopular) return aPopular ? -1 : 1;
      } else {
        final aPrefix = a.toLowerCase().startsWith(query),
            bPrefix = b.toLowerCase().startsWith(query);
        if (aPrefix != bPrefix) return aPrefix ? -1 : 1;
      }
      return a.compareTo(b);
    });
    return matches.take(12);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final lang = LanguageService.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => RawAutocomplete<String>(
        textEditingController: _controller,
        focusNode: _focus,
        optionsBuilder: _options,
        onSelected: (station) {
          widget.onSelected(station);
          _focus.unfocus();
        },
        fieldViewBuilder: (context, controller, focus, submit) =>
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => TextField(
                controller: controller,
                focusNode: focus,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.words,
                scrollPadding: const EdgeInsets.only(bottom: 240),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(dark),
                ),
                decoration: InputDecoration(
                  labelText: widget.label,
                  hintText: lang.tr('Station', 'স্টেশন'),
                  filled: true,
                  fillColor: AppColors.inputFill(dark),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        widget.icon,
                        size: 20,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  suffixIcon: value.text.isEmpty
                      ? const Icon(Icons.search_rounded, size: 20)
                      : IconButton(
                          tooltip: lang.tr('Clear', 'মুছুন'),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            controller.clear();
                            widget.onSelected('');
                            focus.requestFocus();
                          },
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: AppColors.inputBorder(dark)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: AppColors.inputBorder(dark)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                  ),
                ),
                onChanged: (text) {
                  final exact = widget.stations.where(
                    (s) =>
                        s.toLowerCase() == text.trim().toLowerCase() &&
                        s.toLowerCase() != widget.otherValue.toLowerCase(),
                  );
                  widget.onSelected(exact.isEmpty ? '' : exact.first);
                },
                onSubmitted: (_) => submit(),
              ),
            ),
        optionsViewBuilder: (context, select, options) {
          final rows = options.toList();
          final query = _controller.text.trim().toLowerCase();
          final height =
              MediaQuery.sizeOf(context).height -
              MediaQuery.viewInsetsOf(context).bottom;
          return Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Material(
                color: AppColors.cardBg(dark),
                elevation: 8,
                shadowColor: Colors.black.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: constraints.maxWidth,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: math.max(80, math.min(240, height * .4)),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final station = rows[index];
                        final highlighted =
                            AutocompleteHighlightedOption.of(context) == index;
                        final start = query.isEmpty
                            ? -1
                            : station.toLowerCase().indexOf(query);
                        return InkWell(
                          onTap: () => select(station),
                          child: Container(
                            color: highlighted
                                ? AppColors.primary.withValues(alpha: .08)
                                : null,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.train_outlined,
                                  size: 20,
                                  color: AppColors.textMuted(dark),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: AppColors.textPrimary(dark),
                                      ),
                                      children: [
                                        if (start < 0)
                                          TextSpan(text: station)
                                        else ...[
                                          TextSpan(
                                            text: station.substring(0, start),
                                          ),
                                          TextSpan(
                                            text: station.substring(
                                              start,
                                              start + query.length,
                                            ),
                                            style: const TextStyle(
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          TextSpan(
                                            text: station.substring(
                                              start + query.length,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.north_west_rounded,
                                  size: 16,
                                  color: AppColors.textMuted(dark),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
