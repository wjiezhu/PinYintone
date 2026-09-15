"""让测试能 import app.*：把 backend/ 加入路径。

不放 tests/__init__.py——那会改变 pytest 的导入模式，
使 app 包被以两个不同名字各导入一次，SQLAlchemy 会报
「Table ... is already defined for this MetaData instance」。
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
