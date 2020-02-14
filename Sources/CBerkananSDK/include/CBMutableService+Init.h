//
// Copyright © 2019-2020 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.md for license information.
//

@import CoreBluetooth.CBService;

@interface CBMutableService (Init)

- (nonnull instancetype)initBerkananSDKWithType:(nonnull CBUUID *)UUID
                                        primary:(BOOL)isPrimary;

@end
