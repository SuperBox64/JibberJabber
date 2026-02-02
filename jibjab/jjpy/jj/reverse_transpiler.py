"""
JibJab Reverse Transpiler - Converts target languages back to JJ
Ported from the Swift ReverseTranspiler implementation.
Uses shared config from common/jj.json and common/targets/*.json
"""

import re
from .lexer import JJ, load_target_config


# MARK: - JJ Emit Helpers

def _jj_print(expr):
    return f"{JJ['keywords']['print']}::{JJ['syntax']['emit']}({expr})"

def _jj_snag(name, val):
    return f"{JJ['keywords']['snag']}{{{name}}}::{JJ['syntax']['val']}({val})"

def _jj_yeet(val):
    return f"{JJ['keywords']['yeet']}{{{val}}}"

def _jj_kaboom(val):
    return f"{JJ['keywords']['kaboom']}{{{val}}}"

def _jj_invoke(name, args):
    return f"{JJ['keywords']['invoke']}{{{name}}}::{JJ['syntax']['with']}({args})"

def _jj_morph(name, params):
    return f"{JJ['blocks']['morph']}{name}({params}){JJ['blockSuffix']}"

def _jj_loop(v, start, end):
    return f"{JJ['blocks']['loop']}{v}{JJ['structure']['colon']}{start}{JJ['structure']['range']}{end}{JJ['blockSuffix']}"

def _jj_when(cond):
    return f"{JJ['blocks']['when']}{cond}{JJ['blockSuffix']}"

JJ_TRY = JJ['blocks']['try']
JJ_OOPS = JJ['blocks']['oops']
JJ_ELSE = JJ['blocks']['else']
JJ_END = JJ['blocks']['end']
JJ_COMMENT = JJ['literals']['comment']

NUM_PREFIX = JJ['literals']['numberPrefix']
STRING_DELIM = JJ['literals']['stringDelim']

OP = JJ['operators']


# MARK: - Shared Helpers

def _jj_indent(level):
    return '  ' * level


def _balanced_parens(s):
    depth = 0
    for c in s:
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
        if depth < 0:
            return False
    return depth == 0


def _replace_outside_strings(text, find, replace):
    result = []
    in_string = False
    i = 0
    while i < len(text):
        if text[i] == '"':
            in_string = not in_string
            result.append(text[i])
            i += 1
            continue
        if in_string:
            result.append(text[i])
            i += 1
            continue
        if text[i:i+len(find)] == find:
            result.append(replace)
            i += len(find)
        else:
            result.append(text[i])
            i += 1
    return ''.join(result)


def _reverse_numbers(s):
    delim = STRING_DELIM
    result = []
    in_string = False
    i = 0
    while i < len(s):
        c = s[i]
        if c == delim:
            in_string = not in_string
            result.append(c)
            i += 1
            continue
        if in_string:
            result.append(c)
            i += 1
            continue

        is_negative = (c == '-' and i + 1 < len(s) and s[i+1].isdigit())
        if c.isdigit() or is_negative:
            prev_char = s[i-1] if i > 0 else ' '
            if prev_char == NUM_PREFIX[0] or prev_char.isalpha() or prev_char == '_':
                result.append(c)
                i += 1
                continue
            num_str = c
            j = i + 1
            while j < len(s) and (s[j].isdigit() or s[j] == '.'):
                num_str += s[j]
                j += 1
            next_char = s[j] if j < len(s) else ' '
            if not next_char.isalpha() and next_char != '_':
                result.append(NUM_PREFIX)
            result.append(num_str)
            i = j
        else:
            result.append(c)
            i += 1
    return ''.join(result)


def _reverse_expr(expr):
    s = expr.strip()

    # Strip outer parens if fully wrapped
    if s.startswith('(') and s.endswith(')'):
        inner = s[1:-1]
        if _balanced_parens(inner):
            s = inner

    # JS-specific operators
    js_target = load_target_config('js')
    if js_target.get('eq', '==') != '==':
        s = _replace_outside_strings(s, f" {js_target['eq']} ", f" {OP['eq']['symbol']} ")
    if js_target.get('neq', '!=') != '!=':
        s = _replace_outside_strings(s, f" {js_target['neq']} ", f" {OP['neq']['symbol']} ")

    # Multi-char emit operators first
    ordered_ops = [
        ('lte', 'lte'), ('gte', 'gte'), ('neq', 'neq'), ('eq', 'eq'),
        ('and', 'and'), ('or', 'or'),
        ('lt', 'lt'), ('gt', 'gt'),
        ('add', 'add'), ('sub', 'sub'), ('mul', 'mul'), ('div', 'div'), ('mod', 'mod'),
    ]
    for op_name, _ in ordered_ops:
        op = OP[op_name]
        s = _replace_outside_strings(s, f" {op['emit']} ", f" {op['symbol']} ")

    s = _reverse_numbers(s)
    return s


def _known_functions(target):
    funcs = set()
    for template in [target.get('print', ''), target.get('printInt', target.get('print', '')),
                     target.get('printStr', target.get('print', '')),
                     target.get('printBool', target.get('print', ''))]:
        if '.' in template:
            dot_idx = template.index('.')
            prefix = template[:dot_idx]
            if '{' not in prefix:
                funcs.add(prefix)
        paren_idx = template.find('(')
        if paren_idx > 0:
            name = template[:paren_idx]
            if '{' not in name and name:
                funcs.add(name)
    for tmpl in [target.get('forRange', ''), target.get('if', ''), target.get('else', ''),
                 target.get('func', ''), target.get('return', ''), target.get('while', ''),
                 target.get('var', ''), target.get('call', '')]:
        first_word = ''
        for c in tmpl:
            if c.isalpha() or c == '_':
                first_word += c
            else:
                break
        if first_word:
            funcs.add(first_word)
    if target.get('main'):
        funcs.add('main')
    return funcs


def _reverse_func_calls(expr, target):
    known = _known_functions(target)
    pattern = re.compile(r'\b([a-zA-Z_][a-zA-Z0-9_]*)\(([^)]*)\)')
    matches = list(pattern.finditer(expr))
    result = expr
    for m in reversed(matches):
        name = m.group(1)
        args = m.group(2)
        if name not in known and name:
            replacement = _jj_invoke(name, args)
            result = result[:m.start()] + replacement + result[m.end():]
    return result


# MARK: - Pattern Builders (from target configs)

