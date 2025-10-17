#!/usr/bin/env zsh
# zsh-alias-preview - Show alias expansions as you type
#
# Configuration:
#   ALIAS_PREVIEW_POSITION - "above" or "below" (default: "above")
#   ALIAS_PREVIEW_PREFIX - Text before expansion (default: "→ ")
#   ALIAS_PREVIEW_COLOR - Color for preview (default: "cyan")
#   ALIAS_PREVIEW_TRIGGER - "space" or "instant" (default: "space")
#     "space": Show preview only after typing alias + space
#     "instant": Show preview as soon as current word matches an alias

# Set defaults
: ${ALIAS_PREVIEW_POSITION:="above"}
: ${ALIAS_PREVIEW_PREFIX:="→ "}
: ${ALIAS_PREVIEW_COLOR:="cyan"}
: ${ALIAS_PREVIEW_TRIGGER:="space"}

# Store the preview text
typeset -g _ALIAS_PREVIEW_TEXT=""

# Function to clear the preview
_alias_preview_clear() {
    if [[ -n "$_ALIAS_PREVIEW_TEXT" ]]; then
        if [[ "$ALIAS_PREVIEW_POSITION" == "above" ]]; then
            # Move cursor up, clear line, move back down
            echoti cuu1  # cursor up
            echoti el    # erase line
        else
            # Save cursor, move down, clear line, restore cursor
            echoti sc    # save cursor
            echoti cud1  # cursor down
            echoti el    # erase line
            echoti rc    # restore cursor
        fi
        _ALIAS_PREVIEW_TEXT=""
    fi
}

# Function to display the preview
_alias_preview_show() {
    local preview_text="$1"
    
    if [[ "$ALIAS_PREVIEW_POSITION" == "above" ]]; then
        # Save cursor position
        echoti sc
        # Move cursor up one line
        echoti cuu1
        # Clear the line
        echoti el
        # Print the preview with color
        print -Pn "%F{${ALIAS_PREVIEW_COLOR}}${ALIAS_PREVIEW_PREFIX}${preview_text}%f"
        # Restore cursor position
        echoti rc
    else
        # Save cursor position
        echoti sc
        # Move cursor down one line
        echoti cud1
        # Clear the line
        echoti el
        # Print the preview with color
        print -Pn "%F{${ALIAS_PREVIEW_COLOR}}${ALIAS_PREVIEW_PREFIX}${preview_text}%f"
        # Restore cursor position
        echoti rc
    fi
    
    _ALIAS_PREVIEW_TEXT="$preview_text"
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
                    
                    local potential_alias expansion
                    
                    if [[ "$ALIAS_PREVIEW_TRIGGER" == "instant" ]]; then
                        # In instant mode, check if the entire segment (or first word) is an alias
                        # First, check if there's a space - if so, use first word
                        if [[ "$cmd_segment" =~ ^([^[:space:]]+)[[:space:]] ]]; then
                            potential_alias="${match[1]}"
                        else
                            # No space yet, check if entire segment is an alias
                            potential_alias="$cmd_segment"
                        fi
                        
                        # Check if it's a regular alias
                        expansion="${aliases[$potential_alias]}"
                        
                        # If not found, check global aliases
                        if [[ -z "$expansion" ]]; then
                            expansion="${galiases[$potential_alias]}"
                        fi
                        
                        # If we found an expansion, show it
                        if [[ -n "$expansion" ]]; then
                            _alias_preview_show "$expansion"
                            return
                        fi
                    else
                        # "space" mode - only show preview after space
                        # Get the first word (potential alias) followed by space
                        if [[ "$cmd_segment" =~ ^([^[:space:]]+)[[:space:]] ]]; then
                            potential_alias="${match[1]}"
                            
                            # Check if it's a regular alias
                            expansion="${aliases[$potential_alias]}"
                            
                            # If not found, check global aliases
                            if [[ -z "$expansion" ]]; then
                                expansion="${galiases[$potential_alias]}"
                            fi
                            
                            # If we found an expansion, show it
                            if [[ -n "$expansion" ]]; then
                                _alias_preview_show "$expansion"
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

# Hook into self-insert to check after each character
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