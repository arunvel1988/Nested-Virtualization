#!/bin/bash
set -e

echo "============================"
echo "   GCP VM Utility Script"
echo "============================"
echo "1. Create image from existing instance and clone"
echo "2. Create new VMs from existing image"
echo
read -p "Select option (1 or 2): " MODE

if [ "$MODE" == "1" ]; then
  echo
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
  read -p "Enter the number of the instance to create an image from: " choice
  index=$((choice-1))

  if [ $index -lt 0 ] || [ $index -ge ${#instances[@]} ]; then
    echo "Invalid selection."
    exit 1
  fi

  INSTANCE_NAME=$(echo "${instances[$index]}" | awk '{print $1}')
  ZONE=$(echo "${instances[$index]}" | awk '{print $2}')
  STATUS=$(echo "${instances[$index]}" | awk '{print $3}')

  echo
  echo "Selected instance: $INSTANCE_NAME (status: $STATUS)"

  if [ "$STATUS" == "RUNNING" ]; then
    read -p "Instance is running. Stop it before creating image? (y/n): " stop_choice
    if [ "$stop_choice" == "y" ]; then
      echo "Stopping instance..."
      gcloud compute instances stop "$INSTANCE_NAME" --zone="$ZONE" --quiet
    else
      echo "Proceeding without stopping..."
    fi
  fi

  IMAGE_NAME="${INSTANCE_NAME}-image-$(date +%Y%m%d%H%M%S)"
  echo
  echo "Creating image: $IMAGE_NAME ..."
  gcloud compute images create "$IMAGE_NAME" \
    --source-disk="$INSTANCE_NAME" \
    --source-disk-zone="$ZONE"

elif [ "$MODE" == "2" ]; then
  echo
  echo "Fetching available images..."
  mapfile -t images < <(gcloud compute images list --no-standard-images --format="value(name)")

  if [ ${#images[@]} -eq 0 ]; then
    echo "No custom images found. Listing public images..."
    mapfile -t images < <(gcloud compute images list --format="value(name,project)")
  fi

  echo "Available images:"
  for i in "${!images[@]}"; do
    echo "$((i+1)). ${images[$i]}"
  done

  echo
  read -p "Select the image number to use: " img_choice
  img_index=$((img_choice-1))

  if [ $img_index -lt 0 ] || [ $img_index -ge ${#images[@]} ]; then
    echo "Invalid selection."
    exit 1
  fi

  IMAGE_NAME=$(echo "${images[$img_index]}" | awk '{print $1}')
else
  echo "Invalid mode selection."
  exit 1
fi

echo
read -p "Enter zone to create the new instances (e.g. asia-south1-c): " NEW_ZONE

echo
echo "Fetching machine types for zone '$NEW_ZONE'..."
mapfile -t machinetypes < <(gcloud compute machine-types list --zones="$NEW_ZONE" --format="value(name)" | sort)

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
read -p "How many new instances to create from image '$IMAGE_NAME'? " COUNT

echo
for ((i=1; i<=COUNT; i++)); do
  NEW_INSTANCE="${IMAGE_NAME}-vm-$i"
  echo "Creating instance: $NEW_INSTANCE ..."
  gcloud compute instances create "$NEW_INSTANCE" \
    --zone="$NEW_ZONE" \
    --image="$IMAGE_NAME" \
    --machine-type="$MACHINE_TYPE"
done

echo
echo "✅ Done! Created $COUNT instance(s) from image '$IMAGE_NAME' using machine type '$MACHINE_TYPE' in zone '$NEW_ZONE'."