def _header_patterns(target):
    header = target.get('header', '')
    parts = header.replace('\\n', '\n').split('\n')
    return [p.strip() for p in parts if p.strip()]


def _comment_prefix(target):
    header = target.get('header', '')
    if header.startswith('//'):
        return '//'
    if header.startswith('#!') or header.startswith('# ') or header.startswith('#\n'):
        return '#'
    if header.startswith('--'):
        return '--'
    return '//'


def _type_alternation(target):
    types = set()
    if 'types' in target:
        for v in target['types'].values():
            types.add(v)
    types.add(target.get('stringType', 'String'))
    types.add(target.get('expandStringType', 'String'))
    types.add('void')
    return '(?:' + '|'.join(re.escape(t) for t in sorted(types, key=lambda x: -len(x))) + ')'


def _main_signature(target):
    main = target.get('main')
    if not main:
        return None
    lines = main.replace('\\n', '\n').split('\n')
    sig = lines[0] if lines else main
    brace_idx = sig.find('{')
    if brace_idx >= 0:
        sig = sig[:brace_idx].strip()
    body_idx = sig.find('{body}')
    if body_idx >= 0:
        sig = sig[:body_idx].strip()
    return sig if sig else None


def _print_pattern(target):
    template = target.get('printInt', target.get('print', ''))
    if not template:
        return None
    if 'printf' in template:
        return re.compile(r'^printf\("%[a-z]*\\n",\s*(?:\(long\))?(.+)\);$')
    if 'std::cout' in template:
        return re.compile(r'^std::cout\s*<<\s*(.+?)\s*<<\s*std::endl;$')
    if 'fmt.Println' in template:
        return re.compile(r'^fmt\.Println\((.+)\)$')
    if 'console.log' in template:
        return re.compile(r'^console\.log\((.+)\);$')
    if template.startswith('log '):
        return re.compile(r'^log\s+(.+)$')
    func_template = template.replace('{expr}', 'PLACEHOLDER')
    paren_idx = func_template.find('(')
    if paren_idx >= 0:
        func_name = func_template[:paren_idx]
        if '{' not in func_name:
            has_semi = template.endswith(';')
            semi = '?' if has_semi else ''
            return re.compile(f'^{re.escape(func_name)}\\((.+)\\);?{semi}$')
    return None


def _dual_print_pattern():
    return re.compile(r'^(?:printf\("%[a-z]*\\n",\s*(?:\(long\))?(.+)\)|std::cout\s*<<\s*(.+?)\s*<<\s*std::endl);$')


def _var_pattern(target):
    template = target.get('var', '')
    if template == '{name} = {value}':
        return re.compile(r'^([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.+)$')
    if template.startswith('set '):
        return re.compile(r'^set\s+(\w+)\s+to\s+(.+)$')
    if '{type}' in template:
        types = _type_alternation(target)
        has_semi = template.endswith(';')
        patterns = [f'{types}\\s+(\\w+)\\s*=\\s*(.+?){";" if has_semi else ""}$']
        var_auto = target.get('varAuto', '')
        if var_auto and var_auto.startswith('auto '):
            patterns.append(r'auto\s+(\w+)\s*=\s*(.+?);$')
        var_infer = target.get('varInfer', '')
        if var_infer and var_infer.startswith('var '):
            patterns.append(r'var\s+(\w+)\s*=\s*(.+)$')
        combined = '|'.join(patterns)
        return re.compile(f'^(?:{combined})')
    for kw in ['let', 'const', 'var']:
        if template.startswith(f'{kw} '):
            has_semi = template.endswith(';')
            if ': {type}' in template:
                types = _type_alternation(target)
                return re.compile(f'^var\\s+(\\w+)(?:\\s*:\\s*{types})?\\s*=\\s*(.+){";" if has_semi else ""}$')
            return re.compile(f'^(?:let|const|var)\\s+(\\w+)\\s*=\\s*(.+){";" if has_semi else ""}$')
    if template.startswith('var ') and '{type}' in template:
        return re.compile(r'^(?:var\s+)?(\w+)\s*:?=\s*(.+)$')
    return None


def _for_pattern(target):
    template = target.get('forRange', '')
    if 'for (' in template or 'for(' in template:
        after_paren = template.split('(', 1)[1] if '(' in template else ''
        if after_paren.startswith('int '):
            iter_type = 'int'
        elif after_paren.startswith('let '):
            iter_type = 'let'
        else:
            iter_type = r'\w+'
        return re.compile(f'^for\\s*\\({re.escape(iter_type)}\\s+(\\w+)\\s*=\\s*(\\d+);\\s*\\w+\\s*<\\s*(\\d+);')
    if '..<' in template:
        return re.compile(r'^for\s+(\w+)\s+in\s+(\d+)\.\.<(\d+)\s*\{$')
    if ':=' in template:
        return re.compile(r'^for\s+(\w+)\s*:=\s*(\d+);\s*\w+\s*<\s*(\d+);')
    if 'range(' in template:
        return re.compile(r'^for\s+(\w+)\s+in\s+range\((\d+),\s*(\d+)\):$')
    if 'repeat with' in template:
        return re.compile(r'^repeat\s+with\s+(\w+)\s+from\s+(\d+)\s+to\s+\((\d+)\s*-\s*1\)$')
    return None


def _if_pattern(target):
    template = target.get('if', '')
    if '({condition})' in template:
        return re.compile(r'^if\s*\((.+)\)\s*\{$')
    if template.endswith('{condition} {'):
        return re.compile(r'^if\s+(.+?)\s*\{$')
    if template.endswith(':'):
        return re.compile(r'^if\s+(.+):$')
    if template.endswith('then'):
        return re.compile(r'^if\s+(.+?)\s+then$')
    return None


def _else_pattern(target):
    template = target.get('else', '')
    if '}' in template and '{' in template:
        return re.compile(r'^\}?\s*else\s*\{?$')
    if template == 'else:':
        return re.compile(r'^else:$')
    return re.compile(r'^else$')


def _func_pattern(target):
    template = target.get('func', '')
    if template.startswith('def '):
        return re.compile(r'^def\s+(\w+)\(([^)]*)\):$')
    if template.startswith('on '):
        return re.compile(r'^on\s+(\w+)\(([^)]*)\)$')
    if template.startswith('function '):
        return re.compile(r'^function\s+(\w+)\(([^)]*)\)\s*\{$')
    if template.startswith('func '):
        return re.compile(r'^func\s+(\w+)\(([^)]*)\)(?:\s*->\s*\w+)?\s*\{$')
    if '{type}' in template:
        types = _type_alternation(target)
        return re.compile(f'^{types}\\s+(\\w+)\\(([^)]*)\\)\\s*\\{{$')
    return None


