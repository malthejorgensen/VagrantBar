//
//  AppDelegate.m
//  Vagrant Bar
//
//  Created by Paul on 22/05/2014.
//  Copyright (c) 2014 BipSync. All rights reserved.
//

#import "AppDelegate.h"


@implementation AppDelegate


- (void) applicationDidFinishLaunching:(NSNotification *)aNotification {
    
    if ( ![self detectVagrantPath] ) {
        
        NSAlert * alert = [NSAlert alertWithMessageText:@"Vagrant Bar" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"Error: Unable to detect path to vagrant\n\nInstall from: http://www.vagrantup.com/\n"];
        [alert runModal];
        
        [[NSApplication sharedApplication] terminate:self];
        return;
        
    }
    
    if ( ![self verifyVagrantVersion] ) {
        
        NSAlert * alert = [NSAlert alertWithMessageText:@"Vagrant Bar" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"Error: Vagrant version 1.6+ is required\n\nUpgrade from: http://www.vagrantup.com/\n"];
        [alert runModal];
        
        [[NSApplication sharedApplication] terminate:self];
        return;
        
    }
    
    [self setupStatusBarItem];
    [self setupMachineSubmenu];
    
    [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];
    
    if ( [self willCheckForUpdate] ) {
        [self checkForUpdate];
    }
    
}

