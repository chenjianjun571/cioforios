//
//  cio.m
//  cio
//
//  Created by chenjianjun on 15/9/21.
//  Copyright © 2015年 cio. All rights reserved.
//

#import "cio.h"
#include "./net/PhysicalSocketServer.h"
#include "./net/SocketDispatcher.h"
#include "./base/Thread.h"
#include "./base/RWLock.h"

#define MAX_RECV_DATA_SIZE 1*1024*1024
#define MAX_SEND_DATA_SIZE 1*1024*1024

using namespace jsbn;

class NetCenter:public sigslot::has_slots<sigslot::multi_threaded_local>
{
public:
    struct stSocketObj
    {
        char* inbuf_;
        char* outbuf_;
        size_t insize_;
        size_t inpos_;
        size_t outsize_;
        size_t outpos_;
        SocketDispatcher* dispatch;
        
        stSocketObj(SocketDispatcher* dispatch_)
        {
            inpos_ = 0;
            outpos_ = 0;
            insize_ = MAX_RECV_DATA_SIZE;
            outsize_ = MAX_SEND_DATA_SIZE;
            inbuf_ = new char[insize_];
            outbuf_ = new char[outsize_];
            dispatch = dispatch_;
        }
        
        ~stSocketObj()
        {
            delete [] inbuf_;
            delete [] outbuf_;
            
            if (nullptr != dispatch) {
                delete dispatch;
            }
        }
    };
    
public:
    NetCenter():_run_flg(false)
    {
        loop_thread_ = std::make_shared<Thread>();
        spcket_service_ = std::make_shared<PhysicalSocketServer>();
        rw_local_ = RWLock::Create();
    }
    
    ~NetCenter()
    {
        NetExit();
    }
    
    int NetInit(id<CIODelegate> delegate)
    {
        if (_run_flg)
        {
            return FUNC_SUCCESS;
        }
        
        spcket_service_->SetPosixSignalHandler(SIGPIPE, SIG_IGN);
        
        // 开启事件监听主线程
        _run_flg = true;
        if (loop_thread_->Start(&_runnable, this))
        {
            _delegate = delegate;
            return FUNC_SUCCESS;
        }
        
        // 开始线程失败置运行标志
        _run_flg = false;
        
        return FUNC_FAILED;
    }
    
    int NetExit()
    {
        if (!_run_flg)
        {
            return FUNC_SUCCESS;
        }
        
        _run_flg = false;
        spcket_service_->WakeUp();
        loop_thread_->Stop();
        
        Clear();
        spcket_service_.reset();
        loop_thread_.reset();
        
        return FUNC_SUCCESS;
    }
    
    int CreateFD()
    {
        if (!_run_flg)
        {
            return -1;
        }
        
        SocketDispatcher* dispatcher = spcket_service_->CreateAsyncSocket(AF_INET, SOCK_STREAM);
        if (nullptr == dispatcher) {
            return -1;
        }
        
        dispatcher->SignalCloseEvent.connect(this, &NetCenter::OnCloseEvent);
        dispatcher->SignalConnectEvent.connect(this, &NetCenter::OnConnectEvent);
        dispatcher->SignalWriteEvent.connect(this, &NetCenter::OnWriteEvent);
        dispatcher->SignalReadEvent.connect(this, &NetCenter::OnReadEvent);
        
        WriteLockScoped wl(*rw_local_);
        
        socket_objs[dispatcher->GetDescriptor()] = new stSocketObj(dispatcher);
        spcket_service_->Add(dispatcher);
        spcket_service_->WakeUp();
        
        return dispatcher->GetDescriptor();
    }
    
    void CloseFD(int fd)
    {
        if (!_run_flg)
        {
            return;
        }
        
        WriteLockScoped wl(*rw_local_);
        std::map<SOCKET, struct stSocketObj*>::iterator it = socket_objs.find(fd);
        if (socket_objs.end() != it)
        {
            it->second->dispatch->SignalCloseEvent.disconnect(this);
            it->second->dispatch->SignalConnectEvent.disconnect(this);
            it->second->dispatch->SignalWriteEvent.disconnect(this);
            it->second->dispatch->SignalReadEvent.disconnect(this);
            
            spcket_service_->Remove(it->second->dispatch);
            spcket_service_->WakeUp();
            
            delete it->second;
            socket_objs.erase(it);
        }
    }
    
    bool ConnectServiceWhitFD(int fd , const char* host_name, int port)
    {
        if (!_run_flg)
        {
            return false;
        }
        
        SocketAddress addr(host_name, port);
        
        ReadLockScoped wl(*rw_local_);
        std::map<SOCKET, struct stSocketObj*>::iterator it = socket_objs.find(fd);
        if (socket_objs.end() == it)
        {
            return false;
        }
        
        if (it->second->dispatch->Connect(addr) != 0)
        {
            return false;
        }
        
        if (it->second->dispatch->GetState() == jsbn::AsyncSocket::CS_CONNECTED)
        {
            [_delegate StatusReportWithFD:it->second->dispatch->GetDescriptor() Status:ENE_CONNECTED];
        }
        
        return true;
    }
    