def _func_decl_pattern(target):
    decl = target.get('funcDecl', '')
    if not decl or not decl.endswith(';'):
        return None
    if '{type}' in decl:
        types = _type_alternation(target)
        return re.compile(f'^{types}\\s+\\w+\\([^)]*\\);$')
    return None


def _return_pattern(target):
    has_semi = target.get('return', '').endswith(';')
    return re.compile(f'^return\\s+(.+?)\\s*{";" if has_semi else ""}$')


def _throw_pattern(target):
    tmpl = target.get('throw')
    if not tmpl:
        return None
    escaped = re.escape(tmpl)
    pattern = escaped.replace(r'\{value\}', '(.+?)')
    has_semi = tmpl.endswith(';')
    if has_semi:
        final = f'^{pattern[:-1]};?$'
    else:
        final = f'^{pattern}$'
    return re.compile(final)


def _comment_pattern(target):
    prefix = _comment_prefix(target)
    return re.compile(f'^{re.escape(prefix)}\\s*(.*)$')


def _catch_var_bind_pattern(target):
    tmpl = target.get('catchVarBind')
    if not tmpl:
        return None
    escaped = re.escape(tmpl)
    pattern = escaped.replace(r'\{var\}', r'(\w+)')
    has_semi = tmpl.endswith(';')
    if has_semi:
        final = f'^{pattern[:-1]};?$'
    else:
        final = f'^{pattern}$'
    return re.compile(final)


def _operator_replacements(target):
    replacements = []
    if target.get('and', '&&') != '&&':
        replacements.append((f" {target['and']} ", f" {OP['and']['symbol']} "))
    if target.get('or', '||') != '||':
        replacements.append((f" {target['or']} ", f" {OP['or']['symbol']} "))
    if target.get('not', '!') != '!':
        replacements.append((target['not'], f"{OP['not']['symbol']} "))
    if target.get('eq', '==') != '==':
        replacements.append((f" {target['eq']} ", f" {OP['eq']['symbol']} "))
    if target.get('neq', '!=') != '!=':
        replacements.append((f" {target['neq']} ", f" {OP['neq']['symbol']} "))
    if target.get('lte', '<=') != '<=':
        replacements.append((f" {target['lte']} ", f" {OP['lte']['symbol']} "))
    if target.get('gte', '>=') != '>=':
        replacements.append((f" {target['gte']} ", f" {OP['gte']['symbol']} "))
    if target.get('mod', '%') != '%':
        replacements.append((f" {target['mod']} ", f" {OP['mod']['symbol']} "))
    return replacements


def _has_autoreleasepool(target):
    main = target.get('main', '')
    return '@autoreleasepool' in main


def _printf_multi_pattern(target):
    if 'printf' not in target.get('printInt', target.get('print', '')):
        return None
    return re.compile(r'^(\s*)printf\("(.+)\\n"(?:,\s*(.+))?\);$')


def _printf_bool_ternary_pattern(target):
    template = target.get('printBool', '')
    if 'printf' not in template or '?' not in template:
        return None
    return re.compile(r'^(\s*)printf\("%s\\n",\s*(\w+)\s*\?\s*"[^"]*"\s*:\s*"[^"]*"\);$')


def _cout_bool_ternary_pattern(target):
    template = target.get('printBool', '')
    if 'std::cout' not in template or '?' not in template:
        return None
    return re.compile(r'^(\s*)std::cout\s*<<\s*\((\w+)\s*\?\s*"[^"]*"\s*:\s*"[^"]*"\)\s*<<\s*std::endl;$')


def _inline_bool_ternary_pattern():
    return re.compile(r'\{(\w+) \? "[^"]*" : "[^"]*"\}')


def _python_print_bool_pattern(target):
    template = target.get('printBool', '')
    if 'str(' not in template or '.lower()' not in template:
        return None
    return re.compile(r'^(\s*)print\(str\((\w+)\)\.lower\(\)\)$')


def _python_fstring_bool_pattern(target):
    template = target.get('printBool', '')
    if 'str(' not in template or '.lower()' not in template:
        return None
    return re.compile(r'\{str\((\w+)\)\.lower\(\)\}')


def _fmt_printf_pattern(target):
    if 'fmt.P' not in target.get('printInt', target.get('print', '')):
        return None
    return re.compile(r'^(\s*)fmt\.Printf\("(.+)\\n"(?:,\s*(.+))?\)$')


# MARK: - Strip Param Types

def _strip_param_types(params, call_style):
    if call_style == 'cFamily':
        # "int n" → "n"
        return ', '.join(p.strip().split()[-1] if p.strip() else '' for p in params.split(','))
    elif call_style == 'swift':
        # "_ n: Int" → "n"
        result = []
        for p in params.split(','):
            cleaned = p.strip()
            if cleaned.startswith('_ '):
                cleaned = cleaned[2:]
            colon_idx = cleaned.find(':')
            if colon_idx >= 0:
                cleaned = cleaned[:colon_idx].strip()
            result.append(cleaned)
        return ', '.join(result)
    elif call_style == 'go':
        # "n int" → "n"
        return ', '.join(p.strip().split()[0] if p.strip() else '' for p in params.split(','))
    return params


def _call_style(target):
    name = target.get('name', '')
    if name == 'Python':
        return 'python'
    elif name == 'Swift':
        return 'swift'
    elif name == 'Go':
        return 'go'
    elif name == 'JavaScript':
        return 'javascript'
    elif name == 'AppleScript':
        return 'applescript'
    return 'cFamily'


# MARK: - Python Reverse Transpiler

