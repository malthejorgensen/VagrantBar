//
//  AppDelegate.h
//  Vagrant Bar
//
//  Created by Paul on 22/05/2014.
//  Copyright (c) 2014 BipSync. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate, NSUserNotificationCenterDelegate> {
    
    NSMutableArray * machineIds;
    BOOL runningGlobalStatus;
    NSMenu * machineSubmenu;
    NSString * vagrantPath;
    BOOL supportsMachineIndex;
    NSMutableDictionary * machinePaths;
    NSTimer * scheduleTimer;
    NSData * previousMachineIndexData;

}

@property (retain) NSStatusItem * statusItem;
@property (retain) NSMenu * mainMenu;

- (NSArray *) parseGlobalStatus:(NSString *)stringOutput;

@end
