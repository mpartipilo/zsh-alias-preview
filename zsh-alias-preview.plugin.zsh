#!/usr/bin/env zsh
# zsh-alias-preview - Show alias expansions as you type
#
# Configuration:
#   ALIAS_PREVIEW_POSITION - "above" or "below" (default: "above")
#   ALIAS_PREVIEW_PREFIX - Text before expansion (default: "→ ")
#   ALIAS_PREVIEW_COLOR - Color for preview (default: "cyan")
#   ALIAS_PREVIEW_TRIGGER - "space", "instant", or "progressive" (default: "space")
#     "space": Show preview only after typing alias + space
#     "instant": Show preview as soon as current word matches an alias exactly
#     "progressive": Show preview for partial matches as you type
#   ALIAS_PREVIEW_MAX_MATCHES - Maximum number of matches to show (default: 3)

# Set defaults
: ${ALIAS_PREVIEW_POSITION:="above"}
: ${ALIAS_PREVIEW_PREFIX:="→ "}
: ${ALIAS_PREVIEW_COLOR:="cyan"}
: ${ALIAS_PREVIEW_TRIGGER:="space"}
: ${ALIAS_PREVIEW_MAX_MATCHES:=3}
: ${ALIAS_PREVIEW_DEBUG:=0}  # Set to 1 to keep xtrace/debug output

# Store the preview text and state
typeset -g _ALIAS_PREVIEW_TEXT=""
typeset -g _ALIAS_PREVIEW_LINES=0

# Function to clear the preview
_alias_preview_clear() {
    emulate -L zsh
    [[ $ALIAS_PREVIEW_DEBUG -eq 1 ]] || setopt no_xtrace
    if [[ $_ALIAS_PREVIEW_LINES -gt 0 ]]; then
        local lines=$_ALIAS_PREVIEW_LINES
        
        if [[ "$ALIAS_PREVIEW_POSITION" == "above" ]]; then
            # Move cursor up and clear each line
            for (( i=0; i<lines; i++ )); do
                echoti cuu1  # cursor up
                echoti el    # erase line
            done
        else
            # Save cursor, move down and clear each line, restore cursor
            echoti sc    # save cursor
            for (( i=0; i<lines; i++ )); do
                echoti cud1  # cursor down
                echoti el    # erase line
            done
            echoti rc    # restore cursor
        fi
        _ALIAS_PREVIEW_LINES=0
    fi
    _ALIAS_PREVIEW_TEXT=""
}

