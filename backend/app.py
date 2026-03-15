from flask import Flask, request, jsonify
from flask_cors import CORS
import pymysql
import os
from flask import Response
from datetime import datetime, timedelta
import hashlib
from flask_mail import Mail
from zoneinfo import ZoneInfo  # Python 3.9+ 自带
import logging
logging.basicConfig(level=logging.DEBUG)

app = Flask(__name__)
CORS(app)

# 根目录
BASE_DIR = os.path.dirname(os.path.abspath(__file__))      # backend 目录
MGBOX_DIR = os.path.dirname(BASE_DIR)     # mgbox目录        

# 数据库连接配置
DB_HOST = os.getenv('DB_HOST', 'database')
DB_PORT = int(os.getenv('DB_PORT', 3306))
DB_USER = os.getenv('DB_USER', 'mgbox')
DB_PASS = os.getenv('DB_PASS', 'mgbox')
DB_NAME = os.getenv('DB_NAME', 'mgbox')



# 邮件配置
app.config['MAIL_SERVER'] = os.getenv('MAIL_SERVER', '')
app.config['MAIL_PORT'] = 465
app.config['MAIL_USE_SSL'] = True
app.config['MAIL_USERNAME'] = os.getenv('MAIL_PASSWORD', '')
app.config['MAIL_PASSWORD'] = os.getenv('MAIL_PASSWORD', '')
app.config['MAIL_DEFAULT_SENDER'] = os.getenv('MAIL_SERVER', '')

# 初始化邮件
mail = Mail(app)

# 导入自定义邮件工具
from email_utils import send_verification_code, generate_verification_code

# 内存存储验证码（生产环境建议用 Redis）
app.config['CODE_STORE'] = {}

def get_db():
    return pymysql.connect(
        host=DB_HOST,
        user=DB_USER,
        password=DB_PASS,
        database=DB_NAME,
        cursorclass=pymysql.cursors.DictCursor
    )

def sha256_password(password):
    return hashlib.sha256(password.encode('utf-8')).hexdigest()

# --------------时区转换----------
def utc_to_local(utc_dt):
    """
    将 naive UTC datetime 转换为本地时间（Asia/Shanghai）的 naive datetime
    """
    if utc_dt is None:
        return None
    # 假设传入的 datetime 是 UTC 时间（naive）
    utc_aware = utc_dt.replace(tzinfo=ZoneInfo('UTC'))
    local_aware = utc_aware.astimezone(ZoneInfo('Asia/Shanghai'))
    # 返回 naive 本地时间，方便与 datetime.now() 比较
    return local_aware.replace(tzinfo=None)

def strftime_local(dt, fmt='%Y-%m-%d %H:%M:%S'):
    """
    将 UTC datetime 转换为本地时间字符串
    """
    if dt is None:
        return None
    local_dt = utc_to_local(dt)
    return local_dt.strftime(fmt)
# =================================================

# --------------获取服务器地址----------
@app.route('/api/mgbox/server', methods=['GET'])
def get_mgbox_server_address():
    """
    从配置文件获取魔盒服务器地址
    """
    return jsonify({'address': os.getenv('MGBOX_SERVER_ADDRESS')})

# ------------------- 发送验证码接口 -------------------
@app.route('/api/send_code', methods=['POST'])
def send_code():
    data = request.get_json()
    email = data.get('email')
    if not email:
        return jsonify({'error': '邮箱不能为空'}), 400

    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("SELECT username FROM user WHERE email = %s", (email,))
        exists = cur.fetchone()
    conn.close()

    if exists:
        return jsonify({'error': '该邮箱已被注册'}), 400

    code = generate_verification_code()
    app.config['CODE_STORE'][email] = {
        'code': code,
        'expires': datetime.now() + timedelta(minutes=5)
    }

    try:
        send_verification_code(email, code)
        return jsonify({'message': '验证码已发送，请查收邮件'})
    except Exception as e:
        print(f"发送失败: {e}")
        return jsonify({'error': '验证码发送失败'}), 500

