//
//  MorphletSnapshot.h
//  Pods
//
//  Created by rit3zh CX on 10/1/26.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

UIView *_Nullable MorphletSnapshotView(UIView *view);

UIImageView *_Nullable MorphletSnapshotImageView(UIView *view);

UIImageView *_Nullable MorphletContentSnapshotImageView(UIView *view);

CALayer *_Nullable MorphletBackgroundLayer(UIView *view);

NSArray<UIView *> *MorphletSurfaceChain(UIView *view);

CGFloat MorphletCornerRadius(UIView *view);

UIColor *MorphletVisibleBackgroundColor(UIView *view, UIColor *fallback);
UIColor *_Nullable MorphletOpaqueBackgroundColor(UIView *view);

NS_ASSUME_NONNULL_END
