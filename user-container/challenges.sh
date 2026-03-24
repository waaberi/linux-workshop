#!/bin/bash
# challenges — View challenge list, optionally filtered by number
# Usage: challenges        (show all)
#        challenges 1.1    (show specific challenge)
#        challenges 4      (show all of concept 4)

FILE="/opt/challenges.txt"

GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
BOLD=$'\033[1m'
CYAN=$'\033[0;36m'
DIM=$'\033[2m'
NC=$'\033[0m'

colorize() {
    sed \
        -e "s/\[E\]/${GREEN}[E]${NC}/g" \
        -e "s/\[M\]/${YELLOW}[M]${NC}/g" \
        -e "s/\[H\]/${RED}[H]${NC}/g" \
        -e "s/Challenge \([0-9]*\.[0-9]*\)/${BOLD}Challenge \1${NC}/" \
        -e "s/CONCEPT \([0-9]*\)/${CYAN}${BOLD}CONCEPT \1${NC}/" \
        -e "s/^  ====.*/${DIM}&${NC}/" \
        -e "s/^  ----.*/${DIM}&${NC}/"
}

if [ -z "$1" ]; then
    colorize < "$FILE" | less -R
else
    if [[ "$1" == *.* ]]; then
        # Specific challenge (e.g. 1.1, 4.3)
        block=$(awk -v id="$1" '
            BEGIN { found=0 }
            /\[.\] Challenge/ {
                if (found) exit
                if ($0 ~ "Challenge " id " ") found=1
            }
            found && /^====/ { exit }
            found { print }
        ' "$FILE")
    else
        # Entire concept (e.g. 1, 4)
        block=$(awk -v id="$1" '
            BEGIN { found=0 }
            /^  CONCEPT/ {
                if (found) exit
                if ($0 ~ "CONCEPT " id " ") found=1
            }
            found { print }
        ' "$FILE")
    fi

    if [ -n "$block" ]; then
        echo "$block" | colorize
    else
        echo "Challenge '$1' not found."
        echo "Usage: challenges [number]"
        echo "  challenges        Show all challenges"
        echo "  challenges 1.1    Show challenge 1.1"
        echo "  challenges 4      Show all of concept 4"
    fi
fi
