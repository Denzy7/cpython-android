#!/bin/bash
git tag $(git -C cpython describe --tags)