class PythonReverseTranspiler:
    def __init__(self):
        self.target = load_target_config('py')
        self._print_re = _print_pattern(self.target)
        self._var_re = _var_pattern(self.target)
        self._for_re = _for_pattern(self.target)
        self._if_re = _if_pattern(self.target)
        self._else_re = _else_pattern(self.target)
        self._def_re = _func_pattern(self.target)
        self._return_re = _return_pattern(self.target)
        self._throw_re = _throw_pattern(self.target)
        self._comment_re = _comment_pattern(self.target)
        self._print_bool_re = _python_print_bool_pattern(self.target)
        self._fstring_bool_re = _python_fstring_bool_pattern(self.target)

    def reverse_transpile(self, code):
        lines = code.split('\n')

        # Strip header
        header_pats = _header_patterns(self.target)
        lines = [l for l in lines if not any(
            l.strip().startswith(p) or l.strip() == p for p in header_pats)]

        # Pre-process: simplify bool patterns
        for i in range(len(lines)):
            trimmed = lines[i].strip()
            leading = lines[i][:len(lines[i]) - len(lines[i].lstrip())]
            if self._print_bool_re:
                m = self._print_bool_re.match(trimmed)
                if m:
                    var_name = m.group(2)
                    lines[i] = f'{leading}print({var_name})'
                    continue
            if self._fstring_bool_re:
                lines[i] = leading + self._fstring_bool_re.sub(r'{\1}', trimmed)

        # Replace booleans/operators
        text = '\n'.join(lines)
        text = _replace_outside_strings(text, self.target['true'], JJ['keywords']['true'])
        text = _replace_outside_strings(text, self.target['false'], JJ['keywords']['false'])
        text = _replace_outside_strings(text, self.target['nil'], JJ['keywords']['nil'])
        for find, replace in _operator_replacements(self.target):
            text = _replace_outside_strings(text, find, replace)
        lines = text.split('\n')

        result = []
        indent_level = 0

        for line in lines:
            trimmed = line.strip()
            if not trimmed:
                result.append('')
                continue

            spaces = len(line) - len(line.lstrip(' '))
            src_indent = spaces // 4

            # For except/else: close to their level without emitting blockEnd
            is_except = trimmed == 'except:' or trimmed.startswith('except ')
            is_else = not is_except and trimmed == 'else:'
            if is_except or is_else:
                while indent_level > src_indent + 1:
                    indent_level -= 1
                    result.append(f'{_jj_indent(indent_level)}{JJ_END}')
                if indent_level > src_indent:
                    indent_level -= 1
                if is_except:
                    if ' as ' in trimmed:
                        var_name = trimmed.split(' as ')[1].rstrip(':').strip()
                        result.append(f'{_jj_indent(indent_level)}{JJ_OOPS} {var_name}')
                    else:
                        result.append(f'{_jj_indent(indent_level)}{JJ_OOPS}')
                else:
                    result.append(f'{_jj_indent(indent_level)}{JJ_ELSE}')
                indent_level += 1
                continue

            # Close blocks when indentation decreases
            while indent_level > src_indent:
                indent_level -= 1
                result.append(f'{_jj_indent(indent_level)}{JJ_END}')

            # Comment
            m = self._comment_re.match(trimmed) if self._comment_re else None
            if m:
                comment = m.group(1)
                result.append(f'{_jj_indent(indent_level)}{JJ_COMMENT} {comment}')
                continue

            # Function def
            m = self._def_re.match(trimmed) if self._def_re else None
            if m:
                name = m.group(1)
                params = m.group(2)
                result.append(f'{_jj_indent(indent_level)}{_jj_morph(name, params)}')
                indent_level += 1
                continue

            # For loop
            m = self._for_re.match(trimmed) if self._for_re else None
            if m:
                v = m.group(1)
                start = m.group(2)
                end = m.group(3)
                result.append(f'{_jj_indent(indent_level)}{_jj_loop(v, start, end)}')
                indent_level += 1
                continue

            # If
            m = self._if_re.match(trimmed) if self._if_re else None
            if m:
                cond = _reverse_expr(m.group(1))
                result.append(f'{_jj_indent(indent_level)}{_jj_when(cond)}')
                indent_level += 1
                continue

            # Try
            if trimmed == 'try:':
                result.append(f'{_jj_indent(indent_level)}{JJ_TRY}')
                indent_level += 1
                continue

            # Return
            m = self._return_re.match(trimmed) if self._return_re else None
            if m:
                val = _reverse_expr(m.group(1))
                result.append(f'{_jj_indent(indent_level)}{_jj_yeet(_reverse_func_calls(val, self.target))}')
                continue

            # Throw
            m = self._throw_re.match(trimmed) if self._throw_re else None
            if m:
                val = _reverse_expr(m.group(1))
                result.append(f'{_jj_indent(indent_level)}{_jj_kaboom(_reverse_func_calls(val, self.target))}')
                continue

            # Print
            m = self._print_re.match(trimmed) if self._print_re else None
            if m:
                expr = _reverse_expr(m.group(1))
                result.append(f'{_jj_indent(indent_level)}{_jj_print(_reverse_func_calls(expr, self.target))}')
                continue

            # Variable
            m = self._var_re.match(trimmed) if self._var_re else None
            if m:
                name = m.group(1)
                if name in _known_functions(self.target):
                    continue
                val = _reverse_expr(m.group(2))
                result.append(f'{_jj_indent(indent_level)}{_jj_snag(name, _reverse_func_calls(val, self.target))}')
                continue

            # Fallback
            reversed_line = _reverse_func_calls(trimmed, self.target)
            result.append(f'{_jj_indent(indent_level)}{reversed_line}')

        # Close remaining blocks
        while indent_level > 0:
            indent_level -= 1
            result.append(f'{_jj_indent(indent_level)}{JJ_END}')

        output = '\n'.join(result).strip()
        return output + '\n' if output else None


# MARK: - Brace-Based Reverse Transpiler

