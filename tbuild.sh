readonly TBUILD_VERSION="v1.2.0"

_tbuild_die() {
    echo "$1" >&2
    return 1
}

_tbuild_project_root() {
    pwd -P
}

_tbuild_validate_project_path() {
    local label="$1" value="$2"

    [[ -n "$value" ]]                              || _tbuild_die "Invalid $label: value cannot be empty."                          || return 1
    [[ "$value" == ./* ]]                          || _tbuild_die "Invalid $label: path must start with ./"                         || return 1
    [[ "$value" != *"//"* ]]                       || _tbuild_die "Invalid $label: repeated slashes are not allowed."               || return 1
    [[ "$value" != *"/../"* && \
       "$value" != *"/.."  && \
       "$value" != *"../"* ]]                      || _tbuild_die "Invalid $label: parent directory traversal is not allowed."      || return 1
    [[ "$value" =~ ^\./[a-zA-Z0-9/._-]+$ ]]        || _tbuild_die "Invalid $label: only alphanumeric characters, /, ., _, and - are allowed." || return 1
}

# Walks every intermediate path component and rejects symlinks.
# The final component is intentionally not checked here; callers are
# responsible for checking it with [ ! -L "$path" ] after this returns.
_tbuild_reject_symlink_path_components() {
    local path="$1"
    local current="."
    local part rest

    rest="${path#./}"

    while [[ "$rest" == */* ]]; do
        part="${rest%%/*}"
        rest="${rest#*/}"
        current="$current/$part"

        if [ -L "$current" ]; then
            _tbuild_die "Refusing symlinked path component: $current"
            return 1
        fi
    done
}

_tbuild_existing_file_in_project() {
    local label="$1" path="$2"
    local root real

    _tbuild_validate_project_path "$label" "$path"           || return 1
    _tbuild_reject_symlink_path_components "$path"           || return 1

    [ -f "$path" ]  || { _tbuild_die "$label missing: $path";     return 1; }
    [ ! -L "$path" ] || { _tbuild_die "$label is symlinked: $path"; return 1; }

    root="$(_tbuild_project_root)"                           || return 1
    real="$(cd "$(dirname "$path")" && pwd -P)/$(basename "$path")" || return 1

    [[ "$real" == "$root/"* ]] || { _tbuild_die "$label resolves outside project: $path"; return 1; }
}

_tbuild_existing_dir_in_project() {
    local label="$1" path="$2"
    local root real

    _tbuild_validate_project_path "$label" "$path"           || return 1
    _tbuild_reject_symlink_path_components "$path"           || return 1

    [ -d "$path" ]   || { _tbuild_die "$label missing: $path";     return 1; }
    [ ! -L "$path" ] || { _tbuild_die "$label is symlinked: $path"; return 1; }

    root="$(_tbuild_project_root)"                           || return 1
    real="$(cd "$path" && pwd -P)"                           || return 1

    [[ "$real" == "$root" || "$real" == "$root/"* ]] || { _tbuild_die "$label resolves outside project: $path"; return 1; }
}

_tbuild_sha256() {
    local file="$1"

    if command -v sha256sum > /dev/null 2>&1; then
        sha256sum "$file" 2>/dev/null | awk '{print $1}'
        return ${PIPESTATUS[0]}
    fi

    if command -v shasum > /dev/null 2>&1; then
        shasum -a 256 "$file" 2>/dev/null | awk '{print $1}'
        return ${PIPESTATUS[0]}
    fi

    _tbuild_die "No sha256 tool found."
}

_tbuild_sed_escape() {
    printf '%s' "$1" | sed 's/[&/\\]/\\&/g'
}

_tbuild_atomic_write() {
    local file="$1"
    local content="$2"
    local dir base tmp old_umask

    if [ -L "$file" ]; then
        _tbuild_die "Refusing to write symlinked file: $file"
        return 1
    fi

    dir="$(dirname "$file")"
    base="$(basename "$file")"

    [ -d "$dir" ] || { _tbuild_die "Target directory missing: $dir"; return 1; }
    [ ! -L "$dir" ] || { _tbuild_die "Target directory is symlinked: $dir"; return 1; }

    old_umask=$(umask)
    umask 077
    tmp="$(mktemp "$dir/.${base}.tmp.XXXXXX")" || {
        umask "$old_umask"
        return 1
    }
    umask "$old_umask"

    printf '%s' "$content" > "$tmp" || {
        rm -f -- "$tmp"
        return 1
    }

    mv -f -- "$tmp" "$file" || {
        rm -f -- "$tmp"
        return 1
    }
}

