# Agentic RAG 实现指南 - 使用 MCP 服务操作 WeKnora

## 什么是 Agentic RAG？

**Agentic RAG (Agentic Retrieval-Augmented Generation)** 是一种增强的 RAG 系统，它不仅仅是简单的"检索-生成"，而是：

1. **自主决策能力** - AI Agent 可以自主决定需要执行哪些操作
2. **多步骤推理** - 可以执行多个检索步骤，逐步完善答案
3. **工具调用** - 可以调用各种工具（搜索、创建知识库、管理会话等）
4. **动态策略** - 根据问题复杂度选择不同的检索和生成策略

## 为什么使用 MCP 服务？

MCP 服务为 Agentic RAG 提供了：

✅ **标准化的工具接口** - 所有 WeKnora 功能都封装为工具  
✅ **安全的 API 访问** - 通过环境变量管理密钥  
✅ **灵活的工具组合** - Agent 可以按需调用多个工具  
✅ **完整的知识管理** - 不仅检索，还能创建和管理知识库  

## Agentic RAG vs 普通 RAG

### 普通 RAG 流程
```
用户问题 → 检索 → 生成答案
```

### Agentic RAG 流程
```
用户问题 
  → Agent 分析问题
  → 决定需要的工具（搜索、创建知识库、查询会话历史等）
  → 执行多个工具调用
  → 整合结果
  → 生成最终答案
  → 如果需要，继续迭代
```

## 实现方案

### 方案一：使用支持 MCP 的 AI 框架（推荐）

#### 1. 使用 LangGraph + MCP

```python
from langgraph.graph import StateGraph, END
from langchain_core.messages import HumanMessage, AIMessage
from mcp import ClientSession, StdioServerParameters
import asyncio

class AgenticRAG:
    def __init__(self, mcp_config):
        self.mcp_client = None
        self.mcp_config = mcp_config
        
    async def setup_mcp(self):
        """初始化 MCP 客户端连接"""
        server_params = StdioServerParameters(
            command=self.mcp_config["command"],
            args=self.mcp_config["args"],
            env=self.mcp_config["env"]
        )
        self.mcp_client = ClientSession(server_params)
        await self.mcp_client.initialize()
    
    async def agent_think(self, state):
        """Agent 思考阶段：分析问题，决定需要的工具"""
        question = state["question"]
        
        # 分析问题类型
        if "创建" in question or "新建" in question:
            return {"action": "create", "tools": ["list_knowledge_bases", "create_knowledge_base"]}
        elif "搜索" in question or "查找" in question:
            return {"action": "search", "tools": ["list_knowledge_bases", "hybrid_search"]}
        elif "聊天" in question or "问答" in question:
            return {"action": "chat", "tools": ["list_sessions", "create_session", "chat"]}
        else:
            return {"action": "search", "tools": ["hybrid_search"]}
    
    async def execute_tools(self, state):
        """执行工具调用"""
        tools = state["tools"]
        results = {}
        
        for tool_name in tools:
            if tool_name == "list_knowledge_bases":
                result = await self.mcp_client.call_tool("list_knowledge_bases", {})
                results["knowledge_bases"] = result
                
            elif tool_name == "hybrid_search":
                kb_id = state.get("kb_id", self._get_default_kb_id(results))
                query = state["question"]
                result = await self.mcp_client.call_tool(
                    "hybrid_search",
                    {"kb_id": kb_id, "query": query}
                )
                results["search_results"] = result
                
            elif tool_name == "create_session":
                kb_id = state.get("kb_id", self._get_default_kb_id(results))
                result = await self.mcp_client.call_tool(
                    "create_session",
                    {"kb_id": kb_id}
                )
                results["session_id"] = result.get("id")
                
            elif tool_name == "chat":
                session_id = state.get("session_id")
                query = state["question"]
                result = await self.mcp_client.call_tool(
                    "chat",
                    {"session_id": session_id, "query": query}
                )
                results["chat_response"] = result
        
        return {"tool_results": results}
    
    async def generate_answer(self, state):
        """基于工具结果生成最终答案"""
        tool_results = state["tool_results"]
        question = state["question"]
        
        # 整合所有工具结果
        context = self._format_context(tool_results)
        
        # 调用 LLM 生成答案
        # 这里可以使用 LangChain 或其他 LLM 框架
        answer = await self._call_llm(question, context)
        
        return {"answer": answer}
    
    def _get_default_kb_id(self, results):
        """从结果中获取默认知识库 ID"""
        if "knowledge_bases" in results:
            kbs = results["knowledge_bases"].get("data", [])
            if kbs:
                return kbs[0]["id"]
        return None
    
    def _format_context(self, tool_results):
        """格式化工具结果为上下文"""
        context_parts = []
        
        if "search_results" in tool_results:
            for result in tool_results["search_results"].get("chunks", []):
                context_parts.append(f"相关内容: {result.get('content', '')}")
        
        if "chat_response" in tool_results:
            context_parts.append(f"对话响应: {tool_results['chat_response']}")
        
        return "\n".join(context_parts)
    
    async def run(self, question):
        """运行 Agentic RAG 流程"""
        # 初始化状态
        state = {"question": question}
        
        # 1. Agent 思考
        state.update(await self.agent_think(state))
        
        # 2. 执行工具
        state.update(await self.execute_tools(state))
        
        # 3. 生成答案
        state.update(await self.generate_answer(state))
        
        return state["answer"]

# 使用示例
async def main():
    mcp_config = {
        "command": "uv",
        "args": [
            "--directory",
            "D:/Agentic RAG based Weknora/WeKnora/mcp-server",
            "run",
            "run_server.py"
        ],
        "env": {
            "WEKNORA_API_KEY": "your_api_key",
            "WEKNORA_BASE_URL": "http://localhost:8080/api/v1"
        }
    }
    
    agent = AgenticRAG(mcp_config)
    await agent.setup_mcp()
    
    answer = await agent.run("在知识库中搜索关于机器学习的内容")
    print(answer)

if __name__ == "__main__":
    asyncio.run(main())
```

