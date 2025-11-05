#!/bin/bash
set -e

# =============================
#     GCP VM Utility Script
# =============================

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

# -----------------------------
# Helper: Zone selection
# -----------------------------
select_zone() {
  echo "Fetching available zones..."
  mapfile -t zones < <(gcloud compute zones list --format="value(name)" | sort)
  if [ ${#zones[@]} -eq 0 ]; then
    echo "No zones found. Check your permissions."
    exit 1
  fi

  echo "Available zones:"
  for i in "${!zones[@]}"; do
    echo "$((i+1)). ${zones[$i]}"
  done

  echo
  read -p "Select zone number: " z_choice
  z_index=$((z_choice-1))
  if [ $z_index -lt 0 ] || [ $z_index -ge ${#zones[@]} ]; then
    echo "Invalid selection."
    exit 1
  fi
  SELECTED_ZONE=${zones[$z_index]}
  echo "Selected zone: $SELECTED_ZONE"
}

# -----------------------------
# Helper: Machine type selection
# -----------------------------
select_machine_type() {
  local zone="$1"
  echo
  echo "Fetching machine types for zone '$zone'..."
  mapfile -t machinetypes < <(gcloud compute machine-types list --zones="$zone" --format="value(name)" | sort)
  if [ ${#machinetypes[@]} -eq 0 ]; then
    echo "No machine types found. Check zone or permissions."
    exit 1
  fi
  echo "Available machine types:"
  for i in "${!machinetypes[@]}"; do
    echo "$((i+1)). ${machinetypes[$i]}"
  done
  echo
  read -p "Select machine type number: " m_choice
  m_index=$((m_choice-1))
  if [ $m_index -lt 0 ] || [ $m_index -ge ${#machinetypes[@]} ]; then
    echo "Invalid selection."
    exit 1
  fi
  MACHINE_TYPE=${machinetypes[$m_index]}
  echo "Selected machine type: $MACHINE_TYPE"
}

# -----------------------------
# Option 1: Create image from existing instance
# -----------------------------
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

  echo
  read -p "Select instance number to create image from: " choice
  index=$((choice-1))
  INSTANCE_NAME=$(echo "${instances[$index]}" | awk '{print $1}')
  ZONE=$(echo "${instances[$index]}" | awk '{print $2}')
  STATUS=$(echo "${instances[$index]}" | awk '{print $3}')

  echo "Selected instance: $INSTANCE_NAME ($STATUS)"
  if [ "$STATUS" == "RUNNING" ]; then
    read -p "Stop instance before creating image? (y/n): " stop_choice
    if [ "$stop_choice" == "y" ]; then
      gcloud compute instances stop "$INSTANCE_NAME" --zone="$ZONE" --quiet
    fi
  fi

  IMAGE_NAME="${INSTANCE_NAME}-image-$(date +%Y%m%d%H%M%S)"
  echo "Creating image: $IMAGE_NAME ..."
  gcloud compute images create "$IMAGE_NAME" --source-disk="$INSTANCE_NAME" --source-disk-zone="$ZONE"
  echo "Image created: $IMAGE_NAME"

  select_zone
  select_machine_type "$SELECTED_ZONE"

  read -p "How many new instances to create from image '$IMAGE_NAME'? " COUNT
  for ((i=1; i<=COUNT; i++)); do
    NEW_INSTANCE="${INSTANCE_NAME}-clone-$i"
    echo "Creating $NEW_INSTANCE ..."
    gcloud compute instances create "$NEW_INSTANCE" \
      --zone="$SELECTED_ZONE" \
      --image="$IMAGE_NAME" \
      --machine-type="$MACHINE_TYPE"
  done
  echo "✅ Created $COUNT new instances in zone $SELECTED_ZONE"

# -----------------------------
# Option 2: Create new VMs from existing image
# -----------------------------
elif [ "$MODE" == "2" ]; then
  echo "Fetching available custom images..."
  mapfile -t images < <(gcloud compute images list --no-standard-images --format="value(name)")
  if [ ${#images[@]} -eq 0 ]; then
    echo "No custom images found."
    exit 1
  fi

  echo "Available images:"
  for i in "${!images[@]}"; do
    echo "$((i+1)). ${images[$i]}"
  done

  read -p "Select image number: " img_choice
  img_index=$((img_choice-1))
  IMAGE_NAME=${images[$img_index]}

  select_zone
  select_machine_type "$SELECTED_ZONE"
  read -p "How many instances to create from '$IMAGE_NAME'? " COUNT

  for ((i=1; i<=COUNT; i++)); do
    NEW_INSTANCE="${IMAGE_NAME}-vm-$i"
    echo "Creating $NEW_INSTANCE ..."
    gcloud compute instances create "$NEW_INSTANCE" \
      --zone="$SELECTED_ZONE" \
      --image="$IMAGE_NAME" \
      --machine-type="$MACHINE_TYPE"
  done
  echo "✅ Created $COUNT instances from image $IMAGE_NAME"

# -----------------------------
# Option 3: Start VMs
# -----------------------------
elif [ "$MODE" == "3" ]; then
  echo "Fetching instances..."
  mapfile -t instances < <(gcloud compute instances list --format="value(name,zone,status)")
  for i in "${!instances[@]}"; do
    name=$(echo "${instances[$i]}" | awk '{print $1}')
    zone=$(echo "${instances[$i]}" | awk '{print $2}')
    status=$(echo "${instances[$i]}" | awk '{print $3}')
    echo "$((i+1)). $name ($status, zone: $zone)"
  done
  read -p "Enter numbers of instances to start (e.g. 1 3 5): " selections
  for num in $selections; do
    idx=$((num-1))
    name=$(echo "${instances[$idx]}" | awk '{print $1}')
    zone=$(echo "${instances[$idx]}" | awk '{print $2}')
    echo "Starting $name ..."
    gcloud compute instances start "$name" --zone="$zone"
  done

# -----------------------------
# Option 4: Stop VMs
# -----------------------------
elif [ "$MODE" == "4" ]; then
  echo "Fetching instances..."
  mapfile -t instances < <(gcloud compute instances list --format="value(name,zone,status)")
  for i in "${!instances[@]}"; do
    name=$(echo "${instances[$i]}" | awk '{print $1}')
    zone=$(echo "${instances[$i]}" | awk '{print $2}')
    status=$(echo "${instances[$i]}" | awk '{print $3}')
    echo "$((i+1)). $name ($status, zone: $zone)"
  done
  read -p "Enter numbers of instances to stop (e.g. 2 4): " selections
  for num in $selections; do
    idx=$((num-1))
    name=$(echo "${instances[$idx]}" | awk '{print $1}')
    zone=$(echo "${instances[$idx]}" | awk '{print $2}')
    echo "Stopping $name ..."
    gcloud compute instances stop "$name" --zone="$zone"
  done

# -----------------------------
# Option 5: Delete VMs
# -----------------------------
elif [ "$MODE" == "5" ]; then
  echo "Fetching instances..."
  mapfile -t instances < <(gcloud compute instances list --format="value(name,zone,status)")
  for i in "${!instances[@]}"; do
    name=$(echo "${instances[$i]}" | awk '{print $1}')
    zone=$(echo "${instances[$i]}" | awk '{print $2}')
    status=$(echo "${instances[$i]}" | awk '{print $3}')
    echo "$((i+1)). $name ($status, zone: $zone)"
  done
  read -p "Enter numbers of instances to delete (e.g. 1 2 3): " selections
  for num in $selections; do
    idx=$((num-1))
    name=$(echo "${instances[$idx]}" | awk '{print $1}')
    zone=$(echo "${instances[$idx]}" | awk '{print $2}')
    echo "Deleting $name ..."
    gcloud compute instances delete "$name" --zone="$zone" --quiet
  done

# -----------------------------
# Option 6: Exit
# -----------------------------
elif [ "$MODE" == "6" ]; then
  echo "Goodbye!"
  exit 0

else
  echo "Invalid selection."
  exit 1
fi
