#!/bin/bash
# cmdlog.sh — Appends a command to the verification log
# Root-only. Called via sudo from PROMPT_COMMAND in .bashrc
printf '%s\n' "$1" >> /opt/.cmd_log