#### 2. 使用 AutoGen + MCP

```python
from autogen import ConversableAgent
from mcp import ClientSession, StdioServerParameters

class WeKnoraAgent(ConversableAgent):
    def __init__(self, mcp_config, **kwargs):
        super().__init__(**kwargs)
        self.mcp_config = mcp_config
        self.mcp_client = None
    
    async def setup_mcp(self):
        """初始化 MCP 连接"""
        server_params = StdioServerParameters(
            command=self.mcp_config["command"],
            args=self.mcp_config["args"],
            env=self.mcp_config["env"]
        )
        self.mcp_client = ClientSession(server_params)
        await self.mcp_client.initialize()
    
    async def search_knowledge(self, query, kb_id=None):
        """搜索知识库"""
        if not kb_id:
            # 先获取知识库列表
            kbs = await self.mcp_client.call_tool("list_knowledge_bases", {})
            kb_id = kbs["data"][0]["id"] if kbs.get("data") else None
        
        if kb_id:
            result = await self.mcp_client.call_tool(
                "hybrid_search",
                {"kb_id": kb_id, "query": query}
            )
            return result
        return None
    
    async def chat_with_kb(self, question, session_id=None):
        """与知识库对话"""
        if not session_id:
            # 创建新会话
            kbs = await self.mcp_client.call_tool("list_knowledge_bases", {})
            kb_id = kbs["data"][0]["id"] if kbs.get("data") else None
            
            if kb_id:
                session = await self.mcp_client.call_tool(
                    "create_session",
                    {"kb_id": kb_id}
                )
                session_id = session.get("id")
        
        if session_id:
            response = await self.mcp_client.call_tool(
                "chat",
                {"session_id": session_id, "query": question}
            )
            return response
        return None

# 使用示例
async def main():
    mcp_config = {
        "command": "uv",
        "args": ["--directory", "path/to/mcp-server", "run", "run_server.py"],
        "env": {
            "WEKNORA_API_KEY": "your_key",
            "WEKNORA_BASE_URL": "http://localhost:8080/api/v1"
        }
    }
    
    agent = WeKnoraAgent(
        name="weknora_agent",
        system_message="你是一个智能助手，可以使用 WeKnora 知识库回答问题。",
        mcp_config=mcp_config
    )
    
    await agent.setup_mcp()
    
    # Agent 可以自主调用工具
    result = await agent.search_knowledge("机器学习")
    print(result)
```