_tbuild_load_config_file() {
    local file="$1"
    local -n _tailwind_input="$2"
    local -n _css_dir="$3"
    local -n _html_file="$4"
    local line key value

    _tailwind_input=""
    _css_dir=""
    _html_file=""

    _tbuild_existing_file_in_project "Config file" "$file" || return 1

    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        if [[ ! "$line" =~ ^(TAILWIND_INPUT|CSS_DIR|HTML_FILE)=\"(\./[a-zA-Z0-9/._-]+)\"[[:space:]]*$ ]]; then
            echo "Config rejected: unexpected content in $file" >&2
            echo "  Offending line: $line" >&2
            return 1
        fi

        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"

        _tbuild_validate_project_path "$key" "$value" || return 1

        case "$key" in
            TAILWIND_INPUT) _tailwind_input="$value" ;;
            CSS_DIR)        _css_dir="$value" ;;
            HTML_FILE)      _html_file="$value" ;;
        esac
    done < "$file"

    # Consistent || return 1 chaining so _tbuild_die failures propagate correctly.
    [ -n "$_tailwind_input" ] || { _tbuild_die "Config rejected: TAILWIND_INPUT is required."; return 1; }
    [ -n "$_css_dir" ]        || { _tbuild_die "Config rejected: CSS_DIR is required.";        return 1; }
    [ -n "$_html_file" ]      || { _tbuild_die "Config rejected: HTML_FILE is required.";      return 1; }
}

_tbuild_write_config_file() {
    local file="$1"
    local tailwind_input="$2"
    local css_dir="$3"
    local html_file="$4"
    local content

    _tbuild_validate_project_path "Config file"    "$file"          || return 1
    _tbuild_validate_project_path "Tailwind input" "$tailwind_input" || return 1
    _tbuild_validate_project_path "CSS directory"  "$css_dir"       || return 1
    _tbuild_validate_project_path "HTML file"      "$html_file"     || return 1

    content=$(cat <<EOL
TAILWIND_INPUT="$tailwind_input"
CSS_DIR="$css_dir"
HTML_FILE="$html_file"
EOL
)

    _tbuild_atomic_write "$file" "$content"$'\n'
}

_tbuild_current_css() {
    local html_file="$1"
    local result

    _tbuild_existing_file_in_project "HTML file" "$html_file" || return 1

    result=$(grep -oE "app_[0-9]{6}_[0-9]{6}\.css" "$html_file" 2>/dev/null | head -n1)

    [[ "$result" =~ ^app_[0-9]{6}_[0-9]{6}\.css$ ]] || return 1

    echo "$result"
}

_tbuild_tailwind_bin() {
    local lock_file="./.tbuild.lock"
    local bin="./tailwindcss"
    local stored_hash actual_hash

    _tbuild_existing_file_in_project "tailwindcss binary" "$bin" || return 1
    [ -x "$bin" ] || { _tbuild_die "tailwindcss binary is not executable: $bin"; return 1; }

    if [ -f "$lock_file" ]; then
        _tbuild_existing_file_in_project "Lock file" "$lock_file" || return 1

        stored_hash=$(grep -oE "^[a-f0-9]{64}$" "$lock_file" 2>/dev/null | head -n1)

        [ -n "$stored_hash" ] || { _tbuild_die "Lock file is invalid: $lock_file"; return 1; }

        actual_hash=$(_tbuild_sha256 "$bin") || return 1

        if [ "$actual_hash" != "$stored_hash" ]; then
            echo "tailwindcss binary checksum mismatch." >&2
            echo "  Expected: $stored_hash" >&2
            echo "  Got:      $actual_hash" >&2
            return 1
        fi
    else
        echo "Warning: no .tbuild.lock found; skipping binary checksum verification." >&2
        echo "Run 'tbuild lock' only after verifying the binary source." >&2
    fi

    echo "$bin"
}

_tbuild_update_html_css() {
    local html_file="$1"
    local new_css="$2"
    local escaped_new_css tmp dir base count

    _tbuild_existing_file_in_project "HTML file" "$html_file" || return 1

    escaped_new_css=$(_tbuild_sed_escape "$new_css")
    dir="$(dirname "$html_file")"
    base="$(basename "$html_file")"

    tmp="$(mktemp "$dir/.${base}.tmp.XXXXXX")" || return 1

    chmod --reference="$html_file" "$tmp" 2>/dev/null || chmod 644 "$tmp"

    count=$(grep -oE "app_[0-9]{6}_[0-9]{6}\.css" "$html_file" | wc -l | awk '{print $1}')

    if [ "$count" -lt 1 ]; then
        rm -f -- "$tmp"
        _tbuild_die "No existing app timestamp CSS reference found in HTML."
        return 1
    fi

    sed -E "s|app_[0-9]{6}_[0-9]{6}\.css|$escaped_new_css|g" "$html_file" > "$tmp" || {
        rm -f -- "$tmp"
        return 1
    }

    grep -q "$new_css" "$tmp" || {
        rm -f -- "$tmp"
        _tbuild_die "HTML update validation failed."
        return 1
    }

    mv -f -- "$tmp" "$html_file" || {
        rm -f -- "$tmp"
        return 1
    }
}

