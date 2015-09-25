//
//  cio.m
//  cio
//
//  Created by chenjianjun on 15/9/21.
//  Copyright © 2015年 cio. All rights reserved.
//

#import "cio.h"
#import "NetCenter.h"

@implementation CIO
{
    std::shared_ptr<NetCenter> net_instance_;
}

-(BOOL)InitWithDelegate:(id<CIODelegate>)delegate
{
    if (net_instance_) {
        NSLog(@"不能重复初期化");
        return NO;
    }
    
    net_instance_ = std::make_shared<NetCenter>();
    if (nullptr == net_instance_) {
        return NO;
    }
    
    if (net_instance_->NetInit(delegate) != FUNC_SUCCESS)
    {
        NSLog(@"网络初期化失败");
        net_instance_.reset();
        return NO;
    }
    
    return YES;
}

-(void)Terminat
{
    if (nullptr == net_instance_)
    {
        return;
    }
    
    net_instance_->NetExit();
    net_instance_.reset();
}

-(int)OpenIOChannel
{
    if (nullptr == net_instance_)
    {
        return -1;
    }
    
    return net_instance_->CreateFD();
}

-(BOOL)ConnectServiceWhitFD:(int)fd
                   HostName:(NSString*)host_name
                       Port:(int)host_port
{
    if (nullptr == net_instance_)
    {
        return NO;
    }
    
    if (net_instance_->ConnectServiceWhitFD(fd, [host_name UTF8String], host_port))
    {
        return YES;
    }
    
    return NO;
}

-(int)SendDataWithFD:(int)fd
                Data:(NSData*)data
{
    if (nullptr == net_instance_)
    {
        return -1;
    }
    
    return net_instance_->SendDataWithFD(fd, [data bytes], (int)[data length]);
}

-(void)CloseIOChannelWithFD:(int)fd
{
    if (nullptr == net_instance_)
    {
        return;
    }
    
    net_instance_->CloseFD(fd);
}

@end
