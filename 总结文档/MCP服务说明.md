# MCP 服务说明文档

## 什么是 MCP 服务？

**MCP (Model Context Protocol)** 是一个标准化的协议，用于让 AI 助手（如 Claude、Cursor 等）能够安全地访问外部工具和数据源。

### MCP 服务的核心作用

1. **桥接 AI 与外部系统**
   - 让 AI 助手能够调用 WeKnora 的 API 功能
   - 无需直接暴露 API 密钥给 AI
   - 提供标准化的工具接口

2. **提供工具化能力**
   - 将 WeKnora 的功能封装成"工具"（Tools）
   - AI 可以按需调用这些工具
   - 支持复杂的知识管理操作

3. **安全访问控制**
   - 通过环境变量管理 API 密钥
   - 控制 AI 可以访问的功能范围
   - 避免直接暴露敏感信息

4. **标准化接口**
   - 遵循 MCP 协议标准
   - 兼容多种 AI 客户端（Claude Desktop、Cursor、KiloCode 等）
   - 统一的工具调用方式

## WeKnora MCP 服务提供的功能

### 1. 租户管理
- `create_tenant` - 创建新租户
- `list_tenants` - 列出所有租户

### 2. 知识库管理
- `create_knowledge_base` - 创建知识库
- `list_knowledge_bases` - 列出知识库
- `get_knowledge_base` - 获取知识库详情
- `delete_knowledge_base` - 删除知识库
- `hybrid_search` - 混合搜索

### 3. 知识管理
- `create_knowledge_from_url` - 从 URL 创建知识
- `create_knowledge_from_file` - 从文件创建知识
- `list_knowledge` - 列出知识
- `get_knowledge` - 获取知识详情
- `delete_knowledge` - 删除知识

### 4. 模型管理
- `create_model` - 创建模型
- `list_models` - 列出模型
- `get_model` - 获取模型详情

### 5. 会话管理
- `create_session` - 创建聊天会话
- `get_session` - 获取会话详情
- `list_sessions` - 列出会话
- `delete_session` - 删除会话

### 6. 聊天功能
- `chat` - 发送聊天消息

### 7. 块管理
- `list_chunks` - 列出知识块
- `delete_chunk` - 删除知识块

## 如何建立 MCP 服务

### 方法一：使用 uv（推荐）

#### 1. 安装 uv

**Windows (PowerShell):**
```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

**macOS/Linux:**
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

#### 2. 配置 MCP 客户端

**在 Cursor 中配置：**

编辑 MCP 配置文件（通常在 `~/.cursor/mcp-config.json` 或 Windows 的 `%APPDATA%\Cursor\mcp-config.json`）：

```json
{
  "mcpServers": {
    "weknora": {
      "command": "uv",
      "args": [
        "--directory",
        "D:/Agentic RAG based Weknora/WeKnora/mcp-server",
        "run",
        "run_server.py"
      ],
      "env": {
        "WEKNORA_API_KEY": "your_api_key_here",
        "WEKNORA_BASE_URL": "http://localhost:8080/api/v1"
      }
    }
  }
}
```

**在 Claude Desktop 中配置：**

编辑配置文件（macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`，Windows: `%APPDATA%\Claude\claude_desktop_config.json`）：

```json
{
  "mcpServers": {
    "weknora": {
      "command": "uv",
      "args": [
        "--directory",
        "D:/Agentic RAG based Weknora/WeKnora/mcp-server",
        "run",
        "run_server.py"
      ],
      "env": {
        "WEKNORA_API_KEY": "your_api_key_here",
        "WEKNORA_BASE_URL": "http://localhost:8080/api/v1"
      }
    }
  }
}
```

### 方法二：使用 pip 安装

#### 1. 安装依赖

```bash
cd WeKnora/mcp-server
pip install -r requirements.txt
```

#### 2. 设置环境变量

**Windows (CMD):**
```cmd
set WEKNORA_BASE_URL=http://localhost:8080/api/v1
set WEKNORA_API_KEY=your_api_key_here
```

**Windows (PowerShell):**
```powershell
$env:WEKNORA_BASE_URL="http://localhost:8080/api/v1"
$env:WEKNORA_API_KEY="your_api_key_here"
```

