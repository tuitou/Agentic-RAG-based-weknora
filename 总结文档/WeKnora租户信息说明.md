# WeKnora 租户（Tenant）信息说明文档

## 📋 概述

租户（Tenant）是 WeKnora 系统中的**多租户隔离机制**，用于在单个系统中为不同的组织/用户提供完全独立的工作空间。这是 WeKnora 实现数据隔离、资源管理和权限控制的核心机制。

---

## 🔑 租户的核心作用

### 1. **身份认证与授权**

- **API Key 认证**：每个租户拥有唯一的 API Key（格式：`sk-xxxxx`）
- **访问控制**：所有 API 请求必须携带 `X-API-Key` 请求头，系统通过 API Key 识别租户身份并授权访问
- **安全隔离**：不同租户的 API Key 互不通用，确保数据安全

**示例**：
```bash
curl -H "X-API-Key: sk-weknora-bab5bd8b1cdfadd675ec33f3c9f71445" \
     http://localhost:8080/api/v1/knowledge-bases
```

### 2. **数据隔离**

- **知识库隔离**：每个知识库都关联到特定的租户（`tenant_id`）
- **会话隔离**：每个对话会话都属于特定的租户
- **模型隔离**：每个租户可以配置自己的 AI 模型
- **数据隔离**：不同租户之间的数据完全隔离，互不可见

### 3. **资源配额管理**

- **存储配额**：每个租户有独立的存储配额限制（默认 10GB）
- **使用统计**：系统跟踪每个租户的存储使用情况（`storage_used`）
- **配额控制**：防止单个租户占用过多系统资源

### 4. **检索引擎配置**

- **自定义检索策略**：每个租户可以配置自己的检索引擎
- **支持多种引擎**：关键词检索（keywords）、向量检索（vector）
- **引擎类型**：PostgreSQL、Elasticsearch 等

### 5. **业务标识**

- **业务分类**：`business` 字段用于标识租户所属的业务领域（如 "wechat"）
- **组织管理**：便于按组织/部门管理不同的租户

---

## 📊 租户信息字段说明

### 当前系统租户信息

| 字段 | 说明 | 当前值 |
|------|------|--------|
| **ID** | 租户唯一标识符 | `1` |
| **Name** | 租户名称 | `Default Tenant` |
| **API Key** | 认证密钥（用于API调用） | `sk-weknora-bab5bd8b1cdfadd675ec33f3c9f71445` |
| **Status** | 租户状态（active/inactive） | `active` |
| **Storage Quota** | 存储配额限制（默认10GB） | `10737418240` 字节（10GB） |
| **Storage Used** | 已使用的存储空间 | `0` 字节 |
| **Retriever Engines** | 检索引擎配置 | `keywords + vector (postgres)` |
| **Business** | 业务标识 | 未设置 |
| **Created At** | 创建时间 | 系统初始化时创建 |
| **Updated At** | 最后更新时间 | 系统初始化时创建 |

### 字段详细说明

#### 1. **ID（租户ID）**
- 类型：整数（uint）
- 说明：系统自动生成的唯一标识符
- 默认起始值：10000（新创建的租户）
- 系统默认租户：1

#### 2. **API Key（API密钥）**
- 格式：`sk-` + base64编码的加密数据
- 长度：约 43 字符
- 用途：
  - 所有 API 请求的身份认证
  - 通过 API Key 提取租户 ID
  - 验证租户的有效性
- **安全提示**：请妥善保管 API Key，避免泄露

#### 3. **Storage Quota（存储配额）**
- 默认值：10GB（10737418240 字节）
- 包含内容：
  - 向量数据
  - 原始文件
  - 文本内容
  - 索引数据
- 配额管理：系统会跟踪使用情况，防止超出配额

#### 4. **Retriever Engines（检索引擎）**
- 支持的检索类型：
  - `keywords`：关键词检索（BM25算法）
  - `vector`：向量检索（语义相似度）
- 支持的引擎类型：
  - `postgres`：PostgreSQL（pgvector扩展）
  - `elasticsearch`：Elasticsearch

---

## 🎯 实际应用场景

### 场景1：多组织部署

**需求**：不同公司或部门需要使用同一个 WeKnora 实例

**解决方案**：
- 为每个组织创建独立的租户
- 每个组织使用自己的 API Key
- 数据完全隔离，互不影响

**示例**：
```
公司A → 租户ID: 10000, API Key: sk-xxx...
公司B → 租户ID: 10001, API Key: sk-yyy...
公司C → 租户ID: 10002, API Key: sk-zzz...
```

### 场景2：API 调用

**使用租户的 API Key 调用 API**：

