#!/bin/bash

# PDF解析日志分析脚本
# 用于分析docreader服务中PDF解析失败的原因

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 容器名称
CONTAINER_NAME="WeKnora-docreader"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 检查容器是否存在
check_container() {
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_error "容器 ${CONTAINER_NAME} 不存在或未运行"
        log_info "请先启动docreader服务: docker-compose up -d docreader"
        exit 1
    fi
    
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_warning "容器 ${CONTAINER_NAME} 存在但未运行"
        log_info "尝试启动容器..."
        docker start ${CONTAINER_NAME} 2>/dev/null || {
            log_error "无法启动容器，请检查docker-compose配置"
            exit 1
        }
        sleep 2
    fi
}

# 显示帮助信息
show_help() {
    cat << EOF
PDF解析日志分析工具

用法: $0 [选项]

选项:
  -h, --help              显示帮助信息
  -f, --follow            实时跟踪日志（类似 tail -f）
  -t, --tail N            显示最后N行日志（默认100）
  -e, --errors            只显示错误日志
  -w, --warnings          显示警告和错误日志
  -p, --pdf-only          只显示PDF相关的日志
  -s, --since TIME        显示指定时间之后的日志（如: 10m, 1h, 2024-01-01T00:00:00）
  -a, --all               显示所有日志（不筛选）
  -d, --debug             显示DEBUG级别日志
  -o, --output FILE       将日志输出到文件
  --summary               显示PDF解析统计摘要

示例:
  $0                      # 显示最近100行PDF相关日志
  $0 -f                   # 实时跟踪PDF解析日志
  $0 -e -p                # 只显示PDF解析错误
  $0 -s 1h                # 显示最近1小时的日志
  $0 --summary            # 显示PDF解析统计摘要
EOF
}

# 显示PDF解析统计摘要
show_summary() {
    log_info "正在分析PDF解析统计信息..."
    echo ""
    
    # 统计总请求数
    total_requests=$(docker logs ${CONTAINER_NAME} 2>&1 | grep -i "Received ReadFromFile request" | grep -i "pdf" | wc -l)
    
    # 统计成功解析
    success_count=$(docker logs ${CONTAINER_NAME} 2>&1 | grep -i "PDF parsing complete" | wc -l)
    
    # 统计失败解析
    error_count=$(docker logs ${CONTAINER_NAME} 2>&1 | grep -iE "Failed to parse PDF|PDF.*error|PDF.*failed" | wc -l)
    
    # 统计使用备用解析器
    fallback_count=$(docker logs ${CONTAINER_NAME} 2>&1 | grep -i "fallback parser" | wc -l)
    
    # 统计PDF验证失败
    validation_failed=$(docker logs ${CONTAINER_NAME} 2>&1 | grep -i "PDF validation failed" | wc -l)
    
    # 统计语法错误
    syntax_errors=$(docker logs ${CONTAINER_NAME} 2>&1 | grep -i "PDF syntax error" | wc -l)
    
    echo -e "${CYAN}=== PDF解析统计摘要 ===${NC}"
    echo -e "总PDF请求数:     ${GREEN}${total_requests}${NC}"
    echo -e "成功解析:         ${GREEN}${success_count}${NC}"
    echo -e "失败解析:         ${RED}${error_count}${NC}"
    echo -e "使用备用解析器:   ${YELLOW}${fallback_count}${NC}"
    echo -e "验证失败:         ${RED}${validation_failed}${NC}"
    echo -e "语法错误:         ${RED}${syntax_errors}${NC}"
    echo ""
    
    if [ ${error_count} -gt 0 ]; then
        log_warning "发现 ${error_count} 个PDF解析错误，建议查看详细日志"
    fi
}

