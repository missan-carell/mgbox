# MGBox
### 部署客户端
1. 从 mgbox CLI 获取设备安装令牌（install_token）
2. 登录客户机，执行如下命令：
```
curl https://mgbox/install?install_token=<INSTALL_TOKEN> | bash
```
### 部署示例
1. 部署服务器
```
docker-compose up -d
docker-compose exec -it mgbox bash

cat /var/log/mgbox.log 
cat /var/log/mgbox_init.log 
ssh mgbox@mgbox
The authenticity of host 'mgbox (172.18.0.3)' can't be established.
ECDSA key fingerprint is SHA256:zYUSLjthI1R2zZSujXrEchyPt5AptHqUE2NdJ0wt0s0.
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added 'mgbox,172.18.0.3' (ECDSA) to the list of known hosts.
   __       __   ______    ______   ______   ______         _______    ______   __    __ 
  /  \     /  | /      \  /      \ /      | /      \       /       \  /      \ /  |  /  |
  $$  \   /$$ |/$$$$$$  |/$$$$$$  |$$$$$$/ /$$$$$$  |      $$$$$$$  |/$$$$$$  |$$ |  $$ |
  $$$  \ /$$$ |$$ |__$$ |$$ | _$$/   $$ |  $$ |  $$/       $$ |__$$ |$$ |  $$ |$$  \/$$/ 
  $$$$  /$$$$ |$$    $$ |$$ |/    |  $$ |  $$ |            $$    $$< $$ |  $$ | $$  $$<  
  $$ $$ $$/$$ |$$$$$$$$ |$$ |$$$$ |  $$ |  $$ |   __       $$$$$$$  |$$ |  $$ |  $$$$  \ 
  $$ |$$$/ $$ |$$ |  $$ |$$ \__$$ | _$$ |_ $$ \__/  |      $$ |__$$ |$$ \__$$ | $$ /$$  |
  $$ | $/  $$ |$$ |  $$ |$$    $$/ / $$   |$$    $$/       $$    $$/ $$    $$/ $$ |  $$ |
  $$/      $$/ $$/   $$/  $$$$$$/  $$$$$$/  $$$$$$/        $$$$$$$/   $$$$$$/  $$/   $$/ 

  MAGIC KEY BOX by lihao@lidai

Press Enter key to login system
Username: test1
Password: 
Welcome test1, login success!

=== MGBOX Client Managerment System ===
Operation Menu:
  1. Device management
  2. Device user management
  3. List device and users
  x. Exit sub menu
  X. Exit system
Choose your Operation: 1
2025-03-16T11:19:49Z [getop_from_menu]: Notice: User 'test1' operation: 1. Device management


=== MGBOX Client Managerment :: Devices Managerment System ===
User: test1
Operation Menu:
  1. List device
  2. Add new device
  3. Update device description
  4. Delete device
  x. Exit sub menu
  X. Exit system
Choose your Operation: 1
2025-03-16T11:19:51Z [getop_from_menu]: Notice: User 'test1' operation: 1. List device

+-------------+------------------+------------------+---------------------+---------------------+-------------+
| device_name | install_token    | access_token     | created_at          | last_modified       | description |
+-------------+------------------+------------------+---------------------+---------------------+-------------+
| vm1         | M2YxYTg5MmU1Mzg5 | YzgxNjcwZjNjMDRi | 2025-03-16 11:17:14 | 2025-03-16 11:17:14 | DC shanghai |
| vm2         | ZWYxOTQ3ZDFhYTgw | YTYyNGJlMTcyNDAw | 2025-03-16 11:17:14 | 2025-03-16 11:17:14 | DC Hangzhou |
+-------------+------------------+------------------+---------------------+---------------------+-------------+
```

2. 部署客户端
```
docker-compose exec -it mgbox bash
root@singa16# curl 'https://mgbox/install?install_token=M2YxYTg5MmU1Mzg5' | bash -
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  8269    0  8269    0     0  90868      0 --:--:-- --:--:-- --:--:-- 90868
2025-03-16T11:21:58Z [setup_sanity_check]: Notice: Checking sanity ...
2025-03-16T11:21:58Z [mgbox_client_config]: Notice: Setting up mgbox client config ...
2025-03-16T11:21:58Z [setup_mgbox_client_script]: Notice: Setting up mgbox client script ...
2025-03-16T11:21:58Z [setup_mgbox_client_service]: Notice: Setting up mgbox client service ...
Created symlink /etc/systemd/system/multi-user.target.wants/mgboxc.service → /etc/systemd/system/mgboxc.service.
2025-03-16T11:21:58Z [main]: Notice: mgbox client setup done.
root@vm3:/# 
root@vm3:/# 
root@vm3:/# cat /var/log/mgbox.log 
2025-03-16T11:21:58Z [setup_sanity_check]: Notice: Checking sanity ...
2025-03-16T11:21:58Z [mgbox_client_config]: Notice: Setting up mgbox client config ...
2025-03-16T11:21:58Z [setup_mgbox_client_script]: Notice: Setting up mgbox client script ...
2025-03-16T11:21:58Z [setup_mgbox_client_service]: Notice: Setting up mgbox client service ...
2025-03-16T11:21:58Z [main]: Notice: mgbox client setup done.
2025-03-16T11:21:58Z [parse_config]: Info MGBOX_SERVER_URL="https://smgbox/account?username=test1&device_name=vm1&access_token=YzgxNjcwZjNjMDRi"
2025-03-16T11:21:58Z [mgboxc_pull_account]: Notice: mgboxc_pull_account ...
2025-03-16T11:21:58Z [mgboxc_pull_account]: Info HTTP/1.1 200 OK
2025-03-16T11:21:58Z [parse_http_response]: Info Parsing HTTP response...
2025-03-16T11:21:58Z [parse_http_response]: Info Device: vm1, User: lihao, LastModify: 1742123834.
2025-03-16T11:21:58Z [parse_http_response]: Notice: Add new user lihao ...
2025-03-16T11:21:59Z [parse_http_response]: Info Device: vm1, User: missan, LastModify: 1742123834.
2025-03-16T11:21:59Z [parse_http_response]: Notice: Add new user missan ...

```

