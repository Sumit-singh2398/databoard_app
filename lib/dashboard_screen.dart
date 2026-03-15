import 'dart:io';
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_gemini/flutter_gemini.dart';
import 'login_page.dart';
import 'package:file_picker/file_picker.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  File? _csvFile;
  List<List<dynamic>> _csvData = [];
  bool _csvLoaded = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    Gemini.init(apiKey: 'AIzaSyBwjh17RYvHg0AXpfWpYEChGFrDokPe9as');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // CSV Upload
  Future<void> _pickCSV() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result != null) {
      _csvFile = File(result.files.single.path!);
      await _loadCSV();
      setState(() => _csvLoaded = true);
      _addMessage('✅ CSV loaded! ${_csvData.length} rows', 'bot');
    }
  }

  // CSV Delete
  void _clearCSV() {
    setState(() {
      _csvFile = null;
      _csvData.clear();
      _csvLoaded = false;
    });
    _addMessage(' CSV cleared! Ready for new file.', 'bot');
  }

  Future<void> _loadCSV() async {
    try {
      String csvText = await _csvFile!.readAsString();
      _csvData = const CsvToListConverter().convert(csvText);
    } catch (e) {
      _addMessage('CSV Error: $e', 'bot');
    }
  }

  void _sendMessage() async {
    String text = _controller.text.trim();
    if (text.isEmpty) return;

    _addMessage(text, 'user');
    _controller.clear();
    setState(() => _isLoading = true);

    await _processWithGemini(text);
    setState(() => _isLoading = false);
  }

  Future<void> _processWithGemini(String query) async {
    try {
      String csvContext = _csvLoaded
          ? 'CSV Data: ${_csvData.length} rows. Columns: ${_getHeaders().join(', ')}'
          : 'No CSV loaded';
      String fullQuery = '$csvContext\n\nUser Question: $query';
      final response = await Gemini.instance.text(fullQuery);
      String aiResponse = response?.output ?? 'No response from AI';

      if (query.toLowerCase().contains('pie')) {
        _addPieChart();
      } else if (query.toLowerCase().contains('bar')) {
        _addBarChart();
      } else if (query.toLowerCase().contains('line') ||
                 query.toLowerCase().contains('chart') ||
                 query.toLowerCase().contains('graph') ||
                 query.toLowerCase().contains('show')) {
        _addLineChart(aiResponse);
      } else {
        _addMessage(aiResponse, 'bot');
      }
    } catch (e) {
      _addMessage('AI Error: $e\nTry: "show chart", "pie chart", "bar graph"', 'bot');
    }
  }

  List<String> _getHeaders() {
    if (_csvData.isEmpty) return [];
    return _csvData[0].map((e) => e.toString()).toList();
  }

  List<double> _getChartData() {
    List<double> data = [];
    if (_csvData.length > 1) {
      for (int i = 1; i < _csvData.length && i <= 12; i++) {
        try {
          if (_csvData[i].length > 1) {
            double value = double.tryParse(_csvData[i][1]?.toString() ?? '0') ?? 1000.0;
            data.add(value);
          }
        } catch (e) {
          data.add(1000.0);
        }
      }
    }
    while (data.length < 8) {
      data.add(data.isEmpty ? 1000.0 : data.last * 0.9);
    }
    return data;
  }

  void _addMessage(String text, String sender) {
    setState(() {
      _messages.add({'text': text, 'sender': sender});
    });
  }

  void _addLineChart(String title) {
    List<double> data = _getChartData();
    _addChartMessage(title, data, ChartType.line, Colors.green);
  }

  void _addBarChart() {
    List<double> data = _getChartData();
    _addChartMessage('Bar Chart - Monthly Data', data, ChartType.bar, Colors.blue);
  }

  void _addPieChart() {
    List<double> data = _getChartData();
    _addChartMessage('Pie Chart - Data Distribution', data, ChartType.pie, Colors.purple);
  }

  void _addChartMessage(String title, List<double> data, ChartType type, Color color) {
    setState(() {
      _messages.add({
        'type': type.toString(),
        'title': title,
        'data': data,
        'color': color,
      });
    });
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('DataBoard AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: Icon(Icons.upload_file, color: _csvLoaded ? Colors.green : Colors.white70, size: 28),
                onPressed: _pickCSV,
              ),
              if (_csvLoaded)
                Positioned(
                  right: 12,
                  top: 12,
                  child: Container(width: 12, height: 12, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                ),
            ],
          ),
          if (_csvLoaded) IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 28), onPressed: _clearCSV),
          IconButton(icon: const Icon(Icons.logout, color: Colors.red, size: 28), onPressed: _signOut),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.analytics_outlined, size: 80, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(_csvLoaded ? 'Ask AI about your data...' : 'Upload CSV first', style: TextStyle(color: Colors.grey[400], fontSize: 18)),
                        const SizedBox(height: 8),
                        Text('Try: "show chart", "pie chart", "bar graph"', style: TextStyle(color: Colors.grey[500])),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      var msg = _messages[index];
                      bool isUser = msg['sender'] == 'user';
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isUser ? Colors.green.withOpacity(0.2) : const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: msg['type'] == null
                              ? Text(msg['text'], style: const TextStyle(color: Colors.white, fontSize: 15))
                              : _buildChartWidget(msg),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(color: Color(0xFF1E293B), border: Border(top: BorderSide(color: Colors.grey))),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: _csvLoaded ? 'Ask AI: "show chart", "pie distribution"...' : 'Upload CSV first...',
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                      filled: true,
                      fillColor: const Color(0xFF334155),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 12),
                _isLoading
                    ? const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(color: Colors.green))
                    : Container(
                        decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(25)),
                        child: IconButton(icon: const Icon(Icons.send, color: Colors.white), onPressed: _sendMessage),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartWidget(Map<String, dynamic> msg) {
    ChartType type = ChartType.line;
    if (msg['type'].toString().contains('pie')) type = ChartType.pie;
    else if (msg['type'].toString().contains('bar')) type = ChartType.bar;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(msg['title'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        Container(
          height: 250,
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
          child: type == ChartType.pie
              ? _buildPieChart(msg['data'], msg['color'])
              : type == ChartType.bar
                  ? _buildBarChart(msg['data'], msg['color'])
                  : _buildLineChart(msg['data'], msg['color']),
        ),
      ],
    );
  }

  Widget _buildBarChart(List<dynamic> data, Color color) {
    List<double> values = data.map((e) => (e as num).toDouble()).toList();
    double maxY = (values.reduce((a, b) => a > b ? a : b)) * 1.2;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(rod.toY.toStringAsFixed(2), const TextStyle(color: Colors.white));
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: maxY / 5,
              getTitlesWidget: (value, meta) => Text(value.toStringAsFixed(0), style: const TextStyle(color: Colors.white, fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) => Text('M${value.toInt() + 1}', style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
        ),
        gridData: FlGridData(show: true, drawHorizontalLine: true),
        borderData: FlBorderData(show: false),
        barGroups: values.asMap().entries.map((e) {
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: e.value,
                color: color,
                width: 20,
                borderRadius: BorderRadius.circular(6),
                backDrawRodData: BackgroundBarChartRodData(show: true, toY: maxY, color: Colors.white.withOpacity(0.05)),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLineChart(List<dynamic> data, Color color) {
    List<double> values = data.map((e) => (e as num).toDouble()).toList();
    double maxY = (values.reduce((a, b) => a > b ? a : b)) * 1.2;

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: values.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
            isCurved: true,
            color: color,
            barWidth: 3,
            dotData: FlDotData(show: true),
            belowBarData: BarAreaData(show: true, color: color.withOpacity(0.2)),
          ),
        ],
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: maxY / 5,
              getTitlesWidget: (value, meta) => Text(value.toStringAsFixed(0), style: const TextStyle(color: Colors.white, fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) => Text('M${value.toInt() + 1}', style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
        ),
        gridData: FlGridData(show: true),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  Widget _buildPieChart(List<dynamic> data, Color baseColor) {
    List<double> values = data.map((e) => (e as num).toDouble()).toList();
    double total = values.fold(0, (a, b) => a + b);

    List<PieChartSectionData> sections = values.asMap().entries.map((e) {
      double percent = (e.value / total) * 100;
      Color color = Colors.primaries[e.key % Colors.primaries.length];
      return PieChartSectionData(
        value: e.value,
        color: color,
        radius: 60,
        title: '${percent.toStringAsFixed(1)}%',
        titleStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      );
    }).toList();

    return PieChart(PieChartData(
      sections: sections,
      sectionsSpace: 2,
      centerSpaceRadius: 30,
      startDegreeOffset: -90,
    ));
  }
}

enum ChartType { line, bar, pie }