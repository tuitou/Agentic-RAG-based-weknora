# PDF解析日志分析指南

## 快速查看PDF解析日志

### 1. 查看实时日志（推荐）

```bash
# 实时跟踪docreader容器日志
docker logs -f WeKnora-docreader

# 只查看PDF相关的日志
docker logs -f WeKnora-docreader 2>&1 | grep -i "pdf\|parsing\|Failed"
```

### 2. 查看最近的错误日志

```bash
# 查看所有错误和警告
docker logs WeKnora-docreader 2>&1 | grep -iE "ERROR|WARNING|Failed"

# 查看PDF相关的错误
docker logs WeKnora-docreader 2>&1 | grep -iE "PDF.*error|PDF.*failed|Failed to parse"
```

### 3. 查看指定时间范围的日志

```bash
# 查看最近1小时的日志
docker logs --since 1h WeKnora-docreader

# 查看最近24小时的日志
docker logs --since 24h WeKnora-docreader

# 查看指定时间之后的日志
docker logs --since "2024-11-11T08:00:00" WeKnora-docreader
```

### 4. 导出日志到文件

```bash
# 导出所有日志
docker logs WeKnora-docreader > docreader_logs.txt 2>&1

# 导出最近1000行日志
docker logs --tail 1000 WeKnora-docreader > docreader_logs.txt 2>&1

# 导出指定时间范围的日志
docker logs --since 24h WeKnora-docreader > docreader_logs_24h.txt 2>&1
```

## 关键日志信息识别

### 成功解析的日志特征

```
INFO  parser.pdf_parser      | Parsing PDF with pdfplumber, content size: 7151857 bytes
INFO  parser.pdf_parser      | PDF has 123 pages
INFO  parser.pdf_parser      | PDF parsing complete. Extracted 590071 text chars.
INFO  __main__               | Successfully parsed file xxx.pdf, returning 799 chunks
```

### 失败解析的日志特征

#### 1. PDF验证失败
```
ERROR parser.pdf_parser      | PDF validation failed: 文件不是有效的PDF格式（缺少PDF文件头）
ERROR parser.pdf_parser      | PDF validation failed: PDF文件太小，可能已损坏
```

#### 2. PDF语法错误
```
ERROR parser.pdf_parser      | PDF syntax error (pdfplumber): [具体错误信息]
DEBUG parser.pdf_parser      | PDF syntax error traceback: [堆栈跟踪]
INFO  parser.pdf_parser      | Trying fallback parser due to PDF syntax error
```

#### 3. pdfplumber解析失败
```
ERROR parser.pdf_parser      | Failed to parse PDF document with pdfplumber: [错误类型]: [错误消息]
DEBUG parser.pdf_parser      | Full traceback: [堆栈跟踪]
INFO  parser.pdf_parser      | Trying fallback parser due to pdfplumber error
```

#### 4. 所有解析方法都失败
```
ERROR parser.pdf_parser      | All PDF parsing methods failed. Error type: [类型], Message: [消息]
```

#### 5. 提取文本为空
```
WARNING parser.pdf_parser    | pdfplumber extracted no text, trying fallback parser
WARNING parser.pdf_parser    | Both pdfplumber and fallback parser extracted no text
```

#### 6. 页面处理错误
```
WARNING parser.pdf_parser    | Error processing page 5: [错误信息]
DEBUG parser.pdf_parser       | Page 5 error traceback: [堆栈跟踪]
```

#### 7. 表格处理错误
```
WARNING parser.pdf_parser    | Error processing table on page 3: [错误信息]
```

#### 8. 备用解析器使用
```
INFO  parser.pdf_parser      | Attempting to parse PDF with pypdf (fallback method)
INFO  parser.pdf_parser      | Fallback parser successfully extracted text
```

## 日志分析步骤

### 步骤1：确认PDF解析是否失败

```bash
# 查找失败的关键词
docker logs WeKnora-docreader 2>&1 | grep -iE "Failed to parse|validation failed|syntax error|All PDF parsing methods failed"
```

### 步骤2：查看详细的错误信息

如果发现错误，查看完整的错误上下文：

```bash
# 查看错误前后的日志（前后各20行）
docker logs WeKnora-docreader 2>&1 | grep -A 20 -B 20 "Failed to parse"
```

### 步骤3：检查是否使用了备用解析器

```bash
# 查看备用解析器的使用情况
docker logs WeKnora-docreader 2>&1 | grep -i "fallback parser"
```

### 步骤4：统计解析成功率

