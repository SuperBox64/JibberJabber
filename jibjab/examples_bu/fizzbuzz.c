 // Transpiled from JibJab
#include <stdio.h>
#include <stdlib.h>

int main() {
    for (int n = 1; n < 101; n++) {
        if (((n % 15) == 0)) {
            printf("%s\n", "FizzBuzz");
        } else {
            if (((n % 3) == 0)) {
                printf("%s\n", "Fizz");
            } else {
                if (((n % 5) == 0)) {
                    printf("%s\n", "Buzz");
                } else {
                    printf("%d\n", n);
                }
            }
        }
    }
    return 0;
}
