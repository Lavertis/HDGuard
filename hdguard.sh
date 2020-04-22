#!/bin/bash

function showHeader
{
    clear
    echo
    echo " ==============================================================================="
    echo " =================================== HDGUARD ==================================="
    echo " ==============================================================================="
    echo

}

function showDiskInfo
{
    echo "Disk: $disk_name"
    echo "Partition: $partition_name"
    echo "Free space: "$current_value_percentage"%"
    echo "Treshold level: "$treshold_percentage"%"
    echo
}

function showLimitWarning
{
    echo "Threshold exceeded!"
    echo "Choose action:"
    echo "1. Partition cleanup"
    echo "2. Ignore"
}

function showPartitionCleanup
{
    echo "Choose action:"
    echo "1. Delete files"
    echo "2. Transfer files to a USB-stick/USB-drive"
}

function showUSBChoice
{
    showHeader
    echo "Is this the device you want to use?"
    echo
    echo "Capacity      Name"
    echo "$USB_device_size_human_readable           $USB_device_name"
    echo
    echo "1. Yes"
    echo "2. No"
    read -rsn1 choice
    echo
}

function getUSBInfo
{
    USB_device_path=$(lsblk | awk 'END{$1=$2=$3=$4=$5=$6=""; print $0}' | cut -c 7-)
    USB_device_name=$(lsblk | awk 'END{$1=$2=$3=$4=$5=$6=""; print $0}' | awk -F'/' '{print $4}')
    USB_device_size_human_readable=$(df -h "$USB_device_path" | awk 'END {print $2}');
    USB_device_free_space_bytes=$(df "$USB_device_path" | awk 'END {A=($4*1000); print A}')
    USB_device_free_space_bytes=$(($USB_device_free_space_bytes*1000))
}

function getDiskInfo
{
    local disk_size_bytes=$(df /home/$USER | awk 'END{A=($2*1000); print A}')
    treshold_percentage_bytes=$(($disk_size_bytes*$treshold_percentage/100))
    partition_name=$(df /home/$USER | awk '/dev/ { print $1 }')
    #storage=$(echo $partition_name | cut -c -8)
    disk_name=$(inxi -d | grep /dev/sdb | grep -o -P '(?<=model: ).*(?= size)')
}

function deleteFiles
{
    while read line
    do
       echo "Deleting file $line"
       rm "$line"
    done <<< $files_after_size_check_paths
    echo
    echo "Files have been removed"
    sleep 4
}

function moveFiles
{
    while read line
    do
       echo "Moving file $line to $USB_device_path"
       mv "$line" "$USB_device_path"
    done <<< $files_after_size_check_paths
    echo
    echo "Files have been transfered"
    sleep 4
}

function moveToUSB
{
    local before=$(lsblk)
    while :
    do
        showHeader
        echo "Insert a USB device and press Enter"
        read
        local after=$(lsblk)
        if [ "$before" = "$after" ]
        then
            echo "No USB device inserted!"
        else
            getUSBInfo
            showUSBChoice
            case $choice in
            
                1)
                    if [[ $USB_device_free_space_bytes -le $USB_required_space_bytes ]]; then
                            echo "There is not enough space on the USB device"
                            echo "Please change the device"
                            echo "Remove USB device and press Enter"
                            read
                            continue
                    fi
                    echo "Type \"yes\" to confirm the operation of moving files"
                    read -s choice
                    if [ "$choice" = "yes" ]; then
                        moveFiles
                    else
                        echo "Operation aborted"
                        sleep 2
                        break
                    fi
                    break
                ;;

                2)
                    echo "Please change the USB Device"
                ;;

                *)
                    echo "Wrong choice"
                ;;

            esac
        fi
        sleep 2
    done
}

function showFiles
{
    echo $'\n'"Files to be processed:"$'\n'
    local current_value_bytes=$(df /home/$USER | awk 'END{A=(($2-$3)*1000); print A}')
    local bytes_to_remove=$(($treshold_percentage_bytes-$current_value_bytes))
    local files_before_size_check=$(find /home/$USER -type f -printf '%T@ %s %p\n' | sort -k1 -n -r | grep -v '/\.'| awk '{$1=""; print $0}' | cut -c 2-)
    local files_after_size_check_megabytes=""
    local sum=0
    files_after_size_check_paths=""

    while read line
    do
        if [ $sum -gt $bytes_to_remove ]; then
            break
        fi
        local size=$(echo $line | cut -d' ' -f1)
        local size_mb=$(echo $size | awk '{printf "%.4f", ($1/1000000)}')
        sum=$(($sum+$size))
        local path=$(echo $line | awk '{$1=""; print $0}' | cut -c 2-)
        files_after_size_check_paths+=$path$'\n'
        files_after_size_check_megabytes+=$(echo $size_mb | awk '{$1 = sprintf("%-11s", $1); print $0}')$path$'\n'

    done <<< $files_before_size_check
    files_after_size_check_paths=${files_after_size_check_paths%?}

    echo "Size(MB)   Path"
    echo "$files_after_size_check_megabytes"
    echo
}

function takeAction
{
    case $choice in
        
        1)
            showFiles
            showPartitionCleanup
            read -rsn1 choice
            echo

            if [ $choice = 1 ]; then
                echo "Type \"yes\" to confirm the operation of deleting files"
                read -s choice
                if [ "$choice" = "yes" ]; then
                    deleteFiles
                else
                    echo "Operation aborted"
                fi
            elif [ $choice = 2 ]; then
                moveToUSB
            fi
        ;;

        2)
            echo "Warning ignored"
            sleep 2
            showHeader
            showDiskInfo
            sleep 60
        ;;

        *)
            echo "Wrong choice"
            sleep 2
        ;;

    esac
}

function mainMenu
{
    while :
    do
        current_value_percentage=$(df /home/$USER | awk 'END{A=(($2-$3)/$2*100); print int(A)}')
        showHeader
        showDiskInfo
        if [ $current_value_percentage -lt $treshold_percentage ]; then
            break
        fi
        sleep 60
    done
    showLimitWarning
    read -rsn1 choice
}

function passedValueCheck
{
    local numberOfPassedValues=$1
    treshold_percentage=$2
    if [ $numberOfPassedValues -eq 0 ]; then
        echo "Error: No argument passed"
        echo "Type: $0 <number>"
        exit 2 # error code 2 -> no argument passed
    elif [ $numberOfPassedValues -gt 1 ]; then
        echo "Error: Too many arguments passed"
        exit 3 # error code 3 -> too many arguments
    elif ! [ "$treshold_percentage" -eq "$treshold_percentage" ] 2> /dev/null; then
        echo "Error: Argument must be a number"
        exit 1 # error code 1 -> argument is not valid
    elif [ $treshold_percentage -gt 90 ] || [ $treshold_percentage -lt 10 ]; then
        echo "Error: Only values between 10% and 90% are available"
        exit 1 # error code 1 -> argument is not valid
    fi
}

###################################################### MAIN ######################################################
passedValueCheck $# $1
getDiskInfo

while :
do
    mainMenu
    takeAction
done

exit 0
# error code 0 -> program executed successfully
# error code 1 -> argument is not valid
# error code 2 -> no argument passed
# error code 3 -> too many arguments
