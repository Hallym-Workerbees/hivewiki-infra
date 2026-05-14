#!/usr/bin/env bash
set -euo pipefail

rm -rf .build/lambda
mkdir -p .build/lambda

build_lambda() {
    name="$1"

    src="lambda/$name"
    dst=".build/lambda/$name"

    echo "Building $name..."

    mkdir -p "$dst"

    if [ -f "$src/requirements.txt" ]; then
        python -m pip install \
            -r "$src/requirements.txt" \
            -t "$dst"
    fi

    cp "$src"/*.py "$dst/"
}

for lambda_dir in lambda/*; do
    [ -d "$lambda_dir" ] || continue
    build_lambda "$(basename "$lambda_dir")"
done
