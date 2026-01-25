// Transpiled from JibJab
#include <stdio.h>
#include <stdlib.h>

int fib(int n);

int fib(int n) {
    if ((n < 2)) {
        return n;
    }
    return (fib((n - 1)) + fib((n - 2)));
}

int main() {
    for (int i = 0; i < 15; i++) {
        printf("%d\n", fib(i));
    }
    return 0;
}
