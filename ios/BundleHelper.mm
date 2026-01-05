#import <Foundation/Foundation.h>
#include <string>

extern "C" {
  const char* getRealTimeNitroCACertPath() {
    static std::string cacertPath;

    if (cacertPath.empty()) {
      NSString *path = nil;

      // Try 1: Look in NitroRealTimeNitro resource bundle
      NSBundle *resourceBundle = [NSBundle bundleWithPath:[[NSBundle mainBundle] pathForResource:@"NitroRealTimeNitro" ofType:@"bundle"]];
      if (resourceBundle) {
        path = [resourceBundle pathForResource:@"cacert" ofType:@"pem"];
        if (path) {
          NSLog(@"[BundleHelper] Found CA cert in resource bundle: %@", path);
        }
      }

      // Try 2: Look in main bundle
      if (!path) {
        path = [[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"];
        if (path) {
          NSLog(@"[BundleHelper] Found CA cert in main bundle: %@", path);
        }
      }

      // Try 3: Look for the bundle by identifier
      if (!path) {
        NSBundle *bundle = [NSBundle bundleWithIdentifier:@"org.cocoapods.NitroRealTimeNitro"];
        if (bundle) {
          path = [bundle pathForResource:@"cacert" ofType:@"pem"];
          if (path) {
            NSLog(@"[BundleHelper] Found CA cert by bundle identifier: %@", path);
          }
        }
      }

      if (path) {
        cacertPath = std::string([path UTF8String]);
      } else {
        NSLog(@"[BundleHelper] WARNING: cacert.pem not found in any bundle");
        NSLog(@"[BundleHelper] Tried: NitroRealTimeNitro.bundle, main bundle, and org.cocoapods.NitroRealTimeNitro");
      }
    }

    return cacertPath.empty() ? nullptr : cacertPath.c_str();
  }
}
