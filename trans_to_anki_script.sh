#!/bin/bash

set -e
set -u
set -o pipefail
#set -x # For Debugging

####################################################################################
# Help                                                                             #
####################################################################################

display_usage() {
	# Display Help
	echo "NAME" 
	echo "		trans_to_anki_script.sh" 
	echo ""
	echo "DESCRIPTION"
	echo "		This script lets you translate words and create Anki flashcards"
	echo "		with MP3 files from the shell."
	echo ""
	echo "		The script repeatedly prompts you for a word to be translated." 
	echo "		Once you enter a word, Translate Shell is used to translate it,"
	echo "		and possible translations are displayed. You can then choose if"
	echo "		you want to save a flashcard for one of the translations. If you"
	echo "		choose to save a flashcard, a string representing the card (with"
	echo "		an formating for Anki) gets appended to a TXT file that stores all"
	echo "		cards and gTTS is used to generate MP3 files for the flashcard."
	echo "		After this you are prompted for the next word to be translated."
	echo ""
	echo "USAGE" 
	echo "		./trans_to_anki_script.sh <code a> <code b> <savepath>"
	echo ""
	echo "		code a 		= source language code e.g. en" 
	echo "		code b 		= target language code e.g. es" 
	echo "		savepath 	= path where you want to save the files" 
	echo "		        	  e.g ~/Desktop/<foldername>" 
	echo ""
}

####################################################################################
# Functions                                                                        #
####################################################################################

### Utility functions ####

get_reply() {
	while true; do	
		#echo -n "Enter \"y\" for yes or \"n\" for no: "
		read reply
		case $reply in
			Y|y) 
				return 0 ;;
			N|n) 
				return 1 ;;
			*)
				echo -n "Invalid answer. Enter your answer again: " ;;
		esac
	done
}

### Helper functions for run_main_loop() ###