### 方案二：直接使用 MCP 客户端库

```python
import asyncio
from mcp import ClientSession, StdioServerParameters

class SimpleAgenticRAG:
    def __init__(self, mcp_config):
        self.mcp_config = mcp_config
        self.session = None
    
    async def connect(self):
        """连接到 MCP 服务器"""
        server_params = StdioServerParameters(
            command=self.mcp_config["command"],
            args=self.mcp_config["args"],
            env=self.mcp_config["env"]
        )
        self.session = ClientSession(server_params)
        await self.session.initialize()
    
    async def answer_question(self, question):
        """Agentic RAG 主流程"""
        # 1. 获取可用工具
        tools = await self.session.list_tools()
        print(f"可用工具: {[t.name for t in tools.tools]}")
        
        # 2. 根据问题决定策略
        strategy = self._decide_strategy(question)
        
        # 3. 执行多步骤操作
        results = []
        
        if "list" in strategy:
            # 列出知识库
            kb_result = await self.session.call_tool("list_knowledge_bases", {})
            results.append(("知识库列表", kb_result))
        
        if "search" in strategy:
            # 搜索知识库
            kbs = await self.session.call_tool("list_knowledge_bases", {})
            if kbs.get("data"):
                kb_id = kbs["data"][0]["id"]
                search_result = await self.session.call_tool(
                    "hybrid_search",
                    {"kb_id": kb_id, "query": question}
                )
                results.append(("搜索结果", search_result))
        
        if "chat" in strategy:
            # 创建会话并聊天
            kbs = await self.session.call_tool("list_knowledge_bases", {})
            if kbs.get("data"):
                kb_id = kbs["data"][0]["id"]
                session = await self.session.call_tool(
                    "create_session",
                    {"kb_id": kb_id}
                )
                session_id = session.get("id")
                
                chat_result = await self.session.call_tool(
                    "chat",
                    {"session_id": session_id, "query": question}
                )
                results.append(("对话结果", chat_result))
        
        return results
    
    def _decide_strategy(self, question):
        """根据问题决定执行策略"""
        strategy = []
        
        if any(word in question for word in ["列出", "查看", "显示"]):
            strategy.append("list")
        
        if any(word in question for word in ["搜索", "查找", "检索"]):
            strategy.append("search")
        
        if any(word in question for word in ["问答", "聊天", "回答"]):
            strategy.append("chat")
        
        # 默认策略
        if not strategy:
            strategy = ["search", "chat"]
        
        return strategy

# 使用示例
async def main():
    mcp_config = {
        "command": "uv",
        "args": [
            "--directory",
            "D:/Agentic RAG based Weknora/WeKnora/mcp-server",
            "run",
            "run_server.py"
        ],
        "env": {
            "WEKNORA_API_KEY": "your_api_key",
            "WEKNORA_BASE_URL": "http://localhost:8080/api/v1"
        }
    }
    
    rag = SimpleAgenticRAG(mcp_config)
    await rag.connect()
    
    results = await rag.answer_question("搜索关于深度学习的相关内容")
    for step, result in results:
        print(f"{step}: {result}")

if __name__ == "__main__":
    asyncio.run(main())
```

### 方案三：在 Cursor/Claude Desktop 中直接使用

如果你在 Cursor 或 Claude Desktop 中配置了 MCP 服务，可以直接与 AI 对话：

```
你：我想实现一个 Agentic RAG 系统，帮我搜索知识库中关于"机器学习"的内容

AI（通过 MCP 调用工具）：
1. 首先调用 list_knowledge_bases 获取知识库列表
2. 然后调用 hybrid_search 搜索相关内容
3. 整合结果并生成答案
```

## Agentic RAG 的核心能力

### 1. 多步骤检索

