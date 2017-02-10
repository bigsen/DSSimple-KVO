![](http://upload-images.jianshu.io/upload_images/790890-6c385d0d8c7f4312.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

#### 一、介绍
本篇文章是介绍的是一种KVO是使用Block方式进行回调的一种实现方式。
使用这种方式可以：更方便的使用KVO，可以利用到很多场景，进行更简单响应编程，可以进行视图和Model的一种绑定关系。

### 使用方法：
1，Block回调
```
[self.data bindingWithKeyPath:@"number" WithBlock:^(id newValue, id oldValue) {
self.label.text = [self.label.text setStr:newValue];
}];
```
2，自动改变对应属性
```
[self.data bindingWithKeyPath:@"number" controlObjc:self.label objcKey:@"text" sync:NO]; 
```

#####调用方式举例：
```
UILabel *label = [[UILabel alloc]init];
[label bindingWithKeyPath:@"text" WithBlock:^(id newValue, id oldValue) {
NSLog(@"%@",newValue);
}];
```
演示：
![](http://upload-images.jianshu.io/upload_images/790890-a2d92101df94b691.gif?imageMogr2/auto-orient/strip)

#### 二、核心原理
1，给NSOBject增加分类。
2，封装`observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary<NSKeyValueChangeKey, id> *)change context:(nullable void *)context`相关逻辑。
3，在内部进行实现KVO监听，利用属性进行存储相应的Key值、Block对象，通过对象的内存地址和锁监听的key值，生成唯一标识符，通过标识符，标识对应各自的Key、Block。
4，接收到监听后，通过自己的唯一标识符，取出来自己的Block，进行执行后回调。

#### 三、代码实现
#####NSObject+DSSimpleKVO.h
```
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
```
#####NSObject+DSSimpleKVO.m
```
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
```
#### 三、代码解析
1，使用Runtime 给分类动态增加属性，在这里为了更方便使用，就用宏定义封装了一下runtime的关联，和宏定义自定义了一下，就不多说介绍了。

2，相关属性
```
@property (nonatomic, assign) BOOL                 sync;            // 是否同步进行修改对应对象属性
@property (nonatomic, assign) DSBindingType        type;            // 当前类型
@property (nonatomic, strong) NSMutableDictionary  *blockDict;
@property (nonatomic, strong) NSString             *currentId;      // 唯一标识符

@property (nonatomic, strong) NSMutableDictionary  *controlDict;    // 控件对象字典(用于存储--控件
@property (nonatomic, strong) NSMutableDictionary  *propertyDict;   // 对象属性字典(用于存储--控件要修改的属性名
@property (nonatomic, strong) NSMutableDictionary  *identifierDict; // 用于存储对象相应的唯一标识符

```
（1）sync 和 type： 可以先忽略，后面会说到。
（2）blockDict 可变字典   ： 用于存储绑定keypath的时候传递进来的KVO。
（3）currentId （唯一标识符）     ：
思考一下，如果注册多个KVO，那么Block回调的时候，到底是执行哪个Block呢 ？
这个时候currentId的作用就出来了，它的作用是，当使用者注册多个kvo的时候，用于存储block的时候，把currentid 当做一个key值，做一个对应关系，一个currentId 对应一个 block 。如：
```
[self.blockDict setValue:block forKey:self.currentId];
```
然后执行在addObserver的时候进行传递的一个参数`context:(void *)context `，把currentId传递进去，当属性发生变化，observeValueForKeyPath 被调用的时候，根据传递进来的context参数，也就是currentID）当做key值，取出对应Block，然后执行。如：
```
ObserveBlock block = self.blockDict[self.currentId];
block(newValue,oldValue);
```
（4）identifierDict ：作用是防止多次重复执行addObserver 进行监听，最明显的是当使用UITableViewCell的时候，Cell会进行复用，这样如果不做处理，默认会走很多次set方法，如果在里面添加了KVO，不做处理的话，那么就会导致添加了很多监听，就会出问题。identifierDict的作用就是为了解决这种情况，只要添加到一次监听，那么identifierDict 就会把 currentId 当做唯一标识符进行存储，如果下次，添加KVO之前，会从identifierDict 里判断是否已经存在过当前currentId，如果存在那么久不做任何操作。
```
// 判断是否监听过
if ([self.identifierDict valueForKey:self.currentId]) {
NSLog(@"已经监听过了,防止重复监听");
return;
}

// 添加监听
[self addObserver:self forKeyPath:key options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld
context:(__bridge void * _Nullable)(self.currentId)];

[self.identifierDict setValue:self.currentId forKey:self.currentId];
```

（5）controlDict 、 propertyDict 和 blockDict 的作用差不多，只不过是存储对象 和 属性名的，后面会说到。

3，调用方法
```
UILabel *label = [[UILabel alloc]init];
[label bindingWithKeyPath:@"text" WithBlock:^(id newValue, id oldValue) {
NSLog(@"%@",newValue);
}];
```
只需要传递进来一个属性，和block即可。

4，调用内部实现
bindingWithKeyPath 这个主要是存储唯一标识符，然后存储Block后，继续下面的逻辑
```
- (void)bindingWithKeyPath:(NSString*)key WithBlock:(ObserveBlock)block
{
NSAssert(block && key, @"参数不能为空");

// 生成唯一标识符，进行赋值
self.currentId = [self convertIdentifier:key];

// 根据唯一标识符，和Block，进行对应关系存储
[self.blockDict setValue:block forKey:self.currentId];

[self setInitWithType:DSBindingKeyPath key:key];
}
```
唯一标识符，本来是需要用户手动传入的，为了做到不让用户手动传入唯一标识符，在这里做了自动生成唯一标识符：
```
/// -----  根据《对象内存地址》和《key值》进行生成唯一标识符 -----
- (NSString *)convertIdentifier:(NSString *)key
{
NSMutableString *objcAddress = DSFormat(@"%p@@@", self).mutableCopy;
[objcAddress appendString:key];
return objcAddress;
}
```
setInitWithType 主要是校验 对象有没有此属性，里面使用try catch 方法。
```
- (void)setInitWithType:(DSBindingType)type key:(NSString *)key{
self.type = type;
if (![self checkInput:key]) {
return;
}
[self registPropertyObserver:key];
}
```

registPropertyObserver 主要就是核心添加kvo的方法，和添加后进行存储currentId唯一标识符。
```
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
```
observeValueForKeyPath 和 processObserver 就是回调之后的操作
```
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
```
自动删除监听的逻辑
在dealloc中，进行遍历identifierDict，取出当前监听的key，进行remove。
```
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
```
到这里基本的核心功能就说完了，大概就这些。
三、 模式2 功能
从最初就提到了 模式2  和 controlDict 、 propertyDict 这些东西，现在，在这里说明一下模式2 。

1，模式2 的作用
模式2 的作用主要是相对于某些场景，更方便的一种解决方法，使用模式2，可以做到，监听某对象属性后，变化后，可指定对应对象的属性，也进行同步进行变化，也可以是如果是需要这种情况的下，就相对于第一种模式，不用写block，而是直接自动修改。比如下图例子：
![](http://upload-images.jianshu.io/upload_images/790890-2d9bb08e17308b17.gif?imageMogr2/auto-orient/strip)

sync 属性的作用是，如果设置为YES，那么在监听发生变化的时候，会把newValue 进行完全赋值给另一个对象的属性，如果设置为NO，那么就会只替换数字的那一部分。 方便于某些场景的使用。

2，调用例子
![](http://upload-images.jianshu.io/upload_images/790890-6e5f65fa3f12a23d.gif?imageMogr2/auto-orient/strip)

```
// 监听 《self.data》对象 的 《number》属性， number 属性变化后，自动 修改 《self.label》对象的《text》属性
[self.data bindingWithKeyPath:@"number" controlObjc:self.label objcKey:@"text" sync:NO];
```

3，实现
在分类中增加了另一个方法`bindingWithKeyPath:(NSString*)key controlObjc:(id)controlObjc objcKey:(NSString *)objcKey  sync:(BOOL)sync;`
key ：是需要监听的key
controlObjc：是监听后变化通知的对象
objcKey ：变化通知对象需要修改的属性
sync： 就是如上面所说的，是否进行完全复制。

和模式1现在区别主要是多了存储通知修改的对象，和对象的属性，和sync属性，在调用方法后，分别使用controlDict 存储对象，和propertyDict 存储对象的属性。type 用于区分，是模式一还是模式二。
```
[self.controlDict  setValue:controlObjc forKey:self.currentId];
[self.propertyDict setValue:objcKey     forKey:self.currentId];
```

在接受到变化的时候，进行分别取出对应的对象和属性，进行赋值：
```
case DSBindingControl:
{
// 根据唯一标识符取出来对象
id objc     = self.controlDict[self.currentId];
// 根据唯一标识符取出来对象对应的属性
id property = self.propertyDict[self.currentId];
// 通过kvc 给控件进行赋值
[objc setValue:[self checkString:newValue] forKey:property];
}

```
关于sync属性，设置自动替换数字的原理，主要是检测字符串，获取字符串中的数字，然后通过stringByReplacingOccurrencesOfString 进行只把新值和数字进行替换。如果新值不是数字，那么也进行完全替换。
```
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
```
isPureNumandCharacters 是判断是否是数字的函数
```
- (BOOL)isPureNumandCharacters:(NSString *)string
{
NSScanner* scan = [NSScanner scannerWithString:string];
float val;
int   val2;
BOOL ffloat = [scan scanFloat:&val] && [scan isAtEnd];
BOOL iint   = [scan scanInt:&val2]  && [scan isAtEnd];

return ffloat || iint;
}
```

###四、最后
gitHub链接地址:https://github.com/SenWinter/DSSimpleKVO
