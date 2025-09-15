import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:polar/polar.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:csv/csv.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Enhanced Polar Monitor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: PolarEnhancedMonitor(),
    );
  }
}

// HAPUS DataType.pvc
enum DataType { hr, rr, ecg, acc }

// Replace the existing SensorData and CsvHelper classes with these modified versions

class SensorData {
  final DataType type;
  final double value;
  final DateTime timestamp;
  final Map<String, dynamic> additionalData;

  SensorData({
    required this.type,
    required this.value,
    required this.timestamp,
    this.additionalData = const {},
  });
}

// New combined row data structure
class CombinedRowData {
  final DateTime timestamp;
  final String deviceId;
  double? hr;
  double? rr;
  double? rrms;
  double? accX;
  double? accY;
  double? accZ;
  double? ecg;

  CombinedRowData({
    required this.timestamp,
    required this.deviceId,
    this.hr,
    this.rr,
    this.rrms,
    this.accX,
    this.accY,
    this.accZ,
    this.ecg,
  });

  List<dynamic> toCsvRow() {
    final unixTimestamp = timestamp.millisecondsSinceEpoch ~/ 1000;
    String fmt(double? v) => v != null ? v.toStringAsFixed(2) : '';
    return [
      unixTimestamp,
      deviceId,
      fmt(hr),
      fmt(rr),
      fmt(rrms),
      fmt(accX),
      fmt(accY),
      fmt(accZ),
      fmt(ecg),
    ];
  }
}


class CsvHelper {
  static final CsvHelper _instance = CsvHelper._internal();
  factory CsvHelper() => _instance;
  CsvHelper._internal();

  String? _csvFolderPath;
  String? _csvFilePath;
  
  // Store current values for combining into one row per second
  CombinedRowData? _currentRow;
  Timer? _csvWriteTimer;
  String? _currentDeviceId;

  Future<String> get csvFolderPath async {
    if (_csvFolderPath != null) return _csvFolderPath!;
    final directory = await getApplicationDocumentsDirectory();
    _csvFolderPath = '${directory.path}/PolarData';
    final folder = Directory(_csvFolderPath!);
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return _csvFolderPath!;
  }

