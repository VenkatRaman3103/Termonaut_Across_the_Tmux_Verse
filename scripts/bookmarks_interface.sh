#!/bin/bash

bookmars_FILE="$HOME/.tmux-bookmars-list"
CURRENT_SESSION=$(tmux display-message -p '#S')
CURRENT_WINDOW=$(tmux display-message -p '#I')
CURRENT_TARGET="${CURRENT_SESSION}:${CURRENT_WINDOW}"

get_tmux_option() {
    local option="$1"
    local default_value="$2"
    local option_value=$(tmux show-option -gqv "$option")
    echo "${option_value:-$default_value}"
}

hex_to_ansi() {
    local hex="$1"
    hex="${hex#\#}"
    
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    
    printf "\033[38;2;%d;%d;%dm" "$r" "$g" "$b"
}

ACTIVE_COLOR_HEX=$(get_tmux_option "@bookmars-active-color" "#87ceeb")
ACTIVE_COLOR=$(hex_to_ansi "$ACTIVE_COLOR_HEX")

SESSION_COLOR_HEX=$(get_tmux_option "@bookmars-session-color" "#ffffff")
SESSION_COLOR=$(hex_to_ansi "$SESSION_COLOR_HEX")

WINDOW_COLOR_HEX=$(get_tmux_option "@bookmars-window-color" "#90ee90")
WINDOW_COLOR=$(hex_to_ansi "$WINDOW_COLOR_HEX")

MARK_COLOR_HEX=$(get_tmux_option "@bookmars-mark-color" "#777777")
MARK_COLOR=$(hex_to_ansi "$MARK_COLOR_HEX")

NORMAL="\033[0m"

FZF_HEIGHT=$(get_tmux_option "@bookmars-fzf-height" "100%")
FZF_BORDER=$(get_tmux_option "@bookmars-fzf-border" "none")
FZF_LAYOUT=$(get_tmux_option "@bookmars-fzf-layout" "no-reverse")
FZF_PREVIEW_POSITION=$(get_tmux_option "@bookmars-fzf-preview-position" "top:60%")
FZF_PROMPT=$(get_tmux_option "@bookmars-fzf-prompt" "bookmars > ")
FZF_POINTER=$(get_tmux_option "@bookmars-fzf-pointer" "▶")

PREVIEW_ENABLED=$(get_tmux_option "@bookmars-preview-enabled" "true")
SHOW_PREVIEW_LINES=$(get_tmux_option "@bookmars-show-preview-lines" "15")
SHOW_PROCESS_COUNT=$(get_tmux_option "@bookmars-show-process-count" "3")

create_bookmars_file() {
    if [ ! -f "$bookmars_FILE" ]; then
        touch "$bookmars_FILE"
    fi
}

get_bookmars_entries() {
    create_bookmars_file
    
    local temp_file=$(mktemp)
    local line_number=1
    
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            local session=$(echo "$line" | cut -d':' -f1)
            local window=$(echo "$line" | cut -d':' -f2)
            
            if tmux has-session -t "$session" 2>/dev/null; then
                if tmux list-windows -t "$session" -F "#I" 2>/dev/null | grep -q "^${window}$"; then
                    local window_name=$(tmux list-windows -t "$session" -F "#I #W" 2>/dev/null | grep "^${window} " | cut -d' ' -f2-)
                    
                    if [ "$line" = "$CURRENT_TARGET" ]; then
                        printf "%b%d. %s:%s%b %b(%s)%b %b(active)%b\n" "${WINDOW_COLOR}" "$line_number" "$session" "$window" "${NORMAL}" "${MARK_COLOR}" "$window_name" "${NORMAL}" "${ACTIVE_COLOR}" "${NORMAL}" >> "$temp_file"
                    else
                        printf "%b%d. %s%b:%b%s%b %b(%s)%b\n" "${MARK_COLOR}" "$line_number" "${SESSION_COLOR}" "$session" "${WINDOW_COLOR}" "$window" "${NORMAL}" "${MARK_COLOR}" "$window_name" "${NORMAL}" >> "$temp_file"
                    fi
                else
                    printf "%b%d. %s:%s%b %b(invalid - window not found)%b\n" "${MARK_COLOR}" "$line_number" "$line" "${NORMAL}" "${MARK_COLOR}" "${NORMAL}" >> "$temp_file"
                fi
            else
                printf "%b%d. %s%b %b(invalid - session not found)%b\n" "${MARK_COLOR}" "$line_number" "$line" "${NORMAL}" "${MARK_COLOR}" "${NORMAL}" >> "$temp_file"
            fi
            line_number=$((line_number + 1))
        fi
    done < "$bookmars_FILE"
    
    cat "$temp_file"
    rm -f "$temp_file"
}

