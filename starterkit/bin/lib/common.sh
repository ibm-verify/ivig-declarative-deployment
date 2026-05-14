#!/bin/bash
# =============================================================================
# Common Library Functions for IVIG Container Scripts
# =============================================================================
# This library provides shared functions used across multiple scripts in the
# devops/container/starter/bin directory tree.
#
# Usage: Source this file at the beginning of your script:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${SCRIPT_DIR}/lib/common.sh" || source "${SCRIPT_DIR}/../lib/common.sh"
#
# Version: 1.0.0
# =============================================================================

# Prevent multiple sourcing
[[ -n "${COMMON_LIB_LOADED:-}" ]] && return 0
readonly COMMON_LIB_LOADED=1

# =============================================================================
# Constants
# =============================================================================

readonly LOCAL_TIMEOUT_DEFAULT=120
readonly TIMEOUT_EXTENDED=300
readonly MAX_RETRIES=3
readonly SLEEP_INTERVAL=5

# Error codes
readonly ERR_KUBECTL_NOT_FOUND=2
readonly ERR_HELM_NOT_FOUND=3
readonly ERR_NAMESPACE_NOT_FOUND=7
readonly ERR_POD_NOT_FOUND=8
readonly ERR_CONFIG_MISSING=36
readonly ERR_INVALID_ARGS=42

# =============================================================================
# Logging Functions
# =============================================================================

# Log an informational message
# Usage: log_info "message"
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

# Log an error message
# Usage: log_error "message"
log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

# Log a warning message
# Usage: log_warn "message"
log_warn() {
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

# Log a debug message (only if DEBUG is set)
# Usage: log_debug "message"
log_debug() {
    [[ -n "${DEBUG:-}" ]] && echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

# Log a success message
# Usage: log_success "message"
log_success() {
    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

# =============================================================================
# Error Handling Functions
# =============================================================================

# Exit with error message and code
# Usage: die "error message" [exit_code]
die() {
    local msg="${1:-Unknown error}"
    local code="${2:-1}"
    log_error "$msg"
    exit "$code"
}

# Check if command succeeded, exit if not
# Usage: check_success "error message" [exit_code]
check_success() {
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        die "${1:-Command failed}" "${2:-$rc}"
    fi
}

# =============================================================================
# User Input Functions
# =============================================================================

# Prompt for input with default value
# Usage: prompt "Question" "default_value"
# Returns: User input or default in $REPLY
prompt() {
    local question="$1"
    local default="${2:-}"
    local input
    
    if [[ -n "$default" ]]; then
        read -r -p "$question [$default]: " input
        REPLY="${input:-$default}"
    else
        read -r -p "$question: " input
        REPLY="$input"
    fi
}

# Prompt for input that cannot be empty
# Usage: prompt_not_empty "Question" "default_value"
# Returns: User input in $REPLY
prompt_not_empty() {
    local question="$1"
    local default="${2:-}"
    
    REPLY=""
    while [[ -z "$REPLY" ]]; do
        prompt "$question" "$default"
        if [[ -z "$REPLY" ]]; then
            log_warn "Value cannot be empty. Please try again."
        fi
    done
}

# Prompt for password (hidden input)
# Usage: pw_prompt "Password prompt"
# Returns: Password in $REPLY
pw_prompt() {
    local prompt_text="$1"
    local password1
    local password2
    
    password1="1"
    password2=""
    
    while [[ "$password1" != "$password2" ]]; do
        read -r -s -p "$prompt_text: " password1
        echo >&2
        read -r -s -p "Re-enter $prompt_text: " password2
        echo >&2
        
        if [[ "$password1" != "$password2" ]]; then
            log_warn "Passwords don't match. Please try again."
            echo >&2
        fi
    done
    
    REPLY="$password1"
}

# Prompt for yes/no confirmation
# Usage: confirm "Question" [default_yes]
# Returns: 0 for yes, 1 for no
confirm() {
    local question="$1"
    local default_yes="${2:-0}"
    local prompt_suffix
    local response
    
    if [[ "$default_yes" -eq 1 ]]; then
        prompt_suffix="[Y/n]"
    else
        prompt_suffix="[y/N]"
    fi
    
    read -r -p "$question $prompt_suffix: " response
    response=$(echo "$response" | tr '[:upper:]' '[:lower:]')
    
    if [[ -z "$response" ]]; then
        return "$default_yes"
    fi
    
    case "$response" in
        y|yes) return 0 ;;
        n|no) return 1 ;;
        *) 
            log_warn "Invalid response. Please answer yes or no."
            confirm "$question" "$default_yes"
            ;;
    esac
}

# =============================================================================
# Validation Functions
# =============================================================================

