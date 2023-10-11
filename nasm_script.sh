#!/bin/bash

# Grabs the $PWD of where the script is being run
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Grabs the library directory from "lib_dir.txt"
LIB_DIR=$(head -n 1 $SCRIPT_DIR/lib_dir.txt | grep -oE '^\S+' | sed 's/\/$//')

# Set to true if you want to keep .o/.out files
keep_obj_files=false
keep_out_files=false


# Colors/text format
END="\e[0m"
BLD="\e[1m"
DIM="\e[2m"
RED="\e[31m"
GRN="\e[32m"
YLW="\e[33m"
BLU="\e[34m"

# Command to build object files
BUILD_CMND="nasm -f elf"

# Command to link object files and produce executable
LINK_CMND="ld -m elf_i386 -o"

function _remove_obj_files()
{
    if find . -type f -name "*.o" | grep -q .; then
        rm *.o
    fi
}

function _remove_lib_obj_files()
{
    if find $LIB_DIR -type f -name "*.o" | grep -q .; then
        rm $LIB_DIR/*.o
    fi
}

function _remove_out_file()
{
    if find . -type f -name "*.out" | grep -q .; then
        rm *.out
    fi
}

function _append_files
{
    # Grab number of .asm files
    num_asm_files=$(ls | grep "\b.asm\b" | wc -l)

    # Exit if no .asm files exist
    if [ $num_asm_files == 0 ]; then
        printf "${BLD}${RED}No *.asm files here!${END}\n"; exit
    # Otherwise append file names to array
    else
        for ((i = 0 ; i < $num_asm_files ; i++)); do
            asm_file[$i]=$(ls | grep "\b.asm\b" | grep .asm -n | grep "$(($i+1)):")
            asm_file[$i]=${asm_file[$i]##*:}
            asm_file[$i]=${asm_file[$i]%.*}
        done
    fi
}

function _list()
{
    # Display how to exit script
    printf "${DIM}Exit script with: ${BLD}${YLW}CTRL + C${END}\n\n"

    # List files in current directory
    for ((i = 0 ; i < $num_asm_files ; i++)); do
        printf "${BLD}${BLU}$(($i+1)).${END} ${asm_file[$i]}.asm\n"
    done
}

function _validate()
{
    # Verify that first character is 'e' or 'd' otherwise exit the function
    if [ "${cmnd[0]}" != 'e' ] && [ "${cmnd[0]}" != 'd' ]; then
        printf "${RED}'e' or 'd' should be the first character${END}\n"
        return
    fi

    # If only 1 letter is entered include all files in curr dir to user's input
    if [ ${#cmnd[@]} == 1 ]; then
        for ((i = 0 ; i < $num_asm_files ; i++)); do
            cmnd[(${#cmnd[@]}+$i)]=$(($i+1))
        done
    # Otherwise evaluate the rest of input
    else
        for ((i = 1 ; i < ${#cmnd[@]} ; i++))
        do
            # If character is an integer
            if [[ ${cmnd[$i]} =~ ^[0-9]+$ ]]; then
                # If integer is not on the list
                if [ ${cmnd[$i]} == 0 ] || [ ${cmnd[$i]} -gt $num_asm_files ]; then
                    printf "${RED}'${cmnd[$i]}' is not on the list${END}\n"
                    return
                fi
            else
                # If character is not an integer
                printf "${RED}'${cmnd[$i]}' is not a valid option at position $(($i+1))${END}\n"
                return
            fi
        done
    fi

    # At this point, input is valid, so save input into history
    history -s "${cmnd[@]}"; HISTCONTROL=ignoredups:erasedups
    prev_input=("${cmnd[@]}")

    # Pass input to next function
    _evaluate "${cmnd[@]}"
}

function _prev_input()
{
    # Check if previous command exists
    if [ ${#prev_input[@]} != 0 ]; then
        # Output the previous command and skip validation
        printf "\e[1A\e[KEnter: ${BLD}${DIM}${YLW}"; echo -n ${prev_input[@]}; printf "${END}\n"
        _evaluate "${prev_input[@]}"
    # Otherwise tell user that no previous command exists
    else
        printf "${RED}No previous command${END}\n"
    fi
}

function _input()
{
    # Grab user input
    read -r -e -p $'\nEnter: \e[1m\e[33m' -a cmnd; printf "${END}"

    # If user input is emtpy then run previous input
    if   [ ${#cmnd[@]} == 0 ]; then
        _prev_input
    # If user enters 'c' then clear terminal
    elif [ ${#cmnd[@]} == 1 ] && [ "${cmnd[0]}" == 'c' ]; then
        clear; _list
    else
        _validate
    fi
}

function _compile_link()
{
    # Grab the argument passed in (file to be compiled)
    local file=$1

    # Compile the file (set -g flag for debugging)
    if [ "${cmnd[0]}" == 'e' ]; then
        $BUILD_CMND "$file.asm"
    else
        $BUILD_CMND -g "$file.asm"
    fi

    # If object file was created then increment counter
    if [ -e "$file.o" ]; then
        ((num_obj_files++))

        # Check if the file is main
        if [ "$file" == "$main_file" ]; then
            link_cmnd_1+=" '$file'.o"
        else
            link_cmnd_2+=" '$file'.o"
        fi
    # Otherwise exit function and return error code
    else
        return 1
    fi
}

function _search_libraries()
{
    # Grab number of libraries declared in main
    lib_count=$(grep -w "lib:" "$main_file.asm" | wc -l)

    # If greater then 0 then continue
    if [ $lib_count -gt 0 ]; then
        # Grab the names of the library files and compile them if they exist
        for ((i = 1 ; i <= $lib_count ; i++))
        do
            # Grab name of library file declared in main file
            local lib_file=$(grep -w "lib:" "$main_file.asm" | grep "lib:" -n | grep $i | awk '{print $3}')
            # Remove the file extension (.asm)
            lib_file="${lib_file%.*}"

            # Check if that file exists
            if find $LIB_DIR -type f -name "$lib_file.asm" | grep -q .; then
                _compile_link "$LIB_DIR/$lib_file"
            else
                printf "${RED}\"$lib_file\" was not found ${END}\n"
            fi
        done
    fi
}

function _evaluate()
{
    # Pass the input from user
    cmnd=("$@")

    # Add counter for main file and object files
    local main_counter=0
    num_obj_files=0

    # These variables setup the linking command
    link_cmnd_1="$LINK_CMND"
    link_cmnd_2=""

    # Go through each file from input
    for ((i = 1 ; i < ${#cmnd[@]} ; i++))
    do
        # Grab the number associated with file from list
        local file_num=${cmnd[$i]}

        # Check if file is main
        local is_main=$(grep "_start" "${asm_file[$file_num-1]}.asm" | wc -l)
        if [ $is_main == 2 ]; then
            ((main_counter++))

            # If input has more than one main file then exit function
            if [ $main_counter -gt 1 ]; then
                printf "${RED}Include (only) one main file${END}\n"
                _remove_obj_files
                return
            # Otherwise declare the name of the main file and add to linking command
            else
                main_file=${asm_file[$file_num-1]}
                link_cmnd_1+=" '$main_file'.out"
            fi
        fi

        # Run file through function
        _compile_link "${asm_file[$file_num-1]}"

        # If there was an error from the function above, exit this function
        if [ $? -eq 1 ]; then return; fi
    done

    # Search for library files declared in main
    _search_libraries
    # Create executable
    _execute_debug
}

function _execute_debug()
{
    # If there's a correct number of object files then we're ready to create executable
    if [ $num_obj_files == $((${#cmnd[@]}-1 + $lib_count)) ]; then

        # Execute the linking command
        eval "$link_cmnd_1$link_cmnd_2"

        # Check if the executable was created
        if [ -e "$main_file.out" ]; then
            if [ ${cmnd[0]} == 'e' ]; then
                eval "./'$main_file'.out"
                printf "Exited ${GRN}$main_file.out${END}\n"
            else
                eval "gdb --quiet '$main_file'.out"
            fi
        fi
    fi

    # Remove all .o/.out files if user chooses so
    if [ $keep_obj_files = false ]; then _remove_obj_files; _remove_lib_obj_files; fi
    if [ $keep_out_files = false ]; then _remove_out_file; fi
}

trap exit 0 SIGINT

function _main()
{
    _input
    _main
}

_append_files
_list
_main
