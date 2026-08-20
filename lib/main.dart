import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app_lock.dart';
import 'constants.dart';
import 'db.dart';
import 'screens/root_shell.dart';
import 'store.dart';

Future<void> main() async {
  configureSqliteLoader();
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsMobile) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: kSurface,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }
  try {
    final AppDatabase database = await AppDatabase.open();
    final AppStore store = AppStore(database)..reload();
    final AppLock lock = await AppLock.load();
    runApp(
      MultiProvider(
        providers: <ChangeNotifierProvider<dynamic>>[
          ChangeNotifierProvider<AppStore>.value(value: store),
          ChangeNotifierProvider<AppLock>.value(value: lock),
        ],
        child: const DailyLedgerApp(),
      ),
    );
  } catch (error, stack) {
    debugPrint('DailyLedger failed to start: $error\n$stack');
    runApp(StartupErrorApp(message: error.toString()));
  }
}

class DailyLedgerApp extends StatelessWidget {
  const DailyLedgerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: kAppName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        // English only: keeps unused Material locale data out of the bundle.
        supportedLocales: const <Locale>[Locale('en')],
        home: const LockGate(child: RootShell()),
      );
}

/// Shown instead of the app when the database cannot be opened — most likely
/// a missing libsqlite3.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: kAppName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        supportedLocales: const <Locale>[Locale('en')],
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.error_outline, color: kExpense, size: 36),
                  const SizedBox(height: 14),
                  const Text(
                    'DailyLedger could not start',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kTextMuted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