# Check if value is a valid Kubernetes name
# Usage: validate_k8s_name "name"
# Returns: 0 if valid, 1 if invalid
validate_k8s_name() {
    local name="$1"
    local length=${#name}
    
    if [[ $length -gt 63 ]]; then
        log_error "Name exceeds 63 characters limit"
        return 1
    fi
    
    if [[ ! $name =~ ^[a-zA-Z0-9][-a-zA-Z0-9]{0,61}[a-zA-Z0-9]$ ]]; then
        log_error "Name must be alphanumeric or hyphen, and start/end with alphanumeric"
        return 1
    fi
    
    if [[ $name =~ ^kube- ]]; then
        log_error "Name cannot start with 'kube-' (reserved for Kubernetes)"
        return 1
    fi
    
    return 0
}

# Check if value is true or false
# Usage: validate_boolean "value"
# Returns: 0 if valid, 1 if invalid
validate_boolean() {
    local value="$1"
    [[ "$value" =~ ^(true|false)$ ]]
}

# Check if file exists and is readable
# Usage: validate_file_readable "path"
# Returns: 0 if valid, 1 if invalid
validate_file_readable() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi
    
    if [[ ! -r "$file" ]]; then
        log_error "File not readable: $file"
        return 1
    fi
    
    return 0
}

# =============================================================================
# Kubernetes Helper Functions
# =============================================================================

# Get kubectl command (handles oc, kubectl, minikube variants)
# Usage: get_kubectl_cmd
# Returns: kubectl command in $REPLY
get_kubectl_cmd() {
    local cmd
    
    for cmd in oc kubectl "minikube kubectl --"; do
        if command -v "${cmd%% *}" >/dev/null 2>&1; then
            if $cmd version >/dev/null 2>&1; then
                REPLY="$cmd"
                return 0
            fi
        fi
    done
    
    log_error "kubectl not found in PATH"
    return "$ERR_KUBECTL_NOT_FOUND"
}

# Get namespace from values.yaml
# Usage: get_namespace "values_yaml_path"
# Returns: namespace in $REPLY
get_namespace() {
    local values_file="${1:-../helm/values.yaml}"
    
    if [[ ! -f "$values_file" ]]; then
        log_error "Values file not found: $values_file"
        return "$ERR_CONFIG_MISSING"
    fi
    
    REPLY=$(grep "^namespace:" "$values_file" | awk '{print $2}' | tr -d '"' | tr -d "'")
    
    if [[ -z "$REPLY" ]]; then
        log_error "Unable to determine namespace from $values_file"
        return "$ERR_NAMESPACE_NOT_FOUND"
    fi
    
    return 0
}

# Get pod name by pattern
# Usage: get_pod_name "namespace" "pattern"
# Returns: pod name in $REPLY
get_pod_name() {
    local namespace="$1"
    local pattern="$2"
    local shouldwarn="${3:-1}"
    local kubectl_cmd
    
    get_kubectl_cmd || return $?
    kubectl_cmd="$REPLY"
    
    REPLY=$($kubectl_cmd -n "$namespace" get pods 2>/dev/null | grep "$pattern" | grep Running | head -n 1 | awk '{print $1}')
    
    if [[ -z "$REPLY" && "$shouldwarn" -eq 1 ]]; then
        log_warn "Unable to find running pod matching pattern: $pattern"
        return "$ERR_POD_NOT_FOUND"
    fi
    
    return 0
}

# Wait for pod to be running
# Usage: wait_for_pod "namespace" "pod_name" [timeout]
# Returns: 0 if successful, 1 if timeout
wait_for_pod() {
    local namespace="$1"
    local pod_name="$2"
    local timeout="${3:-$LOCAL_TIMEOUT_DEFAULT}"
    local kubectl_cmd
    local timer=0
    local status
    
    get_kubectl_cmd || return $?
    kubectl_cmd="$REPLY"
    
    log_info "Waiting for pod $pod_name to be running (timeout: ${timeout}s)"
    
    while [[ $timer -lt "$timeout" ]]; do
        status=$($kubectl_cmd -n "$namespace" get pod "$pod_name" -o jsonpath='{.status.phase}' 2>/dev/null)
        
        if [[ "$status" = "Running" ]]; then
            log_success "Pod $pod_name is running"
            return 0
        fi
        
        if [[ "$status" =~ (Error|Failed|CrashLoopBackOff) ]]; then
            log_error "Pod $pod_name failed with status: $status"
            $kubectl_cmd -n "$namespace" describe pod "$pod_name"
            return 1
        fi
        
        sleep "$SLEEP_INTERVAL"
        timer=$((timer + SLEEP_INTERVAL))
        
        if [[ $((timer % 30)) -eq 0 ]]; then
            log_info "Still waiting... (${timer}s elapsed)"
        fi
    done
    
    log_error "Timeout waiting for pod $pod_name (${timeout}s)"
    return 1
}