class BraceReverseTranspiler:
    def __init__(self, target):
        self.target = target
        self.header_pats = _header_patterns(target)
        self.has_main = target.get('main') is not None
        self.main_pattern = _main_signature(target) or ''
        self.print_re = _print_pattern(target)
        self.var_re = _var_pattern(target)
        self.for_re = _for_pattern(target)
        self.if_re = _if_pattern(target)
        self.else_re = _else_pattern(target)
        self.func_re = _func_pattern(target)
        self.return_re = _return_pattern(target)
        self.throw_re = _throw_pattern(target)
        self.comment_pfx = _comment_prefix(target)
        self.true_val = target.get('true', 'true')
        self.false_val = target.get('false', 'false')
        self.nil_val = target.get('nil', 'null')
        self.style = _call_style(target)
        self.fwd_decl_re = _func_decl_pattern(target)
        self.strip_semi = target.get('return', '').endswith(';')
        self.autoreleasepool = _has_autoreleasepool(target)
        self.catch_var_bind_re = _catch_var_bind_pattern(target)
        self.block_end = target.get('blockEnd', '}')

    def preprocess(self, code):
        """Override in subclasses for language-specific preprocessing."""
        return code

    def reverse_transpile(self, code):
        code = self.preprocess(code)
        lines = code.split('\n')

        # Strip header
        lines = [l for l in lines if not any(
            l.strip().startswith(p) or l.strip() == p for p in self.header_pats)]

        # Strip forward declarations
        if self.fwd_decl_re:
            lines = [l for l in lines if not self.fwd_decl_re.match(l.strip())]

        # Replace booleans/null
        text = '\n'.join(lines)
        text = _replace_outside_strings(text, self.true_val, JJ['keywords']['true'])
        text = _replace_outside_strings(text, self.false_val, JJ['keywords']['false'])
        if self.nil_val != '0':
            text = _replace_outside_strings(text, self.nil_val, JJ['keywords']['nil'])
        for find, replace in _operator_replacements(self.target):
            text = _replace_outside_strings(text, find, replace)
        lines = text.split('\n')

        result = []
        indent_level = 0
        in_main = False
        in_autoreleasepool = False
        just_emitted_oops = False

        try_pat = self.target.get('try', 'try {').strip()
        catch_pat = self.target.get('catch', '} catch {').strip()

        for line in lines:
            trimmed = line.strip()
            if not trimmed:
                result.append('')
                continue

            # Check catchVarBind pattern
            if just_emitted_oops and self.catch_var_bind_re:
                trimmed_for_match = trimmed
                if trimmed_for_match.endswith(';'):
                    trimmed_for_match = trimmed_for_match[:-1]
                m = self.catch_var_bind_re.match(trimmed) or self.catch_var_bind_re.match(trimmed_for_match)
                if m:
                    var_name = m.group(1)
                    if result:
                        last_line = result[-1]
                        if last_line.endswith(JJ_OOPS):
                            result[-1] = last_line + f' {var_name}'
                    just_emitted_oops = False
                    continue
                just_emitted_oops = False

            # Skip main wrapper
            if self.has_main:
                if self.main_pattern and self.main_pattern in trimmed and '{' in trimmed:
                    in_main = True
                    continue
                if self.autoreleasepool and self.target.get('main', '').count('@autoreleasepool') and '@autoreleasepool' in trimmed and '{' in trimmed:
                    in_autoreleasepool = True
                    continue
                if in_main and indent_level == 0 and trimmed.startswith('return '):
                    continue
                if in_main and indent_level == 0 and trimmed == self.block_end:
                    if in_autoreleasepool:
                        in_autoreleasepool = False
                        continue
                    in_main = False
                    continue

            # Closing block
            if trimmed == self.block_end:
                if indent_level > 0:
                    indent_level -= 1
                result.append(f'{_jj_indent(indent_level)}{JJ_END}')
                continue

            # Try/catch
            if trimmed == try_pat or trimmed == 'try {' or (trimmed.startswith('@try') and trimmed.endswith('{')):
                result.append(f'{_jj_indent(indent_level)}{JJ_TRY}')
                indent_level += 1
                continue

            if trimmed == catch_pat or trimmed.startswith('} catch') or trimmed.startswith('} @catch'):
                if indent_level > 0:
                    indent_level -= 1
                # Extract catch variable
                paren_open = trimmed.find('(')
                paren_close = trimmed.find(')')
                if paren_open >= 0 and paren_close >= 0:
                    var_name = trimmed[paren_open+1:paren_close].strip()
                    if var_name and ' ' not in var_name and var_name != '...':
                        result.append(f'{_jj_indent(indent_level)}{JJ_OOPS} {var_name}')
                    else:
                        result.append(f'{_jj_indent(indent_level)}{JJ_OOPS}')
                        just_emitted_oops = True
                else:
                    result.append(f'{_jj_indent(indent_level)}{JJ_OOPS}')
                    just_emitted_oops = True
                indent_level += 1
                continue

            # Comment
            if trimmed.startswith(self.comment_pfx):
                comment = trimmed[len(self.comment_pfx):].strip()
                result.append(f'{_jj_indent(indent_level)}{JJ_COMMENT} {comment}')
                continue

            # Function definition
            m = self.func_re.match(trimmed) if self.func_re else None
            if m:
                name = m.group(1)
                params = m.group(2)
                clean_params = _strip_param_types(params, self.style)
                result.append(f'{_jj_indent(indent_level)}{_jj_morph(name, clean_params)}')
                indent_level += 1
                continue

            # For loop
            m = self.for_re.match(trimmed) if self.for_re else None
            if m:
                v = m.group(1)
                start = m.group(2)
                end = m.group(3)
                result.append(f'{_jj_indent(indent_level)}{_jj_loop(v, start, end)}')
                indent_level += 1
                continue

            # If
            m = self.if_re.match(trimmed) if self.if_re else None
            if m:
                cond = _reverse_expr(m.group(1))
                result.append(f'{_jj_indent(indent_level)}{_jj_when(cond)}')
                indent_level += 1
                continue

            # Else
            m = self.else_re.match(trimmed) if self.else_re else None
            if m:
                result.append(f'{_jj_indent(indent_level)}{JJ_ELSE}')
                indent_level += 1
                continue

            # Return
            m = self.return_re.match(trimmed) if self.return_re else None
            if m:
                val = m.group(1)
                if val.endswith(';'):
                    val = val[:-1]
                val = _reverse_expr(val)
                result.append(f'{_jj_indent(indent_level)}{_jj_yeet(_reverse_func_calls(val, self.target))}')
                continue

            # Throw (config pattern)
            m = self.throw_re.match(trimmed) if self.throw_re else None
            if m:
                val = m.group(1)
                if val.endswith(';'):
                    val = val[:-1]
                val = _reverse_expr(val)
                result.append(f'{_jj_indent(indent_level)}{_jj_kaboom(_reverse_func_calls(val, self.target))}')
                continue

            # Throw (generic fallback for rewritten patterns)
            if trimmed.startswith('throw '):
                val = trimmed[len('throw '):]
                if val.endswith(';'):
                    val = val[:-1]
                val = _reverse_expr(val)
                result.append(f'{_jj_indent(indent_level)}{_jj_kaboom(_reverse_func_calls(val, self.target))}')
                continue

            # Print
            m = self.print_re.match(trimmed) if self.print_re else None
            if m:
                captured = None
                if m.group(1) is not None:
                    captured = m.group(1)
                elif m.lastindex and m.lastindex >= 2 and m.group(2) is not None:
                    captured = m.group(2)
                if captured:
                    expr = _reverse_expr(captured)
                    result.append(f'{_jj_indent(indent_level)}{_jj_print(_reverse_func_calls(expr, self.target))}')
                    continue

            # Variable
            m = self.var_re.match(trimmed) if self.var_re else None
            if m:
                # Find first valid capture group pair
                name = None
                val = None
                for g in range(1, m.lastindex or 0, 2):
                    if m.group(g) is not None and g + 1 <= (m.lastindex or 0) and m.group(g + 1) is not None:
                        name = m.group(g)
                        val = m.group(g + 1)
                        break
                if name is None and m.group(1) is not None:
                    name = m.group(1)
                    if m.lastindex and m.lastindex >= 2 and m.group(2) is not None:
                        val = m.group(2)
                if name and val:
                    if val.endswith(';'):
                        val = val[:-1]
                    val = _reverse_expr(val)
                    result.append(f'{_jj_indent(indent_level)}{_jj_snag(name, _reverse_func_calls(val, self.target))}')
                    continue

            # Unrecognized
            cleaned = trimmed
            if cleaned.endswith(';'):
                cleaned = cleaned[:-1]
            result.append(f'{_jj_indent(indent_level)}{_reverse_func_calls(_reverse_expr(cleaned), self.target)}')

        # Close remaining blocks
        while indent_level > 0:
            indent_level -= 1
            result.append(f'{_jj_indent(indent_level)}{JJ_END}')

        output = '\n'.join(result).strip()
        return output + '\n' if output else None


