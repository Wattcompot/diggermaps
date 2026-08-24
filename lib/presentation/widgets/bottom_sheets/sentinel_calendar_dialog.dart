import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SentinelCalendarSelection {
  const SentinelCalendarSelection({
    required this.date,
    required this.maxCloudCoverage,
    required this.imageCloudCoverage,
  });

  final DateTime date;
  final double maxCloudCoverage;
  final double imageCloudCoverage;
}

class SentinelCalendarDialog extends StatefulWidget {
  const SentinelCalendarDialog({
    super.key,
    required this.cloudByDate,
    required this.initialDate,
    required this.initialCloudCoverage,
  });

  final Map<DateTime, double> cloudByDate;
  final DateTime initialDate;
  final double initialCloudCoverage;

  static Future<SentinelCalendarSelection?> show(
    BuildContext context, {
    required Map<DateTime, double> cloudByDate,
    required DateTime initialDate,
    required double initialCloudCoverage,
  }) {
    return showDialog<SentinelCalendarSelection>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SentinelCalendarDialog(
        cloudByDate: cloudByDate,
        initialDate: initialDate,
        initialCloudCoverage: initialCloudCoverage,
      ),
    );
  }

  @override
  State<SentinelCalendarDialog> createState() => _SentinelCalendarDialogState();
}

class _SentinelCalendarDialogState extends State<SentinelCalendarDialog> {
  late DateTime _visibleMonth;
  DateTime? _selectedDate;
  late double _cloudCoverage;

  @override
  void initState() {
    super.initState();
    final day = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
    );
    _selectedDate = widget.cloudByDate.containsKey(day) ? day : null;
    final now = DateTime.now();
    _visibleMonth = _selectedDate == null
        ? DateTime(now.year, now.month)
        : DateTime(_selectedDate!.year, _selectedDate!.month);
    _cloudCoverage = widget.initialCloudCoverage;
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return AlertDialog(
      title: const Text('Свежие снимки'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
          minWidth: 300,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(height: 300, child: _calendar(today)),
              const Divider(),
              Row(
                children: <Widget>[
                  const Text('Облачность: '),
                  Text('${_cloudCoverage.round()}%'),
                  Expanded(
                    child: Slider(
                      value: _cloudCoverage,
                      max: 100,
                      onChanged: (value) => setState(() {
                        _cloudCoverage = value;
                        if (_selectedDate != null &&
                            (widget.cloudByDate[_selectedDate!] ?? 101) >
                                value) {
                          _selectedDate = null;
                        }
                      }),
                    ),
                  ),
                ],
              ),
              if (_selectedDate != null)
                Text(
                  'Выбрано: ${DateFormat('dd.MM.yyyy').format(_selectedDate!)} · '
                  'облачность '
                  '${(widget.cloudByDate[_selectedDate!] ?? 0).toStringAsFixed(1)}%',
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: _selectedDate == null
              ? null
              : () => Navigator.pop(
                    context,
                    SentinelCalendarSelection(
                      date: _selectedDate!,
                      maxCloudCoverage: _cloudCoverage,
                      imageCloudCoverage:
                          widget.cloudByDate[_selectedDate!] ?? _cloudCoverage,
                    ),
                  ),
          child: const Text('Показать'),
        ),
      ],
    );
  }

  Widget _calendar(DateTime today) {
    final year = _visibleMonth.year;
    final month = _visibleMonth.month;
    final firstDay = DateTime(year, month);
    final lastDay = DateTime(year, month + 1, 0);
    final startWeekday = firstDay.weekday % 7;
    final monthTitle = DateFormat('LLLL yyyy', 'ru_RU').format(_visibleMonth);
    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(
                () => _visibleMonth = DateTime(year, month - 1),
              ),
            ),
            Text(
              monthTitle[0].toUpperCase() + monthTitle.substring(1),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: year == today.year && month == today.month
                  ? null
                  : () => setState(
                        () => _visibleMonth = DateTime(year, month + 1),
                      ),
            ),
          ],
        ),
        Expanded(
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemCount: startWeekday + lastDay.day,
            itemBuilder: (_, index) {
              if (index < startWeekday) return const SizedBox.shrink();
              final date = DateTime(year, month, index - startWeekday + 1);
              final cloud = widget.cloudByDate[date];
              final available = cloud != null && cloud <= _cloudCoverage;
              final selected = _selectedDate == date;
              final isToday = date.year == today.year &&
                  date.month == today.month &&
                  date.day == today.day;
              return GestureDetector(
                onTap: date.isAfter(today) || !available
                    ? null
                    : () => setState(() => _selectedDate = date),
                child: Container(
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.blue
                        : available
                            ? Colors.green.shade400
                            : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                    border: isToday
                        ? Border.all(color: Colors.black, width: 1.5)
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                      color: available ? Colors.white : Colors.grey,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
