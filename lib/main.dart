import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter/services.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:installed_apps/installed_apps.dart';

void main() {
  runApp(ScreenTimeApp());
}

class ScreenTimeApp extends StatelessWidget {
  const ScreenTimeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(textTheme: GoogleFonts.patrickHandTextTheme()),
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends HookWidget {
  const HomeScreen({super.key});

  static const platform = MethodChannel('screen_time_channel');

  @override
  Widget build(BuildContext context) {
    final unlocks = useState(0);
    final screenTime = useState("0h 0m");
    final screenTimeProgress = useState(0.0);
    final peakUsage = useState("-");
    final longestSession = useState("0m");
    final mostUsedApps = useState<List<Map<String, dynamic>>>([]);
    final hasPermission = useState(false);

    Future<void> fetchScreenTimeData() async {
      try {
        final Map<dynamic, dynamic> result = await platform.invokeMethod(
          'getScreenStats',
        );

        int screenTimeInSeconds = (result['screenTime'] ?? 0) as int;
        double progress = screenTimeInSeconds / 86400;

        screenTime.value = formatDuration(screenTimeInSeconds);
        unlocks.value = result['unlocks'];
        longestSession.value = formatDuration(result['longestSession']);
        screenTimeProgress.value = progress;
        peakUsage.value = result['peakUsageTime'];

        final appsData = await Future.wait(
          (result['topApps'] as List<dynamic>).map((app) async {
            String packageName = app['packageName'];
            var appData = await InstalledApps.getAppInfo(packageName, null);
            var iconData = appData?.icon;
            return {"packageName": packageName, "icon": iconData};
          }),
        );
        mostUsedApps.value = List<Map<String, dynamic>>.from(appsData);

        debugPrint("Most Used Apps: ${mostUsedApps.value.length}");
      } catch (e) {
        debugPrint("Failed to get screen time data: $e");
      }
    }

    Future<void> requestPermission() async {
      final intent = AndroidIntent(
        action: 'android.settings.USAGE_ACCESS_SETTINGS',
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
    }

    Future<void> checkPermission() async {
      try {
        final Map<dynamic, dynamic> result = await platform.invokeMethod(
          'getScreenStats',
        );

        if (result["hasPermission"] == true) {
          print("✅ Permission already granted");
          hasPermission.value = true;
          fetchScreenTimeData(); // Fetch data only if permission exists
        } else {
          print("❌ Permission not granted. Redirecting to settings...");
          hasPermission.value = false;
          requestPermission();
        }
      } catch (e) {
        print("⚠️ Error while checking permission: $e");
        hasPermission.value = false;
        requestPermission();
      }
    }

    useEffect(() {
      checkPermission();
      return null;
    }, []);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Hello, User 👋",
                style: GoogleFonts.patrickHand(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              Text(
                "Here's your screen time today:",
                style: GoogleFonts.patrickHand(
                  fontSize: 18,
                  color: Colors.black,
                ),
              ),
              SizedBox(height: 30),
              _buildStatsCard(screenTime.value, screenTimeProgress.value),
              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _buildUsageCard(
                      Icons.lock,
                      unlocks.value.toString(),
                      "Unlocks",
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _buildUsageCard(
                      Icons.timer,
                      longestSession.value,
                      "Longest Session",
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: _buildMostUsedAppsCard(mostUsedApps.value)),
                  SizedBox(width: 10),
                  Expanded(
                    child: _buildUsageCard(
                      null,
                      peakUsage.value,
                      "Most usage at",
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsCard(String screenTime, double progress) {
    return Container(
      decoration: _boxDecoration(),
      padding: EdgeInsets.all(25),
      child: Row(
        children: [
          CircularProgressIndicator(
            value: progress, // Dynamic progress
            strokeWidth: 6,
            backgroundColor: Colors.white,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
          ),
          SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "${(progress * 100).toStringAsFixed(1)}% of today",
                style: _textStyle(22),
              ),
              Text("Used $screenTime", style: _textStyle(18)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUsageCard(IconData? icon, String value, String label) {
    return Container(
      padding: EdgeInsets.fromLTRB(0, 25, 0, 25),
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) Icon(icon, size: 40, color: Colors.black),
          SizedBox(height: 5),
          Text(value, style: _textStyle(28, bold: true)),
          SizedBox(height: 5),
          Text(label, style: _textStyle(18)),
        ],
      ),
    );
  }

  Widget _buildMostUsedAppsCard(List<Map<String, dynamic>> appData) {
    return Container(
      padding: EdgeInsets.all(25),
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text("Most Used Apps", style: _textStyle(22)),
          SizedBox(height: 10),
          // Use a Row to display the icons horizontally without overlap
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children:
                appData.map((app) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child:
                        app["icon"] != null
                            ? Image.memory(
                              app["icon"], // Assuming the icon is passed as a Uint8List
                              width: 23,
                              height: 23,
                            )
                            : Container(
                              width: 23,
                              height: 23,
                              color:
                                  Colors.grey, // Placeholder for missing icon
                            ),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }

  BoxDecoration _boxDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: Colors.black, width: 3),
      boxShadow: [BoxShadow(color: Colors.black, offset: Offset(4, 4))],
    );
  }

  TextStyle _textStyle(double size, {bool bold = false}) {
    return GoogleFonts.patrickHand(
      fontSize: size,
      color: Colors.black,
      textStyle: TextStyle(
        fontWeight: bold == true ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  String formatDuration(int seconds) {
    int hours = seconds ~/ 3600;
    int minutes = (seconds % 3600) ~/ 60;
    return "${hours}h ${minutes}m";
  }
}
