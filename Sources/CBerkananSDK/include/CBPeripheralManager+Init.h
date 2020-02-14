//
// Copyright © 2019-2020 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.md for license information.
//

@import CoreBluetooth.CBPeripheralManager;

@interface CBPeripheralManager (Init)

- (nonnull instancetype)initBerkananSDKWithDelegate:(nullable id<CBPeripheralManagerDelegate>)delegate
                                              queue:(nullable dispatch_queue_t)queue
                                            options:(nullable NSDictionary<NSString *, id> *)options;

@end
