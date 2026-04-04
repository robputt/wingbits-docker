#!/bin/bash

# Official install script for wingbits - created/managed by wingbits team
WINGBITS_CONFIG_VERSION="0.2.1"

# Example usage:
# Pulling install from Gitlab:
# curl -sL https://gitlab.com/wingbits/config/-/raw/master/download.sh | sudo heatmap=true initial=true loc="-31.966645, 115.862013" bash
# Running locally:
# sudo heatmap=true initial=true loc="-31.966645, 115.862013" ./download.sh

# Parameters:
# heatmap=true                  - Enable the heatmap config
# initial=true                  - Perform install as if no existing Wingbits install is present (/etc/wingbits directory does not exist)
# loc="-31.966645, 115.862013"  - Location latitude/longitude


# Note: Can be run without parameters and will prompt for input.
# Example: curl -sL https://gitlab.com/wingbits/config/-/raw/master/download.sh | sudo bash


# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root to set up the service correctly"
    echo "Run it like this:"
    echo "sudo ./download.sh"
    exit 1
fi

current_datetime=$(date +'%Y-%m-%d_%H-%M')
# Setup logfile location/name
LOG_FILE="/var/log/wingbits/install_${current_datetime}.log"


# Function to get input for install actions and other prep
function install_prep() {

	# Read in values passed in from cmd line
	station_loc=$loc
	
	
	# Check if this is an initial WB install by checking if the /etc/wingbits dir exists or $initial value set to true from cmd line
	if [[ ! -d "/etc/wingbits" ]] || [[ "$initial" = true ]]; then
		initial_install=true
	else
		initial_install=true
	fi
	
	logdir=$(dirname "$LOG_FILE")
	mkdir -p "$logdir"
	
	# Write start date/time to log					 	
	echo "$(date): Wingbits install start time" >> "$LOG_FILE"
	
	# Write the OS details to log file
	cat /etc/os-release >> "$LOG_FILE"

	# Create config directory doesn't exist
	mkdir -p /etc/wingbits

	# Set auto-update to true
	auto_update=true
		
	echo ""
	echo "Note: For inputs that show a correct current value, you can just hit 'Enter' to submit that current value."
	echo ""
}


# Function to check if GeoSigner present and ask to continue if not
function geosigner_check() {
	return 0
}


# Function to validate lat/long coordinates
function check_coordinates() {   
    latitude="none"
    longitude="none"
    local lat_regex='^[-+]?([0-9]|[1-8][0-9])(\.[0-9]+)?$'
    local lon_regex='^[-+]?([0-9]|[1-9][0-9]|1[0-7][0-9]|180)(\.[0-9]+)?$'
    
   	latitude=$(echo "$1" | cut -d ',' -f1)
	longitude=$(echo "$1" | cut -d ',' -f2 | tr -d ' ')

	# Validate latitude from -90 to +90
	if [[ $latitude =~ $lat_regex && $(awk -v lat="$latitude" 'BEGIN {if (lat >= -90 && lat <= 90) print 1; else print 0}') -eq 1 ]]; then
		echo -e "\033[0;32m✓\033[0m Valid coordinate for latitude: $latitude"		
	else
		echo -e "\033[0;31m✗\033[0m Invalid coordinate for latitude: $latitude"
		return 1
	fi

	# Validate longitude from -180 to +180
	if [[ $longitude =~ $lon_regex && $(awk -v lon="$longitude" 'BEGIN {if (lon >= -180 && lon <= 180) print 1; else print 0}') -eq 1 ]]; then
		echo -e "\033[0;32m✓\033[0m Valid coordinate for longitude: $longitude"
	else
		echo -e "\033[0;31m✗\033[0m Invalid coordinate for longitude: $longitude"
		return 1
	fi
}


