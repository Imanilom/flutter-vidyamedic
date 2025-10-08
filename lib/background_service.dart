import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:polar/polar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;

enum DataType { hr, rr, ecg, acc }

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

class CombinedRowData {
  final DateTime timestamp;
  final String deviceId;
  final String? activity;
  
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
    this.activity,
    this.hr,
    this.rr,
    this.rrms,
    this.accX,
    this.accY,
    this.accZ,
    this.ecg,
  });

  List<String> toCsvRow() {
    final now = DateTime.now();
    String fmt(double? v) => v != null ? v.toStringAsFixed(2) : '';
    String fmtAcc(double? v) => v != null ? v.toStringAsFixed(6) : '';
    
    return [
      (timestamp.millisecondsSinceEpoch ~/ 1000).toString(), // timestamp (Unix)
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}', // date_created
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}', // time_created
      fmt(hr), // hr
      fmt(rr), // rr
      fmt(rrms) ?? '0.0', // rrms
      fmtAcc(accX), // acc_x
      fmtAcc(accY), // acc_y
      fmtAcc(accZ), // acc_z
      fmt(ecg), // ecg
      deviceId, // device_id
      activity ?? 'Rest', // activity
    ];
  }

  Map<String, dynamic> toJson() {
    final now = DateTime.now();
    return {
      'timestamp': timestamp.millisecondsSinceEpoch ~/ 1000,
      'date_created': '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      'time_created': '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
      'hr': hr,
      'rr': rr,
      'rrms': rrms ?? 0.0,
      'acc_x': accX,
      'acc_y': accY,
      'acc_z': accZ,
      'ecg': ecg,
      'device_id': deviceId,
      'activity': activity ?? 'Rest',
    };
  }
}

class BackgroundCsvHelper {
  static final BackgroundCsvHelper _instance = BackgroundCsvHelper._internal();
  factory BackgroundCsvHelper() => _instance;
  BackgroundCsvHelper._internal();

  String? _csvFolderPath;
  String? _csvFilePath;
  
  CombinedRowData? _currentRow;
  Timer? _csvWriteTimer;
  Timer? _uploadTimer;
  String? _currentDeviceId;
  String? _currentActivity;

  List<double> _rrIntervals = [];
  final List<Map<String, dynamic>> _pendingUploads = [];
  static const String _uploadUrl = 'https://smart-device.lskk.co.id/api/log/logs';
  bool _isUploading = false;