switch_to_bookmars() {
    local selection="$1"
    local line_number=$(echo "$selection" | awk '{print $1}' | sed 's/\.//')
    local target=$(sed -n "${line_number}p" "$bookmars_FILE")
    
    if [ -n "$target" ]; then
        local session=$(echo "$target" | cut -d':' -f1)
        local window=$(echo "$target" | cut -d':' -f2)
        
        if tmux has-session -t "$session" 2>/dev/null; then
            if tmux list-windows -t "$session" -F "#I" 2>/dev/null | grep -q "^${window}$"; then
                tmux switch-client -t "$session"
                tmux select-window -t "$session:$window"
                tmux display-message "Switched to bookmars: $session:$window"
            else
                tmux display-message "Error: Window $window not found in session $session"
            fi
        else
            tmux display-message "Error: Session $session not found"
        fi
    fi
}

remove_bookmars_entry() {
    local selection="$1"
    local line_number=$(echo "$selection" | awk '{print $1}' | sed 's/\.//')
    local target=$(sed -n "${line_number}p" "$bookmars_FILE")
    
    if [ -n "$target" ]; then
        local temp_file=$(mktemp)
        sed "${line_number}d" "$bookmars_FILE" > "$temp_file"
        mv "$temp_file" "$bookmars_FILE"
        
        tmux display-message "Removed bookmars entry: $target"
        main
    fi
}

add_current_to_bookmars() {
    create_bookmars_file
    
    if grep -Fxq "$CURRENT_TARGET" "$bookmars_FILE" 2>/dev/null; then
        tmux display-message "Current window already in bookmars list"
    else
        echo "$CURRENT_TARGET" >> "$bookmars_FILE"
        tmux display-message "Added to bookmars: $CURRENT_TARGET"
    fi
    main
}

clear_all_bookmarss() {
    local confirmation=$(echo -e "y\nn" | fzf --header="Clear all bookmars entries? Select 'y' to confirm" --reverse --border="$FZF_BORDER")
    
    if [ "$confirmation" = "y" ]; then
        > "$bookmars_FILE"
        tmux display-message "Cleared all bookmars entries"
    fi
    main
}

clean_invalid_entries() {
    create_bookmars_file
    
    local temp_file=$(mktemp)
    local cleaned_count=0
    
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            local session=$(echo "$line" | cut -d':' -f1)
            local window=$(echo "$line" | cut -d':' -f2)
            
            if tmux has-session -t "$session" 2>/dev/null; then
                if tmux list-windows -t "$session" -F "#I" 2>/dev/null | grep -q "^${window}$"; then
                    echo "$line" >> "$temp_file"
                else
                    cleaned_count=$((cleaned_count + 1))
                fi
            else
                cleaned_count=$((cleaned_count + 1))
            fi
        fi
    done < "$bookmars_FILE"
    
    mv "$temp_file" "$bookmars_FILE"
    
    if [ "$cleaned_count" -gt 0 ]; then
        tmux display-message "Cleaned $cleaned_count invalid bookmars entries"
    else
        tmux display-message "No invalid entries found"
    fi
    main
}

create_preview_script() {
    local preview_script=$(mktemp -t "bookmars_preview_XXXXXX.sh")
    
    cat > "$preview_script" << PREVIEW_EOF
#!/bin/bash

selection="\$1"
line_number=\$(echo "\$selection" | awk '{print \$1}' | sed 's/\\.//')
target=\$(sed -n "\${line_number}p" "$bookmars_FILE")

if [ -n "\$target" ]; then
    session=\$(echo "\$target" | cut -d':' -f1)
    window=\$(echo "\$target" | cut -d':' -f2)
    
    printf "\033[1;36mbookmars Entry:\033[0m \033[1;33m%s\033[0m\n\n" "\$target"
    
    if tmux has-session -t "\$session" 2>/dev/null; then
        if tmux list-windows -t "\$session" -F "#I" 2>/dev/null | grep -q "^\${window}\$"; then
            window_info=\$(tmux list-windows -t "\$session" -F "#I: #W #{window_active}" 2>/dev/null | grep "^\$window:")
            printf "\033[1;36mWindow Info:\033[0m %s\n\n" "\$window_info"
            
            active_pane=\$(tmux list-panes -t "\$session:\$window" -F "#{pane_active} #{pane_id}" 2>/dev/null | grep "^1" | awk '{print \$2}')
            if [ -z "\$active_pane" ]; then
                active_pane=\$(tmux list-panes -t "\$session:\$window" -F "#{pane_id}" 2>/dev/null | head -1)
            fi
            
            if [ -n "\$active_pane" ]; then
                printf "\033[1;36mPane Content:\033[0m\n"
                tmux capture-pane -e -t "\$active_pane" -p 2>/dev/null | tail -$SHOW_PREVIEW_LINES
                
                printf "\n\033[1;36mRunning Processes:\033[0m\n"
                pane_pid=\$(tmux list-panes -t "\$active_pane" -F "#{pane_pid}" 2>/dev/null | head -1)
                if [ -n "\$pane_pid" ]; then
                    ps --ppid \$pane_pid -o pid=,cmd= 2>/dev/null | head -$SHOW_PROCESS_COUNT | while read line; do
                        if [ -n "\$line" ]; then
                            printf "\033[1;35m%s\033[0m \033[1;37m%s\033[0m\n" "\$(echo \$line | awk '{print \$1}')" "\$(echo \$line | cut -d' ' -f2-)"
                        fi
                    done
                fi
            fi
        else
            printf "\033[1;31mError:\033[0m Window \$window not found in session \$session\n"
        fi
    else
        printf "\033[1;31mError:\033[0m Session \$session not found\n"
    fi
else
    printf "\033[1;31mError:\033[0m No target found for line \$line_number\n"
fi
PREVIEW_EOF

    chmod +x "$preview_script"
    echo "$preview_script"
}