**Linux/macOS:**
```bash
export WEKNORA_BASE_URL="http://localhost:8080/api/v1"
export WEKNORA_API_KEY="your_api_key_here"
```

#### 3. 配置 MCP 客户端

**在 Cursor 中配置：**

```json
{
  "mcpServers": {
    "weknora": {
      "command": "python",
      "args": [
        "D:/Agentic RAG based Weknora/WeKnora/mcp-server/main.py"
      ],
      "env": {
        "WEKNORA_API_KEY": "your_api_key_here",
        "WEKNORA_BASE_URL": "http://localhost:8080/api/v1"
      }
    }
  }
}
```

### 方法三：作为 Python 包安装

#### 1. 安装包

```bash
cd WeKnora/mcp-server
pip install -e .
```

#### 2. 配置 MCP 客户端

```json
{
  "mcpServers": {
    "weknora": {
      "command": "weknora-mcp-server",
      "env": {
        "WEKNORA_API_KEY": "your_api_key_here",
        "WEKNORA_BASE_URL": "http://localhost:8080/api/v1"
      }
    }
  }
}
```

## 验证 MCP 服务

### 1. 检查环境配置

```bash
cd WeKnora/mcp-server
python main.py --check-only
```

这将显示：
- WeKnora API 基础 URL 配置
- API 密钥设置状态
- 依赖包安装状态

### 2. 测试服务器启动

```bash
python main.py --verbose
```

### 3. 在 AI 客户端中测试

配置完成后，重启 Cursor 或 Claude Desktop，然后尝试询问 AI：

- "列出所有知识库"
- "创建一个新的知识库"
- "在知识库中搜索相关内容"

如果 MCP 服务正常工作，AI 应该能够调用这些工具并返回结果。

## 常见问题

### 1. MCP 服务无法启动

**检查项：**
- Python 版本是否 >= 3.10
- 依赖是否已安装：`pip install -r requirements.txt`
- 环境变量是否正确设置

### 2. AI 无法调用工具

**检查项：**
- MCP 配置文件路径是否正确
- 配置文件 JSON 格式是否正确
- 是否重启了 AI 客户端
- 查看客户端日志中的错误信息

### 3. API 调用失败

**检查项：**
- `WEKNORA_BASE_URL` 是否正确
- `WEKNORA_API_KEY` 是否有效
- WeKnora 服务是否正在运行
- 网络连接是否正常

## 工作原理

```
AI 客户端 (Cursor/Claude Desktop)
    ↓
MCP 协议通信 (stdio)
    ↓
WeKnora MCP Server
    ↓
WeKnoraClient (封装 API 调用)
    ↓
WeKnora API (HTTP 请求)
    ↓
WeKnora 后端服务
```

1. **AI 客户端** 通过 MCP 协议与 MCP 服务器通信
2. **MCP 服务器** 接收工具调用请求
3. **WeKnoraClient** 将请求转换为 HTTP API 调用
4. **WeKnora API** 处理请求并返回结果
5. **结果** 通过 MCP 协议返回给 AI 客户端

## 开发新工具

如果你想添加新的工具功能：

1. **在 `WeKnoraClient` 类中添加 API 方法**
   ```python
   def new_method(self, param: str) -> Dict:
       return self._request("POST", "/new-endpoint", json={"param": param})
   ```

2. **在 `handle_list_tools()` 中注册工具**
   ```python
   types.Tool(
       name="new_tool",
       description="新工具的描述",
       inputSchema={...}
   )
   ```

3. **在 `handle_call_tool()` 中实现工具逻辑**
   ```python
   elif name == "new_tool":
       result = client.new_method(args["param"])
   ```

## 总结

MCP 服务是连接 AI 助手和 WeKnora 系统的桥梁，它：

- ✅ 让 AI 能够直接操作 WeKnora 的知识库
- ✅ 提供标准化的工具接口
- ✅ 安全地管理 API 访问
- ✅ 支持多种 AI 客户端

通过配置 MCP 服务，你可以让 AI 助手帮助你管理知识库、搜索内容、创建会话等，大大提升工作效率！

