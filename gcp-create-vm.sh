#!/bin/bash
set -e

# ===================================
#   GCP VM Utility Script (Full)
# ===================================
echo "============================"
echo "   GCP VM Utility Script"
echo "============================"
echo "1. Create image from existing instance and clone"
echo "2. Create new VMs from existing image"
echo "3. Start VM(s)"
echo "4. Stop VM(s)"
echo "5. Delete VM(s)"
echo "6. Exit"
echo
read -p "Select option (1-6): " MODE
echo

# --- Ensure Firewall for RDP ---
ensure_rdp_rule() {
  RULE_NAME="allow-rdp"
  if ! gcloud compute firewall-rules list --format="value(name)" | grep -q "^${RULE_NAME}$"; then
    echo "Creating firewall rule '${RULE_NAME}' to allow TCP:3389 ..."
    gcloud compute firewall-rules create "$RULE_NAME" \
      --allow=tcp:3389 \
      --direction=INGRESS \
      --priority=1000 \
      --target-tags=rdp-only \
      --source-ranges=0.0.0.0/0
  else
    echo "Firewall rule '${RULE_NAME}' already exists."
  fi
}

# --- Select Zone ---
select_zone() {
  echo "Fetching available zones..."
  mapfile -t zones < <(gcloud compute zones list --format="value(name)" | sort)
  for i in "${!zones[@]}"; do
    echo "$((i+1)). ${zones[$i]}"
  done
  read -p "Select zone number: " z_choice
  SELECTED_ZONE=${zones[$((z_choice-1))]}
}

# --- Select Machine Type ---
select_machine_type() {
  local zone="$1"
  echo
  echo "Fetching machine types for zone '$zone'..."
  mapfile -t machinetypes < <(gcloud compute machine-types list --zones="$zone" --format="value(name)" | sort)
  for i in "${!machinetypes[@]}"; do
    echo "$((i+1)). ${machinetypes[$i]}"
  done
  read -p "Select machine type number: " m_choice
  MACHINE_TYPE=${machinetypes[$((m_choice-1))]}
}