# MARK: - C-Family Printf Handler

class CFamilyPrintfReverseTranspiler(BraceReverseTranspiler):
    def __init__(self, target):
        super().__init__(target)
        self.printf_multi_re = _printf_multi_pattern(target)
        self.bool_ternary_printf_re = _printf_bool_ternary_pattern(target)
        self.inline_bool_ternary_re = _inline_bool_ternary_pattern()

    def preprocess(self, code):
        code = super().preprocess(code)
        lines = code.split('\n')
        for i in range(len(lines)):
            trimmed = lines[i].strip()
            leading = lines[i][:len(lines[i]) - len(lines[i].lstrip())]

            # Bool ternary printf
            if self.bool_ternary_printf_re:
                m = self.bool_ternary_printf_re.match(trimmed)
                if m:
                    var_name = m.group(2)
                    replacement = self.target.get('printInt', self.target.get('print', '')).replace('{expr}', var_name)
                    lines[i] = f'{leading}{replacement}'
                    continue

            # Multi-specifier printf
            if self.printf_multi_re:
                m = self.printf_multi_re.match(trimmed)
                if m:
                    fmt = m.group(2)
                    spec_count = fmt.count('%')
                    if spec_count > 1 and m.group(3):
                        args_str = m.group(3)
                        args = self._split_args(args_str)
                        result_str = fmt
                        for arg in args:
                            result_str = re.sub(r'%[dsgflv]+', '{' + arg + '}', result_str, count=1)
                        if self.inline_bool_ternary_re:
                            result_str = self.inline_bool_ternary_re.sub(r'{\1}', result_str)
                        str_print = self.target.get('printStr', self.target.get('print', '')).replace('{expr}', f'"{result_str}"')
                        lines[i] = f'{leading}{str_print}'
        return '\n'.join(lines)

    def _split_args(self, s):
        args = []
        current = ''
        depth = 0
        for c in s:
            if c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
            if c == ',' and depth == 0:
                args.append(current.strip())
                current = ''
            else:
                current += c
        if current.strip():
            args.append(current.strip())
        return args


# MARK: - Language-Specific Transpilers

class CReverseTranspiler(CFamilyPrintfReverseTranspiler):
    def __init__(self):
        super().__init__(load_target_config('c'))

    def preprocess(self, code):
        lines = code.split('\n')
        lines = self._rewrite_c_try_catch(lines)
        return super().preprocess('\n'.join(lines))

    def _rewrite_c_try_catch(self, input_lines):
        output = []
        i = 0
        while i < len(input_lines):
            trimmed = input_lines[i].strip()
            leading = input_lines[i][:len(input_lines[i]) - len(input_lines[i].lstrip())]

            if trimmed == 'const char *_jj_err = NULL;':
                i += 1
                if i < len(input_lines) and input_lines[i].strip() == '{':
                    i += 1
                try_lines = []
                catch_lines = []
                catch_var = None
                in_catch = False

                while i < len(input_lines):
                    t = input_lines[i].strip()

                    if not in_catch and t.startswith('_jj_err = ') and 'goto _jj_catch' in t:
                        throw_val = t.replace('_jj_err = ', '').replace('; goto _jj_catch;', '')
                        throw_leading = input_lines[i][:len(input_lines[i]) - len(input_lines[i].lstrip())]
                        try_lines.append(f'{throw_leading}throw {throw_val};')
                        i += 1
                        continue

                    if t == 'goto _jj_endtry;':
                        i += 1
                        continue

                    if t == '} _jj_catch: {':
                        in_catch = True
                        i += 1
                        continue

                    if t == '_jj_endtry:;':
                        i += 1
                        break

                    if in_catch and '= _jj_err' in t:
                        parts = t.split('=')
                        if parts:
                            var_name = parts[0].replace('const char *', '').replace('const char*', '').strip()
                            if var_name:
                                catch_var = var_name
                        i += 1
                        continue

                    if in_catch and t == '}':
                        i += 1
                        if i < len(input_lines) and input_lines[i].strip() == '_jj_endtry:;':
                            i += 1
                        break

                    if in_catch:
                        catch_lines.append(input_lines[i])
                    else:
                        try_lines.append(input_lines[i])
                    i += 1

                output.append(f'{leading}try {{')
                output.extend(try_lines)
                if catch_var:
                    output.append(f'{leading}}} catch ({catch_var}) {{')
                else:
                    output.append(f'{leading}}} catch {{')
                output.extend(catch_lines)
                output.append(f'{leading}}}')
            else:
                output.append(input_lines[i])
                i += 1
        return output


