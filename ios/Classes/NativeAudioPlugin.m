#import "NativeAudioPlugin.h"
#import <native_audio/native_audio-Swift.h>

@implementation NativeAudioPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [AudioPlugin registerWithRegistrar:registrar];
}
@end
