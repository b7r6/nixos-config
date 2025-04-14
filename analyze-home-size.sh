#!/usr/bin/env bash
# Home directory size analyzer for backup planning
# This script shows the size of your home directory before and after filtering

# Set colors for better readability
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to print section headers
print_header() {
  echo -e "\n${BLUE}${BOLD}========================================${NC}"
  echo -e "${BLUE}${BOLD} $1 ${NC}"
  echo -e "${BLUE}${BOLD}========================================${NC}\n"
}

# Function to display sizes in human-readable format
display_size() {
  local name=$1
  local size_bytes=$2
  local size_human=$(numfmt --to=iec-i --suffix=B --format="%.2f" "$size_bytes")
  
  echo -e "${BOLD}$name:${NC} $size_human ($size_bytes bytes)"
}

# Function to check if a path exists
check_path() {
  if [ ! -d "$1" ]; then
    echo -e "${RED}Directory $1 does not exist. Exiting.${NC}"
    exit 1
  fi
}

# Function to analyze directory size with specified excludes
analyze_with_excludes() {
  local dir=$1
  shift
  local excludes=("$@")
  
  local exclude_args=""
  for exclude in "${excludes[@]}"; do
    exclude_args="$exclude_args --exclude='$exclude'"
  done
  
  # Use eval to properly handle the exclude arguments
  local cmd="du -sb $exclude_args \"$dir\""
  local size=$(eval "$cmd" | cut -f1)
  
  echo "$size"
}

