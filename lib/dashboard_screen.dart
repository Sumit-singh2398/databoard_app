import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemini/flutter_gemini.dart';

import 'login_page.dart';

enum ChartType { line, bar, pie }

enum MessageSender { user, bot }

class ChatMessage {
  ChatMessage.text({
    required this.sender,
    required this.text,
  })  : type = null,
        title = null,
        data = null,
        color = null;

  ChatMessage.chart({
    required this.title,
    required this.data,
    required this.type,
    required this.color,
  }) : sender = MessageSender.bot,
       text = null;

  final MessageSender sender;
  final String? text;
  final String? title;
  final List<double>? data;
  final ChartType? type;
  final Color? color;

  bool get isChart => type != null;
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const Color _bg = Color(0xFF0B1120);
  static const Color _surface = Color(0xFF111C2E);
  static const Color _surfaceAlt = Color(0xFF16233A);
  static const Color _border = Color(0xFF233247);
  static const Color _accent = Color(0xFF22C55E);
  static const Color _accentSoft = Color(0xFF163A2A);

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];

  File? _csvFile;
  String? _csvFileName;
  List<List<dynamic>> _csvData = [];

  bool _csvLoaded = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    final apiKey = const String.fromEnvironment('GEMINI_API_KEY');
    if (apiKey.isNotEmpty) {
      Gemini.init(apiKey: apiKey);
    }

    _messages.add(
      ChatMessage.text(
        sender: MessageSender.bot,
        text:
            'Welcome to DataBoard AI 👋\n\nUpload a CSV file, then ask things like:\n• “Show a line chart”\n• “Create a bar graph”\n• “Show pie distribution”',
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickCSV() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: false,
    );

    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);

    setState(() {
      _isLoading = true;
      _csvFile = file;
      _csvFileName = result.files.single.name;
    });

    await _loadCSV(file);

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _loadCSV(File file) async {
    try {
      final csvText = await file.readAsString();
      final parsed = const CsvToListConverter().convert(csvText);

      if (parsed.isEmpty) {
        _showError('The selected CSV file is empty.');
        return;
      }

      setState(() {
        _csvData = parsed;
        _csvLoaded = true;
      });

      _addBotMessage(
        'CSV loaded successfully ✅\n\n'
        'File: ${_csvFileName ?? 'Unknown'}\n'
        'Rows: ${parsed.length - 1}\n'
        'Columns: ${_getHeaders().join(', ')}',
      );
    } catch (e) {
      _showError('Could not read CSV file.\n$e');
    }
  }

  void _clearCSV() {
    setState(() {
      _csvFile = null;
      _csvFileName = null;
      _csvData.clear();
      _csvLoaded = false;
    });

    _addBotMessage('CSV cleared. Upload a new file to continue.');
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;

    if (!_csvLoaded) {
      _addBotMessage('Please upload a CSV file first.');
      return;
    }

    _controller.clear();
    _messages.add(ChatMessage.text(sender: MessageSender.user, text: text));
    _safeSetState();
    _scrollToBottom();

    setState(() => _isLoading = true);

    await _processWithGemini(text);

    if (!mounted) return;
    setState(() => _isLoading = false);
    _scrollToBottom();
  }

  Future<void> _processWithGemini(String query) async {
    try {
      final headers = _getHeaders();
      final csvContext = '''
You are a data analysis assistant.
The user has uploaded a CSV file.

File name: ${_csvFileName ?? 'Unknown'}
Total rows including header: ${_csvData.length}
Columns: ${headers.join(', ')}

First few rows:
${_getPreviewRows()}

User question: $query

Give a clear, short, professional answer.
''';

      final response = await Gemini.instance.text(csvContext);
      final aiResponse = response?.output?.trim();

      if (aiResponse == null || aiResponse.isEmpty) {
        _addBotMessage('I could not generate a response. Please try again.');
        return;
      }

      final lower = query.toLowerCase();

      if (lower.contains('pie')) {
        _addPieChart();
      } else if (lower.contains('bar')) {
        _addBarChart();
      } else if (lower.contains('line') ||
          lower.contains('chart') ||
          lower.contains('graph') ||
          lower.contains('show')) {
        _addLineChart(aiResponse);
      } else {
        _addBotMessage(aiResponse);
      }
    } catch (e) {
      _showError(
        'AI request failed.\n\nTry:\n• “Show line chart”\n• “Show bar chart”\n• “Show pie chart”',
      );
    }
  }

  String _getPreviewRows() {
    final buffer = StringBuffer();

    final limit = _csvData.length < 6 ? _csvData.length : 6;

    for (int i = 0; i < limit; i++) {
      buffer.writeln(_csvData[i].join(' | '));
    }

    return buffer.toString();
  }

  List<String> _getHeaders() {
    if (_csvData.isEmpty) return [];
    return _csvData.first.map((e) => e.toString()).toList();
  }

  List<double> _getChartData() {
    final data = <double>[];

    if (_csvData.length > 1) {
      for (int i = 1; i < _csvData.length && i <= 12; i++) {
        final row = _csvData[i];

        if (row.length > 1) {
          final value = double.tryParse(row[1]?.toString() ?? '');
          if (value != null) data.add(value);
        }
      }
    }

    if (data.isEmpty) {
      return List.generate(6, (index) => 10 + index * 5);
    }

    return data;
  }

  void _addBotMessage(String text) {
    _messages.add(ChatMessage.text(sender: MessageSender.bot, text: text));
    _safeSetState();
  }

  void _showError(String text) {
    _messages.add(
      ChatMessage.text(sender: MessageSender.bot, text: '⚠️ $text'),
    );
    _safeSetState();
  }

  void _addLineChart(String title) {
    _messages.add(
      ChatMessage.chart(
        title: title.length > 80 ? 'Line Chart' : title,
        data: _getChartData(),
        type: ChartType.line,
        color: const Color(0xFF22C55E),
      ),
    );
    _safeSetState();
  }

  void _addBarChart() {
    _messages.add(
      ChatMessage.chart(
        title: 'Bar Chart',
        data: _getChartData(),
        type: ChartType.bar,
        color: const Color(0xFF3B82F6),
      ),
    );
    _safeSetState();
  }

  void _addPieChart() {
    _messages.add(
      ChatMessage.chart(
        title: 'Pie Distribution',
        data: _getChartData(),
        type: ChartType.pie,
        color: const Color(0xFFA855F7),
      ),
    );
    _safeSetState();
  }

  void _safeSetState() {
    if (mounted) setState(() {});
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          if (_csvLoaded) _buildCsvStatusCard(),
          Expanded(child: _buildMessages()),
          _buildInputBar(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: _surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.insights_rounded,
              color: _accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DataBoard AI',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              Text(
                'CSV insights & smart charts',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Upload CSV',
          onPressed: _isLoading ? null : _pickCSV,
          icon: Icon(
            Icons.upload_file_rounded,
            color: _csvLoaded ? _accent : Colors.white70,
          ),
        ),
        if (_csvLoaded)
          IconButton(
            tooltip: 'Remove CSV',
            onPressed: _clearCSV,
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: Color(0xFFF87171),
            ),
          ),
        IconButton(
          tooltip: 'Sign out',
          onPressed: _signOut,
          icon: const Icon(Icons.logout_rounded, color: Colors.white70),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildCsvStatusCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.table_chart_rounded,
              color: _accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _csvFileName ?? 'CSV loaded',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_csvData.length - 1} data rows • ${_getHeaders().length} columns',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _accentSoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Active',
              style: TextStyle(
                color: _accent,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    if (_messages.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];

        if (message.isChart) {
          return _buildChartBubble(message);
        }

        return _buildTextBubble(message);
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _surfaceAlt,
                shape: BoxShape.circle,
                border: Border.all(color: _border),
              ),
              child: const Icon(
                Icons.query_stats_rounded,
                size: 46,
                color: _accent,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Ask questions about your CSV',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _csvLoaded
                  ? 'Try asking for insights or a chart.'
                  : 'Upload a CSV file to get started.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildSuggestionChip('Show line chart'),
                _buildSuggestionChip('Show bar chart'),
                _buildSuggestionChip('Show pie distribution'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionChip(String label) {
    return ActionChip(
      backgroundColor: _surfaceAlt,
      side: const BorderSide(color: _border),
      label: Text(
        label,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
      onPressed: () {
        _controller.text = label;
        _sendMessage();
      },
    );
  }

  Widget _buildTextBubble(ChatMessage message) {
    final isUser = message.sender == MessageSender.user;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: isUser ? _accentSoft : _surfaceAlt,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          border: Border.all(
            color: isUser ? _accent.withOpacity(0.25) : _border,
          ),
        ),
        child: SelectableText(
          message.text ?? '',
          style: TextStyle(
            color: isUser ? Colors.white : Colors.white.withOpacity(0.88),
            fontSize: 14.5,
            height: 1.45,
          ),
        ),
      ),
    );
  }

  Widget _buildChartBubble(ChatMessage message) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(maxWidth: 440),
        decoration: BoxDecoration(
          color: _surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (message.color ?? _accent).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getChartIcon(message.type!),
                    size: 18,
                    color: message.color ?? _accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message.title ?? 'Chart',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              height: 250,
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _bg.withOpacity(0.55),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border),
              ),
              child: _buildChart(message),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getChartIcon(ChartType type) {
    switch (type) {
      case ChartType.line:
        return Icons.show_chart_rounded;
      case ChartType.bar:
        return Icons.bar_chart_rounded;
      case ChartType.pie:
        return Icons.pie_chart_rounded;
    }
  }

  Widget _buildChart(ChatMessage message) {
    final data = message.data ?? [];
    final color = message.color ?? _accent;

    switch (message.type!) {
      case ChartType.line:
        return _buildLineChart(data, color);
      case ChartType.bar:
        return _buildBarChart(data, color);
      case ChartType.pie:
        return _buildPieChart(data);
    }
  }

  Widget _buildLineChart(List<double> values, Color color) {
    if (values.isEmpty) {
      return _buildNoData();
    }

    final maxY = values.reduce((a, b) => a > b ? a : b) * 1.2;

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 5,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.white.withOpacity(0.07),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: maxY / 5,
              reservedSize: 42,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(0),
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) => Text(
                'M${value.toInt() + 1}',
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: values
                .asMap()
                .entries
                .map((e) => FlSpot(e.key.toDouble(), e.value))
                .toList(),
            isCurved: true,
            color: color,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: color.withOpacity(0.16),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map(
                  (spot) => LineTooltipItem(
                    spot.y.toStringAsFixed(2),
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildBarChart(List<double> values, Color color) {
    if (values.isEmpty) {
      return _buildNoData();
    }

    final maxY = values.reduce((a, b) => a > b ? a : b) * 1.2;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 5,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.white.withOpacity(0.07),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: maxY / 5,
              reservedSize: 42,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(0),
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) => Text(
                'M${value.toInt() + 1}',
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                rod.toY.toStringAsFixed(2),
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              );
            },
          ),
        ),
        barGroups: values.asMap().entries.map((entry) {
          return BarChartGroupData(
            x: entry.key,
            barRods: [
              BarChartRodData(
                toY: entry.value,
                color: color,
                width: 18,
                borderRadius: BorderRadius.circular(6),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: maxY,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPieChart(List<double> values) {
    final positiveValues = values.where((value) => value > 0).toList();

    if (positiveValues.isEmpty) {
      return _buildNoData();
    }

    final total = positiveValues.fold<double>(0, (a, b) => a + b);

    final sections = positiveValues.asMap().entries.map((entry) {
      final percent = (entry.value / total) * 100;
      final color = Colors.primaries[entry.key % Colors.primaries.length];

      return PieChartSectionData(
        value: entry.value,
        color: color,
        radius: 58,
        title: '${percent.toStringAsFixed(1)}%',
        titleStyle: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      );
    }).toList();

    return PieChart(
      PieChartData(
        sections: sections,
        sectionsSpace: 3,
        centerSpaceRadius: 34,
        startDegreeOffset: -90,
        pieTouchData: PieTouchData(
          touchCallback: (event, response) {},
        ),
      ),
    );
  }

  Widget _buildNoData() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.white38,
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            'No valid numeric data found',
            style: TextStyle(color: Colors.white.withOpacity(0.55)),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                style: const TextStyle(color: Colors.white, fontSize: 14.5),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                decoration: InputDecoration(
                  hintText: _csvLoaded
                      ? 'Ask about your data...'
                      : 'Upload a CSV file first...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: _surfaceAlt,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: const BorderSide(color: _border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: const BorderSide(color: _accent),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _isLoading
                ? const SizedBox(
                    width: 44,
                    height: 44,
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        color: _accent,
                        strokeWidth: 2.5,
                      ),
                    ),
                  )
                : Material(
                    color: _accent,
                    borderRadius: BorderRadius.circular(28),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(28),
                      onTap: _sendMessage,
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(
                          Icons.arrow_upward_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}