class CppReverseTranspiler(CFamilyPrintfReverseTranspiler):
    def __init__(self):
        target = load_target_config('cpp')
        super().__init__(target)
        self.cout_bool_re = _cout_bool_ternary_pattern(target)

    def preprocess(self, code):
        lines = code.split('\n')
        for i in range(len(lines)):
            trimmed = lines[i].strip()
            leading = lines[i][:len(lines[i]) - len(lines[i].lstrip())]
            if self.cout_bool_re:
                m = self.cout_bool_re.match(trimmed)
                if m:
                    var_name = m.group(2)
                    replacement = self.target.get('printInt', self.target.get('print', '')).replace('{expr}', var_name)
                    if 'std::cout' in replacement:
                        lines[i] = f'{leading}{replacement}'
        return super().preprocess('\n'.join(lines))


class JavaScriptReverseTranspiler(BraceReverseTranspiler):
    def __init__(self):
        super().__init__(load_target_config('js'))


class SwiftReverseTranspiler(BraceReverseTranspiler):
    def __init__(self):
        super().__init__(load_target_config('swift'))


class GoReverseTranspiler(BraceReverseTranspiler):
    def __init__(self):
        target = load_target_config('go')
        super().__init__(target)
        self.printf_re = _fmt_printf_pattern(target)

    def preprocess(self, code):
        lines = code.split('\n')

        # Strip multi-line import block
        filtered = []
        in_import = False
        for line in lines:
            trimmed = line.strip()
            if trimmed == 'import (':
                in_import = True
                continue
            if in_import:
                if trimmed == ')':
                    in_import = False
                continue
            filtered.append(line)
        lines = filtered

        # Convert fmt.Printf to fmt.Println
        for i in range(len(lines)):
            trimmed = lines[i].strip()
            leading = lines[i][:len(lines[i]) - len(lines[i].lstrip())]
            if self.printf_re:
                m = self.printf_re.match(trimmed)
                if m:
                    fmt_str = m.group(2)
                    println_template = self.target.get('printStr', self.target.get('print', ''))
                    if m.group(3):
                        args_str = m.group(3)
                        args = [a.strip() for a in args_str.split(',')]
                        result_str = fmt_str
                        for arg in args:
                            result_str = result_str.replace('%v', '{' + arg + '}', 1)
                        lines[i] = f'{leading}{println_template.replace("{expr}", chr(34) + result_str + chr(34))}'
                    else:
                        lines[i] = f'{leading}{println_template.replace("{expr}", chr(34) + fmt_str + chr(34))}'

        # Rewrite Go defer/recover try-catch
        lines = self._rewrite_go_try_catch(lines)

        return super().preprocess('\n'.join(lines))

    def _rewrite_go_try_catch(self, input_lines):
        output = []
        i = 0
        while i < len(input_lines):
            trimmed = input_lines[i].strip()
            leading = input_lines[i][:len(input_lines[i]) - len(input_lines[i].lstrip())]

            if (trimmed == 'func() {' and i + 1 < len(input_lines) and
                    input_lines[i+1].strip().startswith('defer func()')):
                oops_lines = []
                try_lines = []
                oops_var = None
                j = i + 1
                j += 1  # skip "defer func() {"

                if j < len(input_lines) and 'recover()' in input_lines[j].strip():
                    j += 1

                depth = 1
                while j < len(input_lines) and depth > 0:
                    t = input_lines[j].strip()
                    if t == '}' or t == '}()':
                        depth -= 1
                        if depth == 0:
                            j += 1
                            break
                    if t.endswith('{'):
                        depth += 1
                    if ':= fmt.Sprint(r)' in t:
                        parts = t.split(':=')
                        if parts:
                            var_name = parts[0].strip()
                            if var_name:
                                oops_var = var_name
                        j += 1
                        continue
                    oops_lines.append(input_lines[j])
                    j += 1

                while j < len(input_lines):
                    t = input_lines[j].strip()
                    if t == '}' or t == '}()':
                        j += 1
                        continue
                    break

                while j < len(input_lines):
                    t = input_lines[j].strip()
                    if t == '}()':
                        j += 1
                        break
                    try_lines.append(input_lines[j])
                    j += 1

                output.append(f'{leading}try {{')
                output.extend(try_lines)
                if oops_var:
                    output.append(f'{leading}}} catch ({oops_var}) {{')
                else:
                    output.append(f'{leading}}} catch {{')
                output.extend(oops_lines)
                output.append(f'{leading}}}')
                i = j
            else:
                output.append(input_lines[i])
                i += 1
        return output


class ObjCReverseTranspiler(CFamilyPrintfReverseTranspiler):
    _throw_re = re.compile(
        r'@throw\s+\[NSException\s+exceptionWithName:@"[^"]*"\s+reason:(@"[^"]*"|\w+)\s+userInfo:nil\];'
    )
    _utf8_re = re.compile(r'\[(\w+)\s+UTF8String\]')

    def __init__(self):
        super().__init__(load_target_config('objc'))

    def preprocess(self, code):
        lines = code.split('\n')
        lines = self._rewrite_objc_throw(lines)
        lines = self._rewrite_objc_print(lines)
        return super().preprocess('\n'.join(lines))

    def _rewrite_objc_throw(self, lines):
        result = []
        for line in lines:
            trimmed = line.strip()
            leading = line[:len(line) - len(line.lstrip())]
            m = self._throw_re.search(trimmed)
            if m:
                val = m.group(1)
                if val.startswith('@"'):
                    val = val[1:]  # strip ObjC @ prefix
                result.append(f'{leading}throw {val};')
            else:
                result.append(line)
        return result

    def _rewrite_objc_print(self, lines):
        return [self._utf8_re.sub(r'\1', line) for line in lines]