# Wait for pod containers to be ready
# Usage: wait_for_pod_ready "namespace" "pod_name" [timeout]
# Returns: 0 if successful, 1 if timeout
wait_for_pod_ready() {
    local namespace="$1"
    local pod_name="$2"
    local timeout="${3:-$LOCAL_TIMEOUT_DEFAULT}"
    local kubectl_cmd
    local timer=0
    local ready_status
    
    get_kubectl_cmd || return $?
    kubectl_cmd="$REPLY"
    
    log_info "Waiting for pod $pod_name containers to be ready (timeout: ${timeout}s)"
    
    while [[ $timer -lt "$timeout" ]]; do
        ready_status=$($kubectl_cmd -n "$namespace" get pod "$pod_name" -o jsonpath='{.status.containerStatuses[*].ready}' 2>/dev/null)
        
        # Check if all containers are ready (no "false" in status)
        if [[ -n "$ready_status" ]] && ! echo "$ready_status" | grep -q "false"; then
            log_success "Pod $pod_name is ready"
            return 0
        fi
        
        sleep "$SLEEP_INTERVAL"
        timer=$((timer + SLEEP_INTERVAL))
        
        if [[ $((timer % 30)) -eq 0 ]]; then
            log_info "Still waiting... (${timer}s elapsed)"
        fi
    done
    
    log_error "Timeout waiting for pod $pod_name to be ready (${timeout}s)"
    return 1
}

# =============================================================================
# Password Generation Functions
# =============================================================================

# Generate a random password
# Usage: generate_password [length]
# Returns: password in $REPLY
generate_password() {
    local length="${1:-32}"
    
    check_length "$length" || return 1
    
    REPLY=$(LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' </dev/urandom | head -c "$length")
    
    if [[ -z "$REPLY" ]]; then
        log_error "Failed to generate password"
        return 1
    fi
    
    return 0
}

# Generate a random alphanumeric password (no special chars)
# Usage: generate_alphanumeric_password [length]
# Returns: password in $REPLY
generate_alphanumeric_password() {
    local length="${1:-32}"
    
    check_length "$length" || return 1
    
    REPLY=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$length")
    
    if [[ -z "$REPLY" ]]; then
        log_error "Failed to generate password"
        return 1
    fi
    
    return 0
}

# Verify the length is a valid integer
# Usage: check_length value
# Returns: 0 if valid, 1 if invalid
check_length() {

    if ! [[ "$1" =~ ^[0-9]+$ ]]; then
        log_error "Length must be a positive integer"
        return 1
    fi

    if [[ "$length" -lt 8 ]] || [[ "$length" -gt 256 ]]; then
        log_error "Password length must be between 8 and 256"
        return 1
    fi

    return 0
}

# =============================================================================
# File Operations Functions
# =============================================================================

# Create a secure temporary file
# Usage: create_temp_file [prefix]
# Returns: temp file path in $REPLY
create_temp_file() {
    local prefix="${1:-tmp}"
    
    REPLY=$(mktemp "/tmp/${prefix}.XXXXXXXXXX")
    
    if [[ ! -f "$REPLY" ]]; then
        log_error "Failed to create temporary file"
        return 1
    fi
    
    # Set restrictive permissions
    chmod 600 "$REPLY"
    
    return 0
}

# Create a secure temporary directory
# Usage: create_temp_dir [prefix]
# Returns: temp directory path in $REPLY
create_temp_dir() {
    local prefix="${1:-tmpdir}"
    
    REPLY=$(mktemp -d "/tmp/${prefix}.XXXXXXXXXX")
    
    if [[ ! -d "$REPLY" ]]; then
        log_error "Failed to create temporary directory"
        return 1
    fi
    
    # Set restrictive permissions
    chmod 700 "$REPLY"
    
    return 0
}

# Backup a file with timestamp
# Usage: backup_file "file_path"
# Returns: backup file path in $REPLY
backup_file() {
    local file="$1"
    local timestamp
    
    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi
    
    timestamp=$(date +"%Y%m%d_%H%M%S")
    REPLY="${file}.${timestamp}.bak"
    
    cp "$file" "$REPLY" || {
        log_error "Failed to backup file: $file"
        return 1
    }
    
    log_info "Backed up $file to $REPLY"
    return 0
}

# =============================================================================
# sed Helper Functions
# =============================================================================

# Get the correct sed command for the platform
# Usage: get_sed_cmd
# Returns: sed command with -i flag in $REPLY
get_sed_cmd() {
    # GNU (Linux) sed has --version, BSD (macOS) sed does not
    if sed --version >/dev/null 2>&1; then
        REPLY="sed -i"
    else
        REPLY="sed -i ''"
    fi
    return 0
}

# =============================================================================
# Retry Logic Functions
# =============================================================================

# Retry a command with exponential backoff
# Usage: retry_command max_attempts "command" "args..."
# Returns: 0 if successful, 1 if all attempts failed
retry_command() {
    local max_attempts="$1"
    shift
    local attempt=1
    local delay=1
    
    while [[ "$attempt" -le "$max_attempts" ]]; do
        log_info "Attempt $attempt of $max_attempts: $*"
        
        if "$@"; then
            log_success "Command succeeded on attempt $attempt"
            return 0
        fi
        
        if [[ "$attempt" -lt "$max_attempts" ]]; then
            log_warn "Command failed, retrying in ${delay}s..."
            sleep "$delay"
            delay=$((delay * 2))
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_error "Command failed after $max_attempts attempts"
    return 1
}

# =============================================================================
# Initialization
# =============================================================================

log_debug "Common library loaded successfully"