### 数据流图 (DFD)

#### 1. **上下文图 (Context Diagram)**
- **外部实体**:
  - 用户 (User)
  - 数据库 (MariaDB)
  - HTTP客户端 (HTTP Client)
  
- **系统边界**: MGBox 系统

- **数据流**:
  - 用户通过 CLI 登录系统，输入用户名和密码。
  - CLI 与数据库交互，验证用户身份。
  - HTTP 客户端通过 HTTP Server 请求数据。
  - HTTP Server 从数据库中获取数据并返回给客户端。

```plaintext
+-------------------+       +-------------------+       +-------------------+
|                   |       |                   |       |                   |
|      User         | ----> |     MGBox System  | <---- |   HTTP Client     |
|                   |       |                   |       |                   |
+-------------------+       +-------------------+       +-------------------+
                                |       ^ 
                                v       |
                        +-------------------+
                        |                   |
                        |      Database     |
                        |                   |
                        +-------------------+
```

#### 2. **一级分解图 (Level 1 DFD)**

- **主要过程**:
  1. **用户登录 (Login)**: 用户通过 CLI 输入用户名和密码，CLI 调用 `mgbox_cli.sh` 进行身份验证。
  2. **数据库初始化 (Database Initialization)**: `mgbox_init.sh` 初始化数据库表结构和测试数据。
  3. **HTTP 请求处理 (HTTP Request Handling)**: `mgbox_server.sh` 处理 HTTP 请求，查询数据库并返回结果。
  4. **设备管理 (Device Management)**: 用户通过 CLI 管理设备和设备用户。
  
- **数据存储**:
  - MariaDB 数据库 (`mgbox` schema)

```plaintext
+-------------------+       +-------------------+       +-------------------+
|                   |       |                   |       |                   |
|      User         | ----> |    mgbox_cli.sh   | ----> |   MariaDB         |
|                   |       |                   |       |                   |
+-------------------+       +-------------------+       +-------------------+
                                |       ^ 
                                v       |
                        +-------------------+
                        |                   |
                        |  mgbox_server.sh  |
                        |                   |
                        +-------------------+
                                |       ^
                                v       |
                        +-------------------+
                        |                   |
                        |   HTTP Client     |
                        |                   |
                        +-------------------+
```

---

### 功能分析

#### 1. **用户登录与身份验证**
- **功能**: 用户通过 CLI 输入用户名和密码，系统调用 `login_check_password` 函数验证用户身份。
- **实现**: 使用 `mysql` 查询 `user` 表，验证用户名和密码的哈希值是否匹配。
- **依赖**: `utils.sh` 提供日志记录和 MySQL 查询封装。

#### 2. **数据库初始化**
- **功能**: 在容器启动时，`mgbox_init.sh` 初始化数据库表结构和测试数据。
- **实现**: 使用 SQL 脚本创建表、视图和索引，并插入测试用户和设备数据。
- **依赖**: MariaDB 容器服务。

#### 3. **HTTP 请求处理**
- **功能**: 提供 HTTP 接口 `/pull_keys`，允许客户端查询设备用户的密钥信息。
- **实现**: `mgbox_server.sh` 解析 HTTP 请求，调用 `handle_http_request` 函数查询数据库并返回结果。
- **依赖**: 数据库视图 `user_device_device_user_view`。

#### 4. **设备与设备用户管理**
- **功能**: 用户通过 CLI 管理设备和设备用户，包括增删改查操作。
- **实现**: CLI 调用 `mgbox_cli.sh` 中的函数，执行相应的 SQL 操作。
- **依赖**: 数据库表 `device` 和 `device_user`。

---

### 优化改进

#### 1. **安全性增强**
- **问题**: 密码以明文形式传输，存在安全风险。
- **建议**:
  - 使用 HTTPS 加密通信。
  - 在数据库中存储密码时，使用更强的加密算法（如 bcrypt）。
  - 对敏感信息（如 `access_token`）进行掩码处理。

#### 2. **性能优化**
- **问题**: 数据库查询频繁，可能导致性能瓶颈。
- **建议**:
  - 增加缓存机制，减少对数据库的直接访问。
  - 优化 SQL 查询，避免全表扫描。

#### 3. **错误处理改进**
- **问题**: 错误处理较为简单，缺乏详细的错误信息。
- **改进**:
  - 增加异常捕获和日志记录，提供更详细的错误提示。
  - 在 HTTP 响应中返回标准化的错误码和消息。

#### 4. **用户体验提升**
- **问题**: CLI 界面交互不够友好，缺乏帮助文档。
- **改进**:
  - 增加命令行参数解析，支持更多操作选项。
  - 提供在线帮助文档或交互式引导。

---

### 总结

MGBox 系统实现了用户管理、设备管理和 HTTP 接口的功能，整体架构清晰，但仍有优化空间。通过代码结构优化、安全性增强、性能优化和用户体验提升，可以进一步提高系统的稳定性和易用性。


~ tonglingyimang ~