# ------------------- 带验证码的注册接口 -------------------
@app.route('/api/register_with_code', methods=['POST'])
def register_with_code():
    data = request.get_json()
    username = data.get('username')
    email = data.get('email')
    password = data.get('password')
    code = data.get('code')

    if not all([username, email, password, code]):
        return jsonify({'error': '所有字段都不能为空'}), 400

    stored = app.config['CODE_STORE'].get(email)
    if not stored:
        return jsonify({'error': '请先获取验证码'}), 400
    if datetime.now() > stored['expires']:
        del app.config['CODE_STORE'][email]
        return jsonify({'error': '验证码已过期，请重新获取'}), 400
    if stored['code'] != code:
        return jsonify({'error': '验证码错误'}), 400

    del app.config['CODE_STORE'][email]

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO user (username, email, password_hash, role, is_verified) VALUES (%s, %s, SHA2(%s, 256), 'user', TRUE)",
                (username, email, password)
            )
        conn.commit()
    except pymysql.IntegrityError as e:
        if "Duplicate entry" in str(e):
            if "username" in str(e):
                return jsonify({'error': '用户名已存在'}), 400
            else:
                return jsonify({'error': '邮箱已被注册'}), 400
        return jsonify({'error': '注册失败'}), 500
    finally:
        conn.close()

    return jsonify({'message': '注册成功，请登录'})

