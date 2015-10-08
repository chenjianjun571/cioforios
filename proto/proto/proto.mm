//
//  proto.m
//  proto
//
//  Created by chenjianjun on 15/9/23.
//  Copyright © 2015年 cio. All rights reserved.
//

#import "proto.h"
#include "jsbn_bss.pb.h"

@implementation Proto

+(NSData*) GetHeartData
{
    std::string buf;
    jsbn::protoc::BSSNetProtocol pc;
    pc.set_type(jsbn::protoc::MSG::Heart_Beat);
    pc.SerializeToString(&buf);
    
    return [[NSData alloc] initWithBytes:buf.c_str() length:buf.length()];
}

+(NSData*) GetLoginRequest
{
    std::string buf;
    jsbn::protoc::BSSNetProtocol pc;
    pc.set_type(jsbn::protoc::MSG::Login_Request);
    pc.mutable_loginrequest()->set_username("ios");
    pc.mutable_loginrequest()->set_password("qwqwqw");
    pc.SerializeToString(&buf);
    
    return [[NSData alloc] initWithBytes:buf.c_str() length:buf.length()];
}

@end
