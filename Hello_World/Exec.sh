#!/bin/bash
set -e

# Diretório do script
cd "$(dirname "$0")"

# Compila o Main.hs gerando o executável "hello"
ghc Main.hs -o hello

# Executa
./hello
