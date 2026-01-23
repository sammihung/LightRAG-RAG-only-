import os
from pathlib import Path
from lightrag.utils import logger

# 1. 嘗試 import RAGAnything
try:
    from raganything import RAGAnything
    RAG_ANYTHING_AVAILABLE = True
except ImportError as e:
    logger.warning(f"RAGAnything import failed. Error details: {e}")
    logger.warning("RAGAnything not found. RAG adapter will be disabled.")
    RAG_ANYTHING_AVAILABLE = False

# 2. 檢查檔案是否支援
def is_supported_by_raganything(filename: str) -> bool:
    if not RAG_ANYTHING_AVAILABLE:
        return False
    # 支援的格式列表
    ext = Path(filename).suffix.lower()
    return ext in ['.pdf', '.docx', '.pptx', '.jpg', '.jpeg', '.png', '.bmp']

# 3. 核心處理函數 (必須接受 3 個參數)
async def process_with_raganything(rag, file_path, track_id):
    if not RAG_ANYTHING_AVAILABLE:
        raise ImportError("RAGAnything module is not installed.")

    logger.info(f"[RAG-Adapter] 初始化 RAGAnything wrapper... (Track ID: {track_id})")

    # 定義 Vision Model Function (動態使用 LightRAG 的 LLM 設定)
    async def vision_model_func(prompt, system_prompt=None, history_messages=[], image_data=None, **kwargs):
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
            
        if image_data:
            # 構建多模態訊息 (OpenAI 兼容格式)
            user_content = [
                {"type": "text", "text": prompt},
                {
                    "type": "image_url", 
                    "image_url": {"url": f"data:image/jpeg;base64,{image_data}"}
                }
            ]
            messages.append({"role": "user", "content": user_content})
        else:
            messages.append({"role": "user", "content": prompt})

        # 調用 LightRAG 本身的 LLM 函數
        return await rag.llm_model_func(
            prompt,
            system_prompt=system_prompt,
            history_messages=history_messages,
            messages=messages,
            **kwargs
        )

    # 初始化 RAGAnything (傳入 lightrag 實例和 vision 函數)
    rag_any_instance = RAGAnything(lightrag=rag, vision_model_func=vision_model_func)

    # 設定輸出目錄
    output_dir = os.path.join(os.path.dirname(file_path), "rag_output")
    os.makedirs(output_dir, exist_ok=True)

    logger.info(f"[RAG-Adapter] 開始處理多模態文檔: {file_path}")
    
    # 執行處理
    await rag_any_instance.process_document_complete(
        file_path=str(file_path),
        output_dir=output_dir
    )
    
    logger.info(f"[RAG-Adapter] 處理完成: {file_path}")
    return True