  Future<void> setCustomFolder() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      if (selectedDirectory != null) {
        _csvFolderPath = '$selectedDirectory/PolarData';
        final folder = Directory(_csvFolderPath!);
        if (!await folder.exists()) {
          await folder.create(recursive: true);
        }
        _csvFilePath = null;
      }
    } catch (e) {
      print('Error selecting directory: $e');
    }
  }

  Future<String> get csvFilePath async {
    if (_csvFilePath != null) return _csvFilePath!;
    final folderPath = await csvFolderPath;
    final now = DateTime.now();
    final dateString = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _csvFilePath = '$folderPath/polar_data_$dateString.csv';

    final file = File(_csvFilePath!);
    if (!await file.exists()) {
      await _createCsvWithHeaders();
    }
    return _csvFilePath!;
  }

  Future<void> _createCsvWithHeaders() async {
    final file = File(await csvFilePath);
    const headers = ['Timestamp', 'DeviceId', 'HR', 'RR', 'RRMS', 'ACC_X', 'ACC_Y', 'ACC_Z', 'ECG'];
    final csvData = const ListToCsvConverter().convert([headers]);
    await file.writeAsString(csvData);
  }

  // Start the 1-second CSV writing timer
  void startPeriodicWriting(String deviceId) {
    _currentDeviceId = deviceId;
    _csvWriteTimer?.cancel();
    _csvWriteTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      _writeCurrentRowToCSV();
    });
  }

  // Stop the CSV writing timer
  void stopPeriodicWriting() {
    _csvWriteTimer?.cancel();
    _csvWriteTimer = null;
    _currentRow = null;
  }

  // Modified method to update sensor data instead of immediately writing
  Future<void> appendSensorData(SensorData data) async {
    if (_currentDeviceId == null) return;
    
    // Initialize current row if needed
    if (_currentRow == null || 
        DateTime.now().difference(_currentRow!.timestamp).inSeconds >= 1) {
      _currentRow = CombinedRowData(
        timestamp: DateTime.now(),
        deviceId: _currentDeviceId!,
      );
    }

    // Update the current row with new sensor data
    switch (data.type) {
      case DataType.hr:
        _currentRow!.hr = data.value;
        break;
      case DataType.rr:
        _currentRow!.rr = data.value;
        // Calculate RRMS if we have RR data (simplified version)
        _updateRRMS(data.value);
        break;
      case DataType.ecg:
        _currentRow!.ecg = data.value;
        break;
      case DataType.acc:
        _currentRow!.accX = data.additionalData['x']?.toDouble();
        _currentRow!.accY = data.additionalData['y']?.toDouble();
        _currentRow!.accZ = data.additionalData['z']?.toDouble();
        break;
    }
  }

  List<double> _rrIntervals = [];
  
  void _updateRRMS(double rrValue) {
    _rrIntervals.add(rrValue);
    if (_rrIntervals.length > 30) {
      _rrIntervals.removeAt(0);
    }
    
    if (_rrIntervals.length >= 2) {
      List<double> differences = [];
      for (int i = 1; i < _rrIntervals.length; i++) {
        differences.add(_rrIntervals[i] - _rrIntervals[i - 1]);
      }
      
      if (differences.isNotEmpty) {
        double sumSquares = differences.map((d) => d * d).reduce((a, b) => a + b);
        double rrmsMeasure = sqrt(sumSquares / differences.length);
        _currentRow?.rrms = double.parse(rrmsMeasure.toStringAsFixed(2));
      }
    }
  }

  // Write current row to CSV (called every second by timer)
  Future<void> _writeCurrentRowToCSV() async {
    if (_currentRow == null) return;

    final file = File(await csvFilePath);

    final newRow = _currentRow!.toCsvRow();
    final csvConverter = const ListToCsvConverter();
    final newRowCsv = csvConverter.convert([newRow]);

    // Append langsung ke file, jangan rewrite semua
    await file.writeAsString(
      '\n$newRowCsv',
      mode: FileMode.append,
      flush: true,
    );

    // Reset untuk row berikutnya
    _currentRow = CombinedRowData(
      timestamp: DateTime.now(),
      deviceId: _currentDeviceId!,
    );
  }


  // Keep existing methods for backward compatibility but modify for new format
  Future<List<SensorData>> getAllSensorData({DataType? filterType, int? limit}) async {
    final file = File(await csvFilePath);
    if (!await file.exists()) {
      return [];
    }
    final csvContent = await file.readAsString();
    if (csvContent.trim().isEmpty) {
      return [];
    }
    
    final csvConverter = const CsvToListConverter();
    final rows = csvConverter.convert(csvContent);
    final dataRows = rows.skip(1).toList(); // Skip header
    
    List<SensorData> sensorDataList = [];
    
    // Convert combined rows back to individual SensorData for UI compatibility
    for (var row in dataRows) {
      try {
        final unixTimestamp = int.parse(row[0].toString());
        final timestamp = DateTime.fromMillisecondsSinceEpoch(unixTimestamp * 1000);
        
        // Extract HR data
        if (filterType == null || filterType == DataType.hr) {
          if (row[2].toString().isNotEmpty) {
            sensorDataList.add(SensorData(
              type: DataType.hr,
              value: double.parse(row[2].toString()),
              timestamp: timestamp,
            ));
          }
        }
        
        // Extract RR data
        if (filterType == null || filterType == DataType.rr) {
          if (row[3].toString().isNotEmpty) {
            sensorDataList.add(SensorData(
              type: DataType.rr,
              value: double.parse(row[3].toString()),
              timestamp: timestamp,
            ));
          }
        }
        
        // Extract ECG data
        if (filterType == null || filterType == DataType.ecg) {
          if (row[8].toString().isNotEmpty) {
            sensorDataList.add(SensorData(
              type: DataType.ecg,
              value: double.parse(row[8].toString()),
              timestamp: timestamp,
            ));
          }
        }
        
        // Extract ACC data
        if (filterType == null || filterType == DataType.acc) {
          if (row[5].toString().isNotEmpty && row[6].toString().isNotEmpty && row[7].toString().isNotEmpty) {
            final x = double.parse(row[5].toString());
            final y = double.parse(row[6].toString());
            final z = double.parse(row[7].toString());
            final magnitude = sqrt(x * x + y * y + z * z);
            
            sensorDataList.add(SensorData(
              type: DataType.acc,
              value: magnitude,
              timestamp: timestamp,
              additionalData: {'x': x, 'y': y, 'z': z},
            ));
          }
        }
      } catch (e) {
        print('Error parsing row: $row, Error: $e');
      }
    }
    
    // Filter by type if specified
    if (filterType != null) {
      sensorDataList = sensorDataList.where((data) => data.type == filterType).toList();
    }
    
    // Sort and limit
    sensorDataList.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (limit != null) {
      sensorDataList = sensorDataList.take(limit).toList();
    }
    
    return sensorDataList;
  }

  Future<void> clearAllData() async {
    final file = File(await csvFilePath);
    if (await file.exists()) {
      await file.delete();
    }
    await _createCsvWithHeaders();
    _currentRow = null;
    _rrIntervals.clear();
  }

  Future<File> getCsvFile() async {
    return File(await csvFilePath);
  }

  Future<String> getDataCount() async {
    final file = File(await csvFilePath);
    if (!await file.exists()) return '0';
    
    final csvContent = await file.readAsString();
    if (csvContent.trim().isEmpty) return '0';
    
    final csvConverter = const CsvToListConverter();
    final rows = csvConverter.convert(csvContent);
    return (rows.length - 1).toString(); // Subtract header row
  }

  String get currentFolderPath => _csvFolderPath ?? 'Not set';
}