# Function to get location for readsb config
function read_location() {
	
	if [[ -n $station_loc ]]; then
		if check_coordinates "$station_loc"; then
			echo "$station_loc is valid" | tee -a "$LOG_FILE"
			station_location=$station_loc
		else	
			echo "Invalid format ($station_location)"
		fi
	
	else
		# Get current lat/long from readsb config
		readsb_file="/etc/default/readsb"
		readsb_station_location="none"
		
		if [[ -e $readsb_file ]]; then
			readsb_lat=$(grep -Po -- '--lat \K-?\d+\.\d+' "$readsb_file")
			readsb_lon=$(grep -Po -- '--lon \K-?\d+\.\d+' "$readsb_file")
			readsb_station_location="$readsb_lat, $readsb_lon"
			echo "readsb_location: $readsb_station_location" >> "$LOG_FILE" 2>&1
			
			if [ "$readsb_station_location" = "none" ]; then
				echo "Lat/Long not found in readsb config file" >> "$LOG_FILE" 2>&1
			fi
		else
			echo -e "No readsb file found." >> "$LOG_FILE" 2>&1
		fi

		while true; do
			read -p "Enter/copy the 'lat, lon' location from stations page, with comma (current: $readsb_station_location): " station_location </dev/tty
		
			# Use the current value if the user presses enter without typing anything
			station_location=${station_location:-$readsb_station_location}
		
			# Validate the location
			if check_coordinates "$station_location"; then
#				echo "$station_location is valid format"
				break
			else
				echo "Invalid format ($station_location)"
			fi
		done
	fi
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


# Function to delete old files that are no longer required
function del_old_files() {

	# Files to delete if present
	files=(
	  "/etc/wingbits/check_status.sh"
	  "/etc/cron.d/wingbits"
	)

	# Loop through each file and if exists, delete it
	for file in "${files[@]}"; do
	  if [ -e "$file" ]; then
		sudo rm "$file"
		if [ $? -eq 0 ]; then
		  echo "$file deleted successfully." >> "$LOG_FILE" 2>&1
		else
		  echo "Failed to delete $file." >> "$LOG_FILE" 2>&1
		fi
	  fi
	done
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
  echo "===================${text}====================" >> "$LOG_FILE"

  for command in "${commands[@]:1}"; do
    (
      eval "${command}" >> "$LOG_FILE" 2>&1
      printf "done" > /tmp/wingbits.done
    ) &
    local pid=$!

    printf "${text}"

    # Wait for the command to finish
    wait "${pid}"

    # Check if the command completed successfully
    if [[ -f /tmp/wingbits.done ]]; then
      rm /tmp/wingbits.done
      printf "\r\033[0;32m✓\033[0m   %s\n" "${text}"
    else
      printf "\r\033[0;31m✗\033[0m   %s\n" "${text}"
    fi
  done
}


# Function to check if ADSB adapter is plugged in
check_adsb_adapter() {
    local rtl_device=$(lsusb | grep -i "RTL28")
    if [[ -n "$rtl_device" ]]; then
        echo -e "\033[0;32m✓\033[0m ADSB adapter found: $rtl_device" | tee -a "$LOG_FILE"
		return 0
    else
        echo -e "\033[0;31m✗\033[0m No (RTL28xx) ADSB adapter found." | tee -a "$LOG_FILE"
		return 1
    fi
}


function check_service_status(){
	local services=("$@")
	# Only delay and try again if not initial install and ADSB SDR found
	if [[ $initial_install != true ]] && check_adsb_adapter ; then
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
	fi
}


# Function to add/update cron
function update_crontab() {

	# Variables
	local UPDATE_SCRIPT_URL="https://gitlab.com/wingbits/config/-/raw/master/update.sh"
	local CRON_IDENTIFIER="wingbits_config_update"  # Unique identifier for the cron job
	local LOG_FILE="/var/log/wingbits/wb_update.log"

	# Remove the old cron job with the unique identifier, if it exists
	if crontab -l | grep -q "$CRON_IDENTIFIER"; then
		(crontab -l | grep -v "$CRON_IDENTIFIER") | crontab -
	fi
	
	# Add the new cron job  							
	if [[ $auto_update = true ]]; then
		local UPDATE_JOB="0 18 * * * /usr/bin/curl -s $UPDATE_SCRIPT_URL | /bin/bash >> $LOG_FILE 2>&1 # $CRON_IDENTIFIER"
		(crontab -l ; echo "$UPDATE_JOB") | crontab -
	fi
}


# Function to change the collectd restart time to every hour from once per day so graphs are written to disk hourly
function collectd_restart() {

	# Define cron file path
	FILE="/etc/cron.d/collectd_to_disk"

	# Define the new cron job line
	NEW_CRON_JOB="42 */1 * * * root /bin/systemctl restart collectd"

	if grep -Fxq "$NEW_CRON_JOB" "$FILE"; then
		echo "collectd restart already at 1hr" >> "$LOG_FILE" 2>&1
	else
		# Comment out the old cron job and add the new one
		sed -i 's/^42 23 \* \* \* root \/bin\/systemctl restart collectd/# 42 23 * * * root \/bin\/systemctl restart collectd/' "$FILE"
		echo "" >> "$FILE"
		echo "# every 1 hour" >> "$FILE"
		echo "$NEW_CRON_JOB" >> "$FILE"

		# Verify the changes
		echo "Modified collectd restart cron file:" >> "$LOG_FILE" 2>&1
		cat "$FILE" >> "$LOG_FILE" 2>&1
	fi
}


# Function to change options in the graphs1090 config file
function graphs1090_config() {

}


# Function to change options in the tar1090 config file
function tar1090_config() {

}


# Function to change options in the tar1090 script file
function tar1090_script() {
}


# Function to add options to readsb config to enable heatmap
function readsb_heatmap() {
}


# Function to make various config changes
function config_changes() {
	
	# if this is a new install or new install option supplied
	if [[ $initial_install = true ]]; then
		collectd_restart
		graphs1090_config
		tar1090_config
		tar1090_script
	fi
	
	# Check if the heatmap=true value was passed on the cmd line
	if [[ $heatmap = true ]]; then
		readsb_heatmap
	fi
}


function sync_time() {
	return 0
}


# Add readsb config changes for Wingbits client if not already present
function wb_readsb_config() {
	# Check if standard config for Wingbits client is already in readsb file
	if grep -qE '^[[:space:]]*[^#].*"[^"]*--net-connector localhost,30006,json_out[^"]*"' /etc/default/readsb ; then
	
		echo -e "\033[0;32m✓\033[0m   readsb already configured for Wingbits client" | tee -a "$LOG_FILE"
		
	else
		# Add connector to readsb	
		sed -i.bak 's/NET_OPTIONS="[^"]*/& '"--net-connector localhost,30006,json_out"'/' /etc/default/readsb >> "$LOG_FILE" 2>&1
				
		echo -e "\033[0;32m✓\033[0m   Added Wingbits config to readsb config file" | tee -a "$LOG_FILE"
	fi
}


# Add readsb config changes for beast mode for Wingbits if not already present
function beast_readsb_config() {
	# Check if config for beast mode is already in readsb file
	if grep -qE '^[[:space:]]*[^#].*"[^"]*--net-connector localhost,30015,beast_reduce_out --net-beast-reduce-optimize-for-mlat --net-beast-reduce-interval=0\.125[^"]*"' /etc/default/readsb; then

		echo -e "\033[0;32m✓\033[0m   readsb already configured for beast mode for Wingbits" | tee -a "$LOG_FILE"

	else
		# Add beast config for Wingbits client to readsb on a line that is not commented out
		sed -i.bak '/^[[:space:]]*#/! s/^[[:space:]]*NET_OPTIONS="[^"]*/& '"--net-connector localhost,30015,beast_reduce_out --net-beast-reduce-optimize-for-mlat --net-beast-reduce-interval=0.125"'/' /etc/default/readsb >> "$LOG_FILE" 2>&1

		echo -e "\033[0;32m✓\033[0m   Added beast mode config to readsb config file" | tee -a "$LOG_FILE"
	fi
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
			echo "Unsupported OS" | tee -a "$LOG_FILE"
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
			echo "Unsupported architecture" | tee -a "$LOG_FILE"
			exit 1
			;;
	esac

	WINGBITS_PATH="/usr/local/bin"
	BINARY_NAME="wingbits"
	echo "Architecture: $GOOS-$GOARCH" >> "$LOG_FILE" 2>&1
	mkdir -p "$WINGBITS_PATH"

	if ! curl -s -o latest.json "https://install.wingbits.com/$GOOS-$GOARCH.json"; then
		echo "Failed to download Wingbits Client version information" | tee -a "$LOG_FILE"
		exit 1
	fi

	version=$(grep -o '"Version": "[^"]*"' latest.json | cut -d'"' -f4)
	if [ -z "$version" ]; then
		echo "Failed to extract Wingbits Client version information" | tee -a "$LOG_FILE"
		rm latest.json
		exit 1
	fi

	if ! curl -s -o "$WINGBITS_PATH/$BINARY_NAME.gz" "https://install.wingbits.com/$version/$GOOS-$GOARCH.gz"; then
		echo "Failed to download wingbits binary" | tee -a "$LOG_FILE"
		rm latest.json
		exit 1
	fi

	rm -f "$WINGBITS_PATH/$BINARY_NAME"
	if ! gunzip "$WINGBITS_PATH/$BINARY_NAME.gz"; then
		echo "Failed to extract wingbits binary" | tee -a "$LOG_FILE"
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
RestartSec=180
StartLimitInterval=10
StartLimitBurst=5

WorkingDirectory=/etc/wingbits
ExecStart=/usr/local/bin/wingbits feeder start

[Install]
WantedBy=default.target
EOF
	rm latest.json
	printf "\r\033[0;32m✓\033[0m   %s\n" "Wingbits Client installed" | tee -a "$LOG_FILE"
}


# Function to save GeoSigner ID to device file
function set_device_id() {
	local timeout=30
    local check_interval=2

	# If wingbits client & GeoSigner is installed, get Geosigner ID
	if command -v wingbits >/dev/null 2>&1; then
	output=$(wingbits geosigner info 2>&1)

		# Check for error message
		if echo "$output" | grep -q "Error: no GeoSigner device found"; then
		
			echo "Error: no GeoSigner device found. Retrying for ${timeout}s" | tee -a "$LOG_FILE"
			local elapsed=0
			# Wait loop
            while echo "$output" | grep -q "Error: no GeoSigner device found" && [ "$elapsed" -lt "$timeout" ]; do
                sleep "$check_interval"
                elapsed=$((elapsed + check_interval))
                output=$(wingbits geosigner info 2>&1)   # refresh output
            done
			
			if echo "$output" | grep -q "Error: no GeoSigner device found"; then
				geosigner_id="none"
				echo "GeoSigner not found" | tee -a "$LOG_FILE"
			else
				geosigner_id=$(echo "$output" | grep "GeoSigner ID" | awk -F'GeoSigner ID: ' '{print $2}' | awk '{print $1}' | tr -d ',')
				echo "GeoSigner ID = $geosigner_id" | tee -a "$LOG_FILE"
			fi
		else
			geosigner_id=$(echo "$output" | grep "GeoSigner ID" | awk -F'GeoSigner ID: ' '{print $2}' | awk '{print $1}' | tr -d ',')
			echo "GeoSigner ID = $geosigner_id" | tee -a "$LOG_FILE"
		fi
	else 
		echo "Wingbits client not installed and required to check GeoSigner ID" | tee -a "$LOG_FILE"
	fi
		
	file_device_id=$geosigner_id
	echo "$file_device_id" > /etc/wingbits/device
	echo "Using Geosigner ID: $file_device_id" >> "$LOG_FILE" 2>&1
}	
	

# extract the version from a given file
extract_wbconfig_version() {
    grep -oP 'VERSION=\K[\d.]+' "$1"
}


# Add wb-config if not already installed
update_wbconfig() {
    local tempfile=$(mktemp)
    local remote_url="https://gitlab.com/wingbits/config/-/raw/master/wb-config/wb-config"
    local local_file="/usr/local/bin/wb-config"

    # If the wb-config config file is missing, install it
    if [[ ! -e "$local_file" ]]; then
	echo "Local wb-config not installed.  Installing..." | tee -a "$LOG_FILE"
        curl -sL https://gitlab.com/wingbits/config/-/raw/master/wb-config/install.sh | bash

        # no need to update as the above would install the latest version, so exit function
        return 0
    fi
    
    # Download the file to a temporary location
    curl --fail -s -o "$tempfile" "$remote_url"

    # Check if the download was successful
    if [[ $? -ne 0 ]]; then
        echo "Failed to download the latest wb-config for version comparison." | tee -a "$LOG_FILE"
        rm "$tempfile"
    else
        # extract versions from the downloaded and local files
        downloaded_version=$(extract_wbconfig_version "$tempfile")
        local_version=$(extract_wbconfig_version "$local_file")

	# set default value for local_version if value missing in file
        if [ -z "$local_version" ]; then
	    echo "wb-config missing version, must be old format, defaulting to v0.0.0" >> "$LOG_FILE" 2>&1
            local_version="0.0.0"
        fi

        # compare versions and replace file if they don't match
        if [ "$downloaded_version" != "$local_version" ]; then
            echo "Replacing wb-config (v${local_version}) with the latest available (v${downloaded_version})." | tee -a "$LOG_FILE"
            curl -sL https://gitlab.com/wingbits/config/-/raw/master/wb-config/install.sh | bash
        else
            echo "Local wb-config is up-to-date. No action taken." | tee -a "$LOG_FILE"
            rm "$tempfile"
        fi
    fi
}


# ************** Pre-install prep **********************

# Various install prep including asking questions, delete files etc
install_prep

# Check that a Geosigner is installed and ask to continue if not
geosigner_check

# Read in readsb location from command line or input
read_location

# Delete old unused files from previous installs
del_old_files

# Stop and disable Vector if present (check if executable in path first)
if [ -x "$(command -v vector)" ]; then
    run_command "Stopping and disabling vector if present" \
		"systemctl disable vector --now" \
		"apt-get purge -y vector" 
fi


# ************** Software Install ***********************

# Step 1: Update package repositories
run_command "Updating package repositories" "apt-get update"

# Step 2: Install dependencies if not present
run_command "Installing curl if not installed" "apt-get -y install curl"
run_command "Installing wget if not installed" "apt-get -y install wget"
run_command "Installing librtlsdr-dev if not installed" "apt-get -y install librtlsdr-dev"
run_command "Installing python if not installed" "apt-get -y install python3"
run_command "Installing pip if not installed" "apt-get -y install python3-pip"
run_command "Installing venv if not installed" "apt-get -y install python3-venv"


# Step 3: Download and install readsb and graphs1090
run_command "Installing readsb (could take up to 15 minutes)" \
	"curl -sL https://github.com/wiedehopf/adsb-scripts/raw/master/readsb-install.sh | bash"
	
run_command "Installing graphs1090" \
	"curl -sL https://github.com/wiedehopf/graphs1090/raw/master/install.sh | bash"
	
# Change readsb service restart to 60sec
sed -i 's/RestartSec=15/RestartSec=60/' /lib/systemd/system/readsb.service >> "$LOG_FILE" 2>&1

# Add readsb config changes for Wingbits client if not already present
wb_readsb_config
beast_readsb_config

# Set readsb location
readsb-set-location $station_location >> "$LOG_FILE" 2>&1


# Step 4: Install Wingbits Client
setup_wb_client


# Step 5: Various config changes
config_changes


# Step 6: Reload systemd daemon, enable and start services
run_command "Starting services" \
  "systemctl daemon-reload" \
  "systemctl enable wingbits" \
  "systemctl restart readsb wingbits"


# Step 7: Check if services are online
check_service_status "wingbits" "readsb"


# Step 8: Create a cron job to check for updates every day at 6pm
update_crontab


# Step 9: Check and sync time if necessary
sync_time
	
# Step 10: Write GeoSigner ID to device file
set_device_id

# Step 11: Add/update wb-config if not already installed
update_wbconfig


# Save the new version number now install complete
echo "$WINGBITS_CONFIG_VERSION" > /etc/wingbits/version | tee -a "$LOG_FILE"
echo

# Output completion info
grep "setting L" "$LOG_FILE"

echo -e "\n\033[0;32mInstallation complete!\033[0m" | tee -a "$LOG_FILE"
echo

echo -e "\nCheck out the station status at https://wingbits.com/dashboard/stations/$device_id?active=map"
echo

grep "All done!" "$LOG_FILE" | sed 's/.*All done!//' | tee -a "$LOG_FILE"
echo

echo -e "\nInstallation log file is available at $LOG_FILE" | tee -a "$LOG_FILE"

echo -e "\nIf there is anything unexpected or for further information, including optimization tips, please read through docs.wingbits.com."

if [ "$geosigner_id" = "none" ]; then
	echo -e "\nGeoSigner was not found during install. If this is a new station, you will need to link the GeoSigner to the station in the Wingbits dashboard on the My Stations page."
	echo -e "\n https://wingbits.com/dashboard/stations"
else
	echo -e "\nIf this is a new station, you will need to link the GeoSigner to the station in the Wingbits dashboard on the My Stations page."	
	echo -e "\n https://wingbits.com/dashboard/stations"
	echo -e "\nYour GeoSinger ID is: $geosigner_id  You will also need the Secret that can be found inside the Geosigner box lid."
fi

echo -e "\n*** Please restart with \"sudo reboot\" to complete the install. ***"
echo

echo "$(date): Wingbits install end time" >> "$LOG_FILE"