# Main function
main() {
  print_header "HOME DIRECTORY SIZE ANALYZER"
  
  # Get home directory path (default to current user's home)
  HOME_DIR=${1:-$HOME}
  check_path "$HOME_DIR"
  
  echo -e "${YELLOW}Analyzing directory: ${BOLD}$HOME_DIR${NC}\n"
  
  # Define filter sets with progressively more aggressive exclusions
  # Basic filter - just the absolute essentials to exclude
  BASIC_EXCLUDES=(
    "node_modules"
    ".git"
    "*/node_modules"
    "*/.git"
  )
  
  # Standard filter - reasonable excludes for most users
  STANDARD_EXCLUDES=(
    "${BASIC_EXCLUDES[@]}"
    "*/target" # Rust builds
    "*/build"  # Generic build directories
    "*/dist"   # Distribution directories
    ".cache"
    "*/cache"
    "*/.cache"
    ".npm"
    ".yarn"
    "*/node_modules/*"
    ".venv"
    "*/venv"
    "*/.venv"
    "*/env"
    "*/.env"
    "*/ENV"
    ".gradle"
    "*/gradle"
  )
  
  # Aggressive filter - exclude most generated/downloaded content
  AGGRESSIVE_EXCLUDES=(
    "${STANDARD_EXCLUDES[@]}"
    "Downloads"
    "*/Downloads"
    "Video"
    "*/Video"
    "Movies"
    "*/Movies"
    "*/tmp"
    "*/temp"
    "*/logs"
    "*/.Trash"
    "*/Trash"
    ".local/share/Steam"
    ".local/share/containers"
    ".local/share/flatpak"
    "*/__pycache__"
    "*/CMakeFiles"
    "*/CMakeCache.txt"
    "*/node_modules/*/*"
    "*/target/debug"
    "*/target/release"
  )
  
  # Development-focused filter - keep personal files but exclude dev artifacts
  DEV_FOCUSED_EXCLUDES=(
    "node_modules"
    "*/node_modules"
    "*/*/node_modules"
    ".git"
    "*/.git"
    "*/target" # Rust builds
    "*/target/debug"
    "*/target/release"
    "*/build"  # Generic build directories
    "*/dist"   # Distribution directories
    ".cache"
    "*/cache"
    "*/.cache"
    ".npm"
    ".yarn"
    ".venv"
    "*/venv"
    "*/.venv"
    "*/env"
    "*/.env"
    "*/ENV"
    ".gradle"
    "*/gradle"
    "*/__pycache__"
    "*/CMakeFiles"
    "*/CMakeCache.txt"
    "*/node_modules/*/*"
    ".rustup"
    ".cargo"
    ".m2"
    ".kube"
    ".docker"
    ".vscode"
    ".idea"
    "*/bin"
    "*/obj"
    ".nix-profile"
    ".local/share/nix"
    ".local/state/nix"
  )
  
  # Get the total size
  echo -e "${YELLOW}Calculating total size...${NC}"
  TOTAL_SIZE=$(du -sb "$HOME_DIR" | cut -f1)
  display_size "Total home directory size" "$TOTAL_SIZE"
  
  # Get sizes with different exclude filters
  echo -e "\n${YELLOW}Calculating sizes with different filter levels...${NC}"
  
  echo -e "${YELLOW}Basic filter (just node_modules and .git)...${NC}"
  BASIC_SIZE=$(analyze_with_excludes "$HOME_DIR" "${BASIC_EXCLUDES[@]}")
  display_size "Size with basic filter" "$BASIC_SIZE"
  echo -e "  ${GREEN}Savings: $(numfmt --to=iec-i --suffix=B --format="%.2f" $((TOTAL_SIZE - BASIC_SIZE))) ($(printf "%.1f" $(echo "scale=3; ($TOTAL_SIZE - $BASIC_SIZE) * 100 / $TOTAL_SIZE" | bc))%)${NC}"
  
  echo -e "\n${YELLOW}Standard filter (common build artifacts and caches)...${NC}"
  STANDARD_SIZE=$(analyze_with_excludes "$HOME_DIR" "${STANDARD_EXCLUDES[@]}")
  display_size "Size with standard filter" "$STANDARD_SIZE"
  echo -e "  ${GREEN}Savings: $(numfmt --to=iec-i --suffix=B --format="%.2f" $((TOTAL_SIZE - STANDARD_SIZE))) ($(printf "%.1f" $(echo "scale=3; ($TOTAL_SIZE - $STANDARD_SIZE) * 100 / $TOTAL_SIZE" | bc))%)${NC}"
  
  echo -e "\n${YELLOW}Aggressive filter (most generated content)...${NC}"
  AGGRESSIVE_SIZE=$(analyze_with_excludes "$HOME_DIR" "${AGGRESSIVE_EXCLUDES[@]}")
  display_size "Size with aggressive filter" "$AGGRESSIVE_SIZE"
  echo -e "  ${GREEN}Savings: $(numfmt --to=iec-i --suffix=B --format="%.2f" $((TOTAL_SIZE - AGGRESSIVE_SIZE))) ($(printf "%.1f" $(echo "scale=3; ($TOTAL_SIZE - $AGGRESSIVE_SIZE) * 100 / $TOTAL_SIZE" | bc))%)${NC}"
  
  echo -e "\n${YELLOW}Development-focused filter (keep personal files, exclude dev artifacts)...${NC}"
  DEV_SIZE=$(analyze_with_excludes "$HOME_DIR" "${DEV_FOCUSED_EXCLUDES[@]}")
  display_size "Size with development-focused filter" "$DEV_SIZE"
  echo -e "  ${GREEN}Savings: $(numfmt --to=iec-i --suffix=B --format="%.2f" $((TOTAL_SIZE - DEV_SIZE))) ($(printf "%.1f" $(echo "scale=3; ($TOTAL_SIZE - $DEV_SIZE) * 100 / $TOTAL_SIZE" | bc))%)${NC}"
  
  # Show the filter contents
  print_header "FILTER DETAILS"
  
  echo -e "${BOLD}Basic filter excludes:${NC}"
  printf "  %s\n" "${BASIC_EXCLUDES[@]}"
  
  echo -e "\n${BOLD}Standard filter excludes:${NC}"
  # Only show the ones not in basic
  for exclude in "${STANDARD_EXCLUDES[@]}"; do
    if ! printf '%s\0' "${BASIC_EXCLUDES[@]}" | grep -Fxqz "$exclude"; then
      echo "  $exclude"
    fi
  done
  
  echo -e "\n${BOLD}Aggressive filter excludes:${NC}"
  # Only show the ones not in standard
  for exclude in "${AGGRESSIVE_EXCLUDES[@]}"; do
    if ! printf '%s\0' "${STANDARD_EXCLUDES[@]}" | grep -Fxqz "$exclude"; then
      echo "  $exclude"
    fi
  done
  
  echo -e "\n${BOLD}Development-focused filter excludes:${NC}"
  printf "  %s\n" "${DEV_FOCUSED_EXCLUDES[@]}"
  
  # Provide backup command examples
  print_header "RECOMMENDED BACKUP COMMANDS"
  
  echo -e "${BOLD}Using rsync with standard filter:${NC}"
  echo -e "rsync -avz \\"
  for exclude in "${STANDARD_EXCLUDES[@]}"; do
    echo -e "  --exclude='$exclude' \\"
  done
  echo -e "  $HOME_DIR/ /path/to/backup/destination/"
  
  echo -e "\n${BOLD}Using rsync with development-focused filter:${NC}"
  echo -e "rsync -avz \\"
  for exclude in "${DEV_FOCUSED_EXCLUDES[@]}"; do
    echo -e "  --exclude='$exclude' \\"
  done
  echo -e "  $HOME_DIR/ /path/to/backup/destination/"
  
  echo -e "\n${BOLD}Using tar with standard filter:${NC}"
  echo -e "tar \\"
  for exclude in "${STANDARD_EXCLUDES[@]}"; do
    echo -e "  --exclude='$exclude' \\"
  done
  echo -e "  -czf home_backup.tar.gz $HOME_DIR/"
  
  print_header "NEXT STEPS"
  echo -e "1. Review the filter options and select the one that best fits your needs"
  echo -e "2. Use one of the provided backup commands to create your backup"
  echo -e "3. Once your backup is secure, you can safely proceed with partitioning changes"
  echo -e "4. After creating a new home partition, restore your files with the inverse rsync command:"
  echo -e "   ${YELLOW}rsync -avz /path/to/backup/destination/ /path/to/new/home/${NC}"
}

# Run the main function
main "$@"
