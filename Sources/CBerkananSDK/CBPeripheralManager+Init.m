//
// Copyright © 2019 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.txt for license information.
//

#import "CBPeripheralManager+Init.h"
#include <objc/message.h>

@implementation CBPeripheralManager (Init)

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

- (nonnull instancetype)initBerkananSDKWithDelegate:(nullable id<CBPeripheralManagerDelegate>)delegate
                                              queue:(nullable dispatch_queue_t)queue
                                            options:(nullable NSDictionary<NSString *, id> *)options {
  NSString *selectorString = @"initWithDelegate:queue:options:";
  SEL selector = NSSelectorFromString(selectorString);
  if (![self respondsToSelector:selector]) {
    return self;
  }
  id (*action)(id, SEL, id<CBPeripheralManagerDelegate>, dispatch_queue_t, NSDictionary<NSString *, id> *) = (id (*)(id, SEL, id<CBPeripheralManagerDelegate>, dispatch_queue_t, NSDictionary<NSString *, id> *)) objc_msgSend;
  action(self, selector, delegate, queue, options);
  return self;
}

#pragma clang diagnostic pop

@end
