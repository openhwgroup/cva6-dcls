/*
** cva6-dcls local hello_world test
** Printf inside loop with \n so putchar buffer flushes on each iteration.
** Original CVA6 upstream version had printf before the loop with no \n.
*/

#include <stdint.h>
#include <stdio.h>

int main(int argc, char* arg[]) {
    for (int i = 0; i < 5; i++) {
        printf("%d: Hello World !\n", i);
    }
    return 0;
}
