#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
微信消息监听模块
使用wxauto库监听微信消息
"""

import time
import threading
from typing import List, Dict, Any, Optional, Callable
from pathlib import Path
import os

def _dbg(tag, msg):
    try:
        import datetime as _dt
        with open(r"C:\wx_plugin_debug.txt", "a", encoding="utf-8") as _f:
            _f.write("%s [%s] %s\n" % (_dt.datetime.now().strftime("%H:%M:%S"), tag, msg))
    except Exception:
        pass



try:
    from astrbot.api import logger
except ImportError:
    # 独立运行模式的简单日志记录器
    class SimpleLogger:
        def info(self, msg): print(f"[INFO] {msg}")
        def error(self, msg): print(f"[ERROR] {msg}")
        def warning(self, msg): print(f"[WARNING] {msg}")
    logger = SimpleLogger()

try:
    import pythoncom
    from wechatauto import WeChat
except ImportError:
    logger.warning("警告: wechatauto库未安装，请运行 pip install wxauto")
    WeChat = None
    pythoncom = None

class WeChatMonitor:
    """微信消息监听器"""
    
    def __init__(self, config_manager):
        """初始化微信监听器
        
        Args:
            config_manager: 配置管理器
        """
        self.config_manager = config_manager
        self.wechat = None  # 修复：统一使用wechat属性
        self.is_running = False
        self.monitor_thread = None
        
        # 消息回调函数
        self.message_callback = None
        
        # 运行状态
        self.running = False
        
        # 监听的用户列表
        self.monitored_users = []
        
        # 消息去重缓存（防止处理自己发送的消息）
        self.sent_message_cache = {}  # content -> timestamp
        self._seen_msg = {}           # message_id -> timestamp（收消息去重）
        self._listen_all_ok = False   # 是否用上了全局监听
        self.cache_expire_time = 30  # 缓存过期时间（秒）
        
        # 文件保存目录
        project_root = Path(__file__).parent.parent
        self.image_save_dir = project_root / self.config_manager.get('message.image_save_dir', 'cache/images')
        self.file_save_dir = project_root / self.config_manager.get('message.file_save_dir', 'cache/files')
        self.voice_save_dir = project_root / self.config_manager.get('message.voice_save_dir', 'cache/voices')
        
        # 创建保存目录
        self.image_save_dir.mkdir(parents=True, exist_ok=True)
        self.file_save_dir.mkdir(parents=True, exist_ok=True)
        self.voice_save_dir.mkdir(parents=True, exist_ok=True)
        
    def set_message_callback(self, callback):
        """设置消息回调函数
        
        Args:
            callback: 消息回调函数
        """
        self.message_callback = callback
        
    def _create_cache_dirs(self):
        """创建缓存目录"""
        project_root = Path(__file__).parent.parent
        
        # 图片缓存目录
        image_cache_dir = project_root / self.config_manager.get('message.image_cache_dir', 'cache/images')
        image_cache_dir.mkdir(parents=True, exist_ok=True)
        
        # 文件缓存目录
        file_cache_dir = project_root / self.config_manager.get('message.file_cache_dir', 'cache/files')
        file_cache_dir.mkdir(parents=True, exist_ok=True)
        
    def start(self) -> bool:
        """启动微信监听
        
        Returns:
            是否启动成功
        """
        if self.running:
            logger.info("微信监听器已在运行中")
            return True
            
        if WeChat is None:
            logger.error("错误: wechatauto库未安装，无法启动微信监听")
            return False
            
        try:
            # 初始化COM组件
            if pythoncom:
                pythoncom.CoInitialize()
            
            # 初始化微信客户端
            self.wechat = WeChat()
            
            # 检查微信是否已登录
            if not self._check_wechat_login():
                logger.error("错误: 微信未登录或无法连接")
                self.running = False
                return False
                
            self.running = True
            
            # 启动监听线程
            self.monitor_thread = threading.Thread(target=self._monitor_loop, daemon=True)
            self.monitor_thread.start()
            
            logger.info("微信监听器启动成功")
            return True
            
        except Exception as e:
            logger.error(f"启动微信监听器失败: {e}")
            self.running = False
            return False
            
    def stop(self) -> bool:
        """停止微信监听
        
        Returns:
            是否停止成功
        """
        if not self.running:
            logger.info("微信监听器未在运行")
            return True
            
        self.running = False
        
        # 等待监听线程结束
        if self.monitor_thread and self.monitor_thread.is_alive():
            self.monitor_thread.join(timeout=5)
            
        # 清理COM组件
        if pythoncom:
            try:
                pythoncom.CoUninitialize()
            except:
                pass
            
        self.wechat = None
        logger.info("微信监听器已停止")
        return True
        
    def is_running(self) -> bool:
        """检查是否正在运行
        
        Returns:
            是否正在运行
        """
        return self.running
        
    def _check_wechat_login(self) -> bool:
        """检查微信是否已登录
        
        Returns:
            是否已登录
        """
        try:
            # 简单检查微信客户端是否可用
            # 如果WeChat对象创建成功，通常表示微信已登录
            if self.wechat is not None:
                logger.info("微信客户端连接成功")
                return True
            return False
        except Exception as e:
            logger.error(f"检查微信登录状态失败: {e}")
            return False
            
    def _on_message_callback(self, msg, chat):
        """消息回调函数"""
        try:
            # 获取聊天对象的昵称
            if hasattr(chat, 'nickname'):
                username = chat.nickname
            elif hasattr(chat, 'name'):
                username = chat.name
            else:
                # 从字符串表示中提取昵称
                chat_str = str(chat)
                if '("' in chat_str and '")' in chat_str:
                    username = chat_str.split('("')[1].split('")')[0]
                else:
                    username = chat_str
            
            # 去重：同一条消息 20 秒内只处理一次
            try:
                mid = str(self._get_message_id(msg))
                now = time.time()
                for k in [k for k, v in list(self._seen_msg.items()) if now - v > 60]:
                    del self._seen_msg[k]
                if mid and mid in self._seen_msg:
                    logger.info(f"⏭️  跳过重复消息: {str(getattr(msg, 'content', ''))[:25]}")
                    return
                self._seen_msg[mid] = now
            except Exception:
                pass

            # 按配置过滤：monitor_users 为空则全部处理，否则只处理列出的会话
            try:
                mus = self.config_manager.get('wechat.monitor_users', []) or []
                names = set()
                for u in mus:
                    if isinstance(u, str):
                        names.add(u)
                    elif isinstance(u, dict) and u.get('nickname'):
                        names.add(u.get('nickname'))
                # 暂时不丢弃，只记录真实会话名，便于拿到准确名字后再过滤
                if names and username not in names:
                    logger.info(f"ℹ️  会话名不在监听列表（仍放行）：真实名={username!r}  列表={sorted(names)!r}")
                else:
                    logger.info(f"✅ 会话名匹配：{username!r}")
            except Exception:
                pass

            _dbg("RECV", "用户名=%r 内容=%r" % (username, str(getattr(msg,"content",""))[:40]))

            # 跳过系统消息
            if hasattr(msg, 'type') and msg.type == 'sys':
                return
            
            # 获取消息内容
            content = msg.content if hasattr(msg, 'content') else str(msg)
            
            # 过滤wxauto库内部的调试消息
            if self._is_wxauto_debug_message(content):
                logger.info(f"🚫 过滤wxauto调试消息: {content[:30]}{'...' if len(content) > 30 else ''}")
                return
                
            logger.info(f"收到来自 {username} 的消息: {content}")
            
            # 处理消息
            self._process_message(username, msg)
            
        except Exception as e:
            logger.error(f"处理回调消息时出错: {e}")
    
    def _monitor_loop(self):
        """监听循环"""
        try:
            # 在监听线程中初始化COM组件
            if pythoncom:
                pythoncom.CoInitialize()
                
            logger.info("开始监听微信消息...")
            
            # 添加监听用户
            self._ensure_window_visible()
            self._setup_listeners()
            
            # 使用回调机制时，只需要保持程序运行
            while self.is_running:
                time.sleep(1)  # 保持程序运行
                    
        except Exception as e:
            logger.error(f"监听循环异常退出: {e}")
        finally:
            # 清理COM组件
            if pythoncom:
                try:
                    pythoncom.CoUninitialize()
                except:
                    pass
                

    def _ensure_window_visible(self):
        """把微信主窗口摆回可见区域（否则发送按钮会跑到屏幕外，导致发不出消息）"""
        try:
            import ctypes
            from ctypes import wintypes as _w
            u32 = ctypes.windll.user32
            EnumWindows = u32.EnumWindows
            CB = ctypes.WINFUNCTYPE(_w.BOOL, _w.HWND, _w.LPARAM)
            targets = []
            def _cb(h, l):
                pid = _w.DWORD(0)
                u32.GetWindowThreadProcessId(h, ctypes.byref(pid))
                cls = ctypes.create_unicode_buffer(256)
                u32.GetClassNameW(h, cls, 256)
                if "QWindowIcon" in cls.value and u32.IsWindowVisible(h):
                    targets.append(h)
                return True
            EnumWindows(CB(_cb), 0)
            if not targets:
                logger.warning("窗口归位：没找到微信主窗口")
                return
            h = targets[0]
            sw = u32.GetSystemMetrics(0)
            sh = u32.GetSystemMetrics(1)
            rect = _w.RECT()
            u32.GetWindowRect(h, ctypes.byref(rect))
            x0, y0, x1, y1 = rect.left, rect.top, rect.right, rect.bottom
            bad = (x0 < 0 or y0 < 0 or x1 > sw or y1 > sh)
            if not bad:
                logger.info(f"窗口位置正常: ({x0},{y0})-({x1},{y1})")
                return
            w = min(1000, sw - 10)
            hh = min(740, sh - 10)
            u32.ShowWindow(h, 9)          # SW_RESTORE
            time.sleep(0.4)
            u32.SetWindowPos(h, 0, 5, 5, w, hh, 0x0040)
            time.sleep(0.5)
            u32.GetWindowRect(h, ctypes.byref(rect))
            logger.info(f"窗口归位: ({x0},{y0})-({x1},{y1}) -> ({rect.left},{rect.top})-({rect.right},{rect.bottom})  屏幕 {sw}x{sh}")
        except Exception as e:
            logger.error(f"窗口归位失败: {e}")

    def _setup_listeners(self):
        """设置监听用户"""
        try:
            # 获取监听用户列表
            monitor_users = self.config_manager.get('wechat.monitor_users', [])
            
            # 优先使用全局监听：一次覆盖全部会话（含群聊，并能自动发现新群）
            try:
                r = self.wechat.AddListenAll(callback=self._on_message_callback, discover=True)
                self._listen_all_ok = True
                logger.info(f"已开启全局监听（含群聊）: {r}")
            except Exception as e:
                self._listen_all_ok = False
                logger.error(f"AddListenAll 失败，继续用逐个监听: {e}")
            # 双路：同时逐个挂上名单里的会话（重复由去重逻辑挡住）

            if not monitor_users:
                logger.warning("未配置监听用户")
                return
                
            # 为每个用户添加监听
            for user in monitor_users:
                try:
                    # 支持两种格式：字符串和对象
                    if isinstance(user, str):
                        nickname = user
                    elif isinstance(user, dict):
                        nickname = user.get('nickname', '')
                    else:
                        continue
                        
                    if nickname:
                        # 使用回调函数方式监听消息
                        self.wechat.AddListenChat(nickname=nickname, callback=self._on_message_callback)
                        logger.info(f"已添加监听用户: {nickname}")
                except Exception as e:
                    logger.error(f"添加监听用户失败: {e}")
                
        except Exception as e:
            logger.error(f"设置监听用户失败: {e}")
            
    def _get_message_timestamp(self, message) -> int:
        """获取消息时间戳
        
        Args:
            message: 消息对象
            
        Returns:
            消息时间戳
        """
        try:
            if hasattr(message, 'time'):
                return int(message.time)
            elif hasattr(message, 'timestamp'):
                return int(message.timestamp)
            else:
                return int(time.time())
        except:
            return int(time.time())
        
    def _get_user_id_by_nickname(self, nickname: str) -> str:
        """根据昵称获取用户ID
        
        Args:
            nickname: 用户昵称
            
        Returns:
            用户ID（数字字符串）
        """
        try:
            monitor_users = self.config_manager.get('wechat.monitor_users', [])
            
            for user in monitor_users:
                if isinstance(user, dict):
                    if user.get('nickname') == nickname:
                        return str(user.get('user_id', nickname))
                elif isinstance(user, str) and user == nickname:
                    # 如果是字符串格式，返回昵称作为用户ID
                    return nickname
                    
            # 如果没找到，返回昵称
            return nickname
            
        except Exception as e:
            logger.error(f"查找用户ID失败: {e}")
            return nickname
            
    def _get_message_id(self, message) -> str:
        """获取消息唯一标识
        
        Args:
            message: 消息对象
            
        Returns:
            消息唯一标识
        """
        # 尝试不同的字段作为消息ID
        try:
            if hasattr(message, 'id'):
                return str(message.id)
            elif hasattr(message, 'time'):
                return str(message.time)
            elif hasattr(message, 'content'):
                return str(hash(f"{message.content}_{self._get_message_timestamp(message)}"))
            else:
                return str(hash(f"{str(message)}_{self._get_message_timestamp(message)}"))
        except:
            return str(hash(f"{str(message)}_{int(time.time())}"))
            
    def _process_message(self, username: str, message):
        """处理消息
        
        Args:
            username: 用户昵称
            message: 消息对象
        """
        try:
            # 直接解析消息内容，因为GetListenMessage只返回新消息
            parsed_msg = self._parse_message(username, message)
            
            if parsed_msg:
                # 检查是否是刚刚发送的消息（防止循环）
                content = parsed_msg.get('content', '')
                raw = parsed_msg.get('raw_message')
                # ① 优先按「消息方向」精确判断（wechatauto 提供 is_self）
                if raw is not None and hasattr(raw, 'is_self'):
                    try:
                        report_self = bool(self.config_manager.get('wechat.report_self', False))
                    except Exception:
                        report_self = False
                    if bool(getattr(raw, 'is_self', False)) and not report_self:
                        logger.info(f"⏭️  跳过自己发送的消息(is_self): {content[:30]}{'...' if len(content) > 30 else ''}")
                        return
                # ② 回退：老式「内容匹配」防循环
                elif self._is_recently_sent_message(content):
                    logger.info(f"⏭️  跳过回显消息: {content[:30]}{'...' if len(content) > 30 else ''}")
                    return
                    
                logger.info(f"📨 {username}: {content[:50]}{'...' if len(content) > 50 else ''}")
                
                # 调用消息回调函数
                if self.message_callback:
                    try:
                        self.message_callback(parsed_msg)
                    except Exception as e:
                        logger.error(f"消息回调执行失败: {e}")
            
        except Exception as e:
            logger.error(f"❌ 处理消息失败: {e}")
            
    def _parse_message(self, username: str, message) -> Optional[Dict[str, Any]]:
        """解析消息
        
        Args:
            username: 用户昵称
            message: 原始消息对象
            
        Returns:
            解析后的消息字典
        """
        try:
            # 根据昵称查找用户ID
            user_id = self._get_user_id_by_nickname(username)
            
            parsed = {
                'user_id': user_id,
                'user_name': username,
                'message_id': self._get_message_id(message),
                'timestamp': self._get_message_timestamp(message),
                'raw_message': message
            }
            
            # 根据消息类型解析内容
            if hasattr(message, 'type'):
                msg_type = message.type
            else:
                msg_type = 'text'  # 默认为文本消息
                
            if msg_type == 'text' or not hasattr(message, 'type'):
                # 文本消息
                content = str(message.content) if hasattr(message, 'content') else str(message)

                # ★ 去掉 wechatauto 群消息自带的「发送者wxid:」前缀
                try:
                    _sw = getattr(message, 'sender_wxid', None)
                    if _sw and content.startswith(_sw):
                        content = content[len(_sw):].lstrip('：: \t\r\n')
                except Exception:
                    pass
                # 兜底：首行形如 "xxxx:"（无空格、较短）则去掉该行
                if '\n' in content:
                    _first, _rest = content.split('\n', 1)
                    _fs = _first.strip()
                    if _fs.endswith(':') and 0 < len(_fs) <= 64 and ' ' not in _fs:
                        content = _rest
                content = content.strip()
                
                # 过滤系统提示消息
                if self._is_system_message(content):
                    logger.info(f"🚫 过滤系统消息: {content[:30]}{'...' if len(content) > 30 else ''}")
                    return None
                
                parsed.update({
                    'message_type': 'text',
                    'content': content
                })
                
            elif msg_type == 'image':
                # 图片消息
                image_path = self._save_image(message)
                parsed.update({
                    'message_type': 'image',
                    'content': '[图片]',
                    'image_path': image_path,
                    'image_url': f'file://{image_path}' if image_path else None
                })
                
            elif msg_type == 'file':
                # 文件消息
                file_path = self._save_file(message)
                parsed.update({
                    'message_type': 'file',
                    'content': '[文件]',
                    'file_path': file_path,
                    'file_name': getattr(message, 'filename', 'unknown_file')
                })
                
            elif msg_type == 'voice':
                # 语音消息
                if self.config_manager.get('message.enable_voice', False):
                    voice_path = self._save_voice(message)
                    parsed.update({
                        'message_type': 'voice',
                        'content': '[语音]',
                        'voice_path': voice_path
                    })
                else:
                    parsed.update({
                        'message_type': 'text',
                        'content': '[语音消息]'
                    })
                    
            else:
                # 其他类型消息
                parsed.update({
                    'message_type': 'text',
                    'content': f'[{msg_type}消息]'
                })
                
            return parsed
            
        except Exception as e:
            logger.error(f"❌ 解析消息失败: {e}")
            return None
            
    def _save_image(self, message) -> Optional[str]:
        """保存图片
        
        Args:
            message: 消息对象
            
        Returns:
            保存的图片路径
        """
        try:
            if not self.config_manager.get('message.enable_image', True):
                return None
                
            # 获取图片缓存目录
            project_root = Path(__file__).parent.parent
            cache_dir = project_root / self.config_manager.get('message.image_cache_dir', 'cache/images')
            
            # 生成文件名
            timestamp = int(time.time())
            filename = f"image_{timestamp}.jpg"
            file_path = cache_dir / filename
            
            # 保存图片（这里需要根据wxauto的实际API调整）
            if hasattr(message, 'save_image'):
                message.save_image(str(file_path))
                return str(file_path)
            elif hasattr(message, 'image_path'):
                # 如果消息已包含图片路径，直接返回
                return message.image_path
                
            return None
            
        except Exception as e:
            logger.error(f"保存图片失败: {e}")
            return None
            
    def _save_file(self, message) -> Optional[str]:
        """保存文件
        
        Args:
            message: 消息对象
            
        Returns:
            保存的文件路径
        """
        try:
            if not self.config_manager.get('message.enable_file', True):
                return None
                
            # 获取文件缓存目录
            project_root = Path(__file__).parent.parent
            cache_dir = project_root / self.config_manager.get('message.file_cache_dir', 'cache/files')
            
            # 生成文件名
            timestamp = int(time.time())
            original_name = getattr(message, 'filename', f'file_{timestamp}')
            file_path = cache_dir / f"{timestamp}_{original_name}"
            
            # 保存文件（这里需要根据wxauto的实际API调整）
            if hasattr(message, 'save_file'):
                message.save_file(str(file_path))
                return str(file_path)
            elif hasattr(message, 'file_path'):
                return message.file_path
                
            return None
            
        except Exception as e:
            logger.error(f"保存文件失败: {e}")
            return None
            
    def _save_voice(self, message) -> Optional[str]:
        """保存语音
        
        Args:
            message: 消息对象
            
        Returns:
            保存的语音路径
        """
        try:
            # 获取文件缓存目录
            project_root = Path(__file__).parent.parent
            cache_dir = project_root / self.config_manager.get('message.file_cache_dir', 'cache/files')
            
            # 生成文件名
            timestamp = int(time.time())
            filename = f"voice_{timestamp}.wav"
            file_path = cache_dir / filename
            
            # 保存语音（这里需要根据wxauto的实际API调整）
            if hasattr(message, 'save_voice'):
                message.save_voice(str(file_path))
                return str(file_path)
            elif hasattr(message, 'voice_path'):
                return message.voice_path
                
            return None
            
        except Exception as e:
            logger.error(f"保存语音失败: {e}")
            return None
            
    def _is_recently_sent_message(self, content: str) -> bool:
        """检查消息是否是最近发送的
        
        Args:
            content: 消息内容
            
        Returns:
            是否是最近发送的消息
        """
        try:
            current_time = time.time()
            
            # 清理过期的缓存
            expired_keys = []
            for cached_content, timestamp in self.sent_message_cache.items():
                if current_time - timestamp > self.cache_expire_time:
                    expired_keys.append(cached_content)
                    
            for key in expired_keys:
                del self.sent_message_cache[key]
                
            # 检查是否是最近发送的消息
            return content in self.sent_message_cache
            
        except Exception as e:
            logger.error(f"检查消息缓存失败: {e}")
            return False
            
    def _record_sent_message(self, content: str):
        """记录发送的消息
        
        Args:
            content: 消息内容
        """
        try:
            self.sent_message_cache[content] = time.time()
        except Exception as e:
            logger.error(f"⚠️  记录发送消息失败: {e}")
            
    def _is_wxauto_debug_message(self, content: str) -> bool:
        """判断是否为wxauto库的调试消息
        
        Args:
            content: 消息内容
            
        Returns:
            是否为wxauto调试消息
        """
        try:
            if not content or not content.strip():
                return False
                
            content_clean = content.strip()
            
            # wxauto库调试消息特征
            wxauto_debug_patterns = [
                "[system base]",
                "[time base]",
                "[base消息]",
                "获取到新消息：",
                "以下为新消息",
                "以上为历史消息"
            ]
            
            # 检查是否包含wxauto调试信息
            for pattern in wxauto_debug_patterns:
                if pattern in content_clean:
                    return True
                    
            return False
            
        except Exception as e:
            logger.error(f"⚠️  判断wxauto调试消息失败: {e}")
            return False
    
    def _is_system_message(self, content: str) -> bool:
        """判断是否为系统消息
        
        Args:
            content: 消息内容
            
        Returns:
            是否为系统消息
        """
        try:
            if not content or not content.strip():
                return True
                
            content_clean = content.strip()
            content_lower = content_clean.lower()
            
            # 调试输出
            logger.info(f"🔍 检查消息是否为系统消息: '{content_clean[:50]}{'...' if len(content_clean) > 50 else ''}'")
            
            # 系统消息关键词列表 - 使用更严格的匹配
            system_keywords = [
                "以下为新消息",
                "以上为历史消息", 
                "消息记录",
                "聊天记录", 
                "历史消息",
                "系统消息",
                "新消息",
                "--- 以上为历史消息 ---",
                "--- 以下为新消息 ---",
                "撤回了一条消息",
                "撤回了消息",
                "withdrew a message",
                "base消息",
                "消息提醒",
                "系统提示",
                "消息通知"
            ]
            
            # 检查系统消息关键词 - 精确匹配和包含匹配
            for keyword in system_keywords:
                if keyword.lower() in content_lower:
                    logger.info(f"🚫 匹配到系统消息关键词: '{keyword}'")
                    return True
            
            # 更严格的正则表达式匹配
            import re
            
            # 匹配各种括号格式的消息
            bracket_patterns = [
                r'^\s*\[.*base.*\]\s*$',  # [任何内容base任何内容]
                r'^\s*\[.*消息.*\]\s*$',  # [任何内容消息任何内容]
                r'^\s*\[.*提示.*\]\s*$',  # [任何内容提示任何内容]
                r'^\s*\[.*通知.*\]\s*$',  # [任何内容通知任何内容]
                r'^\s*\[.*记录.*\]\s*$',  # [任何内容记录任何内容]
                r'^\s*\[.*历史.*\]\s*$',  # [任何内容历史任何内容]
                r'^\s*\[.*系统.*\]\s*$',  # [任何内容系统任何内容]
                r'^\s*\[[^\]]{1,20}\]\s*$',  # 短的纯括号消息
                r'^\s*\[.*\]\s*\.{3,}\s*$',  # [任何内容]...
                r'^\s*\[.*\]\s*…+\s*$',  # [任何内容]…
            ]
            
            for pattern in bracket_patterns:
                if re.search(pattern, content_clean, re.IGNORECASE | re.MULTILINE):
                    logger.info(f"🚫 匹配到括号格式系统消息: 模式 '{pattern}'")
                    return True
            
            # 匹配纯符号和省略号消息
            symbol_patterns = [
                r'^\s*\.{3,}\s*$',  # 纯省略号
                r'^\s*…+\s*$',  # 纯中文省略号
                r'^\s*[-=*_]{3,}\s*$',  # 纯分隔符
                r'^\s*[。]{3,}\s*$',  # 纯中文句号
                r'^\s*[\s\.…。\-=*_]+\s*$',  # 只包含空格和符号
            ]
            
            for pattern in symbol_patterns:
                if re.match(pattern, content_clean):
                    logger.info(f"🚫 匹配到符号格式系统消息: 模式 '{pattern}'")
                    return True
            
            # 检查是否包含"新消息"、"历史"等关键词的短消息
            short_system_patterns = [
                r'.*新消息.*',
                r'.*历史.*消息.*',
                r'.*消息.*记录.*',
                r'.*以下.*消息.*',
                r'.*以上.*消息.*',
                r'.*base.*',
            ]
            
            # 对于短消息（少于20个字符）进行更严格的检查
            if len(content_clean) < 20:
                for pattern in short_system_patterns:
                    if re.search(pattern, content_lower):
                        logger.info(f"🚫 匹配到短系统消息: 模式 '{pattern}'")
                        return True
            
            # 注释掉纯数字和短纯字母的过滤，只保留真正的系统消息过滤
            # if re.match(r'^\s*[0-9]+\s*$', content_clean):  # 纯数字
            #     print(f"🚫 匹配到纯数字消息")
            #     return True
                
            # if re.match(r'^\s*[a-zA-Z]+\s*$', content_clean) and len(content_clean.strip()) < 10:  # 短纯字母
            #     print(f"🚫 匹配到短纯字母消息")
            #     return True
            
            logger.info(f"✅ 消息通过系统消息过滤")
            return False
            
        except Exception as e:
            logger.error(f"⚠️  判断系统消息失败: {e}")
            return False
            
    def send_message(self, username: str, content: str, msg_type: str = 'text') -> bool:
        """发送消息给指定用户
        
        Args:
            username: 用户昵称
            content: 消息内容
            msg_type: 消息类型
            
        Returns:
            是否发送成功
        """
        _dbg("SEND", "目标=%r 内容=%r running=%s wechat=%s" % (username, str(content)[:40], self.running, bool(self.wechat)))
        try:
            if not self.wechat or not self.running:
                logger.warning("⚠️  微信监听器未运行")
                _dbg("SEND-FAIL", "监听器未运行")
                return False
                
            # 根据消息类型记录不同的内容用于回显判断
            if msg_type == 'text':
                # 文本消息记录原内容
                self._record_sent_message(content)
                # 发送文本消息
                _dbg("SEND-CALL", "调用 wechat.SendMsg(who=%r)" % (username,))
                self.wechat.SendMsg(content, who=username)
            elif msg_type == 'image':
                # 图片消息记录标准化内容
                self._record_sent_message('[图片]')
                # 发送图片文件
                self.wechat.SendFiles(content, who=username)
            elif msg_type == 'file':
                # 文件消息记录标准化内容
                self._record_sent_message('[文件]')
                # 发送文件
                self.wechat.SendFiles(content, who=username)
            elif msg_type == 'voice':
                # 语音消息记录标准化内容
                if self.config_manager.get('message.enable_voice', False):
                    self._record_sent_message('[语音]')
                else:
                    self._record_sent_message('[语音消息]')
                # 发送语音文件
                self.wechat.SendFiles(content, who=username)
            else:
                # 其他类型当作文本发送
                self._record_sent_message(content)
                self.wechat.SendMsg(content, who=username)
                
            logger.info(f"✅ 发送至 {username}: {content[:30]}{'...' if len(content) > 30 else ''}")
            return True
            
        except Exception as e:
            logger.error(f"❌ 发送消息失败: {e}")
            return False
            
    def send_image(self, username: str, image_path: str) -> bool:
        """发送图片给指定用户
        
        Args:
            username: 用户昵称
            image_path: 图片路径
            
        Returns:
            是否发送成功
        """
        return self.send_message(username, image_path, 'image')
        
    def send_file(self, username: str, file_path: str) -> bool:
        """发送文件给指定用户
        
        Args:
            username: 用户昵称
            file_path: 文件路径
            
        Returns:
            是否发送成功
        """
        return self.send_message(username, file_path, 'file')
            
    def get_user_list(self) -> List[str]:
        """获取微信好友列表
        
        Returns:
            好友昵称列表
        """
        try:
            if not self.wechat:
                return []
                
            # 获取好友列表（这里需要根据wxauto的实际API调整）
            if hasattr(self.wechat, 'GetAllFriends'):
                friends = self.wechat.GetAllFriends()
                return [friend.name for friend in friends if hasattr(friend, 'name')]
            else:
                return []
                
        except Exception as e:
            logger.error(f"获取好友列表失败: {e}")
            return []