- (void) setupStatusBarItem {
    
    NSMenu * menu = [[NSMenu alloc] init];
    menu.delegate = self;
    
    NSStatusBar * bar = [NSStatusBar systemStatusBar];
    NSStatusItem * item = [bar statusItemWithLength:NSVariableStatusItemLength];
    item.highlightMode = YES;
    item.menu = menu;
    
    NSString * imageName = @"18";
    NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
    if ( [defaults boolForKey:@"monoIcon"] ) {
        imageName = @"18_mono";
    }
    
    item.image = [NSImage imageNamed:imageName];
    item.toolTip = [NSString stringWithFormat:@"Vagrant Bar v%@",
                    [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
    
    self.statusItem = item;
    self.mainMenu = menu;

}

- (void) setupMachineSubmenu {
    
    machineSubmenu = [[NSMenu alloc] init];
    machineSubmenu.autoenablesItems = NO;
    [self addMenuItem:@"Halt" withImage:NSImageNameStopProgressTemplate toMenu:machineSubmenu];
    [self addMenuItem:@"Provision" withImage:NSImageNameActionTemplate toMenu:machineSubmenu];
    [self addMenuItem:@"Reload" withImage:NSImageNameRefreshTemplate toMenu:machineSubmenu];
    [self addMenuItem:@"Resume" withImage:NSImageNameLockUnlockedTemplate toMenu:machineSubmenu];
    [self addMenuItem:@"Suspend" withImage:NSImageNameLockLockedTemplate toMenu:machineSubmenu];
    [self addMenuItem:@"Up" withImage:NSImageNameGoRightTemplate toMenu:machineSubmenu];
    
}

- (void) applicationWillTerminate:(NSNotification *)notification {
    
    self.statusItem = nil;
    
}

- (void) quit {
    
    [[NSApplication sharedApplication] terminate:self];
    
}

- (void) menuWillOpen:(NSMenu *)menu {
    
    if ( menu != self.mainMenu ) {
        return;
    }
    
    [menu removeAllItems];
    [menu addItemWithTitle:@"Fetching machine status.." action:nil keyEquivalent:@""];
    [self appendCommonMenuItems:menu];
    
    [self performSelectorInBackground:@selector(runGlobalStatus) withObject:nil];
    
}

- (void) menuDidClose:(NSMenu *)menu {
    
    [menu performSelector:@selector(removeAllItems) withObject:nil afterDelay:1];
    
}

- (void) appendCommonMenuItems:(NSMenu *)menu {
    
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit Vagrant Bar" action:@selector(quit) keyEquivalent:@""];
    
}

- (void) runGlobalStatus {
    
    if ( runningGlobalStatus ) {
        return;
    }
    runningGlobalStatus = YES;
    
    NSTask * task = [self runCommandWithArguments:@[ @"global-status", @"--prune" ]];
    
    NSFileHandle * fileOutput = [task.standardOutput fileHandleForReading];
    NSData * dataOutput = [fileOutput readDataToEndOfFile];
    NSString * stringOutput = [[NSString alloc] initWithData:dataOutput encoding:NSUTF8StringEncoding];
    
    NSMutableArray * machineItems = [@[] mutableCopy];
    
    NSArray * machineStatuses = [self parseGlobalStatus:stringOutput];
    for ( NSDictionary * machineStatus in machineStatuses ) {
        
        NSString * title = [NSString stringWithFormat:@"%@ (%@): %@",
                            machineStatus[ @"name" ],
                            machineStatus[ @"id" ],
                            machineStatus[ @"state" ]
                            ];
        NSMenuItem * item = [[NSMenuItem alloc] initWithTitle:title action:@selector(machineAction:) keyEquivalent:@""];
        
        
        if ( !machineIds ) {
            machineIds = [@[] mutableCopy];
        }
        [machineIds addObject:machineStatus[ @"id" ]];
        
        item.tag = [machineIds count] - 1;
        item.submenu = [machineSubmenu copy];
        [self setupMachineSubmenuExtras:item.submenu];
        
        BOOL running = [machineStatus[ @"state" ] isEqualToString:@"running"],
        suspended = [machineStatus[ @"state" ] isEqualToString:@"suspended"] || [machineStatus[ @"state" ] isEqualToString:@"saved"],
        stopped = [machineStatus[ @"state" ] isEqualToString:@"stopped"] || [machineStatus[ @"state" ] isEqualToString:@"poweroff"];
        
        [[item.submenu itemAtIndex:0] setEnabled:!stopped]; // halt
        [[item.submenu itemAtIndex:1] setEnabled:running]; // provision
        [[item.submenu itemAtIndex:2] setEnabled:running]; // reload
        [[item.submenu itemAtIndex:3] setEnabled:suspended]; // resume
        [[item.submenu itemAtIndex:4] setEnabled:running]; // suspend
        [[item.submenu itemAtIndex:5] setEnabled:!running]; //up
        
        [machineItems addObject:item];
        
    }
    
    [self.mainMenu removeAllItems];
    if ( [machineItems count] ) {
        NSMenuItem * allItem = [[NSMenuItem alloc] initWithTitle:@"All Machines" action:@selector(allAction:) keyEquivalent:@""];
        allItem.submenu = [machineSubmenu copy];
        allItem.tag = -1;
        [self.mainMenu addItem:allItem];
        [self.mainMenu addItem:[NSMenuItem separatorItem]];
        for ( NSMenuItem * machineItem in machineItems ) {
            [self.mainMenu addItem:machineItem];
        }
    }
    else {
        NSMenuItem * noItem = [[NSMenuItem alloc] initWithTitle:@"No machines registered" action:@selector(allAction:) keyEquivalent:@""];
        [noItem setEnabled:NO];
        [self.mainMenu addItem:noItem];
    }
    [self appendCommonMenuItems:self.mainMenu];
    
    runningGlobalStatus = NO;
    
}

- (void) allAction:(id)sender {
    
}

- (void) machineAction:(id)sender {
    
}

- (void) machineHalt:(id)sender {
    
    NSString * machineId = [self machineIdFromSender:sender];
    [self runBackgroundCommand:@"halt" withMachine:machineId];
    
}

- (void) machineProvision:(id)sender {
    
    NSString * machineId = [self machineIdFromSender:sender];
    [self runBackgroundCommand:@"provision" withMachine:machineId];
    
}

- (void) machineReload:(id)sender {
    
    NSString * machineId = [self machineIdFromSender:sender];
    [self runBackgroundCommand:@"reload" withMachine:machineId];
    
}

- (void) machineResume:(id)sender {
    
    NSString * machineId = [self machineIdFromSender:sender];
    [self runBackgroundCommand:@"resume" withMachine:machineId];
    
}

- (void) machineSuspend:(id)sender {
    
    NSString * machineId = [self machineIdFromSender:sender];
    [self runBackgroundCommand:@"suspend" withMachine:machineId];
    
}

- (void) machineUp:(id)sender {
    
    NSString * machineId = [self machineIdFromSender:sender];
    [self runBackgroundCommand:@"up" withMachine:machineId];
    
}

- (NSString *) machineIdFromSender:(id)sender {
    
    if ( ![sender isKindOfClass:[NSMenuItem class]] ) {
        return nil;
    }
    NSMenuItem * item = sender;
    if ( !item.parentItem ) {
        return nil;
    }
    long index = item.parentItem.tag;
    if ( index < 0 || index > [machineIds count] - 1 ) {
        return nil;
    }
    return [machineIds objectAtIndex:index];
    
}

- (void) runCommand:(NSString *)command withMachine:(NSString *)machineId {
    
    if ( machineId ) {
        [self runCommandWithArguments:@[ command, machineId ]];
    }
    else {
        for ( NSString * otherMachineId in machineIds ) {
            [self runCommandWithArguments:@[ command, otherMachineId ]];
        }
    }
    
}

- (NSTask *) runCommandWithArguments:(NSArray *)arguments {
    
    NSTask * task = [[NSTask alloc] init];
    task.launchPath = vagrantPath;
    task.arguments = arguments;
    task.standardOutput = [NSPipe pipe];
    [task launch];
    
    return task;
    
}

- (void) runBackgroundCommand:(NSString *)command withMachine:(NSString *)machineId {
    
    if ( machineId ) {
        [self runBackgroundCommandWithArguments:@[ command, machineId ]];
    }
    else {
        for ( NSString * otherMachineId in machineIds ) {
            [self runBackgroundCommandWithArguments:@[ command, otherMachineId ]];
        }
    }
    
}

- (NSTask *) runBackgroundCommandWithArguments:(NSArray *)arguments {
    
    NSTask * task = [[NSTask alloc] init];
    task.launchPath = vagrantPath;
    task.arguments = arguments;
    task.standardOutput = [NSPipe pipe];
    
    NSString * askPassPath = [[NSBundle mainBundle] pathForResource:@"AskPass" ofType:@""];
    
    NSMutableDictionary * environment = [[[NSProcessInfo processInfo] environment] mutableCopy];
    [environment setValue:@"NONE" forKey:@"DISPLAY"];
    [environment setValue:askPassPath forKey:@"SUDO_ASKPASS"];
    task.environment = environment;
    
    NSNotificationCenter * notificationCenter = [NSNotificationCenter defaultCenter];
    
    NSFileHandle * readOutput = [task.standardOutput fileHandleForReading];
    [notificationCenter addObserver:self
                           selector:@selector(outputReadNotification:)
                               name:NSFileHandleReadCompletionNotification
                             object:readOutput];
    
    [task launch];
    
    [readOutput readInBackgroundAndNotify];
    
    return task;
    
}

- (void) addMenuItem:(NSString *)title withImage:(NSString *)imageName toMenu:(NSMenu *)menu {
    
    NSMenuItem * item =
    [menu addItemWithTitle:[NSString stringWithFormat:@" %@", title]
                    action:NSSelectorFromString( [NSString stringWithFormat:@"machine%@:", title] ) keyEquivalent:@""];
    
    item.image = [NSImage imageNamed:imageName];
    item.image.size = NSSizeFromString(@"{11,12}");
    
}

- (void) outputReadNotification:(NSNotification *)notification {
    
    NSData * data = [notification.userInfo objectForKey:NSFileHandleNotificationDataItem];
    NSString * string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    if ( ![string length] ) {
        return;
    }
    
    if ( [string length] > 4 && [[string substringToIndex:4] isEqualToString:@"==> "] ) {
        string = [string substringFromIndex:4];
    }
    NSUserNotification * userNotification =
    [self createUserNotification:string];
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:userNotification];
    
    //
    
    NSFileHandle * readOutput = notification.object;
    [readOutput readInBackgroundAndNotify];
    
}

- (BOOL) userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification {
    
    return YES;
    
}

- (NSArray *) parseGlobalStatus:(NSString *)stringOutput {
    
    NSMutableArray * status = [@[] mutableCopy];
    
    NSArray * lines = [stringOutput componentsSeparatedByString:@"\n"];
    BOOL listingMachines = NO;
    for ( NSString * line in lines ) {
        if ( [line length] > 4 && [[line substringToIndex:5] isEqualToString:@"-----"] ) {
            listingMachines = YES;
            continue;
        }
        if ( listingMachines ) {
            NSArray * tokens = [line componentsSeparatedByString:@" "];
            NSMutableArray * validTokens = [@[] mutableCopy];
            for ( NSString * token in tokens ) {
                if ( [[token stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0 ) {
                    [validTokens addObject:token];
                }
            }
            if ( [validTokens count] == 5 ) {
                
                [status addObject:@{
                                    @"id" : validTokens[ 0 ],
                                    @"name" : validTokens[ 1 ],
                                    @"provider" : validTokens[ 2 ],
                                    @"state" : validTokens[ 3 ],
                                    @"path" : validTokens[ 4 ]
                                    }];
                
            }
            else {
                break;
            }
        }
    }
    return status;
    
}

- (BOOL) detectVagrantPath {
    
    NSTask * task = [[NSTask alloc] init];
    task.launchPath = @"/bin/bash";
    task.arguments = @[ @"-c", @"which vagrant" ];
    task.standardOutput = [NSPipe pipe];
    [task launch];
    
    NSFileHandle * output = [task.standardOutput fileHandleForReading];
    NSData * data = [output readDataToEndOfFile];
    if ( ![data length] ) {
        return NO;
    }
    NSString * string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    vagrantPath = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    return YES;
    
}

- (BOOL) verifyVagrantVersion {

    NSTask * task = [[NSTask alloc] init];
    task.launchPath = vagrantPath;
    task.arguments = @[ @"-v" ];
    task.standardOutput = [NSPipe pipe];
    [task launch];
    
    NSFileHandle * output = [task.standardOutput fileHandleForReading];
    NSData * data = [output readDataToEndOfFile];
    if ( ![data length] ) {
        return NO;
    }
    NSString * string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    NSRegularExpression * regex =
    [NSRegularExpression regularExpressionWithPattern:@"\\d+\\.\\d+\\.\\d+" options:0 error:nil];
    
    NSArray * matches = [regex matchesInString:string options:0 range:NSMakeRange( 0, [string length] )];
    for ( NSTextCheckingResult * match in matches ) {
        NSString * version = [string substringWithRange:match.range];
        NSArray * versionComponents = [version componentsSeparatedByString:@"."];
        if ( [versionComponents[ 0 ] intValue] > 1 || [versionComponents[ 1 ] intValue] > 5 ) {
            return YES;
        }
    }
    
    return NO;
    
}

- (void) setupMachineSubmenuExtras:(NSMenu *)menu {
    
    [menu addItem:[NSMenuItem separatorItem]];
    [self addMenuItem:@"SSH" withImage:NSImageNameFollowLinkFreestandingTemplate toMenu:menu];
    
}

- (void) machineSSH:(id)sender {
    
    NSString * machineId = [self machineIdFromSender:sender];
    
    NSString * script = @"clear\n";
    script = [script stringByAppendingString:
              [NSString stringWithFormat:@"%@ ssh %@", vagrantPath, machineId]];
    
    [self runScriptInTerminal:script];
    
}

- (void) runScriptInTerminal:(NSString *)script {
    
    NSString * tempFile =
    [NSTemporaryDirectory() stringByAppendingPathComponent: [NSString stringWithFormat: @"%.0f.%@", [NSDate timeIntervalSinceReferenceDate] * 1000.0, @"sh"]];
    
    if ( ![script writeToFile:tempFile atomically:NO encoding:NSUTF8StringEncoding error:nil] ) {
        return;
    }
    
    NSDictionary * attributes;
    NSNumber * permissions = [NSNumber numberWithUnsignedLong:0x777];
    attributes = [NSDictionary dictionaryWithObject:permissions forKey:NSFilePosixPermissions];
    [[NSFileManager defaultManager] setAttributes:attributes ofItemAtPath:tempFile error:nil];
    
    NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
    NSString * terminalAppName = [defaults stringForKey:@"terminalAppName"];
    if ( !terminalAppName ) {
        terminalAppName = @"Terminal";
    }
    
    [NSTask launchedTaskWithLaunchPath:
     [NSString stringWithFormat:@"/usr/bin/open"]
                             arguments:@[ @"-a", terminalAppName, tempFile ]];
    
}

- (void) checkForUpdate {
    
    NSURL * url = [NSURL URLWithString:@"https://api.github.com/repos/BipSync/VagrantBar/tags"];
    NSURLSession * session = [NSURLSession sharedSession];
    NSURLSessionDownloadTask * task =
    [session downloadTaskWithURL:url
               completionHandler:^( NSURL * location, NSURLResponse * response, NSError * error ) {
                   
                   if ( error ) {
                       return;
                   }
                   NSHTTPURLResponse * httpResponse = (NSHTTPURLResponse *)response;
                   if ( httpResponse.statusCode != 200 ) {
                       return;
                   }
                   NSString * json = [NSString stringWithContentsOfURL:location encoding:NSUTF8StringEncoding error:nil];
                   
                   NSArray * tags = (NSArray *)[NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:0];
                   if ( !tags || ![tags count] ) {
                       return;
                   }
                   NSDictionary * latestTag = tags[ 0 ];
                   if ( ![latestTag[ @"name" ] isEqualToString:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]] ) {
                       
                       NSUserNotification * userNotification =
                       [self createUserNotification:@"Update available, click to download"];
                       userNotification.subtitle = latestTag[ @"name" ];
                       
                       [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:userNotification];
                       
                   }
                   
               }];
    [task resume];
    
}

- (NSUserNotification *) createUserNotification:(NSString *)informativeText {
    
    NSUserNotification * userNotification = [[NSUserNotification alloc] init];
    userNotification.title = @"Vagrant Bar";
    userNotification.informativeText = informativeText;
    userNotification.soundName = NSUserNotificationDefaultSoundName;
    return userNotification;
    
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification {
    
    if ( notification.subtitle ) {
        [[NSWorkspace sharedWorkspace] openURL:
         [NSURL URLWithString:@"https://github.com/BipSync/VagrantBar/releases"]];
    }
    
}

- (BOOL) willCheckForUpdate {
    
    NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
    if ( [defaults valueForKey:@"checkForUpdates"] && [defaults boolForKey:@"checkForUpdates"] == NO ) {
        return NO;
    }
    NSString * defaultsKey = @"lastCheckForUpdate";
    NSTimeInterval lastCheckTime = [defaults doubleForKey:defaultsKey];
    NSTimeInterval nowTime = [NSDate timeIntervalSinceReferenceDate];
    if ( lastCheckTime && nowTime - lastCheckTime < 3600 ) {
        return NO;
    }
    [defaults setValue:[NSNumber numberWithDouble:nowTime] forKey:defaultsKey];
    return YES;
    
}



@end