```bash
# 查询知识库列表
curl -X GET "http://localhost:8080/api/v1/knowledge-bases" \
     -H "X-API-Key: sk-weknora-bab5bd8b1cdfadd675ec33f3c9f71445" \
     -H "Content-Type: application/json"

# 创建知识库
curl -X POST "http://localhost:8080/api/v1/knowledge-bases" \
     -H "X-API-Key: sk-weknora-bab5bd8b1cdfadd675ec33f3c9f71445" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "我的知识库",
       "description": "知识库描述"
     }'
```

### 场景3：资源管理

**监控和管理租户资源**：

```sql
-- 查询租户存储使用情况
SELECT 
    id,
    name,
    storage_quota,
    storage_used,
    ROUND(storage_used::numeric / storage_quota::numeric * 100, 2) as usage_percent
FROM tenants
WHERE status = 'active';
```

### 场景4：权限控制

**通过 API Key 控制访问权限**：

- 每个租户只能访问自己的数据
- 系统自动验证 API Key 的有效性
- 可以禁用租户（设置 `status = 'inactive'`）来阻止访问

---

## 🔐 安全机制

### API Key 生成与验证

1. **生成过程**：
   - 系统使用 AES-GCM 加密算法
   - 将租户 ID 加密后编码为 base64
   - 添加 `sk-` 前缀

2. **验证过程**：
   - 提取 `sk-` 后的部分
   - Base64 解码
   - AES-GCM 解密获取租户 ID
   - 验证 API Key 是否与数据库中的一致

3. **安全特性**：
   - API Key 包含加密的租户 ID，无法伪造
   - 每次请求都会验证 API Key 的有效性
   - 支持 API Key 轮换（更新租户信息时会生成新的 API Key）

---

## 📝 租户管理操作

### 创建新租户

**通过 API**：
```bash
curl -X POST "http://localhost:8080/api/v1/tenants" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "新租户",
       "description": "租户描述",
       "business": "wechat",
       "retriever_engines": {
         "engines": [
           {
             "retriever_type": "keywords",
             "retriever_engine_type": "postgres"
           },
           {
             "retriever_type": "vector",
             "retriever_engine_type": "postgres"
           }
         ]
       }
     }'
```

**响应示例**：
```json
{
  "success": true,
  "data": {
    "id": 10000,
    "name": "新租户",
    "api_key": "sk-新生成的API密钥",
    "status": "active",
    "storage_quota": 10737418240,
    "storage_used": 0
  }
}
```

### 查询租户信息

**通过数据库查询**：
```sql
-- 查询所有租户
SELECT id, name, LEFT(api_key, 30) as api_key_preview, 
       storage_quota, storage_used, status
FROM tenants
WHERE deleted_at IS NULL;

-- 查询特定租户
SELECT * FROM tenants WHERE id = 1;
```

### 更新租户信息

**注意**：更新租户信息会生成新的 API Key

```bash
curl -X PUT "http://localhost:8080/api/v1/tenants/1" \
     -H "X-API-Key: 旧API密钥" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "更新后的名称",
       "status": "active"
     }'
```

---

## 🎓 总结

### 租户的核心价值

租户是 WeKnora 系统的**隔离与资源管理单元**，它提供了：

1. ✅ **身份认证**：通过 API Key 实现安全的身份识别
2. ✅ **数据隔离**：确保不同租户的数据完全隔离
3. ✅ **资源管理**：通过配额机制控制资源使用
4. ✅ **灵活配置**：支持自定义检索引擎和业务标识

### 当前系统状态

- **默认租户**：ID = 1，名称为 "Default Tenant"
- **API Key**：`sk-weknora-bab5bd8b1cdfadd675ec33f3c9f71445`
- **状态**：active（活跃）
- **存储配额**：10GB（未使用）
- **检索引擎**：已配置 keywords 和 vector 检索（PostgreSQL）

### 使用建议

1. **单用户/小团队**：使用默认租户即可
2. **多组织部署**：为每个组织创建独立租户
3. **API 开发**：使用租户的 API Key 进行 API 调用
4. **资源监控**：定期检查租户的存储使用情况
5. **安全实践**：妥善保管 API Key，定期轮换

---

## 📚 相关资源

- **API 文档**：`WeKnora/docs/API.md`
- **代码位置**：
  - 租户类型定义：`internal/types/tenant.go`
  - 租户服务：`internal/application/service/tenant.go`
  - 认证中间件：`internal/middleware/auth.go`
- **数据库表**：`tenants` 表

---

**文档生成时间**：2025年11月11日  
**WeKnora 版本**：v0.1.3

