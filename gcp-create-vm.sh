#!/bin/bash
set -e

echo "Fetching all Compute Engine instances across all zones..."
echo

# Fetch instance names and zones
mapfile -t instances < <(gcloud compute instances list --format="value(name,zone)")

if [ ${#instances[@]} -eq 0 ]; then
  echo "No instances found."
  exit 1
fi

# Display instances with numbering
echo "Available instances:"
for i in "${!instances[@]}"; do
  name=$(echo "${instances[$i]}" | awk '{print $1}')
  zone=$(echo "${instances[$i]}" | awk '{print $2}')
  echo "$((i+1)). $name  (zone: $zone)"
done

# Ask user to choose
echo
read -p "Enter the number of the instance you want to stop and create an image from: " choice
index=$((choice-1))

if [ $index -lt 0 ] || [ $index -ge ${#instances[@]} ]; then
  echo "Invalid selection."
  exit 1
fi

INSTANCE_NAME=$(echo "${instances[$index]}" | awk '{print $1}')
ZONE=$(echo "${instances[$index]}" | awk '{print $2}')

echo
echo "Stopping instance: $INSTANCE_NAME in zone: $ZONE ..."
gcloud compute instances stop "$INSTANCE_NAME" --zone="$ZONE" --quiet

# Create image name
IMAGE_NAME="${INSTANCE_NAME}-image-$(date +%Y%m%d%H%M%S)"

echo
echo "Creating image: $IMAGE_NAME ..."
gcloud compute images create "$IMAGE_NAME" \
  --source-disk="$INSTANCE_NAME" \
  --source-disk-zone="$ZONE"

# Ask how many instances to create
echo
read -p "How many new instances would you like to create from image '$IMAGE_NAME'? " COUNT
read -p "Enter zone to create the new instances in (e.g. asia-south1-c): " NEW_ZONE

echo
echo "Fetching available machine types for zone '$NEW_ZONE'..."
mapfile -t machinetypes < <(gcloud compute machine-types list --zones="$NEW_ZONE" --format="value(name)" | sort)

if [ ${#machinetypes[@]} -eq 0 ]; then
  echo "No machine types found for zone $NEW_ZONE. Check your zone or permissions."
  exit 1
fi

echo "Available machine types:"
for i in "${!machinetypes[@]}"; do
  echo "$((i+1)). ${machinetypes[$i]}"
done

echo
read -p "Select the machine type number you want to use: " m_choice
m_index=$((m_choice-1))

if [ $m_index -lt 0 ] || [ $m_index -ge ${#machinetypes[@]} ]; then
  echo "Invalid selection."
  exit 1
fi

MACHINE_TYPE=${machinetypes[$m_index]}
echo
echo "You selected machine type: $MACHINE_TYPE"
echo

# Create the instances
for ((i=1; i<=COUNT; i++)); do
  NEW_INSTANCE="${INSTANCE_NAME}-clone-$i"
  echo "Creating instance: $NEW_INSTANCE in zone: $NEW_ZONE (type: $MACHINE_TYPE) ..."
  gcloud compute instances create "$NEW_INSTANCE" \
    --zone="$NEW_ZONE" \
    --image="$IMAGE_NAME" \
    --machine-type="$MACHINE_TYPE"
done

echo
echo "✅ Done! Created $COUNT new instances from image '$IMAGE_NAME' using machine type '$MACHINE_TYPE' in zone '$NEW_ZONE'."
