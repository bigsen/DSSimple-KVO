//
//  NSObject+DSSimpleRAC.m
//  DSSimpleRAC
//
//  Created by zhangdasen on 2016/12/15.
//  Copyright © 2016年 zhangdasen. All rights reserved.
//
#import <objc/runtime.h>
#import "NSObject+DSSimpleKVO.h"
#import "AppDelegate.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"
#pragma clang diagnostic ignored "-Wenum-conversion"

#define DSFormat(format,objc) [NSString stringWithFormat:format,objc]

#define setAssignAssociated_MuDict if (!getAssociated()) {setValueAssociated(@{}.mutableCopy,Policy_Retain);}\
return getAssociated();

// 获取关联对象
#define getAssociated() objc_getAssociatedObject(self,_cmd)
// 设置assign类型的关联
#define setAssignAssociated(value,value2,policy) objc_setAssociatedObject(self,@selector(value2),value,policy)
// 设置关联的对象
#define setValueAssociated(objc,policy) objc_setAssociatedObject(self,_cmd,objc,((objc_AssociationPolicy)(policy)))
// 设置关联
#define setAssociated(value,policy) objc_setAssociatedObject(self,@selector(value), value,((objc_AssociationPolicy)(policy)))

typedef NS_OPTIONS(NSUInteger, DSBindingType) {
    DSBindingKeyPath       = 0,
    DSBindingControl       = 1,
};

typedef OBJC_ENUM(uintptr_t, objc_Policy) {
    Policy_Assign = 0,              /**< Specifies a weak reference to the associated object. */
    Policy_Retain = 1,              /**< Specifies a strong reference to the associated object.*/
    Policy_Copy   = 3               /**< Specifies that the associated object is copied. */
};

@interface NSObject ()
@property (nonatomic, assign) BOOL                 sync;            // 是否同步进行修改对应对象属性
@property (nonatomic, assign) DSBindingType        type;            // 当前类型
@property (nonatomic, strong) NSString             *currentId;      // 唯一标识符
@property (nonatomic, strong) NSMutableDictionary  *blockDict;      // 存储Block字典

@property (nonatomic, strong) NSMutableDictionary  *controlDict;    // 控件对象字典(用于存储--控件)
@property (nonatomic, strong) NSMutableDictionary  *propertyDict;   // 对象属性字典(用于存储--控件要修改的属性名)
@property (nonatomic, strong) NSMutableDictionary  *identifierDict; // 唯一标示字典(用于存储对象相应的唯一标识符)

@end

@implementation NSObject (DSSimpleKVO)

/// 模式 1
- (void)bindingWithKeyPath:(NSString*)key WithBlock:(ObserveBlock)block
{
    NSAssert(block && key, @"参数不能为空");
    
    // 生成唯一标识符，进行赋值
    self.currentId = [self convertIdentifier:key];
    
    // 根据唯一标识符，和Block，进行对应关系存储
    [self.blockDict setValue:block forKey:self.currentId];
    
    [self setInitWithType:DSBindingKeyPath key:key];
}

/// 模式 2
- (void)bindingWithKeyPath:(NSString*)key controlObjc:(id)controlObjc objcKey:(NSString *)objcKey sync:(BOOL)sync
{
    NSAssert(controlObjc && objcKey, @"参数不能为空");
    
    self.currentId  = [self convertIdentifier:key];
    self.sync       = sync;
    
    [self.controlDict  setValue:controlObjc forKey:self.currentId];
    [self.propertyDict setValue:objcKey     forKey:self.currentId];

    [self setInitWithType:DSBindingControl key:key];
}

- (void)setInitWithType:(DSBindingType)type key:(NSString *)key{
    self.type = type;
    if (![self checkInput:key]) {
        return;
    }
    [self registPropertyObserver:key];
}

#pragma mark - 核心处理

/// 添加Observer监听
- (void)registPropertyObserver:(NSString*)key{

    // 判断是否监听过
    if ([self.identifierDict valueForKey:self.currentId]) {
        return;
    }
    // 添加监听
    [self addObserver:self forKeyPath:key options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld
              context:(__bridge void * _Nullable)(self.currentId)];
    [self.identifierDict setValue:self.currentId forKey:self.currentId];
}

#pragma mark - 事件处理
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context
{
    self.currentId = (__bridge NSString *)(context);
    [self processObserver:keyPath change:change];
}

- (void)processObserver:(NSString *)keyPath change:(NSDictionary *)change{
    
    id newValue = change[NSKeyValueChangeNewKey];
    id oldValue = change[NSKeyValueChangeOldKey];
    switch (self.type) {
        case DSBindingKeyPath:
        {
            ObserveBlock block = self.blockDict[self.currentId];
            block(newValue,oldValue);
        }
            break;
        case DSBindingControl:
        {
            // 根据唯一标识符取出来对象
            id objc     = self.controlDict[self.currentId];
            // 根据唯一标识符取出来对象对应的属性
            id property = self.propertyDict[self.currentId];
            // 通过kvc 给控件进行赋值
            [objc setValue:[self checkString:newValue] forKey:property];
        }
            break;
        default:
            break;
    }
}