# ------------------- 原有注册接口（可保留） -------------------
@app.route('/api/register', methods=['POST'])
def register():
    data = request.get_json()
    username = data.get('username')
    password = data.get('password')
    email = data.get('email')
    if not username or not password or not email:
        return jsonify({'error': '用户名、密码和邮箱不能为空'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO user (username, email, password_hash, role) VALUES (%s, %s, SHA2(%s, 256), 'user')",
                (username, email, password)
            )
        conn.commit()
    except pymysql.IntegrityError as e:
        if "Duplicate entry" in str(e):
            if "username" in str(e):
                return jsonify({'error': '用户名已存在'}), 400
            else:
                return jsonify({'error': '邮箱已被注册'}), 400
        return jsonify({'error': '注册失败'}), 500
    finally:
        conn.close()
    return jsonify({'message': '注册成功，请登录'})

# ------------------- 登录接口 -------------------
@app.route('/api/login', methods=['POST'])
def login():
    data = request.get_json()
    username = data.get('username')
    password = data.get('password')
    if not username or not password:
        return jsonify({'error': '用户名和密码不能为空'}), 400

    conn = get_db()
    with conn.cursor() as cur:
        cur.execute(
            "SELECT username, role FROM user WHERE (username=%s OR email=%s) AND password_hash=%s",
            (username, username, sha256_password(password))
        )
        user = cur.fetchone()
    conn.close()

    if user:
        return jsonify({'username': user['username'], 'role': user['role'], 'message': '登录成功'})
    else:
        return jsonify({'error': '用户名或密码错误'}), 401

# ------------------- 设备列表接口 -------------------
@app.route('/api/devices')
def devices():
    all_flag = request.args.get('all')
    username = request.args.get('username')

    conn = get_db()
    with conn.cursor() as cur:
        if all_flag == 'true':
            cur.execute("""
                SELECT udv.device_name, udv.description, udv.username AS owner,
                    dcs.last_access
                FROM user_device_view udv
                LEFT JOIN device_connect_state dcs ON udv.device_id = dcs.device_id
            """)
        else:
            if not username:
                return jsonify({'error': '缺少 username 参数'}), 400
            cur.execute("""
                SELECT udv.device_name, udv.description, udv.username AS owner,
                    dcs.last_access
                FROM user_device_view udv
                LEFT JOIN device_connect_state dcs ON udv.device_id = dcs.device_id
                WHERE udv.username = %s
            """, (username,))
        rows = cur.fetchall()
    conn.close()

    result = []
    now = datetime.utcnow()  # 服务器UTC时间
    for row in rows:
        online = False
        last_access_utc = row['last_access']
        if last_access_utc:
            app.logger.debug(f"UTC now: {now}, last_access_utc: {last_access_utc}")
			
            #  检查超时 (比较 UTC 时间)
            if (now - last_access_utc).total_seconds() < 20:
                online = True
				
            # 将 UTC 时间转换为本地时间（naive）
            last_access_local = utc_to_local(last_access_utc)
        else:
            last_access_local = None

        result.append({
            'device_name': row['device_name'],
            'description': row['description'] or '',
            'online': online,
            # 返回给前端的 last_access 也转换为本地时间字符串
            'last_access': strftime_local(last_access_utc) if last_access_utc else None,
            'owner': row.get('owner') 
        })
    return jsonify(result)

# ------------- 普通用户申请设备 ------------
@app.route('/api/device_apply', methods=['POST'])
def device_apply():
    data = request.get_json()
    username = data.get('username')  # 由前端传递当前登录用户名
    device_name = data.get('device_name')
    description = data.get('description', '')
    if not username or not device_name:
        return jsonify({'error': '缺少必要参数'}), 400

    # 获取用户id
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("SELECT userid FROM user WHERE username = %s", (username,))
        user = cur.fetchone()
        if not user:
            return jsonify({'error': '用户不存在'}), 404

        # 检查该用户是否已有同名设备（已存在的设备或待审批的申请）
        cur.execute("""
            SELECT 1 FROM device WHERE userid = %s AND device_name = %s
            UNION
            SELECT 1 FROM device_application WHERE userid = %s AND device_name = %s AND status = 'pending'
        """, (user['userid'], device_name, user['userid'], device_name))
        if cur.fetchone():
            return jsonify({'error': '设备名已存在或已有待审批的申请'}), 400

        # 插入申请
        cur.execute(
            "INSERT INTO device_application (userid, device_name, description) VALUES (%s, %s, %s)",
            (user['userid'], device_name, description)
        )
        conn.commit()
    conn.close()
    return jsonify({'message': '申请已提交，请等待管理员审批'})



# ------- 管理员接受申请------------
@app.route('/api/device_applications')
def device_applications():
    # 简单起见，返回所有申请（可按需分页）
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("""
            SELECT a.id, u.username, a.device_name, a.description, a.status,
                   a.install_token, a.created_at
            FROM device_application a
            JOIN user u ON a.userid = u.userid
            ORDER BY a.created_at DESC
        """)
        apps = cur.fetchall()
    conn.close()
    for a in apps:
        a['created_at'] = strftime_local(a['created_at']) if a['created_at'] else ''
    return jsonify(apps)
# ---------- 审批通过 ------------------
@app.route('/api/device_applications/<int:app_id>/approve', methods=['POST'])
def approve_application(app_id):
    import secrets
    install_token = secrets.token_urlsafe(16)[:24]
    conn = get_db()
    try:
        with conn.cursor() as cur:
            # 获取申请信息，同时获取 username
            cur.execute("""
                SELECT a.userid, u.username, a.device_name, a.description
                FROM device_application a
                JOIN user u ON a.userid = u.userid
                WHERE a.id = %s AND a.status = 'pending'
            """, (app_id,))
            app = cur.fetchone()
            if not app:
                return jsonify({'error': '申请不存在或已处理'}), 404

            # 插入 device
            cur.execute(
                "INSERT INTO device (userid, device_name, description, install_token) VALUES (%s, %s, %s, %s)",
                (app['userid'], app['device_name'], app['description'], install_token)
            )
            # 更新申请状态
            cur.execute(
                "UPDATE device_application SET status='approved', install_token=%s, processed_at=CURRENT_TIMESTAMP WHERE id=%s",
                (install_token, app_id)
            )
            # 插入历史
            cur.execute(
                "INSERT INTO device_application_history (userid, username, device_name, description, status, install_token) VALUES (%s, %s, %s, %s, 'approved', %s)",
                (app['userid'], app['username'], app['device_name'], app['description'], install_token)
            )
            # 清理历史，保留最近30条
            cur.execute("""
                DELETE FROM device_application_history
                WHERE id <= (
                    SELECT id FROM (
                        SELECT id FROM device_application_history ORDER BY processed_at DESC LIMIT 1 OFFSET 30
                    ) AS tmp
                )
            """)
            conn.commit()
    except Exception as e:
        return jsonify({'error': str(e)}), 500
    finally:
        conn.close()
    return jsonify({'message': '已批准', 'install_token': install_token})

# ---------- 审批未通过 ----------------
@app.route('/api/device_applications/<int:app_id>/reject', methods=['POST'])
def reject_application(app_id):
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE device_application SET status = 'rejected', processed_at = CURRENT_TIMESTAMP WHERE id = %s AND status = 'pending'",
            (app_id,)
        )
        affected = cur.rowcount
    conn.commit()
    conn.close()
    if affected == 0:
        return jsonify({'error': '申请不存在或已处理'}), 404
    return jsonify({'message': '已拒绝'})