```bash
# 统计成功解析的数量
docker logs WeKnora-docreader 2>&1 | grep -c "Successfully parsed file.*pdf"

# 统计失败解析的数量
docker logs WeKnora-docreader 2>&1 | grep -c "Failed to parse\|validation failed\|All PDF parsing methods failed"
```

## 常见错误模式分析

### 模式1：PDF文件格式问题

**日志特征：**
```
ERROR parser.pdf_parser | PDF validation failed: 文件不是有效的PDF格式（缺少PDF文件头）
```

**可能原因：**
- PDF文件损坏
- 文件不是真正的PDF格式
- 文件传输过程中损坏

**解决方案：**
- 检查PDF文件是否可以在其他PDF阅读器中打开
- 重新下载或获取PDF文件
- 使用PDF修复工具修复文件

### 模式2：PDF语法错误

**日志特征：**
```
ERROR parser.pdf_parser | PDF syntax error (pdfplumber): [错误信息]
INFO  parser.pdf_parser  | Trying fallback parser due to PDF syntax error
```

**可能原因：**
- PDF文件格式不标准
- PDF生成工具产生的非标准PDF
- PDF文件部分损坏

**解决方案：**
- 系统会自动尝试备用解析器（pypdf）
- 如果备用解析器也失败，需要修复PDF文件

### 模式3：提取文本为空

**日志特征：**
```
WARNING parser.pdf_parser | pdfplumber extracted no text, trying fallback parser
WARNING parser.pdf_parser | Both pdfplumber and fallback parser extracted no text
```

**可能原因：**
- PDF是扫描版（纯图像，无文本层）
- PDF使用特殊编码或字体
- PDF内容为图像或图表

**解决方案：**
- 启用OCR功能（`enable_multimodal=True`）
- 检查PDF是否包含可提取的文本层
- 对于扫描版PDF，需要使用OCR识别

### 模式4：页面处理错误

**日志特征：**
```
WARNING parser.pdf_parser | Error processing page 5: [错误信息]
```

**可能原因：**
- 特定页面格式特殊
- 页面包含损坏的内容
- 页面处理超时或内存不足

**解决方案：**
- 系统会自动跳过失败的页面，继续处理其他页面
- 检查日志了解哪些页面失败及原因
- 如果失败页面较多，可能需要修复PDF文件

### 模式5：内存或资源问题

**日志特征：**
```
ERROR parser.pdf_parser | Failed to parse PDF document with pdfplumber: MemoryError: [错误信息]
```

**可能原因：**
- PDF文件过大
- 系统内存不足
- 并发处理过多PDF文件

**解决方案：**
- 增加容器内存限制
- 减少并发处理的PDF数量
- 分批处理大型PDF文件

## 使用日志分析脚本

项目提供了日志分析脚本（`scripts/analyze_pdf_logs.sh`），可以更方便地分析日志：

```bash
# 显示PDF解析统计摘要
./scripts/analyze_pdf_logs.sh --summary

# 实时跟踪PDF解析日志
./scripts/analyze_pdf_logs.sh -f

# 只显示错误日志
./scripts/analyze_pdf_logs.sh -e

# 显示最近1小时的日志
./scripts/analyze_pdf_logs.sh -s 1h
```

## 调试模式

如果需要更详细的日志信息，可以设置日志级别为DEBUG：

```bash
# 在docker-compose.yml中设置
environment:
  - LOG_LEVEL=DEBUG

# 或者直接设置环境变量
export LOG_LEVEL=DEBUG
docker-compose restart docreader
```

DEBUG级别会输出：
- 完整的堆栈跟踪信息
- 详细的处理步骤
- 每个页面的处理状态
- 表格检测和提取的详细信息

## 日志文件位置

如果使用Docker，日志默认输出到stdout/stderr，可以通过以下方式查看：

```bash
# 查看容器日志
docker logs WeKnora-docreader

# 查看最近的日志
docker logs --tail 100 WeKnora-docreader

# 实时跟踪日志
docker logs -f WeKnora-docreader
```

## 联系支持

如果遇到PDF解析问题，请提供以下信息：

1. **错误日志**：包含ERROR和WARNING级别的完整日志
2. **PDF文件信息**：文件大小、页数、来源
3. **重现步骤**：如何触发解析失败
4. **环境信息**：Docker版本、系统资源（内存、CPU）
5. **PDF文件样本**：如可能，提供失败的PDF文件样本

这将有助于进一步诊断和解决问题。

