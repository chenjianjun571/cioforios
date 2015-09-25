//
//  cio.h
//  cio
//
//  Created by chenjianjun on 15/9/21.
//  Copyright © 2015年 cio. All rights reserved.
//

#import <Foundation/Foundation.h>

enum emNetEvent {
    EVE_UNKNOWN = -1,// 未知错误
    ENE_CONNECTED = 0,// 连接建立
    ENE_HEART,// 心跳
    ENE_HEART_TIMEOUT,// 心跳检测超时
    ENE_ACCEPT_ERROR,// 监听失败
    ENE_CLOSE// 连接关闭
};

@protocol CIODelegate <NSObject>
-(int)RecvTCPDataWithFD:(int)fd Data:(NSData*)data;
-(int)StatusReportWithFD:(int)fd Status:(enum emNetEvent)status;
@end

@interface CIO : NSObject

/**
 *	@brief	初期化
 *
 *	@param 	delegate 代理接口实现
 *
 *	@return	成功or失败
 */
-(BOOL)InitWithDelegate:(id<CIODelegate>)delegate;

/**
 *	@brief	退出
 *
 *	@return	成功or失败
 */
-(void)Terminat;

/**
 *	@brief	打开一个通道
 *
 *	@return	返回一个句柄，后续的操作都是基于这个句柄，失败返回-1
 */
-(int)OpenIOChannel;

/**
 *	@brief	通过句柄连接服务器
 *
 *	@param 	fd 	调用OpenIOChannel返回的句柄
 *	@param 	host_name 	服务器域名 www.jsbn.com
 *	@param 	host_port 	端口
 *
 *	@return	YES 成功 NO 失败
 */
-(BOOL)ConnectServiceWhitFD:(int)fd
                   HostName:(NSString*)host_name
                       Port:(int)host_port;

/**
 *	@brief	发送数据
 *
 *	@param 	fd 	调用OpenIOChannel返回的句柄
 *	@param 	data 	数据
 *
 *	@return	0成功，-1失败
 */
-(int)SendDataWithFD:(int)fd
                Data:(NSData*)data;

/**
 *	@brief	关闭连接
 *
 *	@param 	fd 	调用OpenIOChannel返回的句柄
 *
 *	@return
 */
-(void)CloseIOChannelWithFD:(int)fd;

@end