/// 自动效验检测中文，插入数据增加
- (NSString *)checkString:(NSString *)newValue{

    id objc       = self.controlDict[self.currentId];
    id property   = self.propertyDict[self.currentId];
    NSString *str = [objc valueForKey:property];
    
    // 进行替换原字符的数字
    NSString *tempStr = [self repleaceStrWithOldStr:str newStr:newValue];
    
    return tempStr;
}

- (NSString *)repleaceStrWithOldStr:(NSString *)str newStr:(NSString *)newStr{

    NSString *oldReplaceStr = [self getNumberOfStrWithStr:str];
    // 进行替换原字符的数字
    NSString *tempStr = [str stringByReplacingOccurrencesOfString:oldReplaceStr withString:newStr];
    
    if (![newStr isKindOfClass:[NSString class]]) {
        return newStr;
    }
    
    if (self.sync || ![self isPureNumandCharacters:newStr]) {
        return newStr;
    }
    
    return tempStr;
}

- (NSString *)getNumberOfStrWithStr:(NSString *)str{
    // 设置set过滤所有字符，只获取数字
    NSCharacterSet* nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    NSString *oldReplaceStr   = [str stringByTrimmingCharactersInSet:nonDigits];
    return oldReplaceStr;
}

- (BOOL)isPureNumandCharacters:(NSString *)string
{
    NSScanner* scan = [NSScanner scannerWithString:string];
    float val;
    int   val2;
    BOOL ffloat = [scan scanFloat:&val] && [scan isAtEnd];
    BOOL iint   = [scan scanInt:&val2]  && [scan isAtEnd];
    
    return ffloat || iint;
}

/// 删除所有监听
- (void)removeAllObserver{
    // 如果没有初始化好，那么就不往下执行，防止引起崩溃。
    if (![UIApplication sharedApplication].delegate) {
        return;
    }
    if (!self.identifierDict.allKeys.count) {
        return;
    }
    NSArray *array = [self observers];
    for (NSString *key in array) {
        [self removeObserver:self forKeyPath:key];
    }
}

/// 获取所有监听对象
- (NSArray *)observers
{
    NSArray *allKey = self.identifierDict.allKeys;
    NSMutableArray *tempArray = @[].mutableCopy;
    for (NSString *keys in allKey) {
       NSString *key = [keys componentsSeparatedByString:@"@@@"].lastObject;
       [tempArray addObject:key];
    }
    return tempArray;
}

/// 校验用户输入 和 防止多次添加
- (BOOL)checkInput:(id)key
{
    // 判断是否存在该属性
    @try {
        [self valueForKey:key];
    } @catch (NSException *exception) {
        NSLog(@"警告！对象没有此属性");
        return NO;
    }
    return YES;
}

/// -----  根据《对象内存地址》和《key值》进行生成唯一标识符 -----
- (NSString *)convertIdentifier:(NSString *)key
{
    NSMutableString *objcAddress = DSFormat(@"%p@@@", self).mutableCopy;
    [objcAddress appendString:key];
    return objcAddress;
}

#pragma mark - Get 方法
- (BOOL)sync            {return [getAssociated() intValue];}
- (NSString *)currentId {return getAssociated();}
- (DSBindingType)type   {return (DSBindingType)[getAssociated() intValue];}

- (NSMutableDictionary *)blockDict{setAssignAssociated_MuDict}
- (NSMutableDictionary *)controlDict{setAssignAssociated_MuDict}
- (NSMutableDictionary *)propertyDict{setAssignAssociated_MuDict}
- (NSMutableDictionary *)identifierDict{setAssignAssociated_MuDict}

#pragma mark - Set 方法

- (void)setSync:(BOOL)sync{
    setAssignAssociated(@(sync), sync, Policy_Retain);
}
- (void)setType:(DSBindingType)type{
    setAssignAssociated(@(type), type, Policy_Retain);
}

- (void)setCurrentId:(NSString *)currentId{
    setAssociated(currentId, Policy_Retain);
}
- (void)setBlockDict:(NSMutableDictionary *)blockDict{
    setAssociated(blockDict, Policy_Retain);
}
- (void)setControlDict:(NSMutableDictionary *)controlDict
{
    setAssociated(controlDict, Policy_Retain);
}
- (void)setPropertyDict:(NSMutableDictionary *)propertyDict
{
    setAssociated(propertyDict, Policy_Retain);
}
- (void)setIdentifierDict:(NSMutableDictionary *)identifierDict
{
    setAssociated(identifierDict, Policy_Retain);
}
#pragma mark - 销毁处理
- (void)dealloc{
    [self removeAllObserver];
}
@end

@implementation NSString (StringAdd)

- (NSString *)setStr:(NSString *)str{
    return [self repleaceStrWithOldStr:self newStr:str];
}
@end
