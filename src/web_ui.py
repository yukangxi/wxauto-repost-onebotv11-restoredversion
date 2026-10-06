#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Web UI模块
提供Web界面进行配置管理和状态监控
"""

import json
import threading
from flask import Flask, render_template, request, jsonify, send_from_directory
from flask_cors import CORS
from pathlib import Path
import os

class WebUI:
    """Web用户界面"""
    
    def __init__(self, config_manager, wechat_monitor=None, onebot_client=None, websocket_client=None, message_handler=None, window_controller=None):
        """初始化WebUI
        
        Args:
            config_manager: 配置管理器
            wechat_monitor: 微信监听器
            onebot_client: OneBot客户端
            websocket_client: WebSocket客户端
            message_handler: 消息处理器
            window_controller: 窗口控制器
        """
        self.config_manager = config_manager
        self.wechat_monitor = wechat_monitor
        self.onebot_client = onebot_client
        self.websocket_client = websocket_client
        self.message_handler = message_handler
        self.window_controller = window_controller
        
        # 创建Flask应用
        self.app = Flask(__name__, 
                        template_folder=self._get_template_dir(),
                        static_folder=self._get_static_dir())
        CORS(self.app)
        
        # 设置路由
        self._setup_routes()
        
        self.running = False
        
    def _get_template_dir(self):
        """获取模板目录"""
        # 模板目录在src/templates
        template_dir = Path(__file__).parent / "templates"
        template_dir.mkdir(parents=True, exist_ok=True)
        return str(template_dir)
        
    def _get_static_dir(self):
        """获取静态文件目录"""
        project_root = Path(__file__).parent.parent
        static_dir = project_root / "static"
        static_dir.mkdir(parents=True, exist_ok=True)
        return str(static_dir)
        
    def _setup_routes(self):
        """设置路由"""
        
        @self.app.route('/')
        def index():
            """主页"""
            return render_template('index.html')
            
        @self.app.route('/api/config', methods=['GET'])
        def get_config():
            """获取配置"""
            try:
                config = self.config_manager.get_all()
                return jsonify({
                    'success': True,
                    'data': config
                })
            except Exception as e:
                return jsonify({
                    'success': False,
                    'error': str(e)
                }), 500
                
        @self.app.route('/api/config', methods=['POST'])
        def update_config():
            """更新配置"""
            try:
                data = request.get_json()
                if not data:
                    return jsonify({
                        'success': False,
                        'error': '无效的JSON数据'
                    }), 400
                    
                # 更新配置
                success = self.config_manager.update(data)
                if success:
                    # 保存配置
                    self.config_manager.save_config()
                    return jsonify({
                        'success': True,
                        'message': '配置更新成功'
                    })
                else:
                    return jsonify({
                        'success': False,
                        'error': '配置更新失败'
                    }), 500
                    
            except Exception as e:
                return jsonify({
                    'success': False,
                    'error': str(e)
                }), 500
                
        @self.app.route('/api/config/validate', methods=['POST'])
        def validate_config():
            """验证配置"""
            try:
                data = request.get_json()
                if not data:
                    return jsonify({
                        'success': False,
                        'error': '无效的JSON数据'
                    }), 400
                    
                # 临时更新配置进行验证
                old_config = self.config_manager.get_all()
                self.config_manager.update(data)
                
                # 验证配置
                errors = self.config_manager.validate_config()
                
                # 恢复原配置
                self.config_manager.config_data = old_config
                
                return jsonify({
                    'success': True,
                    'valid': len(errors) == 0,
                    'errors': errors
                })
                
            except Exception as e:
                return jsonify({
                    'success': False,
                    'error': str(e)
                }), 500
                
        @self.app.route('/api/monitor/users', methods=['GET'])
        def get_monitor_users():
            """获取监听用户列表"""
            try:
                users = self.config_manager.get_monitor_users()
                return jsonify({
                    'success': True,
                    'data': users
                })
            except Exception as e:
                return jsonify({
                    'success': False,
                    'error': str(e)
                }), 500
                
        @self.app.route('/api/monitor/users', methods=['POST'])
        def add_monitor_user():
            """添加监听用户"""
            try:
                data = request.get_json()
                
                # 支持新格式（nickname + user_id）和旧格式（username）
                if 'nickname' in data and 'user_id' in data:
                    # 新格式：包含昵称和用户ID的映射
                    nickname = data.get('nickname', '').strip()
                    user_id = data.get('user_id', '').strip()
                    
                    if not nickname:
                        return jsonify({
                            'success': False,
                            'error': '昵称不能为空'
                        }), 400
                        
                    if not user_id:
                        return jsonify({
                            'success': False,
                            'error': '用户ID不能为空'
                        }), 400
                    
                    user_data = {
                        'nickname': nickname,
                        'user_id': user_id
                    }
                    success = self.config_manager.add_monitor_user(user_data)
                    display_name = f'{nickname} (QQ: {user_id})'
                else:
                    # 旧格式：仅用户名
                    username = data.get('username', '').strip()
                    
                    if not username:
                        return jsonify({
                            'success': False,
                            'error': '用户名不能为空'
                        }), 400
                        
                    success = self.config_manager.add_monitor_user(username)
                    display_name = username
                
                if success:
                    self.config_manager.save_config()
                    return jsonify({
                        'success': True,
                        'message': f'已添加监听用户: {display_name}'
                    })
                else:
                    return jsonify({
                        'success': False,
                        'error': '添加用户失败'
                    }), 500
                    
            except Exception as e:
                return jsonify({
                    'success': False,
                    'error': str(e)
                }), 500
                
        @self.app.route('/api/monitor/users/<username>', methods=['DELETE'])
        def remove_monitor_user(username):
            """移除监听用户"""
            try:
                success = self.config_manager.remove_monitor_user(username)
                if success:
                    self.config_manager.save_config()
                    return jsonify({
                        'success': True,
                        'message': f'已移除监听用户: {username}'
                    })
                else:
                    return jsonify({
                        'success': False,
                        'error': '移除用户失败'
                    }), 500
                    
            except Exception as e:
                return jsonify({
                    'success': False,
                    'error': str(e)
                }), 500
                
        @self.app.route('/api/status', methods=['GET'])
        def get_status():
            """获取系统状态"""
            try:
                status = {
                    'wechat': {
                        'enabled': self.config_manager.get('wechat.enabled', False),
                        'running': self.wechat_monitor.running if self.wechat_monitor else False,
                        'monitor_users': self.config_manager.get_monitor_users()
                    },
                    'onebot': {
                        'enabled': self.config_manager.get('onebot.enabled', False),
                        'connected': self.websocket_client.is_connected if self.websocket_client else False,
                        'ws_url': self.config_manager.get('onebot.ws_url', '')
                    },
                    'webui': {
                        'running': self.running,
                        'port': self.config_manager.get('webui.port', 10001)
                    },
                    'window_controller': self.window_controller.get_status() if self.window_controller else {
                        'enabled': self.config_manager.get('wechat.window_minimize.enabled', False),
                        'running': False,
                        'wechat_window_found': False,
                        'wechat_windows_count': 0,
                        'wechat_windows': [],
                        'config': {
                            'enabled': self.config_manager.get('wechat.window_minimize.enabled', False),
                            'interval': self.config_manager.get('wechat.window_minimize.interval', 3600),
                            'restore_delay': self.config_manager.get('wechat.window_minimize.restore_delay', 1)
                        }
                    }
                }
                
                return jsonify({
                    'success': True,
                    'data': status
                })
                
            except Exception as e:
                return jsonify({
                    'success': False,
                    'error': str(e)
                }), 500
                
        @self.app.route('/api/window/test-minimize', methods=['POST'])
        def test_minimize():
            """测试窗口最小化功能"""
            try:
                if not self.window_controller:
                    return jsonify({
                        'success': False,
                        'error': '窗口控制器未初始化'
                    }), 500
                    
                success = self.window_controller.minimize_and_restore()
                
                if success:
                    return jsonify({
                        'success': True,
                        'message': '测试最小化操作已执行'
                    })
                else:
                    return jsonify({
                        'success': False,
                        'error': '未找到微信窗口或操作失败'
                    }), 500
                    
            except Exception as e:
                return jsonify({
                    'success': False,
                    'error': str(e)
                }), 500
                
        @self.app.route('/api/control/<service>/<action>', methods=['POST'])
        def control_service(service, action):
            """控制服务"""
            try:
                if service == 'wechat' and self.wechat_monitor:
                    if action == 'start':
                        result = self.wechat_monitor.start()
                        message = '微信监听已启动' if result else '微信监听启动失败'
                    elif action == 'stop':
                        result = self.wechat_monitor.stop()
                        message = '微信监听已停止' if result else '微信监听停止失败'
                    else:
                        return jsonify({
                            'success': False,
                            'error': '无效的操作'
                        }), 400
                        
                elif service == 'onebot' and self.onebot_client:
                    if action == 'start':
                        result = self.onebot_client.start()
                        message = 'OneBot客户端已启动' if result else 'OneBot客户端启动失败'
                    elif action == 'stop':
                        result = self.onebot_client.stop()
                        message = 'OneBot客户端已停止' if result else 'OneBot客户端停止失败'
                    else:
                        return jsonify({
                            'success': False,
                            'error': '无效的操作'
                        }), 400
                        
                elif service == 'window' and self.window_controller:
                    if action == 'start':
                        result = self.window_controller.start()
                        message = '窗口控制器已启动' if result else '窗口控制器启动失败'
                    elif action == 'stop':
                        result = self.window_controller.stop()
                        message = '窗口控制器已停止' if result else '窗口控制器停止失败'
                    else:
                        return jsonify({
                            'success': False,
                            'error': '无效的操作'
                        }), 400
                else:
                    return jsonify({
                        'success': False,
                        'error': '无效的服务'
                    }), 400
                    
                return jsonify({
                    'success': result,
                    'message': message
                })
                
            except Exception as e:
                return jsonify({
                    'success': False,
                    'error': str(e)
                }), 500
                
    def run(self):
        """启动Web服务器"""
        if self.running:
            return
            
        self.running = True
        
        host = self.config_manager.get('webui.host', '0.0.0.0')
        port = self.config_manager.get('webui.port', 10001)
        debug = self.config_manager.get('webui.debug', False)
        
        try:
            self.app.run(host=host, port=port, debug=debug, threaded=True)
        except Exception as e:
            print(f"Web服务器启动失败: {e}")
            self.running = False
            
    def start(self):
        """启动Web UI服务"""
        try:
            port = self.config_manager.get('webui.port', 10001)
            print(f"启动Web UI服务，端口: {port}")
            # 在单独的线程中启动Flask应用，避免阻塞主线程
            self.web_thread = threading.Thread(target=self.run, daemon=True)
            self.web_thread.start()
        except Exception as e:
            print(f"Web UI启动失败: {e}")
            raise
            
    def stop(self):
        """停止Web服务器"""
        self.running = False
        print("Web UI服务停止")