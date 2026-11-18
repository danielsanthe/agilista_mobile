import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../nucleo/tema/app_theme.dart';

class SeletorPeriodoWidget extends StatefulWidget {
  final DateTime dataInicio;
  final DateTime dataFim;
  final Function(DateTime inicio, DateTime fim) onDatasAlteradas;
  final VoidCallback onFiltrarClicado;

  const SeletorPeriodoWidget({
    super.key,
    required this.dataInicio,
    required this.dataFim,
    required this.onDatasAlteradas,
    required this.onFiltrarClicado,
  });

  @override
  State<SeletorPeriodoWidget> createState() => _SeletorPeriodoWidgetState();
}

class _SeletorPeriodoWidgetState extends State<SeletorPeriodoWidget> {
  late DateTime _inicio;
  late DateTime _fim;

  @override
  void initState() {
    super.initState();
    _inicio = widget.dataInicio;
    _fim = widget.dataFim;
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          InkWell(
            onTap: () async {
              final range = await showDateRangePicker(
                context: context,
                locale: const Locale('pt', 'BR'), // IDIOMA PORTUGUÊS-BR
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
                initialDateRange: DateTimeRange(start: _inicio, end: _fim),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.light(
                        primary: AppTheme.primaryBlue,
                        onPrimary: Colors.white,
                        onSurface: AppTheme.textDark,
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (range != null) {
                setState(() {
                  _inicio = range.start;
                  _fim = range.end;
                });
                widget.onDatasAlteradas(_inicio, _fim);
              }
            },
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 18, color: AppTheme.primaryBlue),
                const SizedBox(width: 8),
                Text(
                  '${fmt.format(_inicio)}  até  ${fmt.format(_fim)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textDark),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: widget.onFiltrarClicado,
            child: const Text('FILTRAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}