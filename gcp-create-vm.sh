#!/bin/bash
set -e

# ===================================
#   GCP VM Utility Script
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

# Ensure RDP firewall rule exists
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

select_zone() {
  echo "Fetching available zones..."
  mapfile -t zones < <(gcloud compute zones list --format="value(name)" | sort)
  for i in "${!zones[@]}"; do
    echo "$((i+1)). ${zones[$i]}"
  done
  read -p "Select zone number: " z_choice
  SELECTED_ZONE=${zones[$((z_choice-1))]}
}

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

# --- MODE 1: Create image + clone ---
if [ "$MODE" == "1" ]; then
  mapfile -t instances < <(gcloud compute instances list --format="value(name,zone,status)")
  for i in "${!instances[@]}"; do
    name=$(echo "${instances[$i]}" | awk '{print $1}')
    zone=$(echo "${instances[$i]}" | awk '{print $2}')
    status=$(echo "${instances[$i]}" | awk '{print $3}')
    echo "$((i+1)). $name (zone: $zone, status: $status)"
  done

  read -p "Select instance number: " choice
  INSTANCE_NAME=$(echo "${instances[$((choice-1))]}" | awk '{print $1}')
  ZONE=$(echo "${instances[$((choice-1))]}" | awk '{print $2}')

  IMAGE_NAME="${INSTANCE_NAME}-image-$(date +%Y%m%d%H%M%S)"
  echo "Creating image: $IMAGE_NAME ..."
  gcloud compute images create "$IMAGE_NAME" --source-disk="$INSTANCE_NAME" --source-disk-zone="$ZONE"
  echo "Image created: $IMAGE_NAME"

  select_zone
  select_machine_type "$SELECTED_ZONE"
  ensure_rdp_rule

  read -p "How many new instances to create from image '$IMAGE_NAME'? " COUNT
  for ((i=1; i<=COUNT; i++)); do
    NEW_INSTANCE="${INSTANCE_NAME}-clone-$i"
    echo "Creating $NEW_INSTANCE ..."
    gcloud compute instances create "$NEW_INSTANCE" \
      --zone="$SELECTED_ZONE" \
      --image="$IMAGE_NAME" \
      --machine-type="$MACHINE_TYPE" \
      --tags=rdp-only
  done
  echo "✅ Created $COUNT instances with tag 'rdp-only' (port 3389 open)"
fi
