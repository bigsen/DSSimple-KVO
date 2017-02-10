//
//  ViewController.m
//  DSSimpleKVO
//
//  Created by zhangdasen on 2017/1/12.
//  Copyright © 2017年 zhangdasen. All rights reserved.
//

#import "ViewController.h"
#import "NSObject+DSSimpleKVO.h"
#import "Data.h"
@interface ViewController ()
@property (nonatomic, strong)UILabel  *label;
@property (nonatomic, strong)Data     *data;


@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.data.number = @"10";
    self.label.text = [NSString stringWithFormat:@"今天有%@人",self.data.number];
    
    [self.data bindingWithKeyPath:@"number" controlObjc:self.label objcKey:@"text" sync:NO];
    
//    [self.data bindingWithKeyPath:@"number" WithBlock:^(id newValue, id oldValue) {
//        self.label.text = [self.label.text setStr:newValue];
//    }];
    
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    self.data.number = @"12";
}

#pragma mark - 懒加载
- (UILabel *)label{
    if (!_label) {
        _label = [[UILabel alloc]initWithFrame:CGRectMake(0, 0, 100, 100)];
        _label.center = self.view.center;
        [self.view addSubview:_label];
    }
    return _label;
}

- (Data *)data{
    if (!_data) {
        _data = [[Data alloc]init];
    }
    return _data;
}

@end