show_help() {
    local help_text="Enter       Jump to selected bookmars entry
ctrl-d      Remove selected bookmars entry
ctrl-a      Add current window to bookmars
ctrl-r      Clear all bookmars entries
ctrl-x      Clean invalid entries (remove non-existent sessions/windows)
ctrl-p      Toggle preview mode (currently: $PREVIEW_ENABLED)
?           Show this help menu
Escape      Exit"

    echo "$help_text" | fzf --reverse --header "bookmars Keyboard Shortcuts" --prompt "Press Escape to return" --border="$FZF_BORDER" --height="$FZF_HEIGHT"
    main
}

toggle_preview() {
    if [ "$PREVIEW_ENABLED" = "true" ]; then
        tmux set-option -g "@bookmars-preview-enabled" "false"
        tmux display-message "bookmars preview disabled"
    else
        tmux set-option -g "@bookmars-preview-enabled" "true"
        tmux display-message "bookmars preview enabled"
    fi
    PREVIEW_ENABLED=$(get_tmux_option "@bookmars-preview-enabled" "true")
    main
}

main() {
    local bookmars_entries=$(get_bookmars_entries)
    
    if [ -z "$bookmars_entries" ]; then
        local empty_options="Add current window to bookmars
Show help
Exit"
        
        local selection=$(echo "$empty_options" | fzf --header="No bookmars entries found" --prompt="$FZF_PROMPT" --reverse --border="$FZF_BORDER" --height="$FZF_HEIGHT")
        
        case "$selection" in
            "Add current window to bookmars")
                add_current_to_bookmars
                ;;
            "Show help")
                show_help
                ;;
            *)
                return 0
                ;;
        esac
        return 0
    fi
    
    local preview_script=""
    local cleanup_preview_func=""
    
    if [ "$PREVIEW_ENABLED" = "true" ]; then
        preview_script=$(create_preview_script)
        cleanup_preview_func() {
            rm -f "$preview_script" 2>/dev/null
        }
        trap cleanup_preview_func EXIT
    fi
    
    local header_text="Enter:Jump / ctrl-d:Remove / ctrl-a:Add Current / ctrl-r:Clear All / ctrl-x:Clean Invalid / ctrl-p:Toggle Preview ($PREVIEW_ENABLED) / ?:Help"
    local fzf_cmd="fzf --header=\"$header_text\" --prompt=\"$FZF_PROMPT\" --pointer=\"$FZF_POINTER\" --ansi --expect=ctrl-d,ctrl-a,ctrl-r,ctrl-x,ctrl-p,? --$FZF_LAYOUT --height=\"$FZF_HEIGHT\" --border=\"$FZF_BORDER\""
    
    if [ "$PREVIEW_ENABLED" = "true" ]; then
        fzf_cmd="$fzf_cmd --preview=\"$preview_script {}\" --preview-window=\"$FZF_PREVIEW_POSITION\""
    fi
    
    local result=$(echo "$bookmars_entries" | eval "$fzf_cmd")
    
    local key=$(echo "$result" | head -1)
    local selection=$(echo "$result" | tail -1)
    
    if [ -z "$selection" ]; then
        [ -n "$cleanup_preview_func" ] && cleanup_preview_func
        return 0
    fi
    
    case "$key" in
        "ctrl-d")
            remove_bookmars_entry "$selection"
            ;;
        "ctrl-a")
            add_current_to_bookmars
            ;;
        "ctrl-r")
            clear_all_bookmarss
            ;;
        "ctrl-x")
            clean_invalid_entries
            ;;
        "ctrl-p")
            toggle_preview
            ;;
        "?")
            show_help
            ;;
        *)
            switch_to_bookmars "$selection"
            ;;
    esac
    
    [ -n "$cleanup_preview_func" ] && cleanup_preview_func
}

if [ -z "$TMUX" ]; then
    echo "This script must be run inside a tmux session."
    exit 1
fi

if ! command -v fzf &> /dev/null; then
    echo "Error: fzf is not installed. Please install it first."
    exit 1
fi

main
