#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <cuda.h>
#include <sys/time.h>
#include <pthread.h>
#include <locale.h>
#include "lib/sha256.cuh"

#define THREADS 1200
#define BLOCKS 256

#define MAX_HASH_RESULTS 40
#define MAX_USER_INPUT MAX_HASH_RESULTS *SHA256_BLOCK_SIZE * 2 + (MAX_HASH_RESULTS - 1)

#define BYTE_LENGTH_TO_BE_FOUND 8

__global__ void sha256_cuda(BYTE *solution, int *blockContainsSolution, unsigned long baseSeed, int userHashCount, WORD *d_realHashedState, BYTE *allowedBytes)
{
    SHA256_CTX ctx;
    baseSeed ^= (unsigned long)blockIdx.x * blockDim.x + threadIdx.x;

    sha256_init(&ctx);
    BYTE i = 0;

    for (i = 0; i < BYTE_LENGTH_TO_BE_FOUND; ++i)
    {
        baseSeed = ((baseSeed << 13) ^ baseSeed ^ (baseSeed >> 17) ^ (baseSeed << 5));
        sha256_update(&ctx, &allowedBytes[baseSeed & 0x0F], 1);
    }
    
    sha256_final(&ctx);

    for (BYTE j = 0; j < userHashCount; ++j)
    {
        for (i = 0; i < 8; ++i)
        {
            if (d_realHashedState[8 * j + i] != ctx.state[i])
            {
                break;
            }
            if (i == 7)
            {
                if (*blockContainsSolution == 1)
                    return;

                *blockContainsSolution = 1;
                for (i = 0; i < BYTE_LENGTH_TO_BE_FOUND; ++i)
                    solution[i] = ctx.data[i];

                return;
            }
        }
    }
}

void reverseBytes(BYTE *bytes, int length)
{
    int i;
    for (i = 0; i < length / 2; ++i)
    {
        BYTE temp = bytes[i];
        bytes[i] = bytes[length - i - 1];
        bytes[length - i - 1] = temp;
    }
}

void retrieveState(const BYTE *hash, WORD *state)
{
    int i, j;
    BYTE temp[4];

    for (i = 0, j = 0; i < 32; i += 4, ++j)
    {
        // Copy 4 bytes from the hash into temp array
        temp[0] = hash[i];
        temp[1] = hash[i + 1];
        temp[2] = hash[i + 2];
        temp[3] = hash[i + 3];

        // Reverse the byte order
        reverseBytes(temp, 4);

        // Combine the bytes to form a uint32_t integer
        state[j] = *(WORD *)temp;
    }
}

bool hexStringToShaStateWords(const char *hexString, WORD *words)
{
    BYTE bytes[SHA256_BLOCK_SIZE];

    for (int i = 0; i < 32; ++i)
    {
        bytes[i] = (BYTE)(((hexString[i * 2] & 0xF) + ((hexString[i * 2] >> 6) * 9)) << 4);
        bytes[i] |= (BYTE)((hexString[i * 2 + 1] & 0xF) + ((hexString[i * 2 + 1] >> 6) * 9));
    }

    retrieveState(bytes, words);

    return true;
}

long long timeInMilliseconds(void)
{
    struct timeval tv;

    gettimeofday(&tv, NULL);
    return (((long long)tv.tv_sec) * 1000) + (tv.tv_usec / 1000);
}

int main()
{
    cudaMemcpyToSymbol(dev_k, host_k, sizeof(host_k), 0, cudaMemcpyHostToDevice);

    unsigned char *d_solution;
    cudaMalloc((void **)&d_solution, sizeof(char) * BYTE_LENGTH_TO_BE_FOUND);

    int *blockContainsSolution = (int *)malloc(sizeof(int));
    int *d_blockContainsSolution;
    cudaMalloc(&d_blockContainsSolution, sizeof(int));

    BYTE allowedBytes[16] = {0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66};
    unsigned char *d_allowedBytes;
    cudaMalloc((void **)&d_allowedBytes, sizeof(BYTE) * 16);
    cudaMemcpy(d_allowedBytes, allowedBytes, sizeof(BYTE) * 16, cudaMemcpyHostToDevice);

    // Get the expected hash result convert to WORD in big endian byte ordering to compare with sha256 context state later and allocate it on the GPU
    char userHashResults[MAX_USER_INPUT];
    char *tokens[MAX_USER_INPUT];
    int userHashCount = 0;
    scanf("%[^\n]%*c", userHashResults);
    char *token = strtok(userHashResults, ",");
    while (token != NULL && userHashCount < MAX_HASH_RESULTS)
    {
        tokens[userHashCount++] = token;
        token = strtok(NULL, ",");
    }
    WORD *d_realHashedState;
    cudaMalloc((void **)&d_realHashedState, sizeof(WORD) * 8 * userHashCount);

    WORD wordResult[8];
    for (int i = 0; i < userHashCount; ++i)
    {
        hexStringToShaStateWords(tokens[i], wordResult);
        cudaMemcpy(d_realHashedState + 8 * i, wordResult, sizeof(WORD) * 8, cudaMemcpyHostToDevice);
    }

    unsigned long hashCount = 0;
    long long start = timeInMilliseconds();
    long long seed = start;

    while (1)
    {
        seed = ((seed << 13) ^ seed ^ (seed >> 17) ^ (seed << 5));
        hashCount += THREADS * BLOCKS;
        sha256_cuda<<<THREADS, BLOCKS>>>(d_solution, d_blockContainsSolution, seed, userHashCount, d_realHashedState, d_allowedBytes);

        // cudaDeviceSynchronize();

        cudaMemcpy(blockContainsSolution, d_blockContainsSolution, sizeof(int), cudaMemcpyDeviceToHost);
        if (*blockContainsSolution == 1)
        {
            BYTE solution[BYTE_LENGTH_TO_BE_FOUND];
            cudaMemcpy(solution, d_solution, sizeof(BYTE) * BYTE_LENGTH_TO_BE_FOUND, cudaMemcpyDeviceToHost);

            long elapsed = timeInMilliseconds() - start;
            printf("Hashes (%'lu) Seconds (%'f) Hashes/sec (%'lu)\n", hashCount, ((float)elapsed) / 1000.0, (unsigned long)((double)hashCount / (double)elapsed) * 1000);
            printf("Hash Found\n");
            for (int i = 0; i < BYTE_LENGTH_TO_BE_FOUND; ++i)
            {
                printf("%c", (char)solution[i]);
            }
            printf("\n");
            break;
        }
        long elapsed = timeInMilliseconds() - start;
        printf("Hashes (%'lu) Seconds (%'f) Hashes/sec (%'lu)\r", hashCount, ((float)elapsed) / 1000.0, (unsigned long)((double)hashCount / (double)elapsed) * 1000);
    }
}