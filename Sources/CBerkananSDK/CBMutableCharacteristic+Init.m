//
// Copyright © 2019-2020 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.md for license information.
//

#import "CBMutableCharacteristic+Init.h"
#include <objc/message.h>

@implementation CBMutableCharacteristic (Init)

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

- (nonnull instancetype)initBerkananSDKWithType:(nonnull CBUUID *)UUID
                                     properties:(CBCharacteristicProperties)properties
                                          value:(nullable NSData *)value
                                    permissions:(CBAttributePermissions)permissions {
  NSString *selectorString = @"initWithType:properties:value:permissions:";
  SEL selector = NSSelectorFromString(selectorString);
  if (![self respondsToSelector:selector]) {
    return self;
  }
  id (*action)(id, SEL, CBUUID *, CBCharacteristicProperties, NSData *, CBAttributePermissions) = (id (*)(id, SEL, CBUUID *, CBCharacteristicProperties, NSData *, CBAttributePermissions)) objc_msgSend;
  action(self, selector, UUID, properties, value, permissions);
  return self;
}

#pragma clang diagnostic pop

@end
