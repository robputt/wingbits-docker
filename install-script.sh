#!/bin/bash

WINGBITS_CONFIG_VERSION="0.1.1"

# Install script to replace Vector with Wingbits Client
# Vector service will be disabled, not removed at this stage
# 2025-01-23 - Added python install for GS and changed service file creation
# 2025-02-05 - Uninstall vector if present & don't prompt for station id

# Example usage: curl -sL https://gitlab.com/wingbits/config/-/raw/master/install-client.sh | sudo bash

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root to set up the service correctly"
    echo "Run it like this:"
    echo "sudo ./install-client.sh"
    exit 1
fi

current_datetime=$(date +'%Y-%m-%d_%H-%M')
# Setup logfile location/name
LOG_FILE="/var/log/wingbits/install_${current_datetime}.log"


# Function to get input for install actions and other prep
function install_prep() {

	# Read in values passed in from cmd line
	station_id=$id
	
	# Check if this is an initial WB install by checking if the /etc/wingbits dir exists or $initial value set to true from cmd line
	if [ ! -d "/etc/wingbits" ] || [ "$initial" = true ]; then
		initial_install=true
	else
		initial_install=false
	fi
	
	logdir=$(dirname $LOG_FILE)
	mkdir -p "$logdir"
	
	# Write start date/time to log					 	
	echo "$(date): Wingbits install start time" >> $LOG_FILE
	
	# Write the OS details to log file
	cat /etc/os-release >> $LOG_FILE
}



# Function to validate the Device ID input format
function validate_deviceid() {

    # handle animal names or device serials
    if [[ "$1" =~ ^[a-z]+-[a-z]+-[a-z]+$ || "$1" =~ ^[0-9A-F]{18}$ || "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        return 0
    else
        echo "Invalid format. You can find this in your Copy Debug Info for the station."
        return 1
    fi
}


# Function to read in the Device_ID
function set_device_id() {
	
	if [[ -n $station_id ]]; then
		# check supplied device id from cmd line is valid
		if validate_deviceid "$station_id"; then
			echo "$station_id is valid" | tee -a $LOG_FILE
			device_id=$station_id
		else	
			echo "Invalid format ($station_id)"
		fi
	else
	
		file_device_id="none"
		# Read in Device ID if already exists
		if [[ -e /etc/wingbits/device ]]; then
			read -r device_id < /etc/wingbits/device
		fi
	fi
	echo "Using device ID: $device_id" | tee -a $LOG_FILE
}



# Function to display loading animation with an airplane icon
function show_loading() {
  local text=$1
  local delay=0.2
  local frames=("⣾" "⣽" "⣻" "⢿" "⡿" "⣟" "⣯" "⣷")
  local frame_count=${#frames[@]}
  local i=0

  while true; do
    local frame_index=$((i % frame_count))
    printf "\r%s  %s" "${frames[frame_index]}" "${text}"
    sleep $delay
    i=$((i + 1))
  done
}


# Function to run multiple commands and log the output
function run_command() {
  local commands=("$@")
  local text=${commands[0]}
  local command
  echo "===================${text}====================" >> $LOG_FILE

  for command in "${commands[@]:1}"; do
    (
      eval "${command}" >> $LOG_FILE 2>&1
      printf "done" > /tmp/wingbits.done
    ) &
    local pid=$!

    show_loading "${text}" &
    local spinner_pid=$!

    # Wait for the command to finish
    wait "${pid}"

    # Kill the spinner
    kill "${spinner_pid}"
    wait "${spinner_pid}" 2>/dev/null

    # Check if the command completed successfully
    if [[ -f /tmp/wingbits.done ]]; then
      rm /tmp/wingbits.done
      printf "\r\033[0;32m✓\033[0m   %s\n" "${text}"
    else
      printf "\r\033[0;31m✗\033[0m   %s\n" "${text}"
    fi
  done
}


function check_service_status(){
	local services=("$@")
	for service in "${services[@]}"; do
	status="$(systemctl is-active "$service".service)"
	if [ "$status" != "active" ]; then
		echo "$service is inactive. Waiting 30 seconds..."
		sleep 30 # on initial decoder install (readsb) a reboot is required, but should start fine on updates/reinstalls
		status="$(systemctl is-active "$service".service)"
		if [ "$status" != "active" ]; then
			echo "$service is still inactive."
		else
			echo "$service is now active. ✈"
		fi
	else
		echo "$service is active. ✈"
	fi
	done
}


# Function to install WB-Client
function setup_wb_client() {
	case "$(uname -s)" in
		Linux)
			GOOS="linux"
			;;
		Darwin)
			GOOS="darwin"
			;;
		*)
			echo "Unsupported OS" | tee -a $LOG_FILE
			exit 1
			;;
	esac

	case "$(uname -m)" in
		x86_64)
			GOARCH="amd64"
			;;
		i386|i686)
			GOARCH="386"
			;;
		armv7l)
			GOARCH="arm"
			;;
		aarch64|arm64)
			GOARCH="arm64"
			;;
		*)
			echo "Unsupported architecture" | tee -a $LOG_FILE
			exit 1
			;;
	esac

	WINGBITS_PATH="/usr/local/bin"
	BINARY_NAME="wingbits"
	echo "Architecture: $GOOS-$GOARCH" >> $LOG_FILE 2>&1
	mkdir -p "$WINGBITS_PATH"

	if ! curl -s -o latest.json "https://install.wingbits.com/$GOOS-$GOARCH.json"; then
		echo "Failed to download version information" | tee -a $LOG_FILE
		exit 1
	fi

	version=$(grep -o '"Version": "[^"]*"' latest.json | cut -d'"' -f4)
	if [ -z "$version" ]; then
		echo "Failed to extract version information" | tee -a $LOG_FILE
		rm latest.json
		exit 1
	fi

	if ! curl -s -o "$WINGBITS_PATH/$BINARY_NAME.gz" "https://install.wingbits.com/$version/$GOOS-$GOARCH.gz"; then
		echo "Failed to download wingbits binary" | tee -a $LOG_FILE
		rm latest.json
		exit 1
	fi

	rm -f "$WINGBITS_PATH/$BINARY_NAME"
	if ! gunzip "$WINGBITS_PATH/$BINARY_NAME.gz"; then
		echo "Failed to extract wingbits binary" | tee -a $LOG_FILE
		rm latest.json
		exit 1
	fi

	chmod +x "$WINGBITS_PATH/$BINARY_NAME"

	# Create wingbits.service file
	rm -f /lib/systemd/system/wingbits.service
	cat >/lib/systemd/system/wingbits.service <<"EOF"
