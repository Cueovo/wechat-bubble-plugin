#import "WBDiagnostics.h"

@implementation WBDiagnostics

+ (NSURL *)writeSnapshot:(NSDictionary<NSString *, id> *)snapshot error:(NSError **)error {
    NSURL *cachesURL = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    if (!cachesURL) {
        return nil;
    }
    NSURL *directoryURL = [cachesURL URLByAppendingPathComponent:@"WeChatBubble" isDirectory:YES];
    if (![NSFileManager.defaultManager createDirectoryAtURL:directoryURL withIntermediateDirectories:YES attributes:nil error:error]) {
        return nil;
    }
    NSURL *fileURL = [directoryURL URLByAppendingPathComponent:@"diagnostics.plist"];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:snapshot format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
    if (!data || ![data writeToURL:fileURL options:NSDataWritingAtomic error:error]) {
        return nil;
    }
    return fileURL;
}

@end
