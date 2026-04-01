#!/bin/bash

# Copyright (c) 2024, NVIDIA CORPORATION.  All rights reserved.

set -e

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Read common configuration
source $ROOT/.isaac_ros_common-config

# Ensure we're reading correct overrides
if [[ -f $ROOT/.isaac_ros_common-config.local ]]; then
    source $ROOT/.isaac_ros_common-config.local
fi

# Automatically detect branch for the container name but use latest image
GIT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")
DEPLOY_FULL_IMAGE="${DEPLOY_IMAGE_NAME}:latest"

echo "Git branch detected: ${GIT_BRANCH}. Target deploy image: ${DEPLOY_FULL_IMAGE}"

# Create container name
CONTAINER_NAME="${DEPLOY_IMAGE_NAME}_${GIT_BRANCH}-container"

# Base Display & Device Forwarding accurately ported from run_dev.sh
DOCKER_ARGS+=("-v /tmp/.X11-unix:/tmp/.X11-unix")
DOCKER_ARGS+=("-v $HOME/.Xauthority:/root/.Xauthority:rw")
DOCKER_ARGS+=("-e XAUTHORITY=/root/.Xauthority")
DOCKER_ARGS+=("-e DISPLAY")
DOCKER_ARGS+=("-e NVIDIA_VISIBLE_DEVICES=all")
DOCKER_ARGS+=("-e NVIDIA_DRIVER_CAPABILITIES=all")

# Automatically authorize local root Docker containers to seamlessly access X11 Display
if command -v xhost &> /dev/null; then
    xhost +local:root > /dev/null 2>&1 || true
fi

DOCKER_ARGS+=("-e ROS_DOMAIN_ID")
DOCKER_ARGS+=("-e ROS_WS=/workspaces/isaac_ros-dev")
DOCKER_ARGS+=("--runtime=nvidia")

echo "Running deploy container: $CONTAINER_NAME from image: ${DEPLOY_FULL_IMAGE}"

# Determine whether to run interactively or headlessly based on arguments
if [[ $# -eq 0 ]]; then
    # Headless / Background deploy execution
    docker run -it --rm \
        --privileged \
        --network host \
        ${DOCKER_ARGS[@]} \
        -v /dev/*:/dev/* \
        -v /etc/localtime:/etc/localtime:ro \
        --name "$CONTAINER_NAME" \
        $DEPLOY_FULL_IMAGE
else
    # Allow appending ROS 2 arguments like run_rviz:=False
    docker run -it --rm \
        --privileged \
        --network host \
        ${DOCKER_ARGS[@]} \
        -v /dev/*:/dev/* \
        -v /etc/localtime:/etc/localtime:ro \
        --name "$CONTAINER_NAME" \
        $DEPLOY_FULL_IMAGE \
        bash -c "ros2 launch $LAUNCH_PACKAGE $LAUNCH_FILE $@"
fi
