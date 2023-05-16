# CUDA SHA256 FINDER

You can give multiple hash result inputs "," separated.
Set the BYTE_LENGTH_TO_BE_FOUND (currently it is 8) and arrange allowedBytes(which bytes have been used to get that hash result, currently it is "0123456789abcdef") before compile.
Run the program, give at least one hash result (hex format string 64 char length)

```
nvcc -o build/findSHA256 findSHA256.cu
```

and run

```
./build/findSHA256
```

Give the hash result

```
a1ba2bcc51b269e776769b546b98464ed1e5ac5a8bbfb861ff9e284b14ce09d0
```

OUTPUT SAMPLE (don't forget to set THREAD and BLOCKS depending on your GPU)

```
Hashes (514867200) Seconds (3.878000) Hashes/sec (132766000)
Hash Found
0abd6e32
```