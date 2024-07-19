//
// Created by r53wang on 8/8/23.
//
#include <iostream>
#include <cstdlib>
using namespace std;

void funca(void**, int);
void funcb(void**, int);

void funcb(void** test, int i) {
    if (i >= 0) {
        if (i == 0) {
            test[i] = malloc(16);
            free(test[i]);
            cout << test[i] << " ";
        }

        funca(test, i - 1);
    }
}


void funca(void** test, int i) {
    if (i >= 0) {
        if (i == 0) {
            test[i] = malloc(16);
            free(test[i]);
            cout << test[i] << " ";
        }

        funcb(test, i - 1);
    }
}


int main() {
    cout << "=====================" << endl;
    cout << "two functions two sites in loop no reuse" << endl;

    void* test[10];
    funca(test, 10);
    cout << endl;

    for (int i = 0; i < 10; i++) {
        for (int j = i + 1; j < 10; j++) {
            if (test[i] == test[j]) {
                cout << "\033[1;31mERROR: same address: " << test[i] << "\033[0m" << endl;
            }
        }
    }
    cout << "=====================" << endl << endl;
    return 0;
}