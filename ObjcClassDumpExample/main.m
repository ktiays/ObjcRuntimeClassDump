//
//  Created by ktiays on 2024/9/1.
//  Copyright (c) 2024 ktiays. All rights reserved.
// 

#import <Foundation/Foundation.h>
#import <ObjcRuntimeClassDump/ObjcRuntimeClassDump.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        objc_dump_classes("/var/tmp/test");
    }
}
