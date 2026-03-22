#!/bin/bash
cat ~/.ssh/id_rsa.pub | ssh root@101.132.159.73 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && chmod 700 ~/.ssh"
