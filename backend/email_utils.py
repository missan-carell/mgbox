import random
import string
from threading import Thread
from flask import current_app
from flask_mail import Message

def send_async_email(app, msg):
    with app.app_context():
        try:
            mail = app.extensions['mail']
            mail.send(msg)
            print(f"邮件发送成功: {msg.recipients}")
        except Exception as e:
            print(f"邮件发送失败: {e}")

def send_verification_code(email, code):
    msg = Message(
        subject="【魔盒】邮箱验证码",
        recipients=[email]
    )
    msg.body = f"""您好！

您的邮箱验证码是：{code}

该验证码5分钟内有效，请勿泄露给他人。

如果非本人操作，请忽略此邮件。

—— 魔盒密钥管理系统
"""
    msg.html = f"""
    <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #e0e0e0; border-radius: 5px;">
        <h2 style="color: #3b82f6;">魔盒 · 邮箱验证</h2>
        <p>您好,欢迎使用魔盒</p>
        <p>您的邮箱验证码是：</p>
        <div style="background-color: #f0f9ff; padding: 15px; text-align: center; font-size: 32px; font-weight: bold; letter-spacing: 5px; color: #2563eb; border-radius: 5px; margin: 20px 0;">
            {code}
        </div>
        <p style="color: #666;">该验证码 <strong>5分钟内有效</strong>，请勿泄露给他人。</p>
        <hr style="border: none; border-top: 1px solid #e0e0e0; margin: 20px 0;">
        <p style="color: #999; font-size: 12px;">如果非本人操作，请忽略此邮件。</p>
        <p style="color: #999; font-size: 12px;">—— 魔盒密钥管理系统</p>
    </div>
    """
    app = current_app._get_current_object()
    thr = Thread(target=send_async_email, args=[app, msg])
    thr.start()
    return True

def generate_verification_code(length=6):
    return ''.join(random.choices(string.digits, k=length))