[Unit]
Description=wingbits
ConditionPathExists=/etc/wingbits
After=network.target

[Service]
Type=simple
LimitNOFILE=1024

Restart=always
RestartSec=30
StartLimitInterval=10
StartLimitBurst=5

WorkingDirectory=/etc/wingbits
ExecStart=/usr/local/bin/wingbits feeder start

[Install]
WantedBy=default.target
EOF
	
	rm latest.json
	printf "\r\033[0;32m✓\033[0m   %s\n" "Wingbits Client installed" | tee -a $LOG_FILE
}


# ************** Pre-install prep **********************

# Various install prep including asking questions, delete files etc
install_prep

# Read in Device_ID from command line or input
set_device_id

# Stop and disable Vector if present (check if executable in path first)
if [ -x "$(command -v vector)" ]; then
    run_command "Stopping and removing vector if present" \
		"systemctl disable vector --now" \
		"apt-get purge -y vector"
fi


# ************** Software Install ***********************

# Update package repositories
run_command "Updating package repositories" "apt-get update"

# Install dependencies if not present
run_command "Installing python if not installed" "apt-get -y install python3"
run_command "Installing pip if not installed" "apt-get -y install python3-pip"
run_command "Installing venv if not installed" "apt-get -y install python3-venv"

# Install Wingbits Client
setup_wb_client

# Save the new version number now install complete
echo $WINGBITS_CONFIG_VERSION > /etc/wingbits/version | tee -a $LOG_FILE
echo -e "\nCheck out the station status at https://wingbits.com/dashboard/stations/$device_id?active=map"
echo						
echo -e "\n\033[0;32mInstallation complete!\033[0m" | tee -a $LOG_FILE