```python
async def multi_step_retrieval(self, question):
    """多步骤检索策略"""
    # 步骤1: 初步搜索
    initial_results = await self.search(question)
    
    # 步骤2: 如果结果不够，扩展查询
    if len(initial_results) < 3:
        expanded_query = await self.expand_query(question)
        expanded_results = await self.search(expanded_query)
        initial_results.extend(expanded_results)
    
    # 步骤3: 重排序
    reranked = await self.rerank(question, initial_results)
    
    return reranked
```

### 2. 动态工具选择

```python
async def dynamic_tool_selection(self, question):
    """根据问题动态选择工具"""
    # 分析问题复杂度
    complexity = self.analyze_complexity(question)
    
    if complexity == "simple":
        # 简单问题：直接搜索
        return ["hybrid_search"]
    elif complexity == "medium":
        # 中等问题：搜索 + 重排序
        return ["hybrid_search", "rerank"]
    else:
        # 复杂问题：多步骤检索 + 会话
        return ["list_knowledge_bases", "hybrid_search", "create_session", "chat"]
```

### 3. 迭代优化

```python
async def iterative_refinement(self, question, max_iterations=3):
    """迭代优化答案"""
    current_answer = None
    
    for i in range(max_iterations):
        # 搜索相关文档
        docs = await self.search(question)
        
        # 生成答案
        answer = await self.generate(question, docs)
        
        # 评估答案质量
        quality = await self.evaluate_answer(question, answer)
        
        if quality > 0.8:  # 质量足够好
            return answer
        
        # 如果质量不够，基于当前答案重新搜索
        question = f"{question} 基于以下信息: {answer}"
    
    return current_answer
```

## 完整示例：Agentic RAG 系统

