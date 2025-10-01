# Define tbuild version
TBUILD_VERSION="v1.0.0"

tbuild() {
		bashrc_file="$HOME/.bashrc"
		config_file="./.tbuildrc"

		# --- AUTO-CREATE CONFIG IF MISSING ---
		if [ ! -f "$config_file" ]; then
				cat > "$config_file" <<EOL
# Default project paths for tbuild
TAILWIND_INPUT="./Core/css/tailwind.css"
CSS_DIR="./public/assets/css"
HTML_FILE="./views/partials/head.php"
EOL
				echo "Created default config: $config_file"
		fi

		# --- LOAD CONFIG ---
		source "$config_file"

		cmd="$1"

		# --- SETUP COMMAND ---
		if [ "$cmd" = "setup" ]; then
				echo "Current tbuild configuration:"
				echo "  Tailwind input file: $TAILWIND_INPUT"
				echo "  CSS output directory: $CSS_DIR"
				echo "  HTML head file: $HTML_FILE"
				echo

				read -p "New Tailwind input file (leave empty to keep current): " tailwind_input
				read -p "New CSS output directory (leave empty to keep current): " css_dir
				read -p "New HTML head file (leave empty to keep current): " html_file

				tailwind_input="${tailwind_input:-$TAILWIND_INPUT}"
				css_dir="${css_dir:-$CSS_DIR}"
				html_file="${html_file:-$HTML_FILE}"

				cat > "$config_file" <<EOL
TAILWIND_INPUT="$tailwind_input"
CSS_DIR="$css_dir"
HTML_FILE="$html_file"
EOL

				echo "Configuration saved to $config_file"
				return 0
		fi

		# --- CONFIG DISPLAY COMMAND ---
		if [ "$cmd" = "config" ]; then
				echo "Current tbuild configuration:"
				echo "  Tailwind input file: $TAILWIND_INPUT"
				echo "  CSS output directory: $CSS_DIR"
				echo "  HTML head file: $HTML_FILE"
				return 0
		fi

		# --- DETERMINE CURRENT CSS ---
		current_css=$(grep -o "app_[0-9]\+\.css" "$bashrc_file" | head -n1)
		[ -z "$current_css" ] && current_css="app_250702_2036.css"

		# --- DEV MODE ---
		if [ "$cmd" = "dev" ]; then
				echo "Using existing file: $current_css"
				./tailwindcss -i "$TAILWIND_INPUT" -o "$CSS_DIR/$current_css" --watch

		# --- BUILD MODE ---
		elif [ "$cmd" = "build" ]; then
				timestamp=$(date +%y%m%d_%H%M)
				new_css="app_${timestamp}.css"

				echo "Updating backup..."
				if [ -f "$CSS_DIR/$current_css" ]; then
						cp "$CSS_DIR/$current_css" "$CSS_DIR/$current_css.bak"
						echo "Backed up current CSS → $current_css.bak"
				fi

				echo "🔧 Building: $new_css"
				./tailwindcss -i "$TAILWIND_INPUT" -o "$CSS_DIR/$new_css" --minify || { echo "Tailwind build failed."; return 1; }

				sed -i "s|app_[0-9]\+\.css|$new_css|g" "$bashrc_file" && echo ".bashrc updated → $new_css"
				[ -f "$HTML_FILE" ] && sed -i "s|app_[0-9]\+\.css|$new_css|g" "$HTML_FILE" && echo "HTML head updated → $new_css"

				echo "Build complete: $new_css"
				echo "CSS directory now contains:"
				echo "  Live: $new_css"
				echo "  Backup: $current_css.bak"

		# --- VERSION ---
		elif [ "$cmd" = "version" ]; then
				css_file=$(ls -1 "$CSS_DIR"/app_*.css 2>/dev/null | sort | tail -n 1 | xargs basename)

				# Extract Tailwind version from the first line of the CSS
				tailwind_version=$(head -n 1 "$CSS_DIR/$css_file" 2>/dev/null | grep -o "v[0-9]\+\.[0-9]\+\.[0-9]\+")

				echo "tbuild version: $TBUILD_VERSION"
				echo "Tailwind CSS: ${tailwind_version:-unknown}"
				echo "CSS file: ${css_file:-none}"

		# --- UPDATE COMMANDS ---
		elif [ "$cmd" = "update" ]; then
				subcmd="$2"

				if [ "$subcmd" = "tailwind" ]; then
						echo "Checking latest TailwindCSS release..."

						# Fetch latest release URL for Linux x64
						latest_url=$(curl -s https://api.github.com/repos/tailwindlabs/tailwindcss/releases/latest \
								| grep "browser_download_url.*tailwindcss-linux-x64\"" \
								| head -n 1 \
								| cut -d '"' -f 4)

						if [ -z "$latest_url" ]; then
								echo "Failed to fetch latest Tailwind release."
								return 1
						fi

						echo "Downloading: $latest_url"
						curl -L -o tailwindcss-linux-x64 "$latest_url" || { echo "Download failed."; return 1; }

						# Backup current binary if exists
						if [ -f "./tailwindcss" ]; then
								mv ./tailwindcss ./tailwindcss.bak
								echo "Existing tailwindcss → tailwindcss.bak"
						fi

						# Replace with new binary
						mv tailwindcss-linux-x64 tailwindcss
						chmod 755 tailwindcss
						echo "Tailwind updated successfully."

				else
						echo "Invalid update target. Try: tbuild update tailwind"
				fi

		# --- HELP ---
		elif [ "$cmd" = "help" ]; then
				echo -e "Usage: tbuild [command]\n"
				echo -e "\033[38;2;59;130;246msetup:   \033[0mSet default paths for this project (shows current config)."
				echo -e "\033[38;2;59;130;246mconfig:  \033[0mShow current configuration without changing it."
				echo -e "\033[38;2;59;130;246mdev:     \033[0mRun Tailwind in dev mode (watch, same file)."
				echo -e "\033[38;2;59;130;246mbuild:   \033[0mBuild + minify with new date filename, keep previous backup."
				echo -e "\033[38;2;59;130;246mversion: \033[0mShow tbuild version and Tailwind CSS file info."
				echo -e "\033[38;2;59;130;246mupdate tailwind: \033[0mDownload and install the latest TailwindCSS Linux binary."
				echo -e "\033[38;2;59;130;246mhelp:    \033[0mShow this help message.\n"

		else
				echo "Invalid command. Try: tbuild help"
		fi
}
