//
//  ViewController.m
//  demo
//
//  Created by chenjianjun on 15/9/23.
//  Copyright © 2015年 cio. All rights reserved.
//

#import "ViewController.h"
#import "cio.h"
#import "proto.h"

@interface ViewController ()<CIODelegate>
{
}

@end

@implementation ViewController
{
    CIO* pcio;
    int fd_;
    BOOL flg;
    NSTimer *timer;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    pcio = [[CIO alloc] init];
    [pcio InitWithDelegate:self];
    fd_ = -1;
    flg = NO;
    
    //timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(timerFired) userInfo:nil repeats:YES];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void) timerFired
{
    NSLog(@"发送心跳");
    [self btnSendData:nil];
}

- (IBAction)btnConnect:(id)sender
{
    if (fd_ > 0)
    {
        flg = NO;
        [pcio CloseIOChannelWithFD:fd_];
        fd_ = -1;
        
        return;
    }
    
    fd_ = [pcio OpenIOChannel];
    if (fd_ == -1) {
        NSLog(@"创建fd失败.");
        return;
    }
    NSLog(@"创建fd:%d.",fd_);
    if ([pcio ConnectServiceWhitFD:fd_ HostName:@"192.168.1.4" Port:5858] == NO) {
        NSLog(@"连接失败");
        return;
    }
}

- (IBAction)btnSendData:(id)sender
{
    if (flg) {
        NSData* data = [Proto GetHeartData];
        
        for (int i =0; i < 15; ++i) {
            [pcio SendDataWithFD:fd_ Data:data];
        }
    }
}

- (IBAction)btnClose:(id)sender
{
    if (fd_ > 0)
    {
        flg = NO;
        [pcio CloseIOChannelWithFD:fd_];
        fd_ = -1;
    }
    
    //[pcio Terminat];
}

-(int)RecvTCPDataWithFD:(int)fd Data:(NSData*)data
{
    // 因为底层已经做了线程分离，所以在此函数里面的操作不会影响到底层
    NSLog(@"%d收到数据包.", fd);
    return 0;
}

-(int)StatusReportWithFD:(int)fd Status:(enum emNetEvent)status
{
    // 因为底层已经做了线程分离，所以在此函数里面的操作不会影响到底层
    switch (status)
    {
        case ENE_CONNECTED:
            flg = YES;
            NSLog(@"连接建立.");
            break;
        case ENE_CLOSE:
            flg = NO;
            [pcio CloseIOChannelWithFD:fd_];
            fd_ = -1;
            NSLog(@"连接关闭");
        default:
            break;
    }
    
    return 0;
}

@end
