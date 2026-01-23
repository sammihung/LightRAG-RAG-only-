from lightrag.utils import logger

class BaseModalProcessor:
    def __init__(self, *args, **kwargs):
        pass

class ImageModalProcessor(BaseModalProcessor):
    pass

class TableModalProcessor(BaseModalProcessor):
    pass

class EquationModalProcessor(BaseModalProcessor):
    pass

class GenericModalProcessor(BaseModalProcessor):
    pass

class ContextExtractor:
    def __init__(self, *args, **kwargs):
        pass