# 主函数
main() {
    local FOLLOW=false
    local TAIL=100
    local ERRORS_ONLY=false
    local WARNINGS=false
    local PDF_ONLY=true
    local SINCE=""
    local ALL=false
    local DEBUG=false
    local OUTPUT=""
    local SUMMARY=false
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -f|--follow)
                FOLLOW=true
                shift
                ;;
            -t|--tail)
                TAIL="$2"
                shift 2
                ;;
            -e|--errors)
                ERRORS_ONLY=true
                shift
                ;;
            -w|--warnings)
                WARNINGS=true
                shift
                ;;
            -p|--pdf-only)
                PDF_ONLY=true
                shift
                ;;
            -s|--since)
                SINCE="$2"
                shift 2
                ;;
            -a|--all)
                ALL=true
                PDF_ONLY=false
                shift
                ;;
            -d|--debug)
                DEBUG=true
                shift
                ;;
            -o|--output)
                OUTPUT="$2"
                shift 2
                ;;
            --summary)
                SUMMARY=true
                shift
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 检查容器
    check_container
    
    # 显示统计摘要
    if [ "$SUMMARY" = true ]; then
        show_summary
        exit 0
    fi
    
    # 构建docker logs命令
    local CMD="docker logs"
    
    if [ "$FOLLOW" = true ]; then
        CMD="$CMD -f"
    else
        CMD="$CMD --tail ${TAIL}"
    fi
    
    if [ -n "$SINCE" ]; then
        CMD="$CMD --since ${SINCE}"
    fi
    
    CMD="$CMD ${CONTAINER_NAME} 2>&1"
    
    log_info "正在获取日志..."
    
    # 执行命令并过滤
    if [ "$OUTPUT" != "" ]; then
        eval $CMD > "$OUTPUT"
        log_success "日志已保存到: $OUTPUT"
        exit 0
    fi
    
    # 应用过滤器
    local FILTER=""
    
    if [ "$ALL" = false ]; then
        if [ "$PDF_ONLY" = true ]; then
            FILTER="grep -iE 'pdf|parsing.*pdf|Failed to parse|PDF.*error|PDF.*failed|pdfplumber|pypdf|PDF validation|PDF syntax'"
        fi
        
        if [ "$ERRORS_ONLY" = true ]; then
            if [ -n "$FILTER" ]; then
                FILTER="$FILTER | grep -iE 'ERROR|error|Failed|failed'"
            else
                FILTER="grep -iE 'ERROR|error|Failed|failed'"
            fi
        elif [ "$WARNINGS" = true ]; then
            if [ -n "$FILTER" ]; then
                FILTER="$FILTER | grep -iE 'ERROR|WARNING|error|warning|Failed|failed'"
            else
                FILTER="grep -iE 'ERROR|WARNING|error|warning|Failed|failed'"
            fi
        fi
        
        if [ "$DEBUG" = false ]; then
            if [ -n "$FILTER" ]; then
                FILTER="$FILTER | grep -v 'DEBUG'"
            else
                FILTER="grep -v 'DEBUG'"
            fi
        fi
    fi
    
    # 执行并显示
    if [ -n "$FILTER" ]; then
        eval $CMD | eval $FILTER | while IFS= read -r line; do
            # 高亮显示错误
            if echo "$line" | grep -qiE "error|failed"; then
                echo -e "${RED}$line${NC}"
            # 高亮显示警告
            elif echo "$line" | grep -qiE "warning"; then
                echo -e "${YELLOW}$line${NC}"
            # 高亮显示成功
            elif echo "$line" | grep -qiE "success|complete|extracted"; then
                echo -e "${GREEN}$line${NC}"
            # 高亮显示PDF相关信息
            elif echo "$line" | grep -qiE "pdf|parsing"; then
                echo -e "${CYAN}$line${NC}"
            else
                echo "$line"
            fi
        done
    else
        eval $CMD | while IFS= read -r line; do
            # 高亮显示错误
            if echo "$line" | grep -qiE "error|failed"; then
                echo -e "${RED}$line${NC}"
            # 高亮显示警告
            elif echo "$line" | grep -qiE "warning"; then
                echo -e "${YELLOW}$line${NC}"
            # 高亮显示成功
            elif echo "$line" | grep -qiE "success|complete|extracted"; then
                echo -e "${GREEN}$line${NC}"
            else
                echo "$line"
            fi
        done
    fi
}

# 运行主函数
main "$@"

