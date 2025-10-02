import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'app.dart';
import 'core/services/supabase_client.dart';
import 'core/services/local_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Disable HTTP timeline logging to avoid Dart IO network profiling assertion in some SDKs
  HttpClient.enableTimelineLogging = false;
  await LocalNotifications.init();
  await dotenv.load(fileName: '.env');
  await Supa.init();
  runApp(const MalawaApp());
}
