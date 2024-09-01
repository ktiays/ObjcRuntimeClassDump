//
//  Created by ktiays on 2024/9/1.
//  Copyright (c) 2024 ktiays. All rights reserved.
// 

#ifndef objc_dump_class_h
#define objc_dump_class_h

#include <objc/runtime.h>

#if defined(__cplusplus)
#define OBJC_DUMP_EXTERN extern "C"
#else
#define OBJC_DUMP_EXTERN extern
#endif

OBJC_DUMP_EXTERN void objc_dump_classes(const char *target_directory);

OBJC_DUMP_EXTERN void objc_dump_class(Class aClass, const char *target_directory);

#endif /* objc_dump_class_h */