# ------------ 部署在用户服务器 -------------
@app.route('/api/device/<device_name>/install_command')
def get_install_command(device_name):
    username = request.args.get('username')
    if not username:
        return jsonify({'error': '缺少用户名'}), 400

    conn = get_db()
    with conn.cursor() as cur:
        # 允许管理员获取任何设备的安装命令
        cur.execute("""
            SELECT d.install_token
            FROM user_device_view udv
            JOIN device d ON udv.device_id = d.device_id
            WHERE (udv.username = %s OR (SELECT role FROM user WHERE username = %s) = 'admin')
              AND udv.device_name = %s
        """, (username, username, device_name))
        row = cur.fetchone()
    conn.close()
    if not row:
        return jsonify({'error': '设备不存在或无权限'}), 404

    install_token = row['install_token']
    # 命令中使用 https 并加上 -k 忽略证书验证, 返回安装命令（假设魔盒服务器地址为当前域名）
    command = f"curl -k '{request.scheme}://{request.host}/install?install_token={install_token}' | bash -"
    return jsonify({'command': command})

# ------------------- 用户管理接口 -------------------
@app.route('/api/users')
def get_users():
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("SELECT username, email, role, created_at, last_modified FROM user")
        users = cur.fetchall()
    conn.close()
    for u in users:
        u['created_at'] = strftime_local(u['created_at']) if u['created_at'] else ''
        u['last_modified'] = strftime_local(u['last_modified']) if u['last_modified'] else ''
    return jsonify(users)

# ------------------- 用户角色接口 -------------------
@app.route('/api/users/<username>/role', methods=['PUT'])
def update_user_role(username):
    data = request.get_json()
    new_role = data.get('role')
    if new_role not in ['admin', 'user']:
        return jsonify({'error': '无效角色'}), 400
    if username == 'admin':
        return jsonify({'error': '不能修改超级管理员'}), 400

    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("UPDATE user SET role=%s, last_modified=CURRENT_TIMESTAMP WHERE username=%s", (new_role, username))
        affected = cur.rowcount
    conn.commit()
    conn.close()
    if affected == 0:
        return jsonify({'error': '用户不存在'}), 404
    return jsonify({'message': f'用户角色已更新为 {new_role}'})

# ---------- 密码检验接口---------------
@app.route('/api/admin/check_default', methods=['GET'])
def check_admin_default():
    username = request.args.get('username')
    if username != 'admin':
        return jsonify({'error': '仅 admin 可查询'}), 403
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("SELECT password_hash FROM user WHERE username='admin'")
        row = cur.fetchone()
    conn.close()
    default_hash = hashlib.sha256(b'admin').hexdigest()
    is_default = (row and row['password_hash'] == default_hash)
    return jsonify({'is_default': is_default})

# ----------新增用户-------------
@app.route('/api/users', methods=['POST'])
def add_user():
    data = request.get_json()
    username = data.get('username')
    password = data.get('password')
    if not username or not password:
        return jsonify({'error': '用户名和密码不能为空'}), 400

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO user (username, password_hash) VALUES (%s, SHA2(%s, 256))",
                (username, password)
            )
        conn.commit()
    except pymysql.IntegrityError:
        return jsonify({'error': '用户名已存在'}), 400
    finally:
        conn.close()
    return jsonify({'message': '用户创建成功'})

