//
// Copyright © 2019 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.txt for license information.
//

@import CoreBluetooth.CBService;

@interface CBMutableService (Init)

- (nonnull instancetype)initBerkananSDKWithType:(nonnull CBUUID *)UUID
                                        primary:(BOOL)isPrimary;

@end
