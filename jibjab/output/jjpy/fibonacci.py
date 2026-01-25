#!/usr/bin/env python3
# Transpiled from JibJab
def fib(n):
    if (n < 2):
        return n
    return (fib((n - 1)) + fib((n - 2)))
for i in range(0, 15):
    print(fib(i))
