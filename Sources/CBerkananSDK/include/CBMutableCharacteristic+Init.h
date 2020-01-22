//
// Copyright © 2019 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.txt for license information.
//

@import CoreBluetooth.CBCharacteristic;

@interface CBMutableCharacteristic (Init)

- (nonnull instancetype)initBerkananSDKWithType:(nonnull CBUUID *)UUID
                                     properties:(CBCharacteristicProperties)properties
                                          value:(nullable NSData *)value
                                    permissions:(CBAttributePermissions)permissions;

@end