# ------------修改用户密码（或描述）--------------
@app.route('/api/users/<username>', methods=['PUT'])
def update_user(username):
    data = request.get_json()
    new_password = data.get('password')
    if not new_password:
        return jsonify({'error': '密码不能为空'}), 400

    conn = get_db()
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE user SET password_hash = SHA2(%s, 256), last_modified = CURRENT_TIMESTAMP WHERE username = %s",
            (new_password, username)
        )
        affected = cur.rowcount
    conn.commit()
    conn.close()
    if affected == 0:
        return jsonify({'error': '用户不存在'}), 404
    return jsonify({'message': '密码更新成功'})

# ------------删除用户--------------
@app.route('/api/users/<username>', methods=['DELETE'])
def delete_user(username):
    if username == 'admin':
        return jsonify({'error': '不能删除管理员'}), 400
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("DELETE FROM user WHERE username = %s", (username,))
        affected = cur.rowcount
    conn.commit()
    conn.close()
    if affected == 0:
        return jsonify({'error': '用户不存在'}), 404
    return jsonify({'message': '用户删除成功'})

# --------------巡检日志---------------
@app.route('/api/inspection_logs')
def get_inspection_logs():
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM inspection_log ORDER BY created_at DESC LIMIT 50")
        logs = cur.fetchall()
    conn.close()
    for log in logs:
        log['created_at'] = strftime_local(log['created_at']) if log['created_at'] else ''
    return jsonify(logs)

# -------- 批量审批---------
@app.route('/api/device_applications/batch_approve', methods=['POST'])
def batch_approve():
    data = request.get_json()
    app_ids = data.get('ids', [])
    if not app_ids:
        return jsonify({'error': '请选择要批准的申请'}), 400

    import secrets
    conn = get_db()
    try:
        with conn.cursor() as cur:
            # 获取申请详情，同时关联 user 表拿到 username
            format_strings = ','.join(['%s'] * len(app_ids))
            cur.execute(f"""
                SELECT a.id, a.userid, u.username, a.device_name, a.description
                FROM device_application a
                JOIN user u ON a.userid = u.userid
                WHERE a.id IN ({format_strings}) AND a.status='pending'
            """, app_ids)
            apps = cur.fetchall()

            if not apps:
                return jsonify({'error': '没有找到待审批的申请'}), 400

            for app in apps:
                install_token = secrets.token_urlsafe(16)[:24]
                # 插入 device 表
                cur.execute(
                    "INSERT INTO device (userid, device_name, description, install_token) VALUES (%s, %s, %s, %s)",
                    (app['userid'], app['device_name'], app['description'], install_token)
                )
                # 更新申请状态
                cur.execute(
                    "UPDATE device_application SET status='approved', install_token=%s, processed_at=CURRENT_TIMESTAMP WHERE id=%s",
                    (install_token, app['id'])
                )
                # 插入历史表
                cur.execute(
                    "INSERT INTO device_application_history (userid, username, device_name, description, status, install_token) VALUES (%s, %s, %s, %s, 'approved', %s)",
                    (app['userid'], app['username'], app['device_name'], app['description'], install_token)
                )
            conn.commit()

            # 可选：清理历史表，保留最近30条
            cur.execute("""
                DELETE FROM device_application_history
                WHERE id <= (
                    SELECT id FROM (
                        SELECT id FROM device_application_history ORDER BY processed_at DESC LIMIT 1 OFFSET 30
                    ) AS tmp
                )
            """)
            conn.commit()
    except Exception as e:
        return jsonify({'error': str(e)}), 500
    finally:
        conn.close()
    return jsonify({'message': f'成功批准 {len(apps)} 条申请'})
# ----------- 设备历史记录 -----------
@app.route('/api/device_applications/history')
def get_application_history():
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("""
            SELECT id, username, device_name, description, status, install_token, processed_at
            FROM device_application_history
            ORDER BY processed_at DESC
            LIMIT 30
        """)
        history = cur.fetchall()
    conn.close()
    for h in history:
        h['processed_at'] = strftime_local(h['processed_at']) if h['processed_at'] else ''
    return jsonify(history)

