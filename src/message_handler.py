#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
消息回复处理模块
负责处理从后端接收到的消息并发送给对应的微信用户
"""

import json
import time
import threading
from typing import Dict, Any, List, Optional
from pathlib import Path
import base64
import requests
from queue import Queue, Empty
def _dbg(tag, msg):
    try:
        import datetime as _dt
        with open(r"C:\wx_plugin_debug.txt", "a", encoding="utf-8") as _f:
            _f.write("%s [%s] %s\n" % (_dt.datetime.now().strftime("%H:%M:%S"), tag, msg))
    except Exception:
        pass



# 尝试导入AstrBot日志记录器
try:
    from astrbot.api import logger
except ImportError:
    # 在独立运行模式下，创建一个简单的日志记录器
    class SimpleLogger:
        def info(self, msg): print(f"[INFO] {msg}")
        def error(self, msg): print(f"[ERROR] {msg}")
        def warning(self, msg): print(f"[WARNING] {msg}")
        def debug(self, msg): print(f"[DEBUG] {msg}")
    logger = SimpleLogger()

class MessageHandler:
    """消息回复处理器"""
    
    def __init__(self, config_manager, wechat_monitor, onebot_converter, websocket_client):
        """初始化消息处理器
        
        Args:
            config_manager: 配置管理器
            wechat_monitor: 微信监听器
            onebot_converter: OneBotV11转换器
            websocket_client: WebSocket客户端
        """
        self.config_manager = config_manager
        self.wechat_monitor = wechat_monitor
        self.onebot_converter = onebot_converter
        self.websocket_client = websocket_client
        
        # 消息处理队列
        self.message_queue = Queue()
        
        # 处理线程
        self.handler_thread = None
        self.is_running = False
        
        # 消息缓存（用于去重和追踪）
        self.sent_messages = {}  # message_id -> timestamp
        self.cache_cleanup_interval = 300  # 5分钟清理一次缓存
        self.last_cleanup = time.time()
        
        # 文件下载缓存目录
        project_root = Path(__file__).parent.parent
        self.download_cache_dir = project_root / self.config_manager.get('message.file_cache_dir', 'cache/downloads')
        self.download_cache_dir.mkdir(parents=True, exist_ok=True)
        
    def start(self) -> bool:
        """启动消息处理器
        
        Returns:
            是否启动成功
        """
        try:
            logger.info("启动消息处理器")
            
            self.is_running = True
            
            # 启动处理线程
            self.handler_thread = threading.Thread(target=self._message_handler_loop, daemon=True)
            self.handler_thread.start()
            
            # 设置WebSocket客户端的消息回调
            self.websocket_client.set_callbacks(
                on_message=self._on_websocket_message,
                on_connect=self._on_websocket_connect,
                on_disconnect=self._on_websocket_disconnect
            )
            
            return True
            
        except Exception as e:
            logger.error(f"启动消息处理器失败: {e}")
            return False
            
    def stop(self):
        """停止消息处理器"""
        logger.info("🛑 停止消息处理器")
        
        self.is_running = False
        
        # 等待处理线程结束
        if self.handler_thread and self.handler_thread.is_alive():
            self.handler_thread.join(timeout=2)
            
    def handle_wechat_message(self, wechat_msg: Dict[str, Any]):
        """处理微信消息（转发到后端）
        
        Args:
            wechat_msg: 微信消息
        """
        try:
            logger.info(f"🔄 处理消息: {wechat_msg.get('user_name', 'unknown')} [{wechat_msg.get('message_type', 'text')}]")
            
            # 检查是否是监听的用户
            user_name = wechat_msg.get('user_name', '')
            monitored_users = self.config_manager.get('wechat.monitor_users', [])
            
            # 支持两种格式：字符串列表和对象列表
            is_monitored = False
            for user in monitored_users:
                if isinstance(user, str):
                    # 字符串格式
                    if user == user_name:
                        is_monitored = True
                        break
                elif isinstance(user, dict):
                    # 对象格式
                    if user.get('nickname') == user_name:
                        is_monitored = True
                        break
            
            if not is_monitored:
                print(f"⚠️  用户 {user_name} 不在监听列表，忽略消息")
                return
                
            # 发送到WebSocket后端
            success = self.websocket_client.send_wechat_message(wechat_msg)
            
            if success:
                print(f"✅ 消息已转发: {user_name}")
            else:
                print(f"❌ 转发失败: {user_name}")
                
        except Exception as e:
            print(f"❌ 处理微信消息失败: {e}")
            
    def _on_websocket_message(self, message: Dict[str, Any]):
        """WebSocket消息回调
        
        Args:
            message: 接收到的消息
        """
        try:
            # 将消息加入处理队列
            self.message_queue.put(message)
            
        except Exception as e:
            print(f"WebSocket消息回调失败: {e}")
            
    def _on_websocket_connect(self):
        """WebSocket连接回调"""
        print("🔗 WebSocket已连接，消息处理器就绪")
        
    def _on_websocket_disconnect(self):
        """WebSocket断开连接回调"""
        print("🔌 WebSocket连接断开，消息处理器暂停")
        
    def _message_handler_loop(self):
        """消息处理循环"""
        while self.is_running:
            try:
                # 获取待处理的消息
                try:
                    message = self.message_queue.get(timeout=1)
                except Empty:
                    # 定期清理缓存
                    self._cleanup_cache()
                    continue
                    
                # 处理消息
                self._process_message(message)
                
                # 标记任务完成
                self.message_queue.task_done()
                
            except Exception as e:
                print(f"❌ 消息处理循环异常: {e}")
                time.sleep(1)
                
    def _process_message(self, message: Dict[str, Any]):
        """处理单个消息
        
        Args:
            message: 要处理的消息
        """
        try:
            # 判断消息类型
            if 'action' in message:
                # API请求
                self._handle_api_request(message)
            elif message.get('post_type') == 'message':
                # 消息事件（通常不会收到，因为这是我们发送的）
                print(f"收到消息事件: {message}")
            elif 'echo' in message:
                # API响应
                self._handle_api_response(message)
            else:
                # 其他类型的消息，尝试作为回复消息处理
                self._handle_reply_message(message)
                
        except Exception as e:
            logger.error(f"处理消息失败: {e}")
            
    def _handle_api_request(self, request: Dict[str, Any]):
        """处理API请求
        
        Args:
            request: API请求
        """
        try:
            action = request.get('action', '')
            params = request.get('params', {})
            echo = request.get('echo', '')
            
            logger.info(f"处理API请求: {action}")
            
            if action == 'send_private_msg':
                # 发送私聊消息
                self._handle_send_private_msg(params, echo)
            elif action == 'send_group_msg':
                # 群消息：本插件把群也当作聊天对象，直接走同一条发送链路
                gid = params.get('group_id', '')
                logger.info(f"群消息按普通消息发送: group_id={gid}")
                self._handle_send_private_msg({'user_id': gid, 'message': params.get('message', '')}, echo)
            elif action in ('send_private_forward_msg', 'send_group_forward_msg'):
                # 合并转发：本插件未实现原生转发接口，摊平成纯文本后发送
                self._handle_forward_msg(params, echo, group=(action == 'send_group_forward_msg'))
            elif action == 'send_msg':
                # 通用发送消息接口
                self._handle_send_msg(params, echo)
            elif action == 'get_login_info':
                # 获取登录信息
                data = {
                    "user_id": self.onebot_converter.self_id,
                    "nickname": "WxAuto Bot"
                }
                self.websocket_client.send_api_response(echo, data)
            elif action == 'get_status':
                # 获取状态
                data = {
                    "online": self.websocket_client.is_connected,
                    "good": True
                }
                self.websocket_client.send_api_response(echo, data)
            else:
                # 未支持的API
                logger.warning(f"未支持的API请求: {action}")
                self.websocket_client.send_api_response(echo, None, 1404, "failed")
                
        except Exception as e:
            logger.error(f"处理API请求失败: {e}")
            if 'echo' in locals():
                self.websocket_client.send_api_response(echo, None, 1500, "failed")
                
    def _handle_send_msg(self, params: Dict[str, Any], echo: str):
        """处理通用发送消息请求
        
        Args:
            params: API参数
            echo: 回声标识
        """
        try:
            # 检查消息类型
            message_type = params.get('message_type')
            
            if message_type == 'private':
                # 私聊消息，转发到send_private_msg处理
                self._handle_send_private_msg(params, echo)
            elif message_type == 'group':
                # 群消息：与 send_group_msg 保持一致，走同一条发送链路
                group_id = params.get('group_id', '')
                logger.info(f"send_msg(group) 按普通消息发送: group_id={group_id}")
                self._handle_send_private_msg({'user_id': group_id, 'message': params.get('message', '')}, echo)
            else:
                # 未知消息类型
                logger.warning(f"未知消息类型: {message_type}")
                self.websocket_client.send_api_response(echo, None, 1400, "invalid message_type")
                
        except Exception as e:
            logger.error(f"处理send_msg请求失败: {e}")
            self.websocket_client.send_api_response(echo, None, 1500, str(e))
    
    def _handle_send_private_msg(self, params: Dict[str, Any], echo: str):
        """处理发送私聊消息请求
        
        Args:
            params: 请求参数
            echo: 请求echo
        """
        try:
            user_id = params.get('user_id', '')
            message = params.get('message', '')
            auto_escape = params.get('auto_escape', False)
            
            if not user_id:
                self.websocket_client.send_api_response(echo, None, 1400, "user_id is required")
                return
                
            if not message:
                self.websocket_client.send_api_response(echo, None, 1400, "message is required")
                return
                
            # 查找对应的微信用户
            target_user = self._find_user_by_id(user_id)
            if not target_user:
                logger.warning(f"⚠️  未找到用户ID: {user_id}")
                self.websocket_client.send_api_response(echo, None, 1404, "user not found")
                return
                
            # 解析消息内容
            wechat_msg = self._parse_onebot_message_content(message, user_id, auto_escape)
            
            # 发送消息到微信
            success = self._send_to_wechat(target_user, wechat_msg)
            
            if success:
                # 发送成功响应
                message_id = int(time.time() * 1000)  # 使用毫秒时间戳
                self.websocket_client.send_api_response(echo, {"message_id": message_id})
                
                # 记录已发送的消息
                self.sent_messages[message_id] = time.time()
            else:
                # 发送失败响应
                self.websocket_client.send_api_response(echo, None, 1500, "send failed")
                
        except Exception as e:
            logger.error(f"处理发送私聊消息失败: {e}")
            self.websocket_client.send_api_response(echo, None, 1500, str(e))
            
    def _handle_forward_msg(self, params: Dict[str, Any], echo: str, group: bool = False):
        """把 OneBot 合并转发摊平成纯文本，再按普通消息发出

        微信这边的发送链路（_send_to_wechat）只认纯文本/图片/文件，
        因此这里把转发节点里的文本拼起来当一条普通消息发出去。
        """
        try:
            uid = params.get('group_id' if group else 'user_id', '')
            nodes = params.get('messages') or []
            parts = []
            for node in nodes:
                data = node.get('data', node) if isinstance(node, dict) else {}
                content = data.get('content')
                if isinstance(content, str):
                    parts.append(content)
                    continue
                for seg in (content or []):
                    if not isinstance(seg, dict):
                        continue
                    t = seg.get('type')
                    d = seg.get('data') or {}
                    if t == 'text':
                        parts.append(str(d.get('text', '')))
                    elif t == 'image':
                        parts.append('[图片]')
                    elif t == 'face':
                        parts.append('[表情]')
                    elif t in ('record', 'voice'):
                        parts.append('[语音]')
            text = "\n".join([p for p in parts if p])
            if not text:
                self.websocket_client.send_api_response(echo, None, 1400, "empty forward message")
                return
            logger.info(f"合并转发已摊平为文本（{len(text)} 字），发给 {uid}")
            self._handle_send_private_msg({'user_id': uid, 'message': text}, echo)
        except Exception as e:
            logger.error(f"处理合并转发失败: {e}")
            self.websocket_client.send_api_response(echo, None, 1500, str(e))

    def _handle_api_response(self, response: Dict[str, Any]):
        """处理API响应
        
        Args:
            response: API响应
        """
        try:
            echo = response.get('echo', '')
            status = response.get('status', 'unknown')
            retcode = response.get('retcode', -1)
            
            logger.info(f"收到API响应: echo={echo}, status={status}, retcode={retcode}")
            
        except Exception as e:
            logger.error(f"处理API响应失败: {e}")
            
    def _handle_reply_message(self, message: Dict[str, Any]):
        """处理回复消息
        
        Args:
            message: 回复消息
        """
        try:
            # 尝试解析为发送消息的请求
            if 'user_id' in message and ('message' in message or 'content' in message):
                user_id = message.get('user_id', '')
                content = message.get('message', message.get('content', ''))
                
                # 查找对应的微信用户
                target_user = self._find_user_by_id(user_id)
                if not target_user:
                    logger.warning(f"⚠️  未找到用户ID: {user_id}")
                    return
                    
                # 构造微信消息
                wechat_msg = {
                    'content': content,
                    'message_type': 'text',
                    'timestamp': int(time.time())
                }
                
                # 发送到微信
                self._send_to_wechat(target_user, wechat_msg)
            else:
                logger.warning(f"⚠️  无法解析回复消息: {message}")
                
        except Exception as e:
            logger.error(f"❌ 处理回复消息失败: {e}")
            
    def _find_user_by_id(self, user_id: str) -> Optional[str]:
        """根据用户ID查找微信用户昵称
        
        Args:
            user_id: 用户ID
            
        Returns:
            微信用户昵称，如果未找到则返回None
        """
        try:
            # 从配置中查找用户映射
            monitored_users = self.config_manager.get('wechat.monitor_users', [])
            
            for user in monitored_users:
                if isinstance(user, dict) and str(user.get('user_id')) == str(user_id):
                    return user.get('nickname')
                    
            # 如果没有找到映射，尝试直接使用user_id作为昵称
            return user_id
            
        except Exception as e:
            logger.error(f"查找用户失败: {e}")
            return None
            
    def _send_to_wechat(self, target_user: str, wechat_msg: Dict[str, Any]) -> bool:
        """发送消息到微信
        
        Args:
            target_user: 目标用户昵称
            wechat_msg: 微信消息
            
        Returns:
            是否发送成功
        """
        _dbg("HANDLE", "target=%r type=%r" % (target_user, wechat_msg.get('message_type')))
        try:
            message_type = wechat_msg.get('message_type', 'text')
            
            if message_type == 'text':
                # 发送文本消息
                content = wechat_msg.get('content', '')
                success = self.wechat_monitor.send_message(target_user, content)
                
            elif message_type == 'image':
                # 发送图片消息
                files = wechat_msg.get('files', [])
                if files:
                    image_path = files[0]
                    success = self.wechat_monitor.send_image(target_user, image_path)
                else:
                    logger.warning("图片消息缺少文件路径")
                    success = False
                    
            elif message_type == 'file':
                # 发送文件消息
                files = wechat_msg.get('files', [])
                if files:
                    file_path = files[0]
                    success = self.wechat_monitor.send_file(target_user, file_path)
                else:
                    logger.warning("文件消息缺少文件路径")
                    success = False
                    
            elif message_type == 'voice':
                # 发送语音消息
                files = wechat_msg.get('files', [])
                if files:
                    voice_path = files[0]
                    success = self.wechat_monitor.send_message(target_user, voice_path, msg_type='voice')
                else:
                    logger.warning("语音消息缺少文件路径")
                    success = False
                    
            else:
                # 其他类型，当作文本发送
                content = wechat_msg.get('content', str(wechat_msg))
                success = self.wechat_monitor.send_message(target_user, content)
                
            if success:
                logger.info(f"✅ 消息已发送: {target_user}")
            else:
                logger.error(f"❌ 发送失败: {target_user}")
                
            return success
            
        except Exception as e:
            logger.error(f"❌ 发送消息到微信失败: {e}")
            return False
            
    def _download_file(self, url: str, filename: str = None) -> Optional[str]:
        """下载文件到本地
        
        Args:
            url: 文件URL
            filename: 文件名（可选）
            
        Returns:
            本地文件路径，如果下载失败则返回None
        """
        try:
            if not filename:
                # 从URL中提取文件名
                filename = url.split('/')[-1]
                if '?' in filename:
                    filename = filename.split('?')[0]
                if not filename:
                    filename = f"download_{int(time.time())}"
                    
            file_path = self.download_cache_dir / filename
            
            # 下载文件
            response = requests.get(url, timeout=30)
            response.raise_for_status()
            
            with open(file_path, 'wb') as f:
                f.write(response.content)
                
            logger.info(f"文件下载成功: {file_path}")
            return str(file_path)
            
        except Exception as e:
            logger.error(f"下载文件失败: {e}")
            return None
            
    def _parse_onebot_message_content(self, message, user_id: str, auto_escape: bool = False) -> Dict[str, Any]:
        """解析OneBotV11消息内容
        
        Args:
            message: 消息内容，可能是字符串、数组或CQ码
            user_id: 用户ID
            auto_escape: 是否自动转义CQ码
            
        Returns:
            微信消息格式
        """
        try:
            # 构造OneBotV11消息格式
            onebot_msg = {
                'user_id': user_id,
                'message': message,
                'time': int(time.time())
            }
            
            # 如果auto_escape为True，将消息作为纯文本处理
            if auto_escape and isinstance(message, str):
                onebot_msg['message'] = [{
                    'type': 'text',
                    'data': {'text': message}
                }]
            elif isinstance(message, str):
                # 解析CQ码格式的字符串消息
                onebot_msg['message'] = self._parse_cq_code(message)
            
            # 使用转换器转换为微信格式
            wechat_msg = self.onebot_converter.onebot_to_wechat(onebot_msg)
            
            return wechat_msg
            
        except Exception as e:
            logger.error(f"❌ 解析OneBotV11消息失败: {e}")
            # 返回错误消息
            return {
                'content': f'[消息解析失败: {e}]',
                'message_type': 'text',
                'timestamp': int(time.time())
            }
            
    def _parse_cq_code(self, message: str) -> List[Dict[str, Any]]:
        """解析CQ码格式的消息
        
        Args:
            message: 包含CQ码的消息字符串
            
        Returns:
            OneBotV11消息段数组
        """
        import re
        
        segments = []
        last_end = 0
        
        # CQ码正则表达式
        cq_pattern = r'\[CQ:([^,\]]+)(?:,([^\]]+))?\]'
        
        for match in re.finditer(cq_pattern, message):
            start, end = match.span()
            
            # 添加CQ码前的文本
            if start > last_end:
                text = message[last_end:start]
                if text:
                    segments.append({
                        'type': 'text',
                        'data': {'text': text}
                    })
            
            # 解析CQ码
            cq_type = match.group(1)
            cq_params_str = match.group(2) or ''
            
            # 解析参数
            cq_data = {}
            if cq_params_str:
                for param in cq_params_str.split(','):
                    if '=' in param:
                        key, value = param.split('=', 1)
                        cq_data[key] = value
            
            segments.append({
                'type': cq_type,
                'data': cq_data
            })
            
            last_end = end
        
        # 添加最后的文本
        if last_end < len(message):
            text = message[last_end:]
            if text:
                segments.append({
                    'type': 'text',
                    'data': {'text': text}
                })
        
        # 如果没有找到CQ码，整个消息作为文本
        if not segments:
            segments.append({
                'type': 'text',
                'data': {'text': message}
            })
        
        return segments
        
    def _cleanup_cache(self):
        """清理过期的消息缓存"""
        try:
            current_time = time.time()
            
            # 检查是否需要清理
            if current_time - self.last_cleanup < self.cache_cleanup_interval:
                return
                
            # 清理过期的消息记录（保留1小时）
            expire_time = current_time - 3600
            expired_keys = []
            
            for message_id, timestamp in self.sent_messages.items():
                if timestamp < expire_time:
                    expired_keys.append(message_id)
                    
            for key in expired_keys:
                del self.sent_messages[key]
                
            if expired_keys:
                logger.info(f"清理了 {len(expired_keys)} 条过期消息记录")
                
            self.last_cleanup = current_time
            
        except Exception as e:
            logger.error(f"清理缓存失败: {e}")
            
    def get_status(self) -> Dict[str, Any]:
        """获取消息处理器状态
        
        Returns:
            状态信息
        """
        return {
            'is_running': self.is_running,
            'message_queue_size': self.message_queue.qsize(),
            'sent_messages_count': len(self.sent_messages),
            'last_cleanup': self.last_cleanup
        }
        
    def add_user_mapping(self, user_id: str, nickname: str):
        """添加用户ID到昵称的映射
        
        Args:
            user_id: 用户ID
            nickname: 微信昵称
        """
        try:
            monitored_users = self.config_manager.get('wechat.monitor_users', [])
            
            # 检查是否已存在
            for user in monitored_users:
                if str(user.get('user_id')) == str(user_id):
                    user['nickname'] = nickname
                    self.config_manager.save_config()
                    logger.info(f"更新用户映射: {user_id} -> {nickname}")
                    return
                    
            # 添加新映射
            monitored_users.append({
                'user_id': user_id,
                'nickname': nickname,
                'enabled': True
            })
            
            self.config_manager.set('wechat.monitor_users', monitored_users)
            self.config_manager.save_config()
            
            logger.info(f"添加用户映射: {user_id} -> {nickname}")
            
        except Exception as e:
            logger.error(f"添加用户映射失败: {e}")