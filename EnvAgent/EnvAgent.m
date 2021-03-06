/* 
 * Copyright 2012 Hannes Schmidt
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <asl.h>

#include "launch.h"

#import <Foundation/Foundation.h>

#import "Environment.h"
#import "Constants.h"

int main( int argc, const char** argv )
{
    NSLog( @"Started agent %s (%u)", argv[0], getpid() );

    NSError* error = nil;
    NSFileManager* fileManager = [NSFileManager defaultManager];

    /*
     * Read current agent configuration.
     */
    NSURL* libraryUrl = [fileManager URLForDirectory: NSLibraryDirectory
                                            inDomain: NSUserDomainMask
                                   appropriateForURL: nil
                                              create: NO
                                               error: &error];
    if( !libraryUrl ) {
        NSLog( @"Can't find current user's library directory: %@", error );
        return 1;
    };

    NSURL* agentConfsUrl = [libraryUrl URLByAppendingPathComponent: @"LaunchAgents"
                                                       isDirectory: YES];

    NSString* agentConfName = [agentLabel stringByAppendingString: @".plist"];

    NSURL* agentConfUrl = [agentConfsUrl URLByAppendingPathComponent: agentConfName];

    NSDictionary* curAgentConf = [NSDictionary dictionaryWithContentsOfURL: agentConfUrl];

    /*
     * As per convention, the path to the preference pane is the first entry in
     * WatchPaths. Normally, the preference pane bundle still exists and we
     * simply export the environment. Otherwise, we uninstall the agent by
     * removing the files created outside the bundle during installation.
     */
    NSString* envPanePath = [curAgentConf objectForKey: @"WatchPaths"][0];
    BOOL isDir;
    if( [fileManager fileExistsAtPath: envPanePath isDirectory: &isDir] && isDir ) {
        NSLog( @"Setting environment" );
        Environment* environment = [Environment loadPlist];
        [environment export];
    } else {
        NSLog( @"Uninstalling agent" );
        /*
         * Remove agent binary
         */
        NSString* agentExecutablePath = [curAgentConf objectForKey: @"ProgramArguments"][0];
        if( ![fileManager removeItemAtPath: agentExecutablePath error: &error] ) {
            NSLog( @"Failed to remove agent executable (%@): %@", agentExecutablePath, error );
        }
        /*
         * Remove agent plist ...
         */
        if( ![fileManager removeItemAtURL: agentConfUrl error: &error] ) {
            NSLog( @"Failed to remove agent configuration (%@): %@", agentConfUrl, error );
        }
        /*
         * ... and its parent directory.
         */
        NSString* envAgentAppSupport = [agentExecutablePath stringByDeletingLastPathComponent];
        if( ![fileManager removeItemAtPath: envAgentAppSupport error: &error] ) {
            NSLog( @"Failed to remove agent configuration (%@): %@", agentConfUrl, error );
        }
        /*
         * Remove the job from launchd. This seems to have the same effect as
         * 'unload' except it doesn't cause the running instance of the agent to
         * be terminated and it works without the presence of agent executable
         * or plist.
         */
        NSTask* task = [NSTask launchedTaskWithLaunchPath: launchctlPath
                                                arguments: @[ @"remove", agentLabel ]];
        [task waitUntilExit];
        if( [task terminationStatus] != 0 ) {
            NSLog( @"Failed to unload agent (%@)", agentLabel );
        }
    }

    NSLog( @"Exiting agent %s (%u)", argv[0], getpid() );
    return 0;
}