# ---------- 修改设备描述 ----------
@app.route('/api/devices/<device_name>', methods=['PUT'])
def update_device(device_name):
    data = request.get_json()
    new_description = data.get('description')
    username = data.get('username')
    if not username or new_description is None:
        return jsonify({'error': '缺少参数'}), 400

    conn = get_db()
    with conn.cursor() as cur:
        # 允许管理员操作任何设备
        cur.execute("""
            SELECT device_id FROM user_device_view udv
            WHERE udv.device_name = %s AND (
                udv.username = %s OR (SELECT role FROM user WHERE username = %s) = 'admin'
            )
        """, (device_name, username, username))
        device = cur.fetchone()
        if not device:
            return jsonify({'error': '设备不存在或无权限'}), 404

        cur.execute(
            "UPDATE device SET description = %s, last_modified = CURRENT_TIMESTAMP WHERE device_id = %s",
            (new_description, device['device_id'])
        )
        affected = cur.rowcount
    conn.commit()
    conn.close()
    if affected == 0:
        return jsonify({'error': '更新失败'}), 500
    return jsonify({'message': '设备描述已更新'})

# ---------- 删除设备 ----------
@app.route('/api/devices/<device_name>', methods=['DELETE'])
def delete_device(device_name):
    username = request.args.get('username')
    if not username:
        return jsonify({'error': '缺少用户名'}), 400

    conn = get_db()
    with conn.cursor() as cur:
        # 允许管理员删除任何设备
        cur.execute("""
            SELECT device_id FROM user_device_view udv
            WHERE udv.device_name = %s AND (
                udv.username = %s OR (SELECT role FROM user WHERE username = %s) = 'admin'
            )
        """, (device_name, username, username))
        device = cur.fetchone()
        if not device:
            return jsonify({'error': '设备不存在或无权限'}), 404

        cur.execute("DELETE FROM device WHERE device_id = %s", (device['device_id'],))
        affected = cur.rowcount
    conn.commit()
    conn.close()
    if affected == 0:
        return jsonify({'error': '删除失败'}), 500
    return jsonify({'message': '设备已删除'})

# ---------- 获取单个设备的所有用户（后续可加强安全管理）----------
# 现有 /api/device/<device_name>/users 可用，但需确保只有设备所有者或管理员能访问
# 后续可加权限验证，不过现有查询没有限制，可能泄露信息。建议加上：
@app.route('/api/device/<device_name>/users')
def device_users(device_name):
    # 从查询参数获取当前用户名，用于权限验证
    cur_username = request.args.get('username')
    if not cur_username:
        return jsonify({'error': '缺少用户名'}), 400

    conn = get_db()
    with conn.cursor() as cur:
        # 先检查用户是否有权访问该设备
        cur.execute("""
            SELECT device_id FROM user_device_view
            WHERE (username = %s OR (SELECT role FROM user WHERE username = %s) = 'admin')
              AND device_name = %s
        """, (cur_username, cur_username, device_name))
        device = cur.fetchone()
        if not device:
            return jsonify({'error': '设备不存在或无权限'}), 404

        cur.execute("""
            SELECT device_user, passtext, description, last_modified
            FROM user_device_device_user_view
            WHERE device_name = %s
        """, (device_name,))
        rows = cur.fetchall()
    conn.close()

    for r in rows:
        if r['last_modified']:
            r['last_modified'] = strftime_local(r['last_modified'])
    return jsonify(rows)

# ---------- 新增设备用户 ----------
@app.route('/api/device/<device_name>/users', methods=['POST'])
def add_device_user(device_name):
    data = request.get_json()
    username = data.get('username')  # 当前登录用户
    device_user = data.get('device_user')
    description = data.get('description', '')
    if not username or not device_user:
        return jsonify({'error': '缺少参数'}), 400

    conn = get_db()
    with conn.cursor() as cur:
        # 检查权限
        cur.execute("""
            SELECT device_id FROM user_device_view
            WHERE (username = %s OR (SELECT role FROM user WHERE username = %s) = 'admin')
              AND device_name = %s
        """, (username, username, device_name))
        device = cur.fetchone()
        if not device:
            return jsonify({'error': '设备不存在或无权限'}), 404

        # 检查是否已存在同名设备用户
        cur.execute("""
            SELECT 1 FROM device_user
            WHERE device_id = %s AND device_user = %s
        """, (device['device_id'], device_user))
        if cur.fetchone():
            return jsonify({'error': '该设备用户已存在'}), 400

        # 插入新设备用户（密码自动生成，由数据库默认值处理）
        cur.execute("""
            INSERT INTO device_user (device_id, device_user, description)
            VALUES (%s, %s, %s)
        """, (device['device_id'], device_user, description))
        conn.commit()
    conn.close()
    return jsonify({'message': '设备用户创建成功'})

