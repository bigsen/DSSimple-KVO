//
//  NSObject+DSSimpleRAC.h
//  DSSimpleRAC
//
//  Created by zhangdasen on 2016/12/15.
//  Copyright © 2016年 zhangdasen. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void (^ObserveBlock)(id newValue,id oldValue);

@interface NSObject (DSSimpleKVO)


/**
 模式 1 ：绑定对象，监听属性变化，进行回调。
 
 @param key 需要监听的模型中的属性名
 @param block 变化回调
 */
- (void)bindingWithKeyPath:(NSString *)key WithBlock:(ObserveBlock)block;

/**
 模式 2 ：绑定对象，监听属性变化，修改对应属性

 @param key 需要监听的模型中的属性名
 @param controlObjc 需要修改的对象
 @param objcKey 需要修改的对象的属性名
 @param sync 如果是字符串，是否进行同步修改，或只修改数字。 YES 是完全同步修改， NO 是自动替换数字
 */
- (void)bindingWithKeyPath:(NSString*)key controlObjc:(id)controlObjc objcKey:(NSString *)objcKey  sync:(BOOL)sync;

@end


@interface NSString (StringAdd)

- (NSString *)setStr:(NSString *)str;

@end
