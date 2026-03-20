// App Constants

class AppConstants {
  // API Configuration
  static const String bybitBaseUrl = 'https://api2.bybit.com';
  static const int apiTimeoutSeconds = 10;
  static const int maxRetries = 3;

  // Database Paths
  static const String dbMobileNumbers = 'mobile_numbers';
  static const String dbTransactions = 'transactions';
  static const String dbSyncData = 'sync_data';

  // Sync Configuration
  static const int syncIntervalMinutes = 5;
  static const int maxOrdersPerSync = 50;

  // Limit Configuration
  static const double minDailyLimit = 10;
  static const double maxDailyLimit = 100000;
  static const double minMonthlyLimit = 100;
  static const double maxMonthlyLimit = 1000000;

  // UI Configuration
  static const double defaultPadding = 16;
  static const double defaultBorderRadius = 8;

  // Error Messages
  static const String errorNoInternet = 'No internet connection';
  static const String errorApiFailure = 'API request failed';
  static const String errorDatabaseFailure = 'Database operation failed';
  static const String errorInvalidInput = 'Invalid input provided';
  static const String errorNoDefaultNumber = 'No default number set';

  // Success Messages
  static const String successNumberAdded = 'Mobile number added successfully';
  static const String successNumberDeleted = 'Mobile number deleted';
  static const String successNumberUpdated = 'Mobile number updated';
  static const String successOrdersSynced = 'Orders synced successfully';
}

class AppColors {
  static const int primaryColor = 0xFFC41E3A; // Vodafone Red
  static const int accentColor = 0xFF1976D2;
  static const int successColor = 0xFF4CAF50;
  static const int warningColor = 0xFFFFC107;
  static const int errorColor = 0xFFF44336;
  static const int backgroundColor = 0xFFFAFAFA;
  static const int surfaceColor = 0xFFFFFFFF;
  static const int textPrimary = 0xFF212121;
  static const int textSecondary = 0xFF757575;
}

class AppStrings {
  // App Title
  static const String appTitle = 'Vodafone Cash Tracker';
  static const String appVersion = '1.0.0';

  // Navigation
  static const String dashboard = 'Dashboard';
  static const String settings = 'Settings';
  static const String addNumber = 'Add Number';
  static const String transactions = 'Transactions';

  // Labels
  static const String phoneNumber = 'Phone Number';
  static const String dailyLimit = 'Daily Limit';
  static const String monthlyLimit = 'Monthly Limit';
  static const String amount = 'Amount';
  static const String currency = 'Currency';
  static const String status = 'Status';
  static const String timestamp = 'Date & Time';
  static const String orderId = 'Order ID';

  // Buttons
  static const String addButton = 'Add';
  static const String saveButton = 'Save';
  static const String deleteButton = 'Delete';
  static const String cancelButton = 'Cancel';
  static const String syncButton = 'Sync';
  static const String refreshButton = 'Refresh';
  static const String settingsButton = 'Settings';

  // Messages
  static const String noNumbersAdded = 'No mobile numbers added';
  static const String noTransactions = 'No transactions yet';
  static const String setAsDefault = 'Set as Default';
  static const String deleteConfirmation = 'Are you sure you want to delete this number?';
  static const String syncingOrders = 'Syncing orders...';
  static const String syncComplete = 'Sync completed';
}
