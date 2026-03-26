#!/bin/bash
#
# run_deploy.sh - Run the pre-built isaac_ros_perceptor_realsense_d456 deploy container.
# Modeled on run_dev.sh. Reads DEPLOY_IMAGE_NAME from .isaac_ros_common-config.
#
# Usage:
#   ./run_deploy.sh              # auto-starts perceptor_realsense_d456.launch.py + RViz2
#   ./run_deploy.sh -s           # interactive bash (for debugging)
#   ./run_deploy.sh -h           # show help
#

set -e

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source "${ROOT}/utils/print_color.sh"

# Source config
if [[ -f "${ROOT}/.isaac_ros_common-config" ]]; then
    . "${ROOT}/.isaac_ros_common-config"
fi
if [[ -f ~/.isaac_ros_common-config ]]; then
    . ~/.isaac_ros_common-config
fi

# Validate
if [[ -z "${DEPLOY_IMAGE_NAME}" ]]; then
    print_error "DEPLOY_IMAGE_NAME not set in .isaac_ros_common-config"
    exit 1
fi

# Parse args
INTERACTIVE_SHELL=0
VALID_ARGS=$(getopt -o sh --long shell,help -- "$@")
eval set -- "$VALID_ARGS"
while [ : ]; do
    case "$1" in
        -s | --shell)
            INTERACTIVE_SHELL=1
            shift
            ;;
        -h | --help)
            echo "Usage: run_deploy.sh [-s|--shell] [launch_args...]"
            echo "  (no args)                  Auto-start with default mode (static)"
            echo "  mode:=dynamic              Dynamic scene reconstruction"
            echo "  mode:=people_segmentation  People segmentation (requires DNN model)"
            echo "  mode:=people_detection     People detection (requires DNN model)"
            echo "  run_rviz:=False            Headless mode"
            echo "  -s, --shell                Open interactive bash for debugging"
            exit 0
            ;;
        --) shift; break ;;
    esac
done

# Check docker group membership (same check as run_dev.sh)
RE="\<docker\>"
if [[ ! $(groups ${USER}) =~ $RE ]]; then
    print_error "User |${USER}| is not in the 'docker' group."
    print_error "Run: sudo usermod -aG docker \${USER} && newgrp docker"
    exit 1
fi

# Check image exists locally
if [[ -z "$(docker image ls --quiet ${DEPLOY_IMAGE_NAME})" ]]; then
    print_error "Deploy image '${DEPLOY_IMAGE_NAME}' not found locally."
    print_error "Run ./scripts/build_deploy.sh first."
    exit 1
fi

PLATFORM="$(uname -m)"
CONTAINER_NAME="${DEPLOY_IMAGE_NAME}-container"

# Remove any previously exited container with the same name
if [ "$(docker ps -a --quiet --filter status=exited --filter name=${CONTAINER_NAME})" ]; then
    docker rm "${CONTAINER_NAME}" > /dev/null
fi

# Allow X11 connections from Docker
xhost +local:root > /dev/null 2>&1 || true

DOCKER_ARGS=()

# --- Display / X11 ---
DOCKER_ARGS+=("-v /tmp/.X11-unix:/tmp/.X11-unix")
DOCKER_ARGS+=("-v ${HOME}/.Xauthority:/root/.Xauthority:rw")
DOCKER_ARGS+=("-e DISPLAY")

# --- NVIDIA GPU ---
DOCKER_ARGS+=("-e NVIDIA_DRIVER_CAPABILITIES=all")

# --- ROS ---
if [[ ! -z "${ROS_DOMAIN_ID}" ]]; then
    DOCKER_ARGS+=("-e ROS_DOMAIN_ID=${ROS_DOMAIN_ID}")
fi

# --- Timezone ---
DOCKER_ARGS+=("-v /etc/localtime:/etc/localtime:ro")

# --- RealSense USB device access ---
DOCKER_ARGS+=("-v /dev:/dev")

# --- Jetson / aarch64-specific volumes ---
if [[ "${PLATFORM}" == "aarch64" ]]; then
    DOCKER_ARGS+=("-e NVIDIA_VISIBLE_DEVICES=nvidia.com/gpu=all,nvidia.com/pva=all")
    DOCKER_ARGS+=("-v /usr/bin/tegrastats:/usr/bin/tegrastats")
    DOCKER_ARGS+=("-v /tmp/:/tmp/")
    DOCKER_ARGS+=("-v /usr/lib/aarch64-linux-gnu/tegra:/usr/lib/aarch64-linux-gnu/tegra")
    DOCKER_ARGS+=("-v /usr/src/jetson_multimedia_api:/usr/src/jetson_multimedia_api")
    DOCKER_ARGS+=("-v /usr/share/vpi3:/usr/share/vpi3")
    DOCKER_ARGS+=("-v /dev/input:/dev/input")
    DOCKER_ARGS+=("--pid=host")
    if [[ $(getent group jtop) ]]; then
        DOCKER_ARGS+=("-v /run/jtop.sock:/run/jtop.sock:ro")
    fi
else
    DOCKER_ARGS+=("-e NVIDIA_VISIBLE_DEVICES=all")
fi

# --- Jetson power optimization ---
if [[ "${PLATFORM}" == "aarch64" ]] && command -v nvpmodel &>/dev/null; then
    CURRENT_MODE=$(nvpmodel -q 2>/dev/null | grep -oP 'NV Power Mode: \K\w+' || true)
    if [[ "${CURRENT_MODE}" != "MAXN" ]]; then
        print_warning "Setting Jetson to MAXN power mode for best performance"
        sudo nvpmodel -m 0 2>/dev/null || true
    fi
    sudo jetson_clocks 2>/dev/null || true
fi

LAUNCH_ARGS="$@"

print_info "Running deploy container: ${CONTAINER_NAME}"
print_info "  Image: ${DEPLOY_IMAGE_NAME}"

if [[ ${INTERACTIVE_SHELL} -eq 1 ]]; then
    print_info "Interactive shell mode (launch file will NOT auto-start)"
    docker run -it --rm \
        --privileged \
        --network host \
        --ipc=host \
        --runtime nvidia \
        ${DOCKER_ARGS[@]} \
        --name "${CONTAINER_NAME}" \
        "${DEPLOY_IMAGE_NAME}" \
        /bin/bash
else
    print_info "Auto-starting: ros2 launch ${LAUNCH_PACKAGE} ${LAUNCH_FILE} ${LAUNCH_ARGS}"
    docker run -it --rm \
        --privileged \
        --network host \
        --ipc=host \
        --runtime nvidia \
        ${DOCKER_ARGS[@]} \
        --name "${CONTAINER_NAME}" \
        "${DEPLOY_IMAGE_NAME}" \
        bash -c "ros2 launch ${LAUNCH_PACKAGE} ${LAUNCH_FILE} ${LAUNCH_ARGS}"
fi
