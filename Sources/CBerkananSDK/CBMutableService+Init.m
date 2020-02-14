//
// Copyright © 2019-2020 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.md for license information.
//

#import "CBMutableService+Init.h"
#include <objc/message.h>

@implementation CBMutableService (Init)

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

- (instancetype)initBerkananSDKWithType:(nonnull CBUUID *)UUID
                                primary:(BOOL)isPrimary {
  NSString *selectorString = @"initWithType:primary:";
  SEL selector = NSSelectorFromString(selectorString);
  if (![self respondsToSelector:selector]) {
    return self;
  }  
  id (*action)(id, SEL, CBUUID *, BOOL) =
  (id (*)(id, SEL, CBUUID *, BOOL)) objc_msgSend;
  action(self, selector, UUID, isPrimary);
  return self;
}

#pragma clang diagnostic pop

@end
