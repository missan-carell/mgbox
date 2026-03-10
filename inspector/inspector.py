import socket
import pymysql
import requests
import time
import os
from datetime import datetime

# ========== 配置区域 ==========
DB_CONFIG = {
    'host': os.getenv('DB_HOST', '127.0.0.1'),
    'port': int(os.getenv('DB_PORT', 3306)),
    'user': os.getenv('DB_USER', 'mgbox'),
    'password': os.getenv('DB_PASS', 'mgbox'),
    'database': os.getenv('DB_NAME', 'mgbox'),
    'cursorclass': pymysql.cursors.DictCursor
}

DEEPSEEK_API_KEY = os.getenv('DEEPSEEK_API_KEY', 'sk-2ea9f1f5ae384e16b682fa0b37e5a2c2')
DEEPSEEK_URL = 'https://api.deepseek.com/v1/chat/completions'

# 巡检间隔（秒）
INSPECTION_INTERVAL = 3600  # 1小时

# 要检查的端口：SSH 端口 22
CHECK_PORT = 22
# ==============================

def get_devices_from_db():
    """从数据库获取需要巡检的设备列表（使用 device_connect_state 中的 client_ip）"""
    conn = pymysql.connect(**DB_CONFIG)
    with conn.cursor() as cur:
        cur.execute("""
            SELECT d.device_name, dcs.client_ip
            FROM device d
            LEFT JOIN device_connect_state dcs ON d.device_id = dcs.device_id
            WHERE dcs.client_ip IS NOT NULL AND dcs.client_ip != ''
        """)
        devices = cur.fetchall()
    conn.close()
    return devices

def save_inspection_log(device_name, status, message, ai_advice=''):
    """将巡检结果写入数据库"""
    conn = pymysql.connect(**DB_CONFIG)
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO inspection_log (device_name, status, message, ai_advice) VALUES (%s, %s, %s, %s)",
            (device_name, status, message[:200] if message else '', ai_advice[:200] if ai_advice else '')
        )
    conn.commit()
    conn.close()

def ask_ai(error_msg):
    """调用 DeepSeek API 生成故障排查建议（超时5秒）"""
    if DEEPSEEK_API_KEY == 'your-api-key-here' or not DEEPSEEK_API_KEY:
        return "（未配置 AI API Key）"
    headers = {
        'Authorization': f'Bearer {DEEPSEEK_API_KEY}',
        'Content-Type': 'application/json'
    }
    payload = {
        'model': 'deepseek-chat',
        'messages': [
            {'role': 'system', 'content': '你是一个运维专家，请根据巡检错误信息给出简洁的故障排查建议。一句话以内，如果没有错误内容可以不输出内容'},
            {'role': 'user', 'content': error_msg}
        ],
        'temperature': 0.3,
        'max_tokens': 100
    }
    try:
        resp = requests.post(DEEPSEEK_URL, json=payload, headers=headers, timeout=5)
        if resp.status_code == 200:
            data = resp.json()
            return data['choices'][0]['message']['content'].strip()
        else:
            return f"AI 服务返回错误: {resp.status_code}"
    except requests.exceptions.Timeout:
        return "AI 请求超时"
    except Exception as e:
        return f"AI 调用失败: {str(e)}"

def check_device_tcp(device_name, ip, port=CHECK_PORT):
    """检查设备指定 TCP 端口是否可达"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        result = sock.connect_ex((ip, port))
        sock.close()
        if result == 0:
            return True, f"端口 {port} 开放"
        else:
            return False, f"端口 {port} 不可达 (错误码 {result})"
    except Exception as e:
        return False, str(e)

def run_inspection():
    """执行一轮巡检"""
    print(f"正在连接到数据库 {DB_CONFIG['host']}:{DB_CONFIG['port']} ...")
    print(f"[{datetime.now()}] 开始巡检...", flush=True)
    devices = get_devices_from_db()
    if not devices:
        print("没有可巡检的设备（无 client_ip）", flush=True)
        return

    for dev in devices:
        device_name = dev['device_name']
        ip = dev['client_ip']
        print(f"正在巡检 {device_name} ({ip})...", flush=True)
        success, msg = check_device_tcp(device_name, ip)
        status = 'success' if success else 'failure'
        ai_advice = ask_ai(msg) if not success else ''
        save_inspection_log(device_name, status, msg, ai_advice)
        print(f"  结果: {status}, 消息: {msg}", flush=True)

def main_loop():
    """主循环，定时执行巡检"""
    print("智能巡检服务已启动，每小时执行一次", flush=True)
    while True:
        run_inspection()
        time.sleep(3600)

if __name__ == '__main__':
    main_loop()