# Function to display the preview (can be multiple lines)
_alias_preview_show() {
    emulate -L zsh
    [[ $ALIAS_PREVIEW_DEBUG -eq 1 ]] || setopt no_xtrace
    local -a preview_lines=("${(@f)1}")  # Split by newlines
    local line_count=${#preview_lines}
    
    if [[ "$ALIAS_PREVIEW_POSITION" == "above" ]]; then
        # Save cursor position
        echoti sc
        # Move cursor up
        for (( i=0; i<line_count; i++ )); do
            echoti cuu1
        done
        # Print each line
        local idx=0
        for line in "${preview_lines[@]}"; do
            echoti el  # clear line
            if [[ $idx -eq 0 ]]; then
                # First line with configured prefix and color
                print -Pn "%F{${ALIAS_PREVIEW_COLOR}}${ALIAS_PREVIEW_PREFIX}${line}%f"
            else
                # Additional matches, indented
                print -Pn "%F{${ALIAS_PREVIEW_COLOR}}  ${line}%f"
            fi
            if [[ $idx -lt $((line_count - 1)) ]]; then
                echoti cud1  # move down for next line
            fi
            ((idx++))
        done
        # Restore cursor position
        echoti rc
    else
        # Save cursor position
        echoti sc
        # Move cursor down and print lines
        local idx=0
        for line in "${preview_lines[@]}"; do
            echoti cud1
            echoti el
            if [[ $idx -eq 0 ]]; then
                print -Pn "%F{${ALIAS_PREVIEW_COLOR}}${ALIAS_PREVIEW_PREFIX}${line}%f"
            else
                print -Pn "%F{${ALIAS_PREVIEW_COLOR}}  ${line}%f"
            fi
            ((idx++))
        done
        # Restore cursor position
        echoti rc
    fi
    
    _ALIAS_PREVIEW_TEXT="$1"
    _ALIAS_PREVIEW_LINES=$line_count
}

# Function to find matching aliases
_alias_preview_find_matches() {
    emulate -L zsh
    [[ $ALIAS_PREVIEW_DEBUG -eq 1 ]] || setopt no_xtrace
    local search_term="$1"
    local -a matches=()
    local name exp
    
    # IMPORTANT: iterate over keys only and fetch value separately so values containing spaces
    # (e.g. 'git add') are not word-split and paired with the next key by mistake.
    # Previous implementation used 'for name exp in ${(kv)aliases};' which splits values on
    # whitespace, leading to corrupted key/value pairs and displaying the expanded value in
    # the bracket instead of the alias name.
    
    # Search in regular aliases
    for name in ${(k)aliases}; do
        exp=${aliases[$name]}
        if [[ "$name" == "$search_term"* ]]; then
            matches+=("$name:$exp")
        fi
    done

    # Search in global aliases
    for name in ${(k)galiases}; do
        exp=${galiases[$name]}
        if [[ "$name" == "$search_term"* ]]; then
            matches+=("$name:$exp")
        fi
    done
    
    # Separate exact vs prefix matches
    local -a exact_matches prefix_matches sorted_matches
    for match in "${matches[@]}"; do
        name="${match%%:*}"
        if [[ "$name" == "$search_term" ]]; then
            exact_matches+=("$match")
        else
            prefix_matches+=("$match")
        fi
    done

    # Sort prefix matches by alias length (shortest first) then alphabetically.
    # Build sortable keys: zero-padded length + NUL + original (NUL simulated by unlikely sequence) then strip.
    local -a keyed prefix_sorted
    local key len
    for match in "${prefix_matches[@]}"; do
        name="${match%%:*}"
        len=${#name}
        # Pad length to 4 digits to preserve numeric order in lexicographic sort
        key="${(l:4::0:)len}|$match"
        keyed+=("$key")
    done
    prefix_sorted=(${(on)keyed})
    # Strip key prefix
    prefix_sorted=(${prefix_sorted[@]#????|})

    sorted_matches=("${exact_matches[@]}" "${prefix_sorted[@]}")
    echo "${(F)sorted_matches[1,$ALIAS_PREVIEW_MAX_MATCHES]}"
}

# Main function to check for aliases and show preview
_alias_preview_check() {
    emulate -L zsh
    [[ $ALIAS_PREVIEW_DEBUG -eq 1 ]] || setopt no_xtrace
    # Clear any existing preview first
    _alias_preview_clear
    
    # Get the current buffer
    local buffer="$BUFFER"
    
    # If buffer is empty, nothing to do
    [[ -z "$buffer" ]] && return
    
    # Normalize separators by replacing &&, ||, | with ; so we can iterate simply.
    local normalized=${buffer//&&/;}
    normalized=${normalized//||/;}
    normalized=${normalized//|/;}
    local -a segments=("${(@s/;/)normalized}")

    local seg potential_alias exp match name
    for seg in "${segments[@]}"; do
        # Trim leading/trailing whitespace (zsh pattern trims all spaces)
        seg="${seg##[[:space:]]##}"
        seg="${seg%%[[:space:]]##}"
        [[ -z "$seg" ]] && continue

        if [[ "$ALIAS_PREVIEW_TRIGGER" == "progressive" ]]; then
            potential_alias="${seg%% *}"  # first word (or entire seg if single word)
            if [[ -n "$potential_alias" ]]; then
                local matches=$(_alias_preview_find_matches "$potential_alias")
                if [[ -n "$matches" ]]; then
                    local -a display_lines=()
                    for match in ${(f)matches}; do
                        name="${match%%:*}"
                        exp="${match#*:}"
                        display_lines+=("$name → $exp")
                    done
                    _alias_preview_show "${(F)display_lines}"
                    return
                fi
            fi
        elif [[ "$ALIAS_PREVIEW_TRIGGER" == "instant" ]]; then
            potential_alias="${seg%% *}"
            exp="${aliases[$potential_alias]}"
            [[ -z "$exp" ]] && exp="${galiases[$potential_alias]}"
            if [[ -n "$exp" ]]; then
                _alias_preview_show "$exp"
                return
            fi
        else
            # space trigger
            if [[ "$seg" == *' '* ]]; then
                potential_alias="${seg%% *}"
                exp="${aliases[$potential_alias]}"
                [[ -z "$exp" ]] && exp="${galiases[$potential_alias]}"
                if [[ -n "$exp" ]]; then
                    _alias_preview_show "$exp"
                    return
                fi
            fi
        fi
    done
}

# Widget to handle the preview
_alias_preview_widget() {
    emulate -L zsh
    [[ $ALIAS_PREVIEW_DEBUG -eq 1 ]] || setopt no_xtrace
    _alias_preview_check
}

# Widget for accept-line to clear preview before execution
_alias_preview_accept_line() {
    emulate -L zsh
    [[ $ALIAS_PREVIEW_DEBUG -eq 1 ]] || setopt no_xtrace
    _alias_preview_clear
    zle .accept-line
}

# Widget for other actions that should clear the preview
_alias_preview_clear_widget() {
    emulate -L zsh
    [[ $ALIAS_PREVIEW_DEBUG -eq 1 ]] || setopt no_xtrace
    _alias_preview_clear
}

# Create ZLE widgets
zle -N _alias_preview_widget
zle -N _alias_preview_accept_line
zle -N _alias_preview_clear_widget

# Hook into line-pre-redraw to check after each change
autoload -Uz add-zle-hook-widget
add-zle-hook-widget line-pre-redraw _alias_preview_widget

# Bind accept-line to clear preview
zle -A _alias_preview_accept_line accept-line

# Clear preview on various actions
add-zle-hook-widget line-init _alias_preview_clear_widget

# Handle Ctrl-C to clear preview
_alias_preview_sigint() {
    emulate -L zsh
    [[ $ALIAS_PREVIEW_DEBUG -eq 1 ]] || setopt no_xtrace
    _alias_preview_clear
}
trap _alias_preview_sigint INT