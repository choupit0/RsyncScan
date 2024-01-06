#!/bin/bash

host=""
hosts="$1"
mode="$2"
green_color="\033[0;32m"
red_color="\033[1;31m"
blue_color="\033[0;36m"
purple_color="\033[1;35m"
error_color="\033[1;41m"
bold_color="\033[1m"
end_color="\033[0m"

if [[ -z $hosts ]]; then
	echo -e "${purple_color}Usage: `basename $0` [path to the hosts file] [sequential mode by default (slowlest) otherwise specify \"p\" for parallel mode]${end_color}"
        exit 1
fi

if [[ ! -s $hosts ]]; then
        echo -e "${red_color}[X] Source file \"$hosts\" does not exist or is empty.${end_color}"
        exit 1
fi

max_parallel_scan="50"
temp_dir="$(mktemp -d /tmp/temp_dir-XXXXXXXX)"
date="$(date +%F_%H-%M-%S)"
nb_rsync_process="$(sort -n $hosts | wc -l)"
rsync_user="username"
rsync_pass=""

# We are checking the hosts one by one.
sequential_mode(){
cat $hosts | while IFS= read -r host; do
	$(rsync --list-only --timeout=5 --contimeout=5 --password-file=$rsync_pass $rsync_user@$host:: > /dev/null 2>&1)
		if [[ $? == "0" ]]; then
			folders_nb=$(rsync --list-only --password-file=$rsync_pass $rsync_user@$host:: | cut -d$'\t' -f1 | wc -l)
			echo -e "${bold_color}$folders_nb visible folder(s) for $host :${end_color}"
			IFS=$'\n'
			for dossier in $(rsync --list-only --password-file=$rsync_pass $rsync_user@$host:: | cut -d$'\t' -f1); do
				proper_folder_name=$(echo $dossier | sed 's/[[:blank:]]*$//')
				rsync --list-only --password-file=$rsync_pass $rsync_user@$host::$proper_folder_name > /dev/null 2>&1
					if [[ $? == "0" ]]; then
						echo -e "${green_color}Folder \"$proper_folder_name\" -> accessible${end_color}"
						echo "rsync --list-only $host::$proper_folder_name" >> rsync_servers_list_$date.txt
					else
						echo -e "${red_color}Folder \"$proper_folder_name\" -> inaccessible${end_color}"
					fi
			done
		else
			echo -e "${error_color}No folder readable for $host or host unreachable.${end_color}"
		fi
done
}

# We are checking multiple hosts at once.
parallel_mode(){
rsync --list-only --timeout=5 --contimeout=5 --password-file=$rsync_pass $rsync_user@$host:: > /dev/null 2>&1

if [[ $? == "0" ]]; then
        folders_nb=$(rsync --list-only --password-file=$rsync_pass $rsync_user@$host:: | cut -d$'\t' -f1 | wc -l)
        #echo -e "${bold_color}$folders_nb visible folder(s) for $host :${end_color}"
        IFS=$'\n'
                if [[ $folders_nb != "0" ]]; then
                        for dossier in $(rsync --list-only --password-file=$rsync_pass $rsync_user@$host:: | cut -d$'\t' -f1); do
                                proper_folder_name=$(echo $dossier | sed 's/[[:blank:]]*$//')
                                rsync --list-only --password-file=$rsync_pass $rsync_user@$host::$proper_folder_name > /dev/null 2>&1
                                        if [[ $? == "0" ]]; then
                                                echo "rsync --list-only $host::$proper_folder_name" >> rsync_servers_list_$date.txt
                                        fi
                        done
                fi
fi

echo "${host}: Done" >> "${temp_dir}"/process_rsync_done.txt

rsync_proc_ended="$(grep "$Done" -co "${temp_dir}"/process_rsync_done.txt)"
pourcentage="$(awk "BEGIN {printf \"%.2f\n\", \"${rsync_proc_ended}\"/\"${nb_rsync_process}\"*100}")"
echo -n -e "\r                                                                                                         "
echo -n -e "${purple_color}${bold_color}\r[I] Rsync test is done for ${host} -> ${rsync_proc_ended}/${nb_rsync_process} rsync process launched...(${pourcentage}%)${end_color}"

}

if [[ -z $mode ]]; then
	echo -e "${green_color}${bold_color}[sequential mode]${end_color}"
	sequential_mode

	if [[ -f "rsync_servers_list_$date.txt" ]]; then
		sort -u rsync_servers_list_$date.txt | sort -t . -n -k1,1 -k2,2 -k3,3 -k4,4 > accessible_files_sorted_$date.txt
	fi

	rm -rf "${temp_dir}" rsync_servers_list_$date.txt > /dev/null 2>&1
	exit 0
fi

if [[ $mode == "p" ]]; then
	echo -e "${green_color}${bold_color}[parallel mode]${end_color}"
	# Controlling the number of rsync scanner to launch
	if [[ ${nb_rsync_process} -ge "$max_parallel_scan" ]]; then
		max_job="$max_parallel_scan"
		echo -e "${blue_color}${bold_color}Warning: A lot of rsync process to launch: ${nb_rsync_process}${end_color}"
		echo -e "${blue_color}[-] So, to ensure a better result and not disturb your system, I will only launch ${max_job} rsync process at time.${end_color}"
	else
		max_job="${nb_rsync_process}"
	    echo -n -e "\r                                                                                             "
		echo -e "${purple_color}${bold_color}\r[I] Launching ${nb_rsync_process} rsync scanner(s).${end_color}"
	fi

	# Queue files
	new_job(){
	active_job="$(jobs | wc -l)"
	while ((active_job >= ${max_job})); do
		active_job="$(jobs | wc -l)"
	done
	parallel_mode "${host}" &
	}

	# We are launching all the rsync scanners in the same time
	count="1"

	while IFS= read -r host; do
		new_job "$i"
		count="$(expr $count + 1)"
	done < $hosts

	wait

	if [[ -f "rsync_servers_list_$date.txt" ]]; then
		sort -u rsync_servers_list_$date.txt | sort -t . -n -k1,1 -k2,2 -k3,3 -k4,4 > accessible_files_sorted_$date.txt
	fi

	rm -rf "${temp_dir}" rsync_servers_list_$date.txt > /dev/null 2>&1
	rm -rf "${temp_dir}" > /dev/null 2>&1
	exit 0
else
	echo -e "${error_color}This parameter doesn't exist.${end_color}"
	exit 1
fi

rm "${temp_dir}" > /dev/null 2>&1

exit 0
