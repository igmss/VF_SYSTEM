import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'models/app_user.dart';
import 'providers/app_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/distribution_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/collector/collector_dashboard.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';
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
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => DistributionProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
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
            return app;
          },
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Vodafone Distribution',
            debugShowCheckedModeBanner: false,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: themeProvider.themeMode,
            home: const _AppRouter(),
          );
        },
      ),
    );
  }
}

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

    final role = auth.currentUser?.role;
    if (role == UserRole.COLLECTOR) {
      return const CollectorDashboard();
    }
    if (role == UserRole.ADMIN || role == UserRole.FINANCE || role == UserRole.OPERATOR) {
      return const AdminDashboard();
    }

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 12),
              const Text('No dashboard is configured for this role.'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => context.read<AuthProvider>().signOut(),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
