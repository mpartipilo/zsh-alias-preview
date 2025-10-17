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

# Store the preview text and state
typeset -g _ALIAS_PREVIEW_TEXT=""
typeset -g _ALIAS_PREVIEW_LINES=0

# Function to clear the preview
_alias_preview_clear() {
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
    local search_term="$1"
    local -a matches=()
    local name exp
    
    # Search in regular aliases
    for name exp in ${(kv)aliases}; do
        if [[ "$name" == "$search_term"* ]]; then
            matches+=("$name:$exp")
        fi
    done
    
    # Search in global aliases
    for name exp in ${(kv)galiases}; do
        if [[ "$name" == "$search_term"* ]]; then
            matches+=("$name:$exp")
        fi
    done
    
    # Sort matches: exact match first, then by length, then alphabetically
    local -a sorted_matches=()
    local -a exact_matches=()
    local -a prefix_matches=()
    
    for match in "${matches[@]}"; do
        name="${match%%:*}"
        if [[ "$name" == "$search_term" ]]; then
            exact_matches+=("$match")
        else
            prefix_matches+=("$match")
        fi
    done
    
    # Sort prefix matches by length then alphabetically
    prefix_matches=(${(on)prefix_matches})  # Sort alphabetically first
    prefix_matches=(${(O)prefix_matches[@]})  # Reverse
    prefix_matches=(${(on)prefix_matches[@]/(#m)*/${#MATCH%%:*}:$MATCH})  # Add length prefix
    prefix_matches=(${prefix_matches[@]#*:})  # Remove length prefix
    
    # Combine: exact matches first, then prefix matches
    sorted_matches=("${exact_matches[@]}" "${prefix_matches[@]}")
    
    # Return up to MAX_MATCHES
    echo "${(F)sorted_matches[1,$ALIAS_PREVIEW_MAX_MATCHES]}"
}

# Main function to check for aliases and show preview
_alias_preview_check() {
    # Clear any existing preview first
    _alias_preview_clear
    
    # Get the current buffer
    local buffer="$BUFFER"
    
    # If buffer is empty, nothing to do
    [[ -z "$buffer" ]] && return
    
    # Split by common separators to handle multiple commands
    local commands
    commands=("${(@s/;/)buffer}")
    
    # Process each command segment
    local cmd_segment
    for cmd_segment in $commands; do
        # Remove leading/trailing whitespace
        cmd_segment="${cmd_segment## #}"
        cmd_segment="${cmd_segment%% #}"
        
        # Also split by && and ||
        local subcmds
        subcmds=("${(@s/&&/)cmd_segment}")
        
        for cmd_segment in $subcmds; do
            subcmds=("${(@s/||/)cmd_segment}")
            
            for cmd_segment in $subcmds; do
                # Remove leading/trailing whitespace again
                cmd_segment="${cmd_segment## #}"
                cmd_segment="${cmd_segment%% #}"
                
                # Also handle pipes
                local pipe_cmds
                pipe_cmds=("${(@s/|/)cmd_segment}")
                
                for cmd_segment in $pipe_cmds; do
                    # Remove leading/trailing whitespace
                    cmd_segment="${cmd_segment## #}"
                    cmd_segment="${cmd_segment%% #}"
                    
                    local potential_alias exp
                    
                    if [[ "$ALIAS_PREVIEW_TRIGGER" == "progressive" ]]; then
                        # Progressive mode - find all matching aliases
                        if [[ "$cmd_segment" =~ ^([^[:space:]]+)[[:space:]] ]]; then
                            potential_alias="${match[1]}"
                        else
                            potential_alias="$cmd_segment"
                        fi
                        
                        if [[ -n "$potential_alias" ]]; then
                            local matches=$(_alias_preview_find_matches "$potential_alias")
                            if [[ -n "$matches" ]]; then
                                # Format matches for display
                                local -a display_lines=()
                                local match name exp
                                for match in ${(f)matches}; do
                                    name="${match%%:*}"
                                    exp="${match#*:}"
                                    display_lines+=("[$name] → $exp")
                                done
                                
                                _alias_preview_show "${(F)display_lines}"
                                return
                            fi
                        fi
                        
                    elif [[ "$ALIAS_PREVIEW_TRIGGER" == "instant" ]]; then
                        # Instant mode - exact match only
                        if [[ "$cmd_segment" =~ ^([^[:space:]]+)[[:space:]] ]]; then
                            potential_alias="${match[1]}"
                        else
                            potential_alias="$cmd_segment"
                        fi
                        
                        # Check if it's a regular alias
                        exp="${aliases[$potential_alias]}"
                        
                        # If not found, check global aliases
                        if [[ -z "$exp" ]]; then
                            exp="${galiases[$potential_alias]}"
                        fi
                        
                        # If we found an expansion, show it
                        if [[ -n "$exp" ]]; then
                            _alias_preview_show "$exp"
                            return
                        fi
                        
                    else
                        # "space" mode - only show preview after space
                        if [[ "$cmd_segment" =~ ^([^[:space:]]+)[[:space:]] ]]; then
                            potential_alias="${match[1]}"
                            
                            # Check if it's a regular alias
                            exp="${aliases[$potential_alias]}"
                            
                            # If not found, check global aliases
                            if [[ -z "$exp" ]]; then
                                exp="${galiases[$potential_alias]}"
                            fi
                            
                            # If we found an expansion, show it
                            if [[ -n "$exp" ]]; then
                                _alias_preview_show "$exp"
                                return
                            fi
                        fi
                    fi
                done
            done
        done
    done
}

# Widget to handle the preview
_alias_preview_widget() {
    _alias_preview_check
}

# Widget for accept-line to clear preview before execution
_alias_preview_accept_line() {
    _alias_preview_clear
    zle .accept-line
}

# Widget for other actions that should clear the preview
_alias_preview_clear_widget() {
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
    _alias_preview_clear
}
trap _alias_preview_sigint INT