# ---------- 修改设备用户描述 ----------
# ---------- 修改设备用户描述 ----------
@app.route('/api/device/<device_name>/users/<device_user>', methods=['PUT'])
def update_device_user(device_name, device_user):
    data = request.get_json()
    username = data.get('username')
    description = data.get('description')
    if not username or description is None:
        return jsonify({'error': '缺少参数'}), 400

    conn = get_db()
    with conn.cursor() as cur:
        # 权限验证
        cur.execute("""
            SELECT udv.device_id FROM user_device_view udv
            JOIN device_user du ON udv.device_id = du.device_id
            WHERE (udv.username = %s OR (SELECT role FROM user WHERE username = %s) = 'admin')
            AND udv.device_name = %s
            AND du.device_user = %s
        """, (username, username, device_name, device_user))
        row = cur.fetchone()
        if not row:
            return jsonify({'error': '设备用户不存在或无权限'}), 404

        # 更新描述
        cur.execute("""
            UPDATE device_user SET description = %s, last_modified = CURRENT_TIMESTAMP
            WHERE device_id = %s AND device_user = %s
        """, (description, row['device_id'], device_user))
        affected = cur.rowcount
    conn.commit()
    conn.close()
    if affected == 0:
        return jsonify({'error': '更新失败'}), 500
    return jsonify({'message': '描述已更新'})

# ---------- 删除设备用户 ----------
@app.route('/api/device/<device_name>/users/<device_user>', methods=['DELETE'])
def delete_device_user(device_name, device_user):
    username = request.args.get('username')
    if not username:
        return jsonify({'error': '缺少用户名'}), 400

    conn = get_db()
    with conn.cursor() as cur:
        # 权限验证
        cur.execute("""
            SELECT udv.device_id FROM user_device_view udv
            JOIN device_user du ON udv.device_id = du.device_id
            WHERE (udv.username = %s OR (SELECT role FROM user WHERE username = %s) = 'admin')
            AND udv.device_name = %s
            AND du.device_user = %s
        """, (username, username, device_name, device_user))
        row = cur.fetchone()
        if not row:
            return jsonify({'error': '设备用户不存在或无权限'}), 404

        # 删除
        cur.execute("""
            DELETE FROM device_user WHERE device_id = %s AND device_user = %s
        """, (row['device_id'], device_user))
        affected = cur.rowcount
    conn.commit()
    conn.close()
    if affected == 0:
        return jsonify({'error': '删除失败'}), 500
    return jsonify({'message': '设备用户已删除'})

# ---------- 手动刷新设备用户密码 ----------
@app.route('/api/device/<device_name>/users/<device_user>/refresh', methods=['POST'])
def refresh_device_user_password(device_name, device_user):
    username = request.args.get('username')  # 当前用户
    if not username:
        return jsonify({'error': '缺少用户名'}), 400

    conn = get_db()
    with conn.cursor() as cur:
        # 权限验证
        cur.execute("""
            SELECT udv.device_id FROM user_device_view udv
            JOIN device_user du ON udv.device_id = du.device_id
            WHERE (udv.username = %s OR (SELECT role FROM user WHERE username = %s) = 'admin')
            AND udv.device_name = %s
            AND du.device_user = %s
        """, (username, username, device_name, device_user))
        row = cur.fetchone()
        if not row:
            return jsonify({'error': '设备用户不存在或无权限'}), 404

        # 刷新密码
        cur.execute("""
            UPDATE device_user SET passtext =
                INSERT(TO_BASE64(LEFT(SHA2(UUID(), 256), 12)),
                       FLOOR(1 + RAND() * 12), 1,
                       SUBSTR('[!@#$%%^&*()]', FLOOR(1 + RAND() * 12), 1)),
                last_modified = CURRENT_TIMESTAMP
            WHERE device_id = %s AND device_user = %s
        """, (row['device_id'], device_user))
        affected = cur.rowcount
    conn.commit()
    conn.close()
    if affected == 0:
        return jsonify({'error': '刷新失败'}), 500
    return jsonify({'message': '密码已刷新'})

