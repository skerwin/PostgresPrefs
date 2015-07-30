//
//  PGServer.m
//  PostgreSQL
//
//  Created by Francis McKenzie on 5/7/15.
//  Copyright (c) 2015 Macca Tech Ltd. All rights reserved.
//

#import "PGServer.h"

#pragma mark - Constants / Functions

NSString *const PGServerDefaultName            = @"PostgreSQL";

NSString *const PGServerNameKey                = @"Name";
NSString *const PGServerDomainKey              = @"Domain";
NSString *const PGServerUsernameKey            = @"Username";
NSString *const PGServerBinDirectoryKey        = @"BinDirectory";
NSString *const PGServerDataDirectoryKey       = @"DataDirectory";
NSString *const PGServerLogFileKey             = @"LogFile";
NSString *const PGServerPortKey                = @"Port";
NSString *const PGServerStartupKey             = @"Startup";

NSString *const PGServerStatusUnknownName      = @"Unknown";
NSString *const PGServerStartingName           = @"Starting";
NSString *const PGServerStartedName            = @"Started";
NSString *const PGServerStoppingName           = @"Stopping";
NSString *const PGServerStoppedName            = @"Stopped";
NSString *const PGServerRetryingName           = @"Retrying";
NSString *const PGServerUpdatingName           = @"Updating";

NSString *const PGServerStartupManualName      = @"Manual";
NSString *const PGServerStartupAtBootName      = @"Boot";
NSString *const PGServerStartupAtLoginName     = @"Login";



#pragma mark - Interfaces

/**
 * A class for generating unique identifiers.
 */
@interface PGUID : NSObject
+ (NSString *)uid;
@end

@interface PGServerSettings()
@end

@interface PGServer()
@end



#pragma mark - PGUID

@implementation PGUID
+ (NSString *)uid
{
    static NSUInteger uid = 0;
    NSUInteger result;
    @synchronized(self) {
        result = uid;
        uid++;
    }
    return [NSNumber numberWithUnsignedInteger:uid].description;
}
@end



#pragma mark - PGServerSettings

@implementation PGServerSettings

- (id)initWithUsername:(NSString *)username binDirectory:(NSString *)binDirectory dataDirectory:(NSString *)dataDirectory logFile:(NSString *)logFile port:(NSString *)port startup:(PGServerStartup)startup
{
    self = [super init];
    if (self) {
        self.username = username;
        self.binDirectory = binDirectory;
        self.dataDirectory = dataDirectory;
        self.logFile = logFile;
        self.port = port;
        self.startup = startup;
    }
    return self;
}
- (id)initWithSettings:(PGServerSettings *)settings
{
    self = [super init];
    if (self) {
        [self importAllSettings:settings];
    }
    return self;
}
- (BOOL)isEqualToSettings:(PGServerSettings *)settings
{
    if (self == settings) return YES;
    if (!settings) return NO;
    if (!self.username && settings.username) return NO;
    if (self.username && ![self.username isEqualToString:settings.username]) return NO;
    if (!self.binDirectory && settings.binDirectory) return NO;
    if (self.binDirectory && ![self.binDirectory isEqualToString:settings.binDirectory]) return NO;
    if (!self.dataDirectory && settings.dataDirectory) return NO;
    if (self.dataDirectory && ![self.dataDirectory isEqualToString:settings.dataDirectory]) return NO;
    if (!self.logFile && settings.logFile) return NO;
    if (self.logFile && ![self.logFile isEqualToString:settings.logFile]) return NO;
    if (self.startup != settings.startup) return NO;
    return YES;
}
- (BOOL)isEqual:(id)object
{
    if (self == object) return YES;
    if (!object) return NO;
    if (![object isKindOfClass:[PGServerSettings class]]) return NO;
    return [self isEqualToSettings:(PGServerSettings *)object];
}
- (void)setUsername:(NSString *)username
{
    _username = TrimToNil(username);
}
- (void)setBinDirectory:(NSString *)binDirectory
{
    _binDirectory = TrimToNil(binDirectory);
}
- (void)setDataDirectory:(NSString *)dataDirectory
{
    _dataDirectory = TrimToNil(dataDirectory);
}
- (void)setLogFile:(NSString *)logFile
{
    _logFile = TrimToNil(logFile);
}
- (void)setPort:(NSString *)port
{
    _port = TrimToNil(port);
}
- (BOOL)hasDifferentUser
{
    NSString *currentUser = NSUserName();
    return NonBlank(self.username) && ![[currentUser lowercaseString] isEqualToString:[self.username lowercaseString]];
}
- (BOOL)valid
{
    return !(self.invalidUsername || self.invalidBinDirectory || self.invalidDataDirectory || self.invalidLogFile || self.invalidPort);
}
- (void)setValid
{
    self.invalidUsername = self.invalidBinDirectory = self.invalidDataDirectory = self.invalidLogFile = self.invalidPort = NO;
}

