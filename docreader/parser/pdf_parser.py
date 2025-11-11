import logging
import os
import io
import traceback
from typing import Any, List, Iterator, Optional, Mapping, Tuple, Dict, Union

import pdfplumber
import tempfile
from .base_parser import BaseParser

logger = logging.getLogger(__name__)

# 尝试导入备用PDF解析库
try:
    import pypdf
    PYPDF_AVAILABLE = True
except ImportError:
    PYPDF_AVAILABLE = False
    logger.warning("pypdf library not available, fallback parsing will be limited")

class PDFParser(BaseParser):
    """
    PDF Document Parser

    This parser handles PDF documents by extracting text content.
    It uses pdfplumber as the primary parser, with pypdf as a fallback.
    """
    def _convert_table_to_markdown(self, table_data: list) -> str:
    
        if not table_data or not table_data[0]: return ""
        def clean_cell(cell):
            if cell is None: return ""
            return str(cell).replace("\n", " <br> ")
        try:
            markdown = ""
            header = [clean_cell(cell) for cell in table_data[0]]
            markdown += "| " + " | ".join(header) + " |\n"
            markdown += "| " + " | ".join(["---"] * len(header)) + " |\n"
            for row in table_data[1:]:
                if not row: continue
                body_row = [clean_cell(cell) for cell in row]
                if len(body_row) != len(header):
                    logger.warning(f"Skipping malformed table row: {body_row}")
                    continue
                markdown += "| " + " | ".join(body_row) + " |\n"
            return markdown
        except Exception as e:
            logger.error(f"Error converting table to markdown: {e}")
            return ""
    
    def _parse_with_pypdf(self, temp_pdf_path: str) -> str:
        """使用pypdf作为备用解析方法"""
        if not PYPDF_AVAILABLE:
            logger.warning("pypdf not available, cannot use fallback parser")
            return ""
        
        try:
            logger.info("Attempting to parse PDF with pypdf (fallback method)")
            all_page_content = []
            
            with open(temp_pdf_path, 'rb') as file:
                pdf_reader = pypdf.PdfReader(file)
                logger.info(f"PDF has {len(pdf_reader.pages)} pages (pypdf)")
                
                for page_num, page in enumerate(pdf_reader.pages):
                    try:
                        text = page.extract_text()
                        if text:
                            all_page_content.append(text)
                            logger.info(f"Extracted {len(text)} characters from page {page_num + 1} (pypdf)")
                        else:
                            logger.warning(f"No text extracted from page {page_num + 1} (pypdf)")
                    except Exception as e:
                        logger.warning(f"Error extracting text from page {page_num + 1} (pypdf): {str(e)}")
                        continue
                
                final_text = "\n\n--- Page Break ---\n\n".join(all_page_content)
                logger.info(f"pypdf parsing complete. Extracted {len(final_text)} text chars.")
                return final_text
        except Exception as e:
            logger.error(f"pypdf fallback parsing failed: {str(e)}")
            logger.debug(f"pypdf error traceback: {traceback.format_exc()}")
            return ""
    
    def _validate_pdf_content(self, content: bytes) -> Tuple[bool, str]:
        """验证PDF文件内容是否有效"""
        try:
            # 检查PDF文件头
            if len(content) < 4:
                return False, "PDF文件太小，可能已损坏"
            
            # PDF文件应该以%PDF开头
            if not content[:4].startswith(b'%PDF'):
                return False, "文件不是有效的PDF格式（缺少PDF文件头）"
            
            # 检查文件大小
            if len(content) == 0:
                return False, "PDF文件为空"
            
            return True, ""
        except Exception as e:
            return False, f"PDF验证失败: {str(e)}"
    
    def parse_into_text(self, content: bytes) -> Union[str, Tuple[str, Dict[str, Any]]]:
       
        logger.info(f"Parsing PDF with pdfplumber, content size: {len(content)} bytes")

        # 验证PDF内容
        is_valid, error_msg = self._validate_pdf_content(content)
        if not is_valid:
            logger.error(f"PDF validation failed: {error_msg}")
            return ""

        all_page_content = []
        temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix=".pdf")
        temp_pdf_path = temp_pdf.name
        
        try:
            temp_pdf.write(content)
            temp_pdf.close()
            logger.info(f"PDF content written to temporary file: {temp_pdf_path}")
            
            # 尝试使用pdfplumber解析
            try:
                with pdfplumber.open(temp_pdf_path) as pdf:
                    logger.info(f"PDF has {len(pdf.pages)} pages")
                    
                    for page_num, page in enumerate(pdf.pages):
                        try:
                            page_content_parts = []
                            
                            # Try-fallback strategy for table detection
                            default_settings = { "vertical_strategy": "lines", "horizontal_strategy": "lines" }
                            found_tables = page.find_tables(default_settings)
                            if not found_tables:
                                logger.info(f"Page {page_num+1}: Default strategy found no tables. Trying fallback strategy.")
                                fallback_settings = { "vertical_strategy": "text", "horizontal_strategy": "lines" }
                                found_tables = page.find_tables(fallback_settings)

                            table_bboxes = [table.bbox for table in found_tables]
                            # Define a filter function that keeps objects NOT inside any table bbox.
                            def not_within_bboxes(obj):
                                """Check if an object is outside all table bounding boxes."""
                                for bbox in table_bboxes:
                                    # Check if the object's vertical center is within a bbox
                                    if bbox[1] <= (obj["top"] + obj["bottom"]) / 2 <= bbox[3]:
                                        return False # It's inside a table, so we DON'T keep it
                                return True # It's outside all tables, so we DO keep it

                            # that contains only the non-table text.
                            non_table_page = page.filter(not_within_bboxes)

                            # Now, extract text from this filtered page view.
                            text = non_table_page.extract_text(x_tolerance=2)
                            if text:
                                page_content_parts.append(text)
                      
                            # Process and append the structured Markdown tables
                            if found_tables:
                                logger.info(f"Found {len(found_tables)} tables on page {page_num + 1}")
                                for table in found_tables:
                                    try:
                                        markdown_table = self._convert_table_to_markdown(table.extract())
                                        page_content_parts.append(f"\n\n{markdown_table}\n\n")
                                    except Exception as e:
                                        logger.warning(f"Error processing table on page {page_num + 1}: {str(e)}")
                                        continue
                            
                            all_page_content.append("".join(page_content_parts))
                        except Exception as e:
                            logger.warning(f"Error processing page {page_num + 1}: {str(e)}")
                            logger.debug(f"Page {page_num + 1} error traceback: {traceback.format_exc()}")
                            # 继续处理下一页
                            continue

                final_text = "\n\n--- Page Break ---\n\n".join(all_page_content)
                logger.info(f"PDF parsing complete. Extracted {len(final_text)} text chars.")
                
                # 如果提取的文本为空，尝试备用方法
                if not final_text.strip():
                    logger.warning("pdfplumber extracted no text, trying fallback parser")
                    fallback_text = self._parse_with_pypdf(temp_pdf_path)
                    if fallback_text.strip():
                        logger.info("Fallback parser successfully extracted text")
                        return fallback_text
                    else:
                        logger.warning("Both pdfplumber and fallback parser extracted no text")
                
                return final_text
                
            except pdfplumber.exceptions.PDFSyntaxError as e:
                logger.error(f"PDF syntax error (pdfplumber): {str(e)}")
                logger.debug(f"PDF syntax error traceback: {traceback.format_exc()}")
                # 尝试备用解析器
                logger.info("Trying fallback parser due to PDF syntax error")
                fallback_text = self._parse_with_pypdf(temp_pdf_path)
                if fallback_text.strip():
                    logger.info("Fallback parser successfully extracted text after syntax error")
                    return fallback_text
                return ""
            except Exception as e:
                error_type = type(e).__name__
                error_msg = str(e)
                logger.error(f"Failed to parse PDF document with pdfplumber: {error_type}: {error_msg}")
                logger.debug(f"Full traceback: {traceback.format_exc()}")
                
                # 尝试备用解析器
                logger.info("Trying fallback parser due to pdfplumber error")
                fallback_text = self._parse_with_pypdf(temp_pdf_path)
                if fallback_text.strip():
                    logger.info("Fallback parser successfully extracted text after error")
                    return fallback_text
                
                # 提供更详细的错误信息
                logger.error(f"All PDF parsing methods failed. Error type: {error_type}, Message: {error_msg}")
                return ""
            
        except Exception as e:
            error_type = type(e).__name__
            error_msg = str(e)
            logger.error(f"Unexpected error during PDF parsing: {error_type}: {error_msg}")
            logger.debug(f"Unexpected error traceback: {traceback.format_exc()}")
            return ""
        finally:
            # This block is GUARANTEED to execute, preventing resource leaks.
            if os.path.exists(temp_pdf_path):
                try:
                    os.remove(temp_pdf_path)
                    logger.info(f"Temporary file cleaned up: {temp_pdf_path}")
                except OSError as e:
                    logger.error(f"Error removing temporary file {temp_pdf_path}: {e}")