    int SendDataWithFD(int fd , const void* pv, int cb)
    {
        ReadLockScoped wl(*rw_local_);
        std::map<SOCKET, struct stSocketObj*>::iterator it = socket_objs.find(fd);
        if (socket_objs.end() == it)
        {
            return false;
        }
        
        if (it->second->outpos_ + cb + kPacketLenSize > it->second->outsize_) {
            it->second->dispatch->SetError(EMSGSIZE);
            return -1;
        }
        
        SetBE16(it->second->outbuf_+it->second->outpos_, cb);
        memcpy(it->second->outbuf_+it->second->outpos_ + kPacketLenSize, pv, cb);
        it->second->outpos_ += cb + kPacketLenSize;
        
        int res = it->second->dispatch->Send(it->second->outbuf_, it->second->outpos_);
        if (res <= 0) {
            return res;
        }
        if (static_cast<size_t>(res) <= it->second->outpos_) {
            it->second->outpos_ -= res;
        } else {
            return -1;
        }
        if (it->second->outpos_ > 0) {
            memmove(it->second->outbuf_, it->second->outbuf_ + res, it->second->outpos_);
        }
        
        return res;
    }
    
protected:
    
    void Clear()
    {
        WriteLockScoped wl(*rw_local_);
        std::map<SOCKET, struct stSocketObj*>::iterator it = socket_objs.begin();
        while (socket_objs.end() != it)
        {
            spcket_service_->Remove(it->second->dispatch);
            delete it->second;
            socket_objs.erase(it++);
        }
        spcket_service_->WakeUp();
    }
    
    void OnConnectEvent(AsyncSocket* socket)
    {
        SocketDispatcher* pSocketDispatcher = static_cast<SocketDispatcher*>(socket);
        dispatch_async(dispatch_get_main_queue(), ^{
            [_delegate StatusReportWithFD:pSocketDispatcher->GetDescriptor() Status:ENE_CONNECTED];
        });
    }
    
    void OnWriteEvent(AsyncSocket* socket_)
    {
        NSLog(@"写事件");
        SocketDispatcher* pSocketDispatcher = static_cast<SocketDispatcher*>(socket_);
        struct stSocketObj* sst = socket_objs[pSocketDispatcher->GetDescriptor()];
        if (sst->outpos_ > 0)
        {
            int res = sst->dispatch->Send(sst->outbuf_, sst->outpos_);
            if (res <= 0) {
                return;
            }
            if (static_cast<size_t>(res) <= sst->outpos_) {
                sst->outpos_ -= res;
            } else {
                return;
            }
            if (sst->outpos_ > 0) {
                memmove(sst->outbuf_, sst->outbuf_ + res, sst->outpos_);
            }
        }
    }
    
    void OnReadEvent(AsyncSocket* socket_)
    {
        NSLog(@"读事件");
        SocketDispatcher* pSocketDispatcher = static_cast<SocketDispatcher*>(socket_);
        struct stSocketObj* sst = socket_objs[pSocketDispatcher->GetDescriptor()];
        
        int len = socket_->Recv(sst->inbuf_ + sst->inpos_, sst->insize_ - sst->inpos_);
        if (len < 0)
        {
            if (!socket_->IsBlocking())
            {
                NSLog(@"Recv() returned error: %d.\n", socket_->GetError());
            }
            return;
        }
        
        sst->inpos_ += len;
        
        while (true)
        {
            if (sst->inpos_ < kPacketLenSize)
            {
                break;
            }
            
            PacketLength pkt_len = GetBE16(sst->inbuf_);
            if (sst->inpos_ < kPacketLenSize + pkt_len)
            {
                break;
            }
            
            NSData* data = [[NSData alloc] initWithBytes:sst->inbuf_+kPacketLenSize length:pkt_len];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [_delegate RecvTCPDataWithFD:pSocketDispatcher->GetDescriptor() Data:data];
            });
            
            sst->inpos_ -= kPacketLenSize + pkt_len;
            if (sst->inpos_ > 0)
            {
                memmove(sst->inbuf_, sst->inbuf_ + kPacketLenSize + pkt_len, sst->inpos_);
            }
        }
        
        if (sst->inpos_ >= sst->insize_)
        {
            NSLog(@"input buffer overflow");
            sst->inpos_ = 0;
        }
    }
    
    void OnCloseEvent(AsyncSocket* socket, int err)
    {
        SocketDispatcher* pSocketDispatcher = static_cast<SocketDispatcher*>(socket);
        dispatch_async(dispatch_get_main_queue(), ^{
            [_delegate StatusReportWithFD:pSocketDispatcher->GetDescriptor() Status:ENE_CLOSE];
        });
    }
    
private:
    class NetRunnable:public Runnable
    {
    public:
        NetRunnable() {}
        ~NetRunnable() {}
        
    protected:
        virtual void Run(void*user_data)
        {
            NetCenter* pNetCenter = (NetCenter*)user_data;
            while (pNetCenter->_run_flg)
            {
                pNetCenter->spcket_service_->Wait(1000, true);
            }
        }
    };
    
    friend class NetRunnable;
    
private:
    id<CIODelegate> _delegate;
    std::shared_ptr<Thread> loop_thread_;
    std::shared_ptr<PhysicalSocketServer> spcket_service_;
    NetRunnable _runnable;
    
    volatile bool _run_flg;
    
    // 网络连接对象
    std::map<SOCKET, struct stSocketObj*> socket_objs;
    RWLock* rw_local_;
};

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
