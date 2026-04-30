import 'package:disable_battery_optimization/disable_battery_optimization.dart';

import 'package:etgmusic/hooks/utils/use_async_effect.dart';
import 'package:etgmusic/services/kv_store/kv_store.dart';
import 'package:etgmusic/utils/platform.dart';

void useDisableBatteryOptimizations() {
  useAsyncEffect(() async {
    if (!kIsAndroid || KVStoreService.askedForBatteryOptimization) return;

    await DisableBatteryOptimization.showDisableBatteryOptimizationSettings();

    await DisableBatteryOptimization
        .showDisableManufacturerBatteryOptimizationSettings(
      "Your device has additional battery optimization",
      "Follow the steps and disable the optimizations to allow smooth functioning of this app",
    );

    await KVStoreService.setAskedForBatteryOptimization(true);
  }, null, []);
}
