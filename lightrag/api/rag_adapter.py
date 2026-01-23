# lightrag/api/rag_adapter.py
import os
from pathlib import Path
from lightrag.utils import logger

# 嘗試 import RAGAnything，如果冇安裝就唔好整爆個 server
try:
    from raganything import RagAnything
    rag_any = RagAnything()
    RAG_ANYTHING_AVAILABLE = True
except ImportError:
    logger.warning("RAGAnything not found. RAG adapter will be disabled.")
    rag_any = None
    RAG_ANYTHING_AVAILABLE = False

def is_supported_by_raganything(filename: str) -> bool:
    """檢查檔案類型是否應該交給 RAGAnything 處理"""
    if not RAG_ANYTHING_AVAILABLE:
        return False
        
    ext = Path(filename).suffix.lower()
    # 這裡列出你想用 RAGAnything 處理的格式
    # 注意：原本 LightRAG 可能已經 handle 咗 .txt，如果你想 override 就可以加埋入去
    return ext in ['.pdf', '.docx', '.pptx', '.jpg', '.png', '.md', '.html']

async def process_with_raganything(file_path: str) -> str:
    """
    使用 RAGAnything 解析檔案並返回純文字
    """
    if not rag_any:
        raise ImportError("RAGAnything module is not loaded.")

    try:
        logger.info(f"[RAG-Adapter] Processing {file_path} with RAGAnything...")
        
        # 假設 rag_any.parse 係同步 (sync) 嘅，如果佢係 async 就要加 await
        # 這裡根據你的 raganything 實際 API 調整
        parsed_result = rag_any.parse(file_path) 
        
        # 確保返回 string
        if hasattr(parsed_result, 'content'):
            return parsed_result.content
        return str(parsed_result)
        
    except Exception as e:
        logger.error(f"[RAG-Adapter] Error processing file: {e}")
        raise e