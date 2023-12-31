#  YAFU Build

This is a repository for building YAFU in a stable environment and creating a container image.

## Usage

A pre-built Docker image is available at ghcr.io/nomeaning777/yafu.

Example usage:
```
$ echo "factor(34887643827257061332233019897238504016552464229603783645553446311649239590777)" | docker run -i ghcr.io/nomeaning777/yafu -v -threads 16
```