  Future<SharedPreferences> _getPrefs() async {
    return await SharedPreferences.getInstance();
  }

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
    // HEADER SESUAI DENGAN STRUKTUR BARU
    const headers = [
      'timestamp', 
      'date_created', 
      'time_created', 
      'hr', 
      'rr', 
      'rrms', 
      'acc_x', 
      'acc_y', 
      'acc_z', 
      'ecg', 
      'device_id', 
      'activity'
    ];
    final csvData = const ListToCsvConverter().convert([headers]);
    await file.writeAsString(csvData);
    print('Created CSV with headers: $headers');
  }

  void startPeriodicWriting(String deviceId, String? activity) {
    _currentDeviceId = deviceId;
    _currentActivity = activity ?? 'Rest';
    _csvWriteTimer?.cancel();
    _uploadTimer?.cancel();
    
    _csvWriteTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      _writeCurrentRowToCSV();
    });

    // Upload data setiap 60 detik
    _uploadTimer = Timer.periodic(Duration(seconds: 60), (timer) async {
      await _uploadPendingData();
    });

    print('Started periodic writing for device: $deviceId, activity: $_currentActivity');
  }

  void stopPeriodicWriting() {
    _csvWriteTimer?.cancel();
    _uploadTimer?.cancel();
    _csvWriteTimer = null;
    _uploadTimer = null;
    _currentRow = null;
    print('Stopped periodic writing');
  }

  Future<void> appendSensorData(SensorData data) async {
    if (_currentDeviceId == null) return;
    
    final now = DateTime.now();
    if (_currentRow == null || 
        now.difference(_currentRow!.timestamp).inSeconds >= 1) {
      _currentRow = CombinedRowData(
        timestamp: now,
        deviceId: _currentDeviceId!,
        activity: _currentActivity,
      );
    }

    switch (data.type) {
      case DataType.hr:
        _currentRow!.hr = data.value;
        break;
      case DataType.rr:
        _currentRow!.rr = data.value;
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

  void _updateRRMS(double rrValue) {
    if (rrValue > 0 && rrValue < 2000) {
      _rrIntervals.add(rrValue);
      
      if (_rrIntervals.length > 30) {
        _rrIntervals.removeAt(0);
      }
      
      if (_rrIntervals.length >= 2) {
        double sumSquaredDifferences = 0;
        int validDifferences = 0;
        
        for (int i = 1; i < _rrIntervals.length; i++) {
          double difference = _rrIntervals[i] - _rrIntervals[i-1];
          if (difference.abs() < 300) {
            sumSquaredDifferences += difference * difference;
            validDifferences++;
          }
        }
        
        if (validDifferences > 0) {
          double rrms = sqrt(sumSquaredDifferences / validDifferences);
          _currentRow?.rrms = double.parse(rrms.toStringAsFixed(2));
        } else {
          _currentRow?.rrms = 0.0;
        }
      } else {
        _currentRow?.rrms = 0.0;
      }
    }
  }

  Future<void> _writeCurrentRowToCSV() async {
    if (_currentRow == null) return;

    try {
      final file = File(await csvFilePath);
      final newRow = _currentRow!.toCsvRow();
      final csvConverter = const ListToCsvConverter();
      final newRowCsv = csvConverter.convert([newRow]);

      await file.writeAsString(
        '$newRowCsv\n',
        mode: FileMode.append,
        flush: true,
      );

      // Tambahkan ke pending uploads (format JSON untuk upload)
      _pendingUploads.add(_currentRow!.toJson());

      print('Written to CSV: ${newRow.length} fields');

    } catch (e) {
      print('Error writing to CSV: $e');
    }

    // Reset untuk row berikutnya
    _currentRow = CombinedRowData(
      timestamp: DateTime.now(),
      deviceId: _currentDeviceId!,
      activity: _currentActivity,
    );
  }

  Future<void> _uploadPendingData() async {
    if (_pendingUploads.isEmpty || _isUploading) return;

    _isUploading = true;
    final dataToUpload = List<Map<String, dynamic>>.from(_pendingUploads);
    
    try {
      print('Uploading ${dataToUpload.length} records to server...');

      // Format data sesuai dengan yang diharapkan server
      final uploadData = {
        'sensor_data': dataToUpload,
        'device_id': _currentDeviceId,
        'upload_timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final response = await http.post(
        Uri.parse(_uploadUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(uploadData),
      ).timeout(Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('Successfully uploaded ${dataToUpload.length} records');
        _pendingUploads.clear();
        
        // Update service notification
        final service = FlutterBackgroundService();
        if (await service.isRunning()) {
          service.invoke('update', {
            'title': 'Polar Monitor - Recording',
            'content': 'Device: ${_currentDeviceId!.substring(0, 8)} | Uploaded: ${dataToUpload.length} records',
          });
        }
      } else {
        print('Upload failed with status: ${response.statusCode}');
        print('Response: ${response.body}');
      }
    } catch (e) {
      print('Error uploading data: $e');
    } finally {
      _isUploading = false;
    }
  }

  Future<void> uploadExistingCsv() async {
    try {
      final file = File(await csvFilePath);
      if (!await file.exists()) {
        print('CSV file does not exist for upload');
        return;
      }

      final csvContent = await file.readAsString();
      if (csvContent.trim().isEmpty) {
        print('CSV file is empty');
        return;
      }

      final csvConverter = const CsvToListConverter();
      final rows = csvConverter.convert(csvContent);
      
      if (rows.length <= 1) {
        print('CSV file has only headers');
        return;
      }

      final dataToUpload = <Map<String, dynamic>>[];
      
      for (var row in rows.skip(1)) {
        try {
          if (row.length >= 12) { // Pastikan row memiliki cukup kolom
            final data = {
              'timestamp': int.parse(row[0].toString()),
              'date_created': row[1].toString(),
              'time_created': row[2].toString(),
              'hr': row[3].toString().isNotEmpty ? double.parse(row[3].toString()) : null,
              'rr': row[4].toString().isNotEmpty ? double.parse(row[4].toString()) : null,
              'rrms': row[5].toString().isNotEmpty ? double.parse(row[5].toString()) : 0.0,
              'acc_x': row[6].toString().isNotEmpty ? double.parse(row[6].toString()) : null,
              'acc_y': row[7].toString().isNotEmpty ? double.parse(row[7].toString()) : null,
              'acc_z': row[8].toString().isNotEmpty ? double.parse(row[8].toString()) : null,
              'ecg': row[9].toString().isNotEmpty ? double.parse(row[9].toString()) : null,
              'device_id': row[10].toString(),
              'activity': row[11].toString(),
            };
            dataToUpload.add(data);
          }
        } catch (e) {
          print('Error parsing row for upload: $e, row: $row');
        }
      }

      if (dataToUpload.isNotEmpty) {
        print('Uploading ${dataToUpload.length} existing records...');
        await _uploadDataBatch(dataToUpload);
      }
    } catch (e) {
      print('Error uploading existing CSV: $e');
    }
  }

  Future<void> _uploadDataBatch(List<Map<String, dynamic>> dataBatch) async {
    try {
      final uploadData = {
        'sensor_data': dataBatch,
        'device_id': _currentDeviceId,
        'batch_timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final response = await http.post(
        Uri.parse(_uploadUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(uploadData),
      ).timeout(Duration(seconds: 60));

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('Successfully uploaded batch of ${dataBatch.length} records');
      } else {
        throw Exception('Upload failed with status: ${response.statusCode}');
      }
    } catch (e) {
      print('Batch upload error: $e');
      rethrow;
    }
  }

  Future<int> getPendingUploadCount() async {
    return _pendingUploads.length;
  }

  Future<String> getCurrentCsvPath() async {
    return await csvFilePath;
  }
}

class BackgroundServiceHelper {
  static final BackgroundServiceHelper _instance = BackgroundServiceHelper._internal();
  factory BackgroundServiceHelper() => _instance;
  BackgroundServiceHelper._internal();

  final Polar polar = Polar();
  final BackgroundCsvHelper _csvHelper = BackgroundCsvHelper();
  
  String? _connectedDeviceId;
  StreamSubscription<PolarHrData>? _hrStreamSubscription;
  StreamSubscription<PolarEcgData>? _ecgStreamSubscription;
  StreamSubscription<PolarAccData>? _accStreamSubscription;

  Future<void> initializeService() async {
    final service = FlutterBackgroundService();
    
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'polar_background_service',
        initialNotificationTitle: 'Polar Monitor',
        initialNotificationContent: 'Monitoring sensor data',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    print('Background service initialized');
  }

  Future<void> startBackgroundService(String deviceId, String? activity) async {
    try {
      _connectedDeviceId = deviceId;
      
      final service = FlutterBackgroundService();
      if (!(await service.isRunning())) {
        await service.startService();
      }
      
      // Simpan state ke shared preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('background_device_id', deviceId);
      await prefs.setBool('is_background_recording', true);
      await prefs.setString('background_activity', activity ?? 'Rest');
      
      // Start background operations
      _csvHelper.startPeriodicWriting(deviceId, activity);
      await _startBackgroundStreaming();
      
      service.invoke('setAsForeground');
      service.invoke('update', {
        'title': 'Polar Monitor - Recording',
        'content': 'Device: ${deviceId.substring(0, 8)}... | Activity: ${activity ?? "Rest"}',
      });

      print('Background service started for device: $deviceId');
      
    } catch (e) {
      print('Error starting background service: $e');
      rethrow;
    }
  }

  Future<void> stopBackgroundService() async {
    try {
      _stopBackgroundStreams();
      _csvHelper.stopPeriodicWriting();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_background_recording', false);
      
      final service = FlutterBackgroundService();
      if (await service.isRunning()) {
        service.invoke('setAsBackground');
        service.invoke('stop');
      }

      print('Background service stopped');
      
    } catch (e) {
      print('Error stopping background service: $e');
    }
  }

  Future<void> _startBackgroundStreaming() async {
    if (_connectedDeviceId == null) return;

    try {
      print('Starting background streaming for device: $_connectedDeviceId');

      // Start HR streaming
      _hrStreamSubscription = polar.startHrStreaming(_connectedDeviceId!).listen(
        (hrData) async {
          if (hrData.samples.isNotEmpty) {
            final sample = hrData.samples.first;
            final heartRate = sample.hr.toDouble();
            
            await _csvHelper.appendSensorData(SensorData(
              type: DataType.hr,
              value: heartRate,
              timestamp: DateTime.now(),
            ));

            // Process RR intervals if available
            final rrList = sample.rrsMs;
            if (rrList.isNotEmpty) {
              for (final rr in rrList) {
                final rrInterval = rr.toDouble();
                if (rrInterval > 0) {
                  await _csvHelper.appendSensorData(SensorData(
                    type: DataType.rr,
                    value: rrInterval,
                    timestamp: DateTime.now(),
                  ));
                }
              }
            }
          }
        },
        onError: (error) {
          print('Background HR streaming error: $error');
        },
        cancelOnError: true,
      );

      // Start ECG streaming jika tersedia
      try {
        _ecgStreamSubscription = polar.startEcgStreaming(_connectedDeviceId!).listen(
          (ecgData) async {
            if (ecgData.samples.isNotEmpty) {
              final ecgValue = ecgData.samples.last.voltage.toDouble();
              
              await _csvHelper.appendSensorData(SensorData(
                type: DataType.ecg,
                value: ecgValue,
                timestamp: DateTime.now(),
              ));
            }
          },
          onError: (error) {
            print('Background ECG streaming error: $error');
          },
          cancelOnError: true,
        );
      } catch (e) {
        print('Background ECG streaming not available: $e');
      }

      // Start ACC streaming jika tersedia
      try {
        _accStreamSubscription = polar.startAccStreaming(_connectedDeviceId!).listen(
          (accData) async {
            if (accData.samples.isNotEmpty) {
              final sample = accData.samples.last;
              
              await _csvHelper.appendSensorData(SensorData(
                type: DataType.acc,
                value: 0.0, // Magnitude akan dihitung di CombinedRowData
                timestamp: DateTime.now(),
                additionalData: {
                  'x': sample.x.toDouble(),
                  'y': sample.y.toDouble(),
                  'z': sample.z.toDouble(),
                },
              ));
            }
          },
          onError: (error) {
            print('Background ACC streaming error: $error');
          },
          cancelOnError: true,
        );
      } catch (e) {
        print('Background ACC streaming not available: $e');
      }

      print('Background streaming started successfully');

    } catch (e) {
      print('Background streaming setup error: $e');
    }
  }

  void _stopBackgroundStreams() {
    _hrStreamSubscription?.cancel();
    _ecgStreamSubscription?.cancel();
    _accStreamSubscription?.cancel();
    _hrStreamSubscription = null;
    _ecgStreamSubscription = null;
    _accStreamSubscription = null;
    print('Background streams stopped');
  }

  Future<bool> isBackgroundRecording() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_background_recording') ?? false;
  }

  Future<String?> getBackgroundDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('background_device_id');
  }

  Future<String?> getBackgroundActivity() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('background_activity');
  }

  Future<void> uploadAllData() async {
    await _csvHelper.uploadExistingCsv();
  }

  Future<int> getPendingUploadCount() async {
    return await _csvHelper.getPendingUploadCount();
  }

  Future<String> getCurrentCsvPath() async {
    return await _csvHelper.getCurrentCsvPath();
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });

    service.on('update').listen((event) {
      if (event!['title'] != null && event['content'] != null) {
        service.setForegroundNotificationInfo(
          title: event['title'],
          content: event['content'],
        );
      }
    });
  }

  service.on('stop').listen((event) {
    service.stopSelf();
  });

  // Initialize CSV helper dan restart recording jika diperlukan
  final backgroundHelper = BackgroundServiceHelper();
  final prefs = await SharedPreferences.getInstance();
  final isRecording = prefs.getBool('is_background_recording') ?? false;
  
  if (isRecording) {
    final deviceId = prefs.getString('background_device_id');
    final activity = prefs.getString('background_activity');
    
    if (deviceId != null) {
      final csvHelper = BackgroundCsvHelper();
      csvHelper.startPeriodicWriting(deviceId, activity);
      
      service.invoke('update', {
        'title': 'Polar Monitor - Recording',
        'content': 'Device: ${deviceId.substring(0, 8)}... | Activity: ${activity ?? "Rest"}',
      });
    }
  }

  // Setup periodic task untuk menjaga service tetap aktif
  Timer.periodic(Duration(seconds: 10), (timer) async {
    if (service is AndroidServiceInstance) {
      if (!await service.isForegroundService()) {
        service.setAsForegroundService();
      }
    }

    // Cek jika service harus berhenti
    final isRecording = prefs.getBool('is_background_recording') ?? false;
    if (!isRecording) {
      timer.cancel();
      service.stopSelf();
    }
  });
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}