get_translations() {
	word="$1"

	# get Translate Shell output and display it
	trans_shell_output="$(trans "$SOURCE_LANG":"$TARGET_LANG" "$word")"
	echo "$trans_shell_output" > "$(tty)"

	# get possible translations form the last line of the Translate Shell output
	poss_trans=$(tail -n 1 <<< "$trans_shell_output")

	# strip formating and leading spaces from the string of possible translations
	# but keep commas between the translations for separation
	poss_trans_clean=$(sed 's/^[[:space:]]*//; s/,[[:space:]]*/,/g;
						 	s/\x1b\[1m//g; s/\x1b\[22m//g' <<< "$poss_trans")
	
	echo "$poss_trans_clean"
}

select_translation() {
	word="$1"
	IFS=',' read -r -a poss_trans <<< "$2"
 
	# display possible translations line by line
    echo -e "\n\nPossible translations for \"$word\":" > "$(tty)"
    for ((i=0; i<${#poss_trans[@]}; i++)); do
		echo "$((i+1)): ${poss_trans[i]} " > "$(tty)"
    done

    # let the user choose one of the translations 
    while true; do
        echo -en "\nEnter the number for the translation you want to choose: " > "$(tty)"
        read number

        if [[ ! $number =~ ^[0-9]*$ || $number -gt ${#poss_trans[@]} ||  
              $number -lt 1 ]]; then
            echo "Invalid number. Enter the number again." > "$(tty)"
		else
			chosen_trans=${poss_trans[((number - 1))]}
            echo -e "Chosen translation: $chosen_trans\n" > "$(tty)"
            break
		fi
    done

    echo "$chosen_trans"
}

save_card() {
	# Append string representing the current card to anki_cards.txt
	word="$1"
	translation="$2"
	echo "${word}[sound:${SOURCE_LANG}_${word}.mp3]," \
		 "${translation}[sound:${TARGET_LANG}_${translation}.mp3]" \
		 >> "$CARDS_FILE"
	echo "Appended \"${word}[sound:${SOURCE_LANG}_${word}.mp3], " \
		 "${translation}[sound:${TARGET_LANG}_${translation}.mp3]\" " \
		 "to $CARDS_FILE ..."
}

create_mp3() {
	# Use gTTS to create a mp3 and save it in AUDIO_DIR_PATH
	word=$1
	lang_code=$2
	audio_filename="${lang_code}_${word}.mp3"
	audio_savepath="${AUDIO_DIR_PATH}/${audio_filename}"
	gtts-cli "$word" --lang "$lang_code" > "$audio_savepath"
	echo "Saved $audio_filename in $AUDIO_DIR_PATH ..."
}

### Functions called the main() function ###

run_main_loop() {
	while true; do 
		# let the user enter a word, pass it to Translate Shell, display the output
		# and save possible translations comma separated in $translations
		echo -n "Enter the word you want to translate or \"q\" to quit: "
		read word		
		if [[ "$word" == "q" ]]; then
			break
		fi
		translations=$(get_translations "$word")
		
		# check if user wants to save one of the translations to the deck
		# if this is the case the string representing the card for the chosen 
		# translation gets appended to anki_cards.txt and the corresponding mp3s 
		# are saved in $SAVE_PATH/audio
		echo -en "\nDo you want to save a translation for \"$word\" to the deck? [Y/n]: "

		if get_reply; then 
			chosen_trans=$(select_translation "$word" "$translations")
			save_card "$word" "$chosen_trans"
			create_mp3 "$word" "$SOURCE_LANG"
			create_mp3 "$chosen_trans" "$TARGET_LANG"
		else
			echo "Continuing without saving a translation of \"$word\" to the deck."		
		fi

		echo -e "\n---------\n"
	done
}

validate_lang_code() {
	# Check if language code exists in the list of vaild codes otherwise exit script
	code=$1
  	valid_codes=(
				 am ar az ba be bg bn bs ca ceb co cs cy da de el emj en eo es et eu 
				 fa fi fj fr fy ga gd gl gu ha haw he hi hmn hr ht hu hy id ig is it 
				 ja jv ka kk km kn ko ku ky la lb lo lt lv mg mhr mi mk ml mn mr mrj
				 ms mt mww my ne nl no ny otq pa pap pl ps pt ro ru sd si sk sl sm sn 
				 so sq sr-Cyrl sr-Latn st su sv sw ta te tg th tl tlh tlh-Qaak to tr 
				 tt ty udm uk ur uz vi xh yi yo yua yua zh-CN zh-TW zu
	)
 
	for validation in "${valid_codes[@]}"; do 
		if [[ "$code" == "$validation" ]]; then
			return
		fi
	done

	echo "The languag code \"$code\" is not valid."
	echo "Valid codes are: "
	echo "${valid_codes[@]}"
	
	exit 0
}

copy_mp3s_to_anki() {
	# copy all mp3s from SAVE_PATH/audio to the Anki media folder
	echo -e "\nIf your anki media folder is located at the default location" \
		 	"(/home/user/.local/share/Anki2/User 1/collection.media/) press" \
			" \"Enter\" otherwise enter the path of your Anki media folder here" \
			"(don't use ~ and don't escape spaces): "
	read -r anki_folder_path
	
	if [[ $anki_folder_path == "" ]]; then 
		anki_folder_path="$HOME/.local/share/Anki2/User 1/collection.media/"	
	fi

	echo "Copying the audio files to $anki_folder_path ..."
	cp "$AUDIO_DIR_PATH"/*.mp3 "$anki_folder_path"
}


#####################################################################################
# Main Function                                                                     #
#####################################################################################

main() {

	if [[ $@ == "--help" || $@ == "-h" || ! $# -eq 3 ]]; then 
		display_usage
		exit 0
	fi
	
	### Set global variables and validate input ###
	
	SOURCE_LANG=$1
	TARGET_LANG=$2
	SAVE_PATH=$3

	validate_lang_code "$SOURCE_LANG"
	validate_lang_code "$TARGET_LANG"

	### Create folder and files	###

	CARDS_FILE="$SAVE_PATH/anki_cards.txt"	
	mkdir -p "$SAVE_PATH"
	touch "$CARDS_FILE"

	AUDIO_DIR_PATH="$SAVE_PATH/audio"
	mkdir -p "$AUDIO_DIR_PATH"

	### Start main loop ###

	run_main_loop	
	
	### Check if user wants to copy mp3s before exiting the script ###
	
	echo -en "\nDo you want to copy the generated audio files to the Anki media" \
			"folder? [Y/n]: "

	if get_reply; then 
		copy_mp3s_to_anki
	fi

	echo "To use your deck open Anki and import the $CARDS_FILE."
	echo "Exiting script ..."

}

main "$@"