_tbuild_create_default_config() {
    local config_file="$1"

    _tbuild_write_config_file "$config_file" \
        "./Core/css/tailwind.css" \
        "./public/assets/css" \
        "./views/partials/head.php" || return 1

    echo "Created default config: $config_file"
}

tbuild() {
    # Require Bash 4.3+ for local -n (name references).
    # macOS ships Bash 3.2 by default; users need to install a newer Bash
    # (e.g. via Homebrew) and source this script from it.
    if [[ "${BASH_VERSINFO[0]}" -lt 4 || \
        ( "${BASH_VERSINFO[0]}" -eq 4 && "${BASH_VERSINFO[1]}" -lt 3 ) ]]; then
        echo "tbuild requires Bash 4.3 or later (current: ${BASH_VERSION})." >&2
        echo "On macOS, install a newer Bash via Homebrew: brew install bash" >&2
        return 1
    fi

    local config_file="./.tbuildrc"
    local cmd="${1:-help}"
    local tailwind_input css_dir html_file

    if [ ! -f "$config_file" ]; then
        _tbuild_create_default_config "$config_file" || return 1
    fi

    _tbuild_load_config_file "$config_file" tailwind_input css_dir html_file || return 1

    if [ "$cmd" = "setup" ]; then
        local new_tailwind_input new_css_dir new_html_file

        echo "Current tbuild configuration:"
        echo "  Tailwind input file: $tailwind_input"
        echo "  CSS output directory: $css_dir"
        echo "  HTML head file: $html_file"
        echo

        read -r -n 256 -p "New Tailwind input file (leave empty to keep current): " new_tailwind_input
        echo
        read -r -n 256 -p "New CSS output directory (leave empty to keep current): " new_css_dir
        echo
        read -r -n 256 -p "New HTML head file (leave empty to keep current): " new_html_file
        echo

        new_tailwind_input="${new_tailwind_input:-$tailwind_input}"
        new_css_dir="${new_css_dir:-$css_dir}"
        new_html_file="${new_html_file:-$html_file}"

        _tbuild_write_config_file "$config_file" "$new_tailwind_input" "$new_css_dir" "$new_html_file" || return 1

        echo "Configuration saved to $config_file"
        return 0
    fi

    if [ "$cmd" = "config" ]; then
        echo "Current tbuild configuration:"
        echo "  Tailwind input file: $tailwind_input"
        echo "  CSS output directory: $css_dir"
        echo "  HTML head file: $html_file"
        return 0
    fi

    if [ "$cmd" = "dev" ]; then
        local current_css tailwind_bin

        current_css=$(_tbuild_current_css "$html_file") || {
            echo "No CSS file found in $html_file. Run 'tbuild build' first." >&2
            return 1
        }

        tailwind_bin=$(_tbuild_tailwind_bin) || return 1

        _tbuild_existing_file_in_project "Tailwind input file" "$tailwind_input" || return 1
        _tbuild_existing_dir_in_project  "CSS output directory" "$css_dir"       || return 1

        echo "Using existing file: $current_css"
        "$tailwind_bin" -i "$tailwind_input" -o "$css_dir/$current_css" --watch
        return $?
    fi

    if [ "$cmd" = "build" ]; then
        local current_css timestamp new_css backup_css tailwind_bin output_file

        tailwind_bin=$(_tbuild_tailwind_bin) || return 1

        _tbuild_existing_file_in_project "Tailwind input file" "$tailwind_input" || return 1
        _tbuild_existing_dir_in_project  "CSS output directory" "$css_dir"       || return 1
        _tbuild_existing_file_in_project "HTML file"            "$html_file"     || return 1

        current_css=$(_tbuild_current_css "$html_file") || true
        timestamp=$(date +%y%m%d_%H%M%S)

        [[ "$timestamp" =~ ^[0-9]{6}_[0-9]{6}$ ]] || { _tbuild_die "Unexpected timestamp format: $timestamp"; return 1; }

        new_css="app_${timestamp}.css"
        output_file="$css_dir/$new_css"

        [[ "$new_css" =~ ^app_[0-9]{6}_[0-9]{6}\.css$ ]] || { _tbuild_die "Generated CSS filename failed validation."; return 1; }

        if [ -e "$output_file" ]; then
            _tbuild_die "Output file already exists: $output_file"
            return 1
        fi

        if [ -n "$current_css" ] && [ -f "$css_dir/$current_css" ]; then
            [ ! -L "$css_dir/$current_css" ] || { _tbuild_die "Current CSS is symlinked: $css_dir/$current_css"; return 1; }

            backup_css="$css_dir/$current_css.bak.$timestamp"

            if [ -e "$backup_css" ]; then
                _tbuild_die "Backup already exists: $backup_css"
                return 1
            fi

            mv -- "$css_dir/$current_css" "$backup_css" || return 1
            echo "Backed up current CSS to $backup_css"
        fi

        echo "Building: $new_css"

        if ! "$tailwind_bin" -i "$tailwind_input" -o "$output_file" --minify; then
            echo "Tailwind build failed." >&2

            if [ -n "${backup_css:-}" ] && [ -f "$backup_css" ]; then
                mv -- "$backup_css" "$css_dir/$current_css"
            fi

            rm -f -- "$output_file"
            return 1
        fi

        if ! _tbuild_update_html_css "$html_file" "$new_css"; then
            echo "Failed to update HTML head. Rolling back." >&2
            rm -f -- "$output_file"

            if [ -n "${backup_css:-}" ] && [ -f "$backup_css" ]; then
                mv -- "$backup_css" "$css_dir/$current_css"
            fi

            return 1
        fi

        echo "HTML head updated to $new_css"
        echo "Build complete: $new_css"

        if [ -n "${backup_css:-}" ]; then
            echo "Backup: $backup_css"
        fi

        return 0
    fi

    if [ "$cmd" = "version" ]; then
        local css_path css_file css_basename tailwind_version

        if [ -d "$css_dir" ] && [ ! -L "$css_dir" ]; then
            css_path=$(find "$css_dir" -maxdepth 1 -type f -name "app_[0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9].css" 2>/dev/null | sort | tail -n1)
        fi

        if [ -n "${css_path:-}" ] && [ -f "$css_path" ] && [ ! -L "$css_path" ]; then
            css_basename=$(basename "$css_path")

            if [[ "$css_basename" =~ ^app_[0-9]{6}_[0-9]{6}\.css$ ]]; then
                css_file="$css_basename"
                tailwind_version=$(head -c 512 "$css_path" 2>/dev/null | head -n1 | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+")
            fi
        fi

        echo "tbuild version: $TBUILD_VERSION"
        echo "Tailwind CSS: ${tailwind_version:-unknown}"
        echo "CSS file: ${css_file:-none}"
        return 0
    fi

    if [ "$cmd" = "lock" ]; then
        local lock_file="./.tbuild.lock"
        local bin="./tailwindcss"
        local hash

        _tbuild_existing_file_in_project "tailwindcss binary" "$bin" || return 1
        [ -x "$bin" ] || { _tbuild_die "tailwindcss binary is not executable."; return 1; }

        hash=$(_tbuild_sha256 "$bin") || return 1
        [[ "$hash" =~ ^[a-f0-9]{64}$ ]] || { _tbuild_die "Failed to compute valid checksum."; return 1; }

        _tbuild_atomic_write "$lock_file" "$hash"$'\n' || return 1

        echo "Checksum written to $lock_file: $hash"
        return 0
    fi

    if [ "$cmd" = "update" ]; then
        echo "Automatic update is disabled for security."
        echo "Download updates manually from the trusted release source, verify them, then replace the files yourself."
        echo "After replacing the binary, run 'tbuild lock' to update the checksum."
        return 1
    fi

    if [ "$cmd" = "help" ]; then
        echo -e "Usage: tbuild [command]\n"
        echo -e "\033[38;2;59;130;246msetup:   \033[0mSet default paths for this project."
        echo -e "\033[38;2;59;130;246mconfig:  \033[0mShow current configuration without changing it."
        echo -e "\033[38;2;59;130;246mdev:     \033[0mRun Tailwind in dev mode."
        echo -e "\033[38;2;59;130;246mbuild:   \033[0mBuild and minify with a new timestamped filename."
        echo -e "\033[38;2;59;130;246mlock:    \033[0mPin the tailwindcss binary checksum to .tbuild.lock."
        echo -e "\033[38;2;59;130;246mversion: \033[0mShow tbuild version and Tailwind CSS file info."
        echo -e "\033[38;2;59;130;246mupdate:  \033[0mDisabled for security."
        echo -e "\033[38;2;59;130;246mhelp:    \033[0mShow this help message.\n"
        return 0
    fi

    echo "Unknown command: '${cmd:-<none>}'. Try: tbuild help" >&2
    return 1
}