class PolarEnhancedMonitor extends StatefulWidget {
  @override
  _PolarEnhancedMonitorState createState() => _PolarEnhancedMonitorState();
}

class _PolarEnhancedMonitorState extends State<PolarEnhancedMonitor> with TickerProviderStateMixin {
  final Polar polar = Polar();
  String? connectedDeviceId;
  Map<DataType, double> currentValues = {
    DataType.hr: 0,
    DataType.rr: 0,
    DataType.ecg: 0,
    DataType.acc: 0,
  };
  bool isConnected = false;
  bool isConnecting = false;
  Map<DataType, bool> isStreaming = {
    DataType.hr: false,
    DataType.rr: false,
    DataType.ecg: false,
    DataType.acc: false,
  };
  List<String> discoveredDevices = [];
  Map<DataType, List<SensorData>> sensorHistory = {
    DataType.hr: [],
    DataType.rr: [],
    DataType.ecg: [],
    DataType.acc: [],
  };
  String totalDataCount = '0';

  // Stream subscriptions
  StreamSubscription<PolarHrData>? hrStreamSubscription;
  StreamSubscription<PolarEcgData>? ecgStreamSubscription;
  StreamSubscription<PolarAccData>? accStreamSubscription;
  StreamSubscription<dynamic>? deviceConnectedSubscription;
  StreamSubscription<dynamic>? deviceDisconnectedSubscription;
  StreamSubscription<dynamic>? sdkFeatureReadySubscription;
  StreamSubscription<PolarDeviceInfo>? searchSubscription;

  final CsvHelper _csvHelper = CsvHelper();
  final TextEditingController _deviceIdController = TextEditingController();

  // Tab controller
  late TabController _tabController;

