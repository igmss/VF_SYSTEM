import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'models/app_user.dart';
import 'providers/app_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/distribution_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/collector/collector_dashboard.dart';
import 'screens/splash_screen.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init warning: $e');
  }

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('ar')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => DistributionProvider()),
        ChangeNotifierProxyProvider<DistributionProvider, AppProvider>(
          create: (_) => AppProvider(),
          update: (_, dist, app) {
            app ??= AppProvider();
            app.setBuyOrderCallback(({
              required bybitOrderId,
              required usdtQuantity,
              required egpAmount,
              required usdtPrice,
              required timestamp,
            }) async {
              await dist.processBuyOrder(
                bybitOrderId: bybitOrderId,
                usdtQuantity: usdtQuantity,
                egpAmount: egpAmount,
                usdtPrice: usdtPrice,
                timestamp: timestamp,
              );
            });
            app.setSellOrderCallback(({
              required bybitOrderId,
              required egpAmount,
              required usdtQuantity,
              required usdtPrice,
              required paymentMethod,
              required vfNumberId,
              required vfNumberLabel,
              required createdByUid,
              required timestamp,
            }) async {
              await dist.recordBybitSellOrder(
                bybitOrderId: bybitOrderId,
                egpAmount: egpAmount,
                usdtQuantity: usdtQuantity,
                usdtPrice: usdtPrice,
                paymentMethod: paymentMethod,
                vfNumberId: vfNumberId,
                vfNumberLabel: vfNumberLabel,
                createdByUid: createdByUid,
                timestamp: timestamp,
              );
            });
            return app!;
          },
        ),
      ],
      child: MaterialApp(
        title: 'Vodafone Distribution',
        debugShowCheckedModeBanner: false,
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFE63946),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF0F0F1A),
        ),
        home: const _AppRouter(),
      ),
    );
  }
}

/// Listens to `AuthProvider` state and routes to the correct screen.
class _AppRouter extends StatelessWidget {
  const _AppRouter();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.isLoading) {
      return const SplashScreen();
    }

    if (!auth.isLoggedIn) {
      return const LoginScreen();
    }

    // Route based on role:
    // - COLLECTOR → dedicated CollectorDashboard (no admin access)
    // - All others (ADMIN, FINANCE, OPERATOR) → AdminDashboard
    final role = auth.currentUser?.role;
    if (role == UserRole.COLLECTOR) {
      return const CollectorDashboard();
    }
    return const AdminDashboard();
  }
}