- (void)importAllSettings:(PGServerSettings *)settings
{
    self.username = settings.username;
    self.port = settings.port;
    self.binDirectory = settings.binDirectory;
    self.dataDirectory = settings.dataDirectory;
    self.logFile = settings.logFile;
    self.startup = settings.startup;
    self.invalidUsername = settings.invalidUsername;
    self.invalidPort = settings.invalidPort;
    self.invalidBinDirectory = settings.invalidBinDirectory;
    self.invalidDataDirectory = settings.invalidDataDirectory;
    self.invalidLogFile = settings.invalidLogFile;
}

+ (PGServerSettings *)settingsWithSettings:(PGServerSettings *)settings
{
    return [[PGServerSettings alloc] initWithSettings:settings];
}

- (NSString *)description
{
    return [@{
             PGServerUsernameKey:self.username?:@"",
             PGServerBinDirectoryKey:self.binDirectory?:@"",
             PGServerDataDirectoryKey:self.dataDirectory?:@"",
             PGServerLogFileKey:self.logFile?:@"",
             PGServerPortKey:self.port?:@"",
             PGServerStartupKey:ServerStartupDescription(self.startup)
    } description];
}

@end



#pragma mark - PGServer

@implementation PGServer

#pragma mark Lifecycle

- (id)init
{
    return [self initWithName:nil domain:nil settings:nil];
}

- (id)initWithName:(NSString *)name domain:(NSString *)domain
{
    return [self initWithName:name domain:domain settings:nil];
}

- (id)initWithName:(NSString *)name domain:(NSString *)domain settings:(PGServerSettings *)settings
{
    self = [super init];
    if (self) {
        _uid = [PGUID uid];
        self.name = name;
        self.domain = domain;
        self.settings = settings;
        self.dirtySettings = [PGServerSettings settingsWithSettings:settings];
        self.dirtySettings = nil;
        self.status = PGServerStatusUnknown;
        self.error = nil;
    }
    return self;
}

- (void)setName:(NSString *)name
{
    _name = TrimToNil(name) ?: @"";
}

- (void)setDomain:(NSString *)domain
{
    _domain = TrimToNil(domain) ?: @"";
}

- (void)setSettings:(PGServerSettings *)settings
{
    _settings = settings ?: [[PGServerSettings alloc] init];
}

- (void)setDirtySettings:(PGServerSettings *)dirtySettings
{
    _dirtySettings = dirtySettings ?: [[PGServerSettings alloc] init];
}

- (NSDictionary *)properties
{
    PGServerSettings *settings = self.settings;
    return @{
             PGServerUsernameKey:settings.username?:@"",
             PGServerBinDirectoryKey:settings.binDirectory?:@"",
             PGServerDataDirectoryKey:settings.dataDirectory?:@"",
             PGServerLogFileKey:settings.logFile?:@"",
             PGServerPortKey:settings.port?:@"",
             PGServerStartupKey:ServerStartupDescription(settings.startup)
     };
}
- (void)setProperties:(NSDictionary *)properties
{
    if (properties == nil) return;
    if (properties[PGServerNameKey]) self.name = ToString(properties[PGServerNameKey]);
    if (properties[PGServerDomainKey]) self.domain = ToString(properties[PGServerDomainKey]);
    if (properties[PGServerUsernameKey]) self.settings.username = ToString(properties[PGServerUsernameKey]);
    if (properties[PGServerBinDirectoryKey]) self.settings.binDirectory = ToString(properties[PGServerBinDirectoryKey]);
    if (properties[PGServerDataDirectoryKey]) self.settings.dataDirectory = ToString(properties[PGServerDataDirectoryKey]);
    if (properties[PGServerLogFileKey]) self.settings.logFile = ToString(properties[PGServerLogFileKey]);
    if (properties[PGServerPortKey]) self.settings.port = ToString(properties[PGServerPortKey]);
    if (properties[PGServerStartupKey]) self.settings.startup = ToServerStartup(properties[PGServerStartupKey]);
}

