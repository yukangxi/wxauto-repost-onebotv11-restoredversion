#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
微信窗口控制模块
实现定时最小化和恢复微信窗口功能，用于规避微信风控
"""

import time
import threading
import win32gui
import win32con
from typing import Optional, Callable

try:
    from astrbot.api import logger
except ImportError:
    # 独立运行模式的简单日志记录器
    class SimpleLogger:
        def info(self, msg): print(f"[INFO] {msg}")
        def error(self, msg): print(f"[ERROR] {msg}")
        def warning(self, msg): print(f"[WARNING] {msg}")
        def debug(self, msg): print(f"[DEBUG] {msg}")
    logger = SimpleLogger()

class WindowController:
    """微信窗口控制器"""
    
    def __init__(self, config_manager):
        """初始化窗口控制器
        
        Args:
            config_manager: 配置管理器
        """
        self.config_manager = config_manager
        self.running = False
        self.timer_thread = None
        self.wechat_hwnds = []  # 改为列表存储所有微信窗口句柄
        self._lock = threading.Lock()
        self.wechat_window_found = False
        
    def start(self) -> bool:
        """启动定时最小化功能
        
        Returns:
            是否启动成功
        """
        if self.running:
            logger.info("微信窗口控制器已在运行中")
            return True
            
        # 检查是否启用了定时最小化功能
        if not self.config_manager.get('wechat.window_minimize.enabled', False):
            logger.info("微信窗口定时最小化功能未启用")
            return False
            
        try:
            # 查找微信窗口
            logger.info("正在查找微信窗口...")
            if not self._find_wechat_windows():
                logger.error("未找到微信窗口，请确保微信已启动")
                return False
            logger.info("微信窗口查找成功")
                
            self.running = True
            
            # 启动定时器线程
            self.timer_thread = threading.Thread(target=self._timer_loop, daemon=True)
            self.timer_thread.start()
            
            interval = self.config_manager.get('wechat.window_minimize.interval', 3600)
            logger.info(f"微信窗口定时最小化功能已启动，间隔: {interval}秒")
            return True
            
        except Exception as e:
            logger.error(f"启动微信窗口控制器失败: {e}")
            self.running = False
            return False
            
    def stop(self) -> bool:
        """停止定时最小化功能
        
        Returns:
            是否停止成功
        """
        if not self.running:
            return True
            
        try:
            self.running = False
            
            # 等待定时器线程结束
            if self.timer_thread and self.timer_thread.is_alive():
                self.timer_thread.join(timeout=2)
                
            logger.info("微信窗口定时最小化功能已停止")
            return True
            
        except Exception as e:
            logger.error(f"停止微信窗口控制器失败: {e}")
            return False
            
    def is_running(self) -> bool:
        """检查是否正在运行
        
        Returns:
            是否正在运行
        """
        return self.running
        
    def _find_wechat_windows(self) -> bool:
        """查找所有微信窗口
        
        Returns:
            是否找到微信窗口
        """
        try:
            # 清空之前的窗口列表
            self.wechat_hwnds = []
            
            # 微信窗口的类名和标题模式
            wechat_class_names = ['WeChatMainWndForPC', 'ChatWnd', 'Qt51514QWindowIcon']
            wechat_titles = ['微信', 'WeChat']
            
            def enum_windows_callback(hwnd, param):
                if win32gui.IsWindowVisible(hwnd):
                    class_name = win32gui.GetClassName(hwnd)
                    window_text = win32gui.GetWindowText(hwnd)
                    
                    # 检查是否为微信窗口
                    if (class_name in wechat_class_names or 
                        any(title in window_text for title in wechat_titles)):
                        # 添加到窗口列表中，不停止枚举
                        self.wechat_hwnds.append({
                            'hwnd': hwnd,
                            'class_name': class_name,
                            'window_text': window_text
                        })
                return True  # 继续枚举所有窗口
                
            win32gui.EnumWindows(enum_windows_callback, None)
            
            if self.wechat_hwnds:
                logger.info(f"找到 {len(self.wechat_hwnds)} 个微信窗口:")
                for i, window_info in enumerate(self.wechat_hwnds):
                    logger.info(f"  [{i+1}] {window_info['window_text']} (类名: {window_info['class_name']}, HWND: {window_info['hwnd']})")
                self.wechat_window_found = True
                return True
            else:
                logger.warning("未找到微信窗口")
                self.wechat_window_found = False
                return False
                
        except Exception as e:
            logger.error(f"查找微信窗口失败: {e}")
            return False
            
    def _timer_loop(self):
        """定时器循环"""
        while self.running:
            try:
                # 获取配置
                interval = self.config_manager.get('wechat.window_minimize.interval', 3600)
                restore_delay = self.config_manager.get('wechat.window_minimize.restore_delay', 1)
                
                # 等待指定间隔
                for _ in range(int(interval)):
                    if not self.running:
                        return
                    time.sleep(1)
                    
                # 执行最小化和恢复操作
                if self.running:
                    self._minimize_and_restore(restore_delay)
                    
            except Exception as e:
                logger.error(f"定时器循环异常: {e}")
                time.sleep(10)  # 出错后等待10秒再继续
                
    def _minimize_and_restore(self, restore_delay: float):
        """最小化并恢复所有微信窗口
        
        Args:
            restore_delay: 恢复延迟时间(秒)
        """
        with self._lock:
            try:
                # 重新查找微信窗口（防止窗口句柄失效）
                if not self._find_wechat_windows():
                    logger.warning("执行最小化操作时未找到微信窗口")
                    return
                
                # 存储每个窗口的原始状态
                window_states = []
                valid_windows = []
                
                # 检查所有窗口是否有效，并记录状态
                for window_info in self.wechat_hwnds:
                    hwnd = window_info['hwnd']
                    if win32gui.IsWindow(hwnd):
                        try:
                            placement = win32gui.GetWindowPlacement(hwnd)
                            current_state = placement[1]
                            window_states.append(current_state)
                            valid_windows.append(window_info)
                        except Exception as e:
                            logger.warning(f"获取窗口状态失败 {window_info['window_text']}: {e}")
                    else:
                        logger.warning(f"窗口句柄无效: {window_info['window_text']} (HWND: {hwnd})")
                
                if not valid_windows:
                    logger.warning("没有有效的微信窗口可以操作")
                    return
                
                logger.info(f"开始执行 {len(valid_windows)} 个微信窗口的最小化操作")
                
                # 最小化所有有效窗口
                for i, window_info in enumerate(valid_windows):
                    try:
                        hwnd = window_info['hwnd']
                        win32gui.ShowWindow(hwnd, win32con.SW_MINIMIZE)
                        logger.debug(f"窗口已最小化: {window_info['window_text']}")
                    except Exception as e:
                        logger.error(f"最小化窗口失败 {window_info['window_text']}: {e}")
                
                # 等待指定时间
                time.sleep(restore_delay)
                
                # 恢复所有窗口到之前的状态
                for i, window_info in enumerate(valid_windows):
                    try:
                        hwnd = window_info['hwnd']
                        current_state = window_states[i]
                        
                        if current_state == win32con.SW_SHOWMAXIMIZED:
                            # 如果之前是最大化状态，恢复为最大化
                            win32gui.ShowWindow(hwnd, win32con.SW_SHOWMAXIMIZED)
                            logger.debug(f"窗口已恢复为最大化状态: {window_info['window_text']}")
                        else:
                            # 否则恢复为正常状态
                            win32gui.ShowWindow(hwnd, win32con.SW_RESTORE)
                            logger.debug(f"窗口已恢复为正常状态: {window_info['window_text']}")
                        
                        # 将窗口置于前台（只对主窗口执行，避免频繁切换）
                        if any(k in window_info['class_name'] for k in ('WeChatMainWndForPC','Qt51514QWindowIcon')):
                            win32gui.SetForegroundWindow(hwnd)
                            
                    except Exception as e:
                        logger.error(f"恢复窗口失败 {window_info['window_text']}: {e}")
                
                logger.info(f"所有微信窗口最小化和恢复操作完成 (处理了 {len(valid_windows)} 个窗口)")
                
            except Exception as e:
                logger.error(f"执行最小化和恢复操作失败: {e}")
                
    def manual_minimize_restore(self) -> bool:
        """手动执行一次最小化和恢复操作
        
        Returns:
            是否执行成功
        """
        try:
            restore_delay = self.config_manager.get('wechat.window_minimize.restore_delay', 1)
            self._minimize_and_restore(restore_delay)
            return True
        except Exception as e:
            logger.error(f"手动执行最小化操作失败: {e}")
            return False
            
    def minimize_and_restore(self) -> bool:
        """执行一次最小化和恢复操作（API接口用）
        
        Returns:
            是否执行成功
        """
        return self.manual_minimize_restore()
            
    def get_status(self) -> dict:
        """获取窗口控制器状态
        
        Returns:
            状态信息字典
        """
        # 构建窗口信息列表
        windows_info = []
        for window_info in self.wechat_hwnds:
            windows_info.append({
                'hwnd': window_info['hwnd'],
                'class_name': window_info['class_name'],
                'window_text': window_info['window_text'],
                'is_valid': win32gui.IsWindow(window_info['hwnd']) if window_info['hwnd'] else False
            })
        
        return {
            'running': self.running,
            'wechat_window_found': len(self.wechat_hwnds) > 0,
            'wechat_windows_count': len(self.wechat_hwnds),
            'wechat_windows': windows_info,
            'config': {
                'enabled': self.config_manager.get('wechat.window_minimize.enabled', False),
                'interval': self.config_manager.get('wechat.window_minimize.interval', 3600),
                'restore_delay': self.config_manager.get('wechat.window_minimize.restore_delay', 1)
            }
        }