# --- MODE 1: Create image from existing instance ---
if [ "$MODE" == "1" ]; then
  echo "Fetching all Compute Engine instances..."
  mapfile -t instances < <(gcloud compute instances list --format="value(name,zone,status)")

  if [ ${#instances[@]} -eq 0 ]; then
    echo "No instances found."
    exit 1
  fi

  echo "Available instances:"
  for i in "${!instances[@]}"; do
    name=$(echo "${instances[$i]}" | awk '{print $1}')
    zone=$(echo "${instances[$i]}" | awk '{print $2}')
    status=$(echo "${instances[$i]}" | awk '{print $3}')
    echo "$((i+1)). $name (zone: $zone, status: $status)"
  done

  read -p "Enter the number of the instance to create image from: " choice
  INSTANCE_NAME=$(echo "${instances[$((choice-1))]}" | awk '{print $1}')
  ZONE=$(echo "${instances[$((choice-1))]}" | awk '{print $2}')
  STATUS=$(echo "${instances[$((choice-1))]}" | awk '{print $3}')

  echo
  echo "Selected instance: $INSTANCE_NAME (status: $STATUS)"

  if [ "$STATUS" == "RUNNING" ]; then
    read -p "Instance is running. Stop it before creating image? (y/n): " stop_choice
    if [ "$stop_choice" == "y" ]; then
      echo "Stopping instance..."
      gcloud compute instances stop "$INSTANCE_NAME" --zone="$ZONE" --quiet
    fi
  fi

  IMAGE_NAME="${INSTANCE_NAME}-image-$(date +%Y%m%d%H%M%S)"
  echo
  echo "Creating image: $IMAGE_NAME ..."
  gcloud compute images create "$IMAGE_NAME" \
    --source-disk="$INSTANCE_NAME" \
    --source-disk-zone="$ZONE"
  echo "✅ Image created: $IMAGE_NAME"

  select_zone
  select_machine_type "$SELECTED_ZONE"
  ensure_rdp_rule

  read -p "How many new instances to create from image '$IMAGE_NAME'? " COUNT
  for ((i=1; i<=COUNT; i++)); do
    NEW_INSTANCE="${INSTANCE_NAME}-clone-$i"
    echo "Creating instance: $NEW_INSTANCE ..."
    gcloud compute instances create "$NEW_INSTANCE" \
      --zone="$SELECTED_ZONE" \
      --image="$IMAGE_NAME" \
      --machine-type="$MACHINE_TYPE" \
      --tags=rdp-only
  done

  echo
  echo "✅ Done! Created $COUNT instance(s) from image '$IMAGE_NAME'."

# --- MODE 2: Create new VM(s) from existing image ---
elif [ "$MODE" == "2" ]; then
  echo "Fetching available images..."
  mapfile -t images < <(gcloud compute images list --no-standard-images --format="value(name)")
  if [ ${#images[@]} -eq 0 ]; then
    echo "No custom images found."
    exit 1
  fi

  for i in "${!images[@]}"; do
    echo "$((i+1)). ${images[$i]}"
  done

  read -p "Select the image number: " img_choice
  IMAGE_NAME=${images[$((img_choice-1))]}

  select_zone
  select_machine_type "$SELECTED_ZONE"
  ensure_rdp_rule

  read -p "How many instances to create from image '$IMAGE_NAME'? " COUNT
  for ((i=1; i<=COUNT; i++)); do
    NEW_INSTANCE="${IMAGE_NAME}-vm-$i"
    echo "Creating instance: $NEW_INSTANCE ..."
    gcloud compute instances create "$NEW_INSTANCE" \
      --zone="$SELECTED_ZONE" \
      --image="$IMAGE_NAME" \
      --machine-type="$MACHINE_TYPE" \
      --tags=rdp-only
  done

  echo "✅ Created $COUNT instance(s) from image '$IMAGE_NAME'."

# --- MODE 3: Start VM(s) ---
elif [ "$MODE" == "3" ]; then
  echo "Fetching stopped instances..."
  mapfile -t instances < <(gcloud compute instances list --filter="status=TERMINATED" --format="value(name,zone)")
  if [ ${#instances[@]} -eq 0 ]; then
    echo "No stopped instances found."
    exit 1
  fi

  for i in "${!instances[@]}"; do
    echo "$((i+1)). ${instances[$i]}"
  done

  read -p "Select instance number(s) to start (space-separated): " -a choices
  for c in "${choices[@]}"; do
    name=$(echo "${instances[$((c-1))]}" | awk '{print $1}')
    zone=$(echo "${instances[$((c-1))]}" | awk '{print $2}')
    echo "Starting $name ..."
    gcloud compute instances start "$name" --zone="$zone"
  done

# --- MODE 4: Stop VM(s) ---
elif [ "$MODE" == "4" ]; then
  echo "Fetching running instances..."
  mapfile -t instances < <(gcloud compute instances list --filter="status=RUNNING" --format="value(name,zone)")
  if [ ${#instances[@]} -eq 0 ]; then
    echo "No running instances found."
    exit 1
  fi

  for i in "${!instances[@]}"; do
    echo "$((i+1)). ${instances[$i]}"
  done

  read -p "Select instance number(s) to stop (space-separated): " -a choices
  for c in "${choices[@]}"; do
    name=$(echo "${instances[$((c-1))]}" | awk '{print $1}')
    zone=$(echo "${instances[$((c-1))]}" | awk '{print $2}')
    echo "Stopping $name ..."
    gcloud compute instances stop "$name" --zone="$zone"
  done

# --- MODE 5: Delete VM(s) ---
elif [ "$MODE" == "5" ]; then
  echo "Fetching all instances..."
  mapfile -t instances < <(gcloud compute instances list --format="value(name,zone,status)")
  if [ ${#instances[@]} -eq 0 ]; then
    echo "No instances found."
    exit 1
  fi

  for i in "${!instances[@]}"; do
    echo "$((i+1)). ${instances[$i]}"
  done

  read -p "Select instance number(s) to delete (space-separated): " -a choices
  for c in "${choices[@]}"; do
    name=$(echo "${instances[$((c-1))]}" | awk '{print $1}')
    zone=$(echo "${instances[$((c-1))]}" | awk '{print $2}')
    echo "Deleting $name ..."
    gcloud compute instances delete "$name" --zone="$zone" --quiet
  done

# --- MODE 6: Exit ---
elif [ "$MODE" == "6" ]; then
  echo "Exiting..."
  exit 0
else
  echo "Invalid option."
  exit 1
fi