  // Chart data
  Map<DataType, List<FlSpot>> chartData = {
    DataType.hr: [],
    DataType.rr: [],
    DataType.ecg: [],
    DataType.acc: [],
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this); // HAPUS 1 tab (PVC)
    _requestPermissions();
    _loadSensorHistory();
    _initializePolarSDK();
  }

  @override
  void dispose() {
    _stopAllStreams();
    _disconnectDevice();
    _tabController.dispose();
    super.dispose();
  }

  void _initializePolarSDK() {
    deviceConnectedSubscription = polar.deviceConnected.listen((event) {
      debugPrint('Device connected: ${event.deviceId}');
      setState(() {
        connectedDeviceId = event.deviceId;
        isConnected = true;
        isConnecting = false;
      });
        _csvHelper.startPeriodicWriting(event.deviceId);
    });

    deviceDisconnectedSubscription = polar.deviceDisconnected.listen((event) {
      setState(() {
        connectedDeviceId = null;
        isConnected = false;
        isConnecting = false;
        isStreaming.updateAll((key, value) => false);
        currentValues.updateAll((key, value) => 0);
      });
        _csvHelper.stopPeriodicWriting();
    });

    sdkFeatureReadySubscription = polar.sdkFeatureReady.listen((event) {
      debugPrint('SDK feature ready: ${event.feature} for device ${event.identifier}');
      if (event.feature == PolarSdkFeature.onlineStreaming) {
        Future.delayed(Duration(seconds: 1), () {
          _startAllStreaming();
        });
      }
    });
  }

  Future<void> _requestPermissions() async {
    await Permission.bluetoothConnect.request();
    await Permission.bluetoothScan.request();
    await Permission.location.request();
    await Permission.storage.request();
  }

  Future<void> _loadSensorHistory() async {
    for (DataType type in DataType.values) {
      final data = await _csvHelper.getAllSensorData(filterType: type, limit: 100);
      setState(() {
        sensorHistory[type] = data;
        chartData[type] = _convertToFlSpots(data);
      });
    }
    final count = await _csvHelper.getDataCount();
    setState(() {
      totalDataCount = count;
    });
  }

  List<FlSpot> _convertToFlSpots(List<SensorData> data) {
    if (data.isEmpty) return [];
    final sortedData = data.reversed.toList();
    return sortedData.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.value);
    }).toList();
  }

  Future<void> _searchForDevices() async {
    setState(() {
      discoveredDevices.clear();
    });
    try {
      searchSubscription = polar.searchForDevice().listen((event) {
        debugPrint('Found device: ${event.deviceId} - ${event.name}');
        if (!discoveredDevices.contains(event.deviceId)) {
          setState(() {
            discoveredDevices.add(event.deviceId);
          });
        }
      });
      Timer(Duration(seconds: 10), () {
        searchSubscription?.cancel();
      });
    } catch (e) {
      debugPrint('Error searching for devices: $e');
      _showSnackBar('Error searching for devices: $e');
    }
  }

  Future<void> _connectToDevice(String deviceId) async {
    setState(() {
      isConnecting = true;
    });
    try {
      await polar.connectToDevice(deviceId);
      debugPrint('Attempting to connect to: $deviceId');
    } catch (e) {
      debugPrint('Error connecting to device: $e');
      setState(() {
        isConnecting = false;
      });
      _showSnackBar('Error connecting to device: $e');
    }
  }

  Future<void> _connectWithCustomId() async {
    final deviceId = _deviceIdController.text.trim();
    if (deviceId.isNotEmpty) {
      await _connectToDevice(deviceId);
    } else {
      _showSnackBar('Please enter a valid device ID');
    }
  }

  // PERBAIKAN 3: HAPUS parameter settings dari startEcgStreaming dan startAccStreaming
  Future<void> _startAllStreaming() async {
    if (connectedDeviceId == null) return;
    try {
      final availableTypes = await polar.getAvailableOnlineStreamDataTypes(connectedDeviceId!);
      debugPrint('Available data types: $availableTypes');

      if (availableTypes.contains(PolarDataType.hr)) {
        await _startHeartRateStreaming();
        await Future.delayed(Duration(milliseconds: 500));
      }

      // PERBAIKAN 3: HAPUS requestStreamSettings dan parameter settings
      if (availableTypes.contains(PolarDataType.ecg)) {
        await _startEcgStreaming(); // Ganti ke versi tanpa settings
        await Future.delayed(Duration(milliseconds: 500));
      }

      // PERBAIKAN 3: HAPUS requestStreamSettings dan parameter settings
      if (availableTypes.contains(PolarDataType.acc)) {
        await _startAccStreaming(); // Ganti ke versi tanpa settings
      }
    } catch (e) {
      debugPrint('Error starting streaming: $e');
      _showSnackBar('Error starting streaming: $e');
    }
  }

  Future<void> _startHeartRateStreaming() async {
    if (connectedDeviceId == null) return;
    try {
      hrStreamSubscription = polar.startHrStreaming(connectedDeviceId!).listen(
        (hrData) {
          if (hrData.samples.isNotEmpty) {
            final heartRate = hrData.samples.first.hr.toDouble();
            final rrList = hrData.samples.first.rrsMs;
            final rrInterval = rrList.isNotEmpty
                ? rrList.first.toDouble()
                : 0.0;
            setState(() {
              currentValues[DataType.hr] = heartRate;
              currentValues[DataType.rr] = rrInterval;
              isStreaming[DataType.hr] = true;
              isStreaming[DataType.rr] = rrInterval > 0;
            });
            _saveSensorData(DataType.hr, heartRate);
            if (rrInterval > 0) {
              _saveSensorData(DataType.rr, rrInterval);
            }
          }
        },
        onError: (error) {
          debugPrint('HR streaming error: $error');
          setState(() {
            isStreaming[DataType.hr] = false;
            isStreaming[DataType.rr] = false;
          });
        },
      );
    } catch (e) {
      debugPrint('Error starting HR streaming: $e');
    }
  }

  // PERBAIKAN 3: HAPUS fungsi dengan settings, ganti dengan versi dasar
  Future<void> _startEcgStreaming() async {
    if (connectedDeviceId == null) return;
    try {
      debugPrint('Starting ECG streaming...');
      ecgStreamSubscription = polar.startEcgStreaming(
        connectedDeviceId!, // Hanya ID device, TIDAK ADA settings
      ).listen(
        (ecgData) {
          if (ecgData.samples.isNotEmpty) {
            final ecgValue = ecgData.samples.last.voltage.toDouble();
            debugPrint('ECG value: $ecgValue');
            setState(() {
              currentValues[DataType.ecg] = ecgValue;
              isStreaming[DataType.ecg] = true;
            });
            _saveSensorData(DataType.ecg, ecgValue);
          }
        },
        onError: (error) {
          debugPrint('ECG streaming error: $error');
          setState(() {
            isStreaming[DataType.ecg] = false;
          });
        },
      );
      debugPrint('ECG streaming started successfully');
    } catch (e) {
      debugPrint('Error starting ECG streaming: $e');
      _showSnackBar('ECG streaming failed: $e');
    }
  }

  // PERBAIKAN 3: HAPUS fungsi dengan settings, ganti dengan versi dasar
  Future<void> _startAccStreaming() async {
    if (connectedDeviceId == null) return;
    try {
      debugPrint('Starting ACC streaming...');
      accStreamSubscription = polar.startAccStreaming(
        connectedDeviceId!, // Hanya ID device, TIDAK ADA settings
      ).listen(
        (accData) {
          if (accData.samples.isNotEmpty) {
            final sample = accData.samples.last;
            final magnitude = sqrt(
              pow(sample.x, 2) + pow(sample.y, 2) + pow(sample.z, 2)
            );
            debugPrint('ACC values - X: ${sample.x}, Y: ${sample.y}, Z: ${sample.z}, Mag: $magnitude');
            setState(() {
              currentValues[DataType.acc] = magnitude;
              isStreaming[DataType.acc] = true;
            });
            _saveSensorData(DataType.acc, magnitude, additionalData: {
              'x': sample.x.toDouble(),
              'y': sample.y.toDouble(),
              'z': sample.z.toDouble(),
            });
          }
        },
        onError: (error) {
          debugPrint('ACC streaming error: $error');
          setState(() {
            isStreaming[DataType.acc] = false;
          });
        },
      );
      debugPrint('ACC streaming started successfully');
    } catch (e) {
      debugPrint('Error starting ACC streaming: $e');
      _showSnackBar('ACC streaming failed: $e');
    }
  }

  Future<void> _saveSensorData(DataType type, double value, {Map<String, dynamic>? additionalData}) async {
    final data = SensorData(
      type: type,
      value: value,
      timestamp: DateTime.now(),
      additionalData: additionalData ?? {},
    );
    await _csvHelper.appendSensorData(data);

    setState(() {
      sensorHistory[type]!.insert(0, data);
      if (sensorHistory[type]!.length > 100) {
        sensorHistory[type]!.removeAt(sensorHistory[type]!.length - 1);
      }
      chartData[type] = _convertToFlSpots(sensorHistory[type]!);
    });
  }

  void _stopAllStreams() {
    hrStreamSubscription?.cancel();
    ecgStreamSubscription?.cancel();
    accStreamSubscription?.cancel();
    searchSubscription?.cancel();
    setState(() {
      isStreaming.updateAll((key, value) => false);
    });
  }

  Future<void> _disconnectDevice() async {
    if (connectedDeviceId != null) {
      try {
        _stopAllStreams();
        await polar.disconnectFromDevice(connectedDeviceId!);
        setState(() {
          connectedDeviceId = null;
          isConnected = false;
          isConnecting = false;
          isStreaming.updateAll((key, value) => false);
          currentValues.updateAll((key, value) => 0);
        });
      } catch (e) {
        debugPrint('Error disconnecting: $e');
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildConnectionTab() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isConnected) ...[
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _searchForDevices,
                      icon: Icon(Icons.bluetooth_searching),
                      label: Text('Search for Polar Devices'),
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _deviceIdController,
                            decoration: InputDecoration(
                              labelText: 'Device ID (e.g., 1C709B20)',
                              border: OutlineInputBorder(),
                              hintText: 'Enter Polar device ID',
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: isConnecting ? null : _connectWithCustomId,
                          child: Text('Connect'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            if (discoveredDevices.isNotEmpty)
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: Text('Discovered Devices'),
                      leading: Icon(Icons.devices),
                    ),
                    ...discoveredDevices.map((deviceId) => ListTile(
                      title: Text('Polar Device'),
                      subtitle: Text('ID: $deviceId'),
                      trailing: ElevatedButton(
                        onPressed: isConnecting ? null : () => _connectToDevice(deviceId),
                        child: Text('Connect'),
                      ),
                    )),
                  ],
                ),
              ),
            if (isConnecting) ...[
              SizedBox(height: 16),
              Center(child: CircularProgressIndicator()),
              Text('Connecting...', textAlign: TextAlign.center),
            ],
          ] else ...[
            Card(
              color: Colors.green.shade50,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.bluetooth_connected, color: Colors.green, size: 40),
                    SizedBox(height: 8),
                    Text(
                      'Connected to: $connectedDeviceId',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildStreamingChip(DataType.hr, 'Heart Rate', Icons.favorite),
                        _buildStreamingChip(DataType.rr, 'RR Interval', Icons.timeline),
                        _buildStreamingChip(DataType.ecg, 'ECG', Icons.monitor_heart),
                        _buildStreamingChip(DataType.acc, 'Accelerometer', Icons.vibration),
                      ],
                    ),
                    SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () async {
                            await _csvHelper.setCustomFolder();
                            _showSnackBar('Folder updated: ${_csvHelper.currentFolderPath}');
                          },
                          icon: Icon(Icons.folder_open),
                          label: Text('Set Folder'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                        ),
                        ElevatedButton.icon(
                          onPressed: _disconnectDevice,
                          icon: Icon(Icons.bluetooth_disabled),
                          label: Text('Disconnect'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'Data Storage',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('Folder: ${_csvHelper.currentFolderPath}'),
                    Text('Total Records: $totalDataCount'),
                    SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () async {
                            await _csvHelper.clearAllData();
                            await _loadSensorHistory();
                            _showSnackBar('All data cleared');
                          },
                          icon: Icon(Icons.clear_all),
                          label: Text('Clear Data'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                        ),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final file = await _csvHelper.getCsvFile();
                            _showSnackBar('CSV: ${file.path}');
                          },
                          icon: Icon(Icons.file_present),
                          label: Text('Show CSV'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStreamingChip(DataType type, String label, IconData icon) {
    final streaming = isStreaming[type] ?? false;
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      backgroundColor: streaming ? Colors.green.shade100 : Colors.grey.shade200,
      side: BorderSide(
        color: streaming ? Colors.green : Colors.grey,
        width: 1,
      ),
    );
  }

  Widget _buildDataTab(DataType type) {
    final data = sensorHistory[type] ?? [];
    final currentValue = currentValues[type] ?? 0;
    final streaming = isStreaming[type] ?? false;
    String unit = '';
    String title = '';
    IconData icon = Icons.show_chart;
    Color color = Colors.blue;
    switch (type) {
      case DataType.hr:
        unit = 'BPM';
        title = 'Heart Rate';
        icon = Icons.favorite;
        color = Colors.red;
        break;
      case DataType.rr:
        unit = 'ms';
        title = 'RR Interval';
        icon = Icons.timeline;
        color = Colors.orange;
        break;
      case DataType.ecg:
        unit = 'µV';
        title = 'ECG';
        icon = Icons.monitor_heart;
        color = Colors.purple;
        break;
      case DataType.acc:
        unit = 'mg';
        title = 'Accelerometer';
        icon = Icons.vibration;
        color = Colors.green;
        break;
    }

    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            color: streaming ? color.withOpacity(0.1) : Colors.grey.shade100,
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(icon, color: streaming ? color : Colors.grey, size: 40),
                  SizedBox(height: 10),
                  Text(
                    currentValue.toStringAsFixed(type == DataType.hr ? 0 : 2),
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: streaming ? color : Colors.grey,
                    ),
                  ),
                  Text(
                    unit,
                    style: TextStyle(
                      fontSize: 16,
                      color: streaming ? color.withOpacity(0.8) : Colors.grey,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    streaming ? 'Streaming Active' : 'Not Streaming',
                    style: TextStyle(
                      fontSize: 12,
                      color: streaming ? Colors.green : Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),
          Expanded(
            flex: 2,
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$title Chart',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 16),
                    Expanded(
                      child: chartData[type]!.isNotEmpty
                          ? LineChart(
                              LineChartData(
                                gridData: FlGridData(show: true),
                                titlesData: FlTitlesData(show: false),
                                borderData: FlBorderData(show: true),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: chartData[type]!,
                                    isCurved: true,
                                    color: color,
                                    barWidth: 2,
                                    isStrokeCapRound: true,
                                    dotData: FlDotData(show: false),
                                    belowBarData: BarAreaData(
                                      show: true,
                                      color: color.withOpacity(0.1),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Center(
                              child: Text(
                                'No data available',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Recent History (${data.length} records)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: data.isNotEmpty
                        ? ListView.builder(
                            itemCount: data.length > 20 ? 20 : data.length,
                            itemBuilder: (context, index) {
                              final item = data[index];
                              return ListTile(
                                dense: true,
                                leading: Icon(icon, color: color, size: 20),
                                title: Text('${item.value.toStringAsFixed(type == DataType.hr ? 0 : 2)} $unit'),
                                subtitle: Text(
                                  '${item.timestamp.toString().substring(0, 19)}',
                                  style: TextStyle(fontSize: 12),
                                ),
                                trailing: type == DataType.acc && item.additionalData.isNotEmpty
                                    ? Text(
                                      'X:${item.additionalData['x']?.toStringAsFixed(1)}\n'
                                      'Y:${item.additionalData['y']?.toStringAsFixed(1)}\n'
                                      'Z:${item.additionalData['z']?.toStringAsFixed(1)}',
                                      style: TextStyle(fontSize: 10),
                                      )
                                    : null,
                              );
                            },
                          )
                        : Center(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: Text(
                                'No history data',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            flex: 2,
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: DataType.values.length,
              itemBuilder: (context, index) {
                final type = DataType.values[index];
                final value = currentValues[type] ?? 0;
                final streaming = isStreaming[type] ?? false;
                String unit = '';
                String title = '';
                IconData icon = Icons.show_chart;
                Color color = Colors.blue;
                switch (type) {
                  case DataType.hr:
                    unit = 'BPM';
                    title = 'Heart Rate';
                    icon = Icons.favorite;
                    color = Colors.red;
                    break;
                  case DataType.rr:
                    unit = 'ms';
                    title = 'RR Interval';
                    icon = Icons.timeline;
                    color = Colors.orange;
                    break;
                  case DataType.ecg:
                    unit = 'µV';
                    title = 'ECG';
                    icon = Icons.monitor_heart;
                    color = Colors.purple;
                    break;
                  case DataType.acc:
                    unit = 'mg';
                    title = 'Accelerometer';
                    icon = Icons.vibration;
                    color = Colors.green;
                    break;
                }
                return Card(
                  color: streaming ? color.withOpacity(0.1) : Colors.grey.shade100,
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icon,
                          color: streaming ? color : Colors.grey,
                          size: 24,
                        ),
                        SizedBox(height: 8),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 4),
                        Text(
                          value.toStringAsFixed(type == DataType.hr ? 0 : 2),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: streaming ? color : Colors.grey,
                          ),
                        ),
                        Text(
                          unit,
                          style: TextStyle(
                            fontSize: 10,
                            color: streaming ? color.withOpacity(0.8) : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            flex: 3,
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Combined Data Chart',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 16),
                    Expanded(
                      child: _buildCombinedChart(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Statistics',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Text('Total Records'),
                          Text(
                            totalDataCount,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          Text('Active Streams'),
                          Text(
                            '${isStreaming.values.where((v) => v).length}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          Text('Connection'),
                          Icon(
                            isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                            color: isConnected ? Colors.green : Colors.red,
                            size: 24,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCombinedChart() {
    List<Color> colors = [Colors.red, Colors.orange, Colors.purple, Colors.green];
    List<LineChartBarData> series = [];
    for (int i = 0; i < DataType.values.length; i++) {
      final type = DataType.values[i];
      final data = chartData[type] ?? [];
      if (data.isNotEmpty && data.length > 1) {
        series.add(
          LineChartBarData(
            spots: data,
            isCurved: true,
            color: colors[i],
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ),
        );
      }
    }
    if (series.isEmpty) {
      return Center(
        child: Text(
          'No data available for chart',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }
    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true),
        titlesData: FlTitlesData(show: false),
        borderData: FlBorderData(show: true),
        lineBarsData: series,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Enhanced Polar Monitor'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(icon: Icon(Icons.bluetooth), text: 'Connection'),
            Tab(icon: Icon(Icons.dashboard), text: 'Overview'),
            Tab(icon: Icon(Icons.favorite), text: 'Heart Rate'),
            Tab(icon: Icon(Icons.timeline), text: 'RR Interval'),
            Tab(icon: Icon(Icons.monitor_heart), text: 'ECG'),
            Tab(icon: Icon(Icons.vibration), text: 'Accelerometer'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildConnectionTab(),
          _buildOverviewTab(),
          _buildDataTab(DataType.hr),
          _buildDataTab(DataType.rr),
          _buildDataTab(DataType.ecg),
          _buildDataTab(DataType.acc),
        ],
      ),
    );
  }
}