- (BOOL)canStartAtLogin
{
    return !self.settings.hasDifferentUser;
}

- (BOOL)daemonInRootContext
{
    // Internal server
    if (!self.external) {
        if (self.settings.hasDifferentUser) return YES;
        if (self.settings.startup == PGServerStartupAtBoot) return YES;
        return NO;
        
    // External server
    } else {
        return self.daemonAllowedContext == PGServerDaemonContextRootOnly;
    }
}

- (NSString *)daemonFileBoot
{
    return [NSString stringWithFormat:@"%@/%@.plist", PGLaunchdDaemonFileBootDir, self.daemonName];
}
- (NSString *)daemonFileGlobal
{
    return [NSString stringWithFormat:@"%@/%@.plist", PGLaunchdDaemonFileLoginGlobalDir, self.daemonName];
}
- (NSString *)daemonFileUser
{
    return [NSString stringWithFormat:@"%@/%@.plist", PGLaunchdDaemonFileLoginUserDir, self.daemonName];
}
- (NSString *)daemonFile
{
    // Internal
    if (!self.external) {
        return self.settings.startup == PGServerStartupAtBoot ?
            self.daemonFileBoot :
            self.daemonFileUser;
    
    // External
    } else {
        if (self.daemonInRootContext) {
            return FileExists(self.daemonFileBoot) ?
                self.daemonFileBoot :
                self.daemonFileGlobal;
        } else {
            return self.daemonFileUser;
        }
        
    }
}

- (BOOL)daemonFileExists
{
    return FileExists(self.daemonFile);
}

- (NSString *)daemonLog
{
    NSString *logDir = self.daemonInRootContext ? PGLaunchdDaemonLogRootDir : PGLaunchdDaemonLogUserDir;
    return [NSString stringWithFormat:@"%@/%@.log", logDir, self.daemonName];
}

- (BOOL)daemonLogExists
{
    return FileExists(self.daemonLog);
}

- (BOOL)editable
{
    return !self.external;
}

- (BOOL)actionable
{
    if (!self.external) return YES;
    
    switch (self.status) {
        case PGServerStarted:  return YES;
        case PGServerRetrying: return YES;
        case PGServerStopped:  return self.daemonFileExists;
        default:               return NO;
    }
}

- (BOOL)saveable
{
    return !self.external;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@""
            "Name:         %@\n"
            "Domain:       %@\n"
            "Daemon Name:  %@\n"
            "Daemon Log:   %@\n"
            "Daemon Log?:  %@\n"
            "Daemon File:  %@\n"
            "Daemon File?: %@\n"
            "Root:         %@\n"
            "%@",
            self.name,
            self.domain,
            self.daemonName,
            [self.daemonLog stringByAbbreviatingWithTildeInPath],
            self.daemonLogExists?@"YES":@"NO",
            self.daemonFile,
            self.daemonFileExists?@"YES":@"NO",
            self.daemonInRootContext?@"YES":@"NO",
            self.settings.description];
}

+ (BOOL)hasAllKeys:(NSDictionary *)properties
{
    if (!properties[PGServerUsernameKey]) return NO;
    if (!properties[PGServerBinDirectoryKey]) return NO;
    if (!properties[PGServerDataDirectoryKey]) return NO;
    if (!properties[PGServerLogFileKey]) return NO;
    if (!properties[PGServerPortKey]) return NO;
    if (!properties[PGServerStartupKey]) return NO;
    return YES;
}

@end