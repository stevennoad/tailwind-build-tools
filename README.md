# Tailwind Build Tools

A lightweight set of Bash utilities for managing Tailwind CSS builds with versioned filenames, automatic backups, and quick development workflows.

---

## 🚀 Features
- **`dev`** → Run Tailwind in watch mode (keeps using the same CSS file).
- **`build`** → Minify and generate a new CSS file with a timestamped filename. Updates:
	- `.bashrc` (so new builds auto-load).
	- `views/partials/head.php` (CSS reference update).
	- Keeps clean backups (`.bak`).
- **`version`** → Show current Tailwind version, and active CSS file.
- **`setup`** → Initialise or update project paths for Tailwind input, CSS output, and HTML head file.
- **`config`** → Show the current project configuration without modifying it.
- **`help`** → Show all available commands.

---

## 📂 Example File Structure

Your project should look something like this:

my-project/
├── Core/
│   └── css/
│       └── tailwind.css        # Tailwind input file
├── public/
│   └── assets/
│       └── css/
│           ├── app_250702_2036.css   # Generated CSS file (timestamped)
│           └── app_250702_2036.css.bak (optional backup)
├── views/
│   └── partials/
│       └── head.php             # HTML head with CSS reference
├── tailwindcss                  # Tailwind CLI binary
├── version.php                  # Contains app version info
├── tbuild.sh                    # Bash function
└── README.md

---

## ⚙️ Installation

Clone the repo and source the function in your `~/.bashrc` (or `~/.zshrc`):

```bash
git clone https://github.com/stevennoad/tailwind-build-tools.git
cd tailwind-build-tools

# Add to your shell config (bash)
echo "source $(pwd)/tbuild.sh" >> ~/.bashrc

# or for zsh
echo "source $(pwd)/tbuild.sh" >> ~/.zshrc

# Reload your shell
source ~/.bashrc
```

## Usage
tbuild dev      # Watch mode, reuses current CSS
tbuild build    # Build new minified CSS with timestamp
tbuild version  # Show app + Tailwind versions
tbuild setup    # Initialize or update project paths
tbuild config   # Show current project configuration
tbuild help     # Show help message
