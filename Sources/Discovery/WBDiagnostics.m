#import "WBDiagnostics.h"

@implementation WBDiagnostics

+ (NSURL *)diagnosticsFileURL:(NSError **)error {
    NSURL *cachesURL = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    if (!cachesURL) {
        return nil;
    }
    NSURL *directoryURL = [cachesURL URLByAppendingPathComponent:@"WeChatBubble" isDirectory:YES];
    if (![NSFileManager.defaultManager createDirectoryAtURL:directoryURL withIntermediateDirectories:YES attributes:nil error:error]) {
        return nil;
    }
    return [directoryURL URLByAppendingPathComponent:@"diagnostics.plist"];
}

+ (NSURL *)writeSnapshot:(NSDictionary<NSString *, id> *)snapshot error:(NSError **)error {
    NSURL *fileURL = [self diagnosticsFileURL:error];
    if (!fileURL) {
        return nil;
    }
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:snapshot format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
    if (!data || ![data writeToURL:fileURL options:NSDataWritingAtomic error:error]) {
        return nil;
    }
    return fileURL;
}

+ (BOOL)updateDiscovery:(NSDictionary<NSString *, id> *)update error:(NSError **)error {
    NSURL *fileURL = [self diagnosticsFileURL:error];
    NSData *data = fileURL ? [NSData dataWithContentsOfURL:fileURL options:0 error:error] : nil;
    if (!data) {
        return NO;
    }
    NSDictionary<NSString *, id> *storedSnapshot = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:error];
    if (![storedSnapshot isKindOfClass:NSDictionary.class]) {
        return NO;
    }
    NSMutableDictionary<NSString *, id> *snapshot = [storedSnapshot mutableCopy];
    NSMutableDictionary<NSString *, id> *discovery = [snapshot[@"discovery"] mutableCopy] ?: [NSMutableDictionary dictionary];
    [discovery addEntriesFromDictionary:update];
    snapshot[@"discovery"] = discovery;
    return [self writeSnapshot:snapshot error:error] != nil;
}

@end
