#!/bin/bash
# Upgrade core tooling (stable for Python 3.9 / EMR)
sudo python3 -m pip install --upgrade "pip<24" setuptools wheel

# Numeric stack (PINNED)
sudo python3 -m pip install --no-cache-dir \
    numpy==1.26.4 \
    pandas==1.5.3 \
    pyarrow==14.0.2

# TensorFlow stack (CPU, compatible)
sudo python3 -m pip install --no-cache-dir \
    ml-dtypes==0.2.0 \
    tensorflow==2.15.0

# Imaging
sudo python3 -m pip install pillow

# AWS / IO
sudo python3 -m pip install \
    boto3 \
    s3fs \
    fsspec