class ObjCppReverseTranspiler(CFamilyPrintfReverseTranspiler):
    _throw_re = re.compile(
        r'@throw\s+\[NSException\s+exceptionWithName:@"[^"]*"\s+reason:(@"[^"]*"|\w+)\s+userInfo:nil\];'
    )
    _utf8_re = re.compile(r'\[(\w+)\s+UTF8String\]')

    def __init__(self):
        target = load_target_config('objcpp')
        super().__init__(target)
        self.cout_bool_re = _cout_bool_ternary_pattern(target)
        # Set up dual print pattern
        self.print_re = _dual_print_pattern()

    def preprocess(self, code):
        lines = code.split('\n')
        # Rewrite ObjC-style throws
        result = []
        for line in lines:
            trimmed = line.strip()
            leading = line[:len(line) - len(line.lstrip())]
            m = self._throw_re.search(trimmed)
            if m:
                val = m.group(1)
                if val.startswith('@"'):
                    val = val[1:]
                result.append(f'{leading}throw {val};')
            else:
                result.append(line)
        lines = result

        # Rewrite [var UTF8String] → var
        lines = [self._utf8_re.sub(r'\1', line) for line in lines]

        # Process cout bool ternary
        for i in range(len(lines)):
            trimmed = lines[i].strip()
            leading = lines[i][:len(lines[i]) - len(lines[i].lstrip())]
            if self.cout_bool_re:
                m = self.cout_bool_re.match(trimmed)
                if m:
                    var_name = m.group(2)
                    replacement = self.target.get('printInt', self.target.get('print', '')).replace('{expr}', var_name)
                    if 'std::cout' in replacement:
                        lines[i] = f'{leading}{replacement}'

        return super().preprocess('\n'.join(lines))


class AppleScriptReverseTranspiler:
    def __init__(self):
        self.target = load_target_config('applescript')
        self.log_re = _print_pattern(self.target)
        self.set_re = _var_pattern(self.target)
        self.repeat_re = _for_pattern(self.target)
        self.if_re = _if_pattern(self.target)
        self.else_re = _else_pattern(self.target)
        self.on_re = _func_pattern(self.target)
        self.return_re = _return_pattern(self.target)
        self.throw_re = _throw_pattern(self.target)
        self.end_re = re.compile(r'^end\s*(\w*)$')
        self.comment_re = _comment_pattern(self.target)

    def reverse_transpile(self, code):
        lines = code.split('\n')

        # Strip header
        header_pats = _header_patterns(self.target)
        lines = [l for l in lines if not any(
            l.strip().startswith(p) or l.strip() == p for p in header_pats)]

        # Replace operators
        text = '\n'.join(lines)
        for find, replace in _operator_replacements(self.target):
            text = _replace_outside_strings(text, find, replace)
        lines = text.split('\n')

        result = []
        indent_level = 0

        for line in lines:
            trimmed = line.strip().strip('\t')
            if not trimmed:
                result.append('')
                continue

            # Comment
            m = self.comment_re.match(trimmed) if self.comment_re else None
            if m:
                comment = m.group(1)
                result.append(f'{_jj_indent(indent_level)}{JJ_COMMENT} {comment}')
                continue

            # Try
            if trimmed == 'try':
                result.append(f'{_jj_indent(indent_level)}{JJ_TRY}')
                indent_level += 1
                continue

            # On error (catch)
            if trimmed == 'on error' or trimmed.startswith('on error '):
                if indent_level > 0:
                    indent_level -= 1
                if trimmed.startswith('on error '):
                    var_name = trimmed[len('on error '):].strip()
                    if var_name:
                        result.append(f'{_jj_indent(indent_level)}{JJ_OOPS} {var_name}')
                    else:
                        result.append(f'{_jj_indent(indent_level)}{JJ_OOPS}')
                else:
                    result.append(f'{_jj_indent(indent_level)}{JJ_OOPS}')
                indent_level += 1
                continue

            # End block
            if self.end_re.match(trimmed):
                if indent_level > 0:
                    indent_level -= 1
                result.append(f'{_jj_indent(indent_level)}{JJ_END}')
                continue

            # Function def
            m = self.on_re.match(trimmed) if self.on_re else None
            if m:
                name = m.group(1)
                params = m.group(2)
                result.append(f'{_jj_indent(indent_level)}{_jj_morph(name, params)}')
                indent_level += 1
                continue

            # For loop
            m = self.repeat_re.match(trimmed) if self.repeat_re else None
            if m:
                v = m.group(1)
                start = m.group(2)
                end = m.group(3)
                result.append(f'{_jj_indent(indent_level)}{_jj_loop(v, start, end)}')
                indent_level += 1
                continue

            # If
            m = self.if_re.match(trimmed) if self.if_re else None
            if m:
                cond = _reverse_expr(m.group(1))
                result.append(f'{_jj_indent(indent_level)}{_jj_when(cond)}')
                indent_level += 1
                continue

            # Else
            m = self.else_re.match(trimmed) if self.else_re else None
            if m:
                result.append(f'{_jj_indent(indent_level)}{JJ_ELSE}')
                indent_level += 1
                continue

            # Return
            m = self.return_re.match(trimmed) if self.return_re else None
            if m:
                val = _reverse_expr(m.group(1))
                result.append(f'{_jj_indent(indent_level)}{_jj_yeet(_reverse_func_calls(val, self.target))}')
                continue

            # Throw
            m = self.throw_re.match(trimmed) if self.throw_re else None
            if m:
                val = _reverse_expr(m.group(1))
                result.append(f'{_jj_indent(indent_level)}{_jj_kaboom(_reverse_func_calls(val, self.target))}')
                continue

            # Print
            m = self.log_re.match(trimmed) if self.log_re else None
            if m:
                expr = _reverse_expr(m.group(1))
                result.append(f'{_jj_indent(indent_level)}{_jj_print(_reverse_func_calls(expr, self.target))}')
                continue

            # Variable
            m = self.set_re.match(trimmed) if self.set_re else None
            if m:
                name = m.group(1)
                val = _reverse_expr(m.group(2))
                result.append(f'{_jj_indent(indent_level)}{_jj_snag(name, _reverse_func_calls(val, self.target))}')
                continue

            # Fallback
            result.append(f'{_jj_indent(indent_level)}{_reverse_func_calls(_reverse_expr(trimmed), self.target)}')

        while indent_level > 0:
            indent_level -= 1
            result.append(f'{_jj_indent(indent_level)}{JJ_END}')

        output = '\n'.join(result).strip()
        return output + '\n' if output else None


# MARK: - Factory

REVERSE_TRANSPILERS = {
    'py': PythonReverseTranspiler,
    'js': JavaScriptReverseTranspiler,
    'c': CReverseTranspiler,
    'cpp': CppReverseTranspiler,
    'swift': SwiftReverseTranspiler,
    'objc': ObjCReverseTranspiler,
    'objcpp': ObjCppReverseTranspiler,
    'go': GoReverseTranspiler,
    'applescript': AppleScriptReverseTranspiler,
}


def get_reverse_transpiler(language):
    cls = REVERSE_TRANSPILERS.get(language)
    if cls:
        return cls()
    return None