# -------- install 路由 ------------
@app.route('/install', methods=['GET'])
def install_script():
    install_token = request.args.get('install_token')
    if not install_token:
        return "install_token missing", 400

    conn = get_db()
    with conn.cursor() as cur:
        cur.execute("SELECT username, device_name, access_token FROM user_device_view WHERE install_token = %s", (install_token,))
        row = cur.fetchone()
    conn.close()
    if not row:
        return "Invalid install_token", 404

    username = row['username']
    device_name = row['device_name']
    access_token = row['access_token']

    # 构建返回的 shell 脚本
    script = "alias curl='curl -k'\n\n"   # （目前）忽略证书验证

    # 读取 utils.sh
    utils_path = os.path.join(MGBOX_DIR, 'utils.sh')
    with open(utils_path, 'r') as f:
        script += f.read() + "\n\n"

    # 生成 mgbox_client_config 函数（动态注入配置）
    script += f"""
mgbox_client_config() {{
  lognote "Setting up mgbox client config ..."
  MGBOXC_SCRIPT='/usr/mgbox/mgboxc.conf'
  [ ! -d "/usr/mgbox" ] && mkdir -p /usr/mgbox && chmod 600 /usr/mgbox
  cat > $MGBOXC_SCRIPT <<SETUP_EOF
# mgbox client config
SERVER_URL=https://{request.host}
USERNAME={username}
DEVICE_NAME={device_name}
ACCESS_TOKEN={access_token}
SETUP_EOF
  return 0
}}
"""

    # 读取 mgbox_client.sh
    client_path = os.path.join(MGBOX_DIR, 'mgbox_client.sh')
    with open(client_path, 'r') as f:
        script += f.read() + "\n\n"

    # 读取 mgbox_client_setup.sh
    setup_path = os.path.join(MGBOX_DIR, 'mgbox_client_setup.sh')
    with open(setup_path, 'r') as f:
        script += f.read() + "\n\n"

    return Response(script, mimetype='text/plain')

# ------------- account 路由 ----------
@app.route('/account', methods=['GET'])
def account():
    username = request.args.get('username')
    device_name = request.args.get('device_name')
    access_token = request.args.get('access_token')
    last_modify = request.args.get('last_modify')   # 可选

    if not all([username, device_name, access_token]):
        return "Missing parameters", 400

    conn = get_db()
    with conn.cursor() as cur:
        # 验证 access_token
        cur.execute("""
            SELECT device_id FROM user_device_view
            WHERE username = %s AND device_name = %s AND access_token = %s
        """, (username, device_name, access_token))
        device = cur.fetchone()
        if not device:
            return "Invalid access_token", 403

        device_id = device['device_id']

        # 获取客户端 IP（注意如果通过代理，需从 headers 获取）
        client_ip = request.remote_addr or 'unknown'

        # 更新连接状态
        cur.execute("""
            REPLACE INTO device_connect_state(device_id, client_ip, last_access)
            VALUES (%s, %s, CURRENT_TIMESTAMP)
        """, (device_id, client_ip))

        # 查询设备用户信息
        cur.execute("""
            SELECT device_name, device_user, passtext, UNIX_TIMESTAMP(last_modified) as last_modified_ts
            FROM user_device_device_user_view
            WHERE username = %s AND device_name = %s
        """, (username, device_name))
        rows = cur.fetchall()
    conn.commit()
    conn.close()

    # 生成响应文本（每行：device_name \t device_user \t passtext \t last_modified_ts）
    output = ""
    for r in rows:
        output += f"{r['device_name']}\t{r['device_user']}\t{r['passtext']}\t{r['last_modified_ts']}\n"
    return Response(output, mimetype='text/plain')

@app.route('/')
def index():
    return app.send_static_file('index.html')


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
