"""
JibJab C Transpiler - Converts JJ to C
Uses shared C-family base from cfamily.py
"""

from .cfamily import CFamilyTranspiler


class CTranspiler(CFamilyTranspiler):
    target_name = 'c'