```python
import asyncio
from typing import List, Dict, Any
from mcp import ClientSession, StdioServerParameters

class AgenticRAGSystem:
    """完整的 Agentic RAG 系统"""
    
    def __init__(self, mcp_config):
        self.mcp_config = mcp_config
        self.session = None
        self.current_kb_id = None
        self.current_session_id = None
    
    async def initialize(self):
        """初始化系统"""
        server_params = StdioServerParameters(
            command=self.mcp_config["command"],
            args=self.mcp_config["args"],
            env=self.mcp_config["env"]
        )
        self.session = ClientSession(server_params)
        await self.session.initialize()
        
        # 获取默认知识库
        kbs = await self.session.call_tool("list_knowledge_bases", {})
        if kbs.get("data"):
            self.current_kb_id = kbs["data"][0]["id"]
    
    async def process_query(self, query: str) -> Dict[str, Any]:
        """处理用户查询的完整流程"""
        # 1. 分析查询意图
        intent = self._analyze_intent(query)
        
        # 2. 制定执行计划
        plan = self._create_plan(intent, query)
        
        # 3. 执行计划
        results = []
        for step in plan:
            result = await self._execute_step(step, query)
            results.append(result)
            
            # 检查是否需要调整计划
            if self._should_adjust_plan(result):
                plan = self._adjust_plan(plan, result)
        
        # 4. 整合结果
        final_answer = self._synthesize_answer(query, results)
        
        return {
            "query": query,
            "intent": intent,
            "plan": plan,
            "results": results,
            "answer": final_answer
        }
    
    def _analyze_intent(self, query: str) -> str:
        """分析查询意图"""
        if "创建" in query or "新建" in query:
            return "create"
        elif "搜索" in query or "查找" in query:
            return "search"
        elif "问答" in query or "回答" in query:
            return "qa"
        elif "列出" in query or "显示" in query:
            return "list"
        else:
            return "qa"  # 默认是问答
    
    def _create_plan(self, intent: str, query: str) -> List[Dict]:
        """创建执行计划"""
        if intent == "create":
            return [
                {"action": "list_knowledge_bases"},
                {"action": "create_knowledge_base", "params": self._extract_create_params(query)}
            ]
        elif intent == "search":
            return [
                {"action": "hybrid_search", "params": {"query": query}}
            ]
        elif intent == "qa":
            return [
                {"action": "create_session"},
                {"action": "chat", "params": {"query": query}}
            ]
        else:
            return [
                {"action": "list_knowledge_bases"},
                {"action": "hybrid_search", "params": {"query": query}}
            ]
    
    async def _execute_step(self, step: Dict, query: str) -> Dict:
        """执行单个步骤"""
        action = step["action"]
        params = step.get("params", {})
        
        if action == "list_knowledge_bases":
            return await self.session.call_tool("list_knowledge_bases", {})
        
        elif action == "hybrid_search":
            if not self.current_kb_id:
                kbs = await self.session.call_tool("list_knowledge_bases", {})
                if kbs.get("data"):
                    self.current_kb_id = kbs["data"][0]["id"]
            
            return await self.session.call_tool(
                "hybrid_search",
                {"kb_id": self.current_kb_id, "query": params.get("query", query)}
            )
        
        elif action == "create_session":
            if not self.current_kb_id:
                kbs = await self.session.call_tool("list_knowledge_bases", {})
                if kbs.get("data"):
                    self.current_kb_id = kbs["data"][0]["id"]
            
            session = await self.session.call_tool(
                "create_session",
                {"kb_id": self.current_kb_id}
            )
            self.current_session_id = session.get("id")
            return session
        
        elif action == "chat":
            return await self.session.call_tool(
                "chat",
                {"session_id": self.current_session_id, "query": params.get("query", query)}
            )
        
        return {}
    
    def _should_adjust_plan(self, result: Dict) -> bool:
        """判断是否需要调整计划"""
        # 如果搜索结果为空，可能需要调整
        if "chunks" in result and len(result.get("chunks", [])) == 0:
            return True
        return False
    
    def _adjust_plan(self, plan: List[Dict], result: Dict) -> List[Dict]:
        """调整执行计划"""
        # 如果搜索无结果，添加扩展搜索
        new_plan = plan.copy()
        new_plan.append({"action": "expand_search"})
        return new_plan
    
    def _synthesize_answer(self, query: str, results: List[Dict]) -> str:
        """整合结果生成最终答案"""
        answer_parts = []
        
        for result in results:
            if "chunks" in result:
                # 搜索结果
                chunks = result.get("chunks", [])
                if chunks:
                    answer_parts.append(f"找到 {len(chunks)} 条相关内容")
                    for chunk in chunks[:3]:  # 只取前3条
                        answer_parts.append(f"- {chunk.get('content', '')[:100]}...")
            
            elif "response" in result:
                # 聊天响应
                answer_parts.append(result.get("response", ""))
        
        return "\n".join(answer_parts) if answer_parts else "未找到相关信息"
    
    def _extract_create_params(self, query: str) -> Dict:
        """从查询中提取创建参数"""
        # 简单的参数提取逻辑
        return {
            "name": "新知识库",
            "description": query
        }

# 使用示例
async def main():
    mcp_config = {
        "command": "uv",
        "args": [
            "--directory",
            "D:/Agentic RAG based Weknora/WeKnora/mcp-server",
            "run",
            "run_server.py"
        ],
        "env": {
            "WEKNORA_API_KEY": "your_api_key",
            "WEKNORA_BASE_URL": "http://localhost:8080/api/v1"
        }
    }
    
    system = AgenticRAGSystem(mcp_config)
    await system.initialize()
    
    # 处理查询
    result = await system.process_query("搜索关于深度学习的相关内容")
    print(f"查询: {result['query']}")
    print(f"意图: {result['intent']}")
    print(f"答案: {result['answer']}")

if __name__ == "__main__":
    asyncio.run(main())
```

## 总结

✅ **可以使用 MCP 服务实现 Agentic RAG**

MCP 服务提供了：
- 21 个工具接口，覆盖知识库管理的各个方面
- 标准化的协议，易于集成
- 安全的 API 访问方式

实现 Agentic RAG 的关键：
1. **工具调用能力** - 通过 MCP 调用 WeKnora 工具
2. **决策能力** - 根据问题自主选择工具
3. **多步骤执行** - 可以执行多个工具调用
4. **结果整合** - 整合多个工具的结果生成最终答案

你可以：
- 直接在 Cursor/Claude Desktop 中使用（已配置 MCP）
- 使用 Python 框架（LangGraph、AutoGen）集成 MCP
- 直接使用 MCP 客户端库构建自定义系统

需要我帮你实现